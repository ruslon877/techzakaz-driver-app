import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../services/push_notification_service.dart';

class RadarScreen extends StatefulWidget {
  const RadarScreen({super.key});

  @override
  State<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen> {
  static const _almaty = LatLng(43.238949, 76.889709);
  final _ordersQuery = FirebaseFirestore.instance
      .collection('orders')
      .where('status', whereIn: ['active', 'in_progress']);
  final MapController _mapController = MapController();
  final _pushNotifications = PushNotificationService.instance;

  LatLng _driverLocation = _almaty;
  bool _isLocating = true;
  bool _mapReady = false;
  String? _locationMessage;
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<RemoteMessage>? _messageSubscription;

  @override
  void initState() {
    super.initState();
    _loadDriverLocation();
    _initializePushNotifications();
  }

  Future<void> _initializePushNotifications() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await _pushNotifications.initializeForUser(user);
      _messageSubscription = _pushNotifications.foregroundMessages.listen((message) {
        if (!mounted) return;
        final title = message.notification?.title ?? 'Новая заявка рядом';
        final body = message.notification?.body ?? 'Проверьте Радар заявок';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$title\n$body')));
      });
    } catch (_) {
      // Push delivery must not block access to the radar.
    }
  }

  Future<void> _loadDriverLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _setLocationMessage('Геолокация выключена. Показываем Алматы.');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        _setLocationMessage('Нет доступа к геолокации. Показываем Алматы.');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      setState(() {
        _driverLocation = LatLng(position.latitude, position.longitude);
        _isLocating = false;
        _locationMessage = null;
      });
      _moveMapToDriver();
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await _pushNotifications.updateDriverLocation(user: user, latitude: position.latitude, longitude: position.longitude);
      }
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 250),
      ).listen((nextPosition) {
        if (!mounted) return;
        setState(() => _driverLocation = LatLng(nextPosition.latitude, nextPosition.longitude));
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser != null) {
          unawaited(_pushNotifications.updateDriverLocation(user: currentUser, latitude: nextPosition.latitude, longitude: nextPosition.longitude));
        }
      });
    } catch (_) {
      _setLocationMessage('Не удалось определить местоположение. Показываем Алматы.');
    }
  }

  void _moveMapToDriver() {
    if (_mapReady) _mapController.move(_driverLocation, 14);
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _messageSubscription?.cancel();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) unawaited(_pushNotifications.markOffline(user));
    super.dispose();
  }

  void _setLocationMessage(String message) {
    if (!mounted) return;
    setState(() {
      _isLocating = false;
      _locationMessage = message;
    });
  }

  bool _isVisibleOrder(Map<String, dynamic> data) {
    final status = data['status']?.toString() ?? 'active';
    if (status == 'active') return true;
    return status == 'in_progress' && data['driverId']?.toString() == FirebaseAuth.instance.currentUser?.uid;
  }

  List<Marker> _markersFrom(QuerySnapshot<Map<String, dynamic>> snapshot) {
    return snapshot.docs.where((document) => _isVisibleOrder(document.data())).map((document) {
      final data = document.data();
      final lat = _asDouble(data['lat']);
      final lon = _asDouble(data['lon']);
      if (lat == null || lon == null) return null;

      return Marker(
        point: LatLng(lat, lon),
        width: 52,
        height: 58,
        child: GestureDetector(
          onTap: () => _showOrderSheet(document.id, data),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF3C622),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF11120E), width: 3),
              boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 3))],
            ),
            child: const Icon(Icons.construction, color: Color(0xFF11120E), size: 25),
          ),
        ),
      );
    }).whereType<Marker>().toList();
  }

  Future<void> _changeOrderStatus(String orderId, String nextStatus) async {
    final driver = FirebaseAuth.instance.currentUser;
    if (driver == null) return;

    final orderRef = FirebaseFirestore.instance.collection('orders').doc(orderId);
    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(orderRef);
        final data = snapshot.data();
        if (data == null) throw StateError('Заявка не найдена.');

        final currentStatus = data['status']?.toString() ?? 'active';
        final assignedDriverId = data['driverId']?.toString();
        if (nextStatus == 'in_progress' && currentStatus != 'active') {
          throw StateError('Эту заявку уже взял другой водитель.');
        }
        if (nextStatus == 'completed' && (currentStatus != 'in_progress' || assignedDriverId != driver.uid)) {
          throw StateError('Завершить можно только свою заявку в работе.');
        }

        final update = <String, dynamic>{
          'status': nextStatus,
          if (nextStatus == 'in_progress') ...{
            'driverId': driver.uid,
            'startedAt': FieldValue.serverTimestamp(),
          },
          if (nextStatus == 'completed') 'completedAt': FieldValue.serverTimestamp(),
        };
        transaction.update(orderRef, update);
      });

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(nextStatus == 'in_progress' ? 'Заявка взята в работу' : 'Заявка завершена')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error is StateError ? error.message : 'Не удалось изменить статус заявки')));
    }
  }

  double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  void _showOrderSheet(String orderId, Map<String, dynamic> data) {
    final type = data['type']?.toString() ?? 'Спецтехника';
    final phone = data['phone']?.toString() ?? 'не указан';
    final address = data['address']?.toString() ?? 'Адрес не указан';
    final destination = data['destinationAddress']?.toString();
    final status = data['status']?.toString() ?? 'active';
    final currentDriverId = FirebaseAuth.instance.currentUser?.uid;
    final assignedDriverId = data['driverId']?.toString();
    final isMine = assignedDriverId != null && assignedDriverId == currentDriverId;
    final lat = _asDouble(data['lat']);
    final lon = _asDouble(data['lon']);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF171914),
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.fiber_manual_record, color: status == 'active' ? const Color(0xFFF3C622) : Colors.lightBlueAccent, size: 12),
                  const SizedBox(width: 8),
                  Text(status == 'active' ? 'Активная заявка' : isMine ? 'Ваша заявка в работе' : 'Заявка уже в работе', style: TextStyle(color: status == 'active' ? const Color(0xFFF3C622) : Colors.lightBlueAccent, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text('#${orderId.substring(0, orderId.length > 6 ? 6 : orderId.length)}', style: const TextStyle(color: Colors.white38)),
                ],
              ),
              const SizedBox(height: 18),
              Text(type, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 18),
              _InfoRow(icon: Icons.phone_outlined, label: 'Телефон клиента', value: phone),
              _InfoRow(icon: Icons.location_on_outlined, label: 'Адрес', value: address),
              if (destination != null && destination.isNotEmpty) _InfoRow(icon: Icons.flag_outlined, label: 'Точка Б', value: destination),
              if (lat != null && lon != null) _InfoRow(icon: Icons.gps_fixed, label: 'Координаты', value: '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}'),
              if ((data['comment']?.toString() ?? '').isNotEmpty) _InfoRow(icon: Icons.notes_outlined, label: 'Детали', value: data['comment'].toString()),
              const SizedBox(height: 16),
              if (status == 'active')
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: () => _changeOrderStatus(orderId, 'in_progress'),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Взять в работу'),
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFFF3C622), foregroundColor: const Color(0xFF11120E)),
                  ),
                )
              else if (isMine)
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: () => _changeOrderStatus(orderId, 'completed'),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Завершить заявку'),
                    style: FilledButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: const Color(0xFF11120E)),
                  ),
                )
              else
                const Text('Эта заявка уже закреплена за другим водителем.', style: TextStyle(color: Colors.white54)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _signOut() => FirebaseAuth.instance.signOut();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0C0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0C0A),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ТехЗаказ', style: TextStyle(fontWeight: FontWeight.w800)),
            Text('РАДАР ЗАЯВОК', style: TextStyle(color: Color(0xFFF3C622), fontSize: 10, letterSpacing: 1.5)),
          ],
        ),
        actions: [
          IconButton(onPressed: _signOut, tooltip: 'Выйти', icon: const Icon(Icons.logout_outlined)),
        ],
      ),
      body: Stack(
        children: [
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _ordersQuery.snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _MapMessage(message: 'Не удалось загрузить заявки. Проверьте доступ к Firestore.');
              }
              final markers = snapshot.hasData ? _markersFrom(snapshot.data!) : <Marker>[];
              return FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _driverLocation,
                  initialZoom: 12.5,
                  onMapReady: () {
                    _mapReady = true;
                    _moveMapToDriver();
                  },
                  interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.techzakaz.app',
                  ),
                  MarkerLayer(markers: markers),
                  MarkerLayer(markers: [
                    Marker(
                      point: _driverLocation,
                      width: 24,
                      height: 24,
                      child: Container(
                        decoration: BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)),
                      ),
                    ),
                  ]),
                ],
              );
            },
          ),
          Positioned(
            left: 16,
            right: 16,
            top: 16,
            child: Row(
              children: [
                _StatusChip(icon: Icons.circle, label: _isLocating ? 'Определяем позицию' : 'Вы на линии', color: _isLocating ? Colors.orange : Colors.greenAccent),
                const Spacer(),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _ordersQuery.snapshots(),
                  builder: (context, snapshot) {
                    final count = snapshot.data?.docs.where((document) => _isVisibleOrder(document.data())).length ?? 0;
                    return _StatusChip(icon: Icons.notifications_active_outlined, label: '$count заявок', color: const Color(0xFFF3C622));
                  },
                ),
              ],
            ),
          ),
          if (_locationMessage != null)
            Positioned(left: 16, right: 16, bottom: 20, child: _MapMessage(message: _locationMessage!)),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFFF3C622), size: 19),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: Colors.white38, fontSize: 12)), const SizedBox(height: 2), Text(value, style: const TextStyle(color: Colors.white, fontSize: 15))])),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: const Color(0xEE171914), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 12, color: color), const SizedBox(width: 7), Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600))]),
      ),
    );
  }
}

class _MapMessage extends StatelessWidget {
  const _MapMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xEE171914), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white12)),
      child: Text(message, style: const TextStyle(color: Colors.white70)),
    );
  }
}
