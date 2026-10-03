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
      .where('status', isEqualTo: 'active');
  final MapController _mapController = MapController();
  final _pushNotifications = PushNotificationService.instance;

  LatLng _driverLocation = _almaty;
  bool _isLocating = true;
  bool _mapReady = false;
  String? _locationMessage;
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<RemoteMessage>? _messageSubscription;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _loadDriverLocation();
    _initializePushNotifications();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _initializePushNotifications() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await _pushNotifications.initializeForUser(user);
      _messageSubscription = _pushNotifications.foregroundMessages.listen((
        message,
      ) {
        if (!mounted) return;
        unawaited(_pushNotifications.showForegroundNotification(message));
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
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _setLocationMessage('Нет доступа к геолокации. Показываем Алматы.');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
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
        await _pushNotifications.updateDriverLocation(
          user: user,
          latitude: position.latitude,
          longitude: position.longitude,
        );
      }
      _positionSubscription =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 250,
            ),
          ).listen((nextPosition) {
            if (!mounted) return;
            setState(
              () => _driverLocation = LatLng(
                nextPosition.latitude,
                nextPosition.longitude,
              ),
            );
            final currentUser = FirebaseAuth.instance.currentUser;
            if (currentUser != null) {
              unawaited(
                _pushNotifications.updateDriverLocation(
                  user: currentUser,
                  latitude: nextPosition.latitude,
                  longitude: nextPosition.longitude,
                ),
              );
            }
          });
    } catch (_) {
      _setLocationMessage(
        'Не удалось определить местоположение. Показываем Алматы.',
      );
    }
  }

  void _moveMapToDriver() {
    if (_mapReady) _mapController.move(_driverLocation, 14);
  }

  Future<void> _centerOnDriver() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
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
        await _pushNotifications.updateDriverLocation(
          user: user,
          latitude: position.latitude,
          longitude: position.longitude,
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось обновить местоположение')),
        );
      }
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _messageSubscription?.cancel();
    _cooldownTimer?.cancel();
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
    return data['status']?.toString() == 'active';
  }

  List<Marker> _markersFrom(QuerySnapshot<Map<String, dynamic>> snapshot) {
    return snapshot.docs
        .where((document) => _isVisibleOrder(document.data()))
        .map((document) {
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
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.construction,
                  color: Color(0xFF11120E),
                  size: 25,
                ),
              ),
            ),
          );
        })
        .whereType<Marker>()
        .toList();
  }

  Future<void> _takeOrder(String orderId) async {
    final driver = FirebaseAuth.instance.currentUser;
    if (driver == null) return;

    final orderRef = FirebaseFirestore.instance
        .collection('orders')
        .doc(orderId);
    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(orderRef);
        final data = snapshot.data();
        if (data == null) throw StateError('Заявка не найдена.');

        final currentStatus = data['status']?.toString() ?? 'active';
        if (currentStatus != 'active') {
          throw StateError('Эту заявку уже взял другой водитель.');
        }
        transaction.update(orderRef, {
          'status': 'in_progress',
          'driverId': driver.uid,
          'startedAt': FieldValue.serverTimestamp(),
        });
      });

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Заказ принят. Проверьте детали и свяжитесь с клиентом.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is StateError
                ? error.message
                : 'Не удалось изменить статус заявки',
          ),
        ),
      );
    }
  }

  Future<void> _didNotAgree(String orderId) async {
    final driver = FirebaseAuth.instance.currentUser;
    if (driver == null) return;
    final orderRef = FirebaseFirestore.instance
        .collection('orders')
        .doc(orderId);
    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(orderRef);
        final data = snapshot.data();
        if (data == null ||
            data['status']?.toString() != 'in_progress' ||
            data['driverId']?.toString() != driver.uid) {
          throw StateError(
            'Заявка уже изменилась или закреплена за другим водителем.',
          );
        }
        transaction.update(orderRef, {
          'status': 'active',
          'driverId': FieldValue.delete(),
          'startedAt': FieldValue.delete(),
        });
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is StateError
                  ? error.message
                  : 'Не удалось вернуть заявку на радар',
            ),
          ),
        );
      }
    }
  }

  Future<void> _departedForOrder(String orderId) async {
    final driver = FirebaseAuth.instance.currentUser;
    if (driver == null) return;
    final orderRef = FirebaseFirestore.instance
        .collection('orders')
        .doc(orderId);
    final driverRef = FirebaseFirestore.instance
        .collection('drivers')
        .doc(driver.uid);
    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final orderSnapshot = await transaction.get(orderRef);
        final data = orderSnapshot.data();
        if (data == null ||
            data['status']?.toString() != 'in_progress' ||
            data['driverId']?.toString() != driver.uid) {
          throw StateError(
            'Заявка уже изменилась или закреплена за другим водителем.',
          );
        }
        final cooldownUntil = Timestamp.fromDate(
          DateTime.now().add(const Duration(minutes: 60)),
        );
        transaction.update(orderRef, {
          'status': 'accepted',
          'acceptedAt': FieldValue.serverTimestamp(),
        });
        transaction.set(driverRef, {
          'driverId': driver.uid,
          'cooldownUntil': cooldownUntil,
        }, SetOptions(merge: true));
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is StateError
                  ? error.message
                  : 'Не удалось подтвердить выезд',
            ),
          ),
        );
      }
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
                  Icon(
                    Icons.fiber_manual_record,
                    color: status == 'active'
                        ? const Color(0xFFF3C622)
                        : Colors.lightBlueAccent,
                    size: 12,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Активная заявка',
                    style: const TextStyle(
                      color: Color(0xFFF3C622),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '#${orderId.substring(0, orderId.length > 6 ? 6 : orderId.length)}',
                    style: const TextStyle(color: Colors.white38),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                type,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 18),
              _InfoRow(
                icon: Icons.phone_outlined,
                label: 'Телефон клиента',
                value: phone,
              ),
              _InfoRow(
                icon: Icons.location_on_outlined,
                label: 'Адрес',
                value: address,
              ),
              if (destination != null && destination.isNotEmpty)
                _InfoRow(
                  icon: Icons.flag_outlined,
                  label: 'Точка Б',
                  value: destination,
                ),
              if (lat != null && lon != null)
                _InfoRow(
                  icon: Icons.gps_fixed,
                  label: 'Координаты',
                  value: '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}',
                ),
              if ((data['comment']?.toString() ?? '').isNotEmpty)
                _InfoRow(
                  icon: Icons.notes_outlined,
                  label: 'Детали',
                  value: data['comment'].toString(),
                ),
              const SizedBox(height: 16),
              if (status == 'active')
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: () => _takeOrder(orderId),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Взять в работу'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFF3C622),
                      foregroundColor: const Color(0xFF11120E),
                    ),
                  ),
                )
              else
                const Text(
                  'Эта заявка уже недоступна.',
                  style: TextStyle(color: Colors.white54),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _signOut() => FirebaseAuth.instance.signOut();

  DateTime? _cooldownUntil(Map<String, dynamic>? data) {
    final value = data?['cooldownUntil'];
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  String _formatRemaining(Duration duration) {
    final totalSeconds = duration.inSeconds.clamp(0, 359999);
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Widget _buildCooldownScreen(DateTime until) {
    final remaining = until.difference(DateTime.now());
    return Scaffold(
      backgroundColor: const Color(0xFF0B0C0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0C0A),
        title: const Text(
          'ТехЗаказ',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            onPressed: _signOut,
            tooltip: 'Выйти',
            icon: const Icon(Icons.logout_outlined),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.route_rounded,
                color: Color(0xFFF3C622),
                size: 74,
              ),
              const SizedBox(height: 24),
              const Text(
                'Вы на заказе',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Радар станет доступен через',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60, fontSize: 16),
              ),
              const SizedBox(height: 10),
              Text(
                _formatRemaining(remaining),
                style: const TextStyle(
                  color: Color(0xFFF3C622),
                  fontSize: 42,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Когда таймер завершится, новые заявки снова появятся на карте.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentOrderScreen(String orderId, Map<String, dynamic> data) {
    final type = data['type']?.toString() ?? 'Спецтехника';
    final phone = data['phone']?.toString() ?? 'Номер не указан';
    final address = data['address']?.toString() ?? 'Адрес не указан';
    final destination = data['destinationAddress']?.toString();
    return Scaffold(
      backgroundColor: const Color(0xFF0B0C0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0C0A),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ТехЗаказ', style: TextStyle(fontWeight: FontWeight.w800)),
            Text(
              'ТЕКУЩИЙ ЗАКАЗ',
              style: TextStyle(
                color: Color(0xFFF3C622),
                fontSize: 10,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _signOut,
            tooltip: 'Выйти',
            icon: const Icon(Icons.logout_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _StatusChip(
                icon: Icons.radio_button_checked,
                label: 'ЗАКАЗ В РАБОТЕ',
                color: Color(0xFFF3C622),
              ),
              const SizedBox(height: 24),
              Text(
                type,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 22),
              _InfoRow(
                icon: Icons.phone_outlined,
                label: 'Телефон клиента',
                value: phone,
              ),
              _InfoRow(
                icon: Icons.location_on_outlined,
                label: 'Точка А',
                value: address,
              ),
              if (destination != null && destination.isNotEmpty)
                _InfoRow(
                  icon: Icons.flag_outlined,
                  label: 'Точка Б',
                  value: destination,
                ),
              if ((data['comment']?.toString() ?? '').isNotEmpty)
                _InfoRow(
                  icon: Icons.notes_outlined,
                  label: 'Детали',
                  value: data['comment'].toString(),
                ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 58,
                child: FilledButton.icon(
                  onPressed: () => _departedForOrder(orderId),
                  icon: const Icon(Icons.directions_car_filled_outlined),
                  label: const Text(
                    'Выехал на заказ',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFF3C622),
                    foregroundColor: const Color(0xFF11120E),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () => _didNotAgree(orderId),
                  icon: const Icon(Icons.undo_rounded),
                  label: const Text('Не договорились'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();
    final driverRef = FirebaseFirestore.instance
        .collection('drivers')
        .doc(user.uid);
    final currentOrderQuery = FirebaseFirestore.instance
        .collection('orders')
        .where('driverId', isEqualTo: user.uid)
        .where('status', isEqualTo: 'in_progress')
        .limit(1);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: driverRef.snapshots(),
      builder: (context, driverSnapshot) {
        final cooldownUntil = _cooldownUntil(driverSnapshot.data?.data());
        if (cooldownUntil != null && cooldownUntil.isAfter(DateTime.now())) {
          return _buildCooldownScreen(cooldownUntil);
        }
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: currentOrderQuery.snapshots(),
          builder: (context, orderSnapshot) {
            if (orderSnapshot.hasData && orderSnapshot.data!.docs.isNotEmpty) {
              final order = orderSnapshot.data!.docs.first;
              return _buildCurrentOrderScreen(order.id, order.data());
            }
            return _buildRadar();
          },
        );
      },
    );
  }

  Widget _buildRadar() {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0C0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0C0A),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ТехЗаказ', style: TextStyle(fontWeight: FontWeight.w800)),
            Text(
              'РАДАР ЗАЯВОК',
              style: TextStyle(
                color: Color(0xFFF3C622),
                fontSize: 10,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _signOut,
            tooltip: 'Выйти',
            icon: const Icon(Icons.logout_outlined),
          ),
        ],
      ),
      body: Stack(
        children: [
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _ordersQuery.snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _MapMessage(
                  message: 'Не удалось загрузить заявки. Проверьте доступ к Firestore.',
                );
              }
              final markers = snapshot.hasData
                  ? _markersFrom(snapshot.data!)
                  : <Marker>[];
              return FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _driverLocation,
                  initialZoom: 12.5,
                  onMapReady: () {
                    _mapReady = true;
                    _moveMapToDriver();
                  },
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.techzakaz.app',
                  ),
                  MarkerLayer(markers: markers),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _driverLocation,
                        width: 24,
                        height: 24,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.blueAccent,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                          ),
                        ),
                      ),
                    ],
                  ),
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
                _StatusChip(
                  icon: Icons.circle,
                  label: _isLocating ? 'Определяем позицию' : 'Вы на линии',
                  color: _isLocating ? Colors.orange : Colors.greenAccent,
                ),
                const Spacer(),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _ordersQuery.snapshots(),
                  builder: (context, snapshot) {
                    final count =
                        snapshot.data?.docs
                            .where(
                              (document) => _isVisibleOrder(document.data()),
                            )
                            .length ??
                        0;
                    return _StatusChip(
                      icon: Icons.notifications_active_outlined,
                      label: '$count заявок',
                      color: const Color(0xFFF3C622),
                    );
                  },
                ),
              ],
            ),
          ),
          if (_locationMessage != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 20,
              child: _MapMessage(message: _locationMessage!),
            ),
          Positioned(
            right: 16,
            bottom: _locationMessage == null ? 24 : 92,
            child: FloatingActionButton.small(
              heroTag: 'center-on-driver',
              onPressed: _centerOnDriver,
              tooltip: 'Моё местоположение',
              backgroundColor: const Color(0xFF171914),
              foregroundColor: const Color(0xFFF3C622),
              child: const Icon(Icons.my_location),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xEE171914),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
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
      decoration: BoxDecoration(
        color: const Color(0xEE171914),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Text(message, style: const TextStyle(color: Colors.white70)),
    );
  }
}
