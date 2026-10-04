import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/push_notification_service.dart';

const vehicleTypes = <String>[
  'эвакуатор',
  'манипулятор',
  'автовышка',
  'автокран',
  'экскаватор',
];

String vehicleTypeLabel(String value) {
  switch (value) {
    case 'эвакуатор':
      return 'Эвакуатор';
    case 'манипулятор':
      return 'Манипулятор';
    case 'автовышка':
      return 'Автовышка';
    case 'автокран':
      return 'Автокран';
    case 'экскаватор':
      return 'Экскаватор';
    default:
      return value;
  }
}

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
  bool _canOpenLocationSettings = false;
  String? _locationMessage;
  String? _notificationMessage;
  String? _vehicleType;
  bool _savingVehicleType = false;
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
      final registered = await _pushNotifications.initializeForUser(user);
      if (mounted) {
        setState(() {
          _notificationMessage = registered ? null : 'Уведомления выключены или FCM-токен не зарегистрирован. Разрешите уведомления в настройках приложения.';
        });
      }
      _messageSubscription = _pushNotifications.foregroundMessages.listen((
        message,
      ) {
        if (!mounted) return;
        unawaited(_pushNotifications.showForegroundNotification(message));
      });
    } catch (error) {
      debugPrint('FCM initialization failed: $error');
      if (mounted) {
        setState(() {
          _notificationMessage = 'Не удалось зарегистрировать уведомления. Проверьте интернет и настройки приложения.';
        });
      }
    }
  }

  Future<void> _loadDriverLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        _setLocationMessage(
          'Доступ к геолокации заблокирован. Разрешите его в настройках приложения.',
          canOpenSettings: true,
        );
        return;
      }
      if (permission == LocationPermission.denied) {
        _setLocationMessage('Разрешение на геолокацию не предоставлено.');
        return;
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _setLocationMessage(
          'Служба геолокации выключена. Включите GPS, чтобы получать заявки рядом.',
          canOpenSettings: true,
        );
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

  void _setLocationMessage(String message, {bool canOpenSettings = false}) {
    if (!mounted) return;
    setState(() {
      _isLocating = false;
      _locationMessage = message;
      _canOpenLocationSettings = canOpenSettings;
    });
  }

  bool _isVisibleOrder(Map<String, dynamic> data) {
    final orderType = (data['vehicleType'] ?? data['type'])
        ?.toString()
        .trim()
        .toLowerCase();
    return data['status']?.toString() == 'active' &&
        orderType == _vehicleType?.toLowerCase();
  }

  Future<void> _saveVehicleType(String? value) async {
    if (value == null || value.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _savingVehicleType = true);
    try {
      await FirebaseFirestore.instance.collection('drivers').doc(user.uid).set({
        'driverId': user.uid,
        'vehicleType': value,
        'isOnline': true,
        'vehicleTypeUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) setState(() => _vehicleType = value);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось сохранить тип техники')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingVehicleType = false);
    }
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
    final comment = data['comment']?.toString() ?? '';

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF171914),
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        final maxHeight = MediaQuery.sizeOf(sheetContext).height * 0.78;
        return SizedBox(
          height: maxHeight,
          child: SafeArea(
            bottom: true,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Column(
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
                      const Expanded(
                        child: Text(
                          'Активная заявка',
                          style: TextStyle(
                            color: Color(0xFFF3C622),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        '#${orderId.substring(0, orderId.length > 6 ? 6 : orderId.length)}',
                        style: const TextStyle(color: Colors.white38),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
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
                              value:
                                  '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}',
                            ),
                          if (comment.isNotEmpty)
                            _InfoRow(
                              icon: Icons.notes_outlined,
                              label: 'Детали',
                              value: comment,
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
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
                    const SizedBox(
                      width: double.infinity,
                      child: Text(
                        'Эта заявка уже недоступна.',
                        style: TextStyle(color: Colors.white54),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
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

  String _phoneDigits(String phone) {
    var digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('8') && digits.length == 11) {
      digits = '7${digits.substring(1)}';
    }
    if (digits.length == 10) {
      digits = '7$digits';
    }
    return digits;
  }

  Future<void> _callClient(String phone) async {
    final digits = _phoneDigits(phone);
    if (digits.length < 11) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Номер клиента указан некорректно')),
        );
      }
      return;
    }
    if (!await launchUrl(
          Uri(scheme: 'tel', path: '+$digits'),
          mode: LaunchMode.externalApplication,
        ) &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть звонилку')),
      );
    }
  }

  Future<void> _openWhatsApp(String phone) async {
    final digits = _phoneDigits(phone);
    if (digits.length < 11) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Номер клиента указан некорректно')),
        );
      }
      return;
    }
    if (!await launchUrl(
          Uri.parse('https://wa.me/$digits'),
          mode: LaunchMode.externalApplication,
        ) &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть WhatsApp')),
      );
    }
  }

  Marker? _currentOrderMarker(Map<String, dynamic>? data) {
    if (data == null) return null;
    final lat = _asDouble(data['lat']);
    final lon = _asDouble(data['lon']);
    if (lat == null || lon == null) return null;
    return Marker(
      point: LatLng(lat, lon),
      width: 58,
      height: 64,
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
          Icons.navigation_rounded,
          color: Color(0xFF11120E),
          size: 28,
        ),
      ),
    );
  }

  Widget _buildActiveOrderMap({
    Map<String, dynamic>? order,
    DateTime? cooldownUntil,
  }) {
    final type = order?['type']?.toString() ?? 'Текущий заказ';
    final phone = order?['phone']?.toString() ?? '';
    final address = order?['address']?.toString() ?? 'Адрес не указан';
    final destination = order?['destinationAddress']?.toString();
    final comment = order?['comment']?.toString() ?? '';
    final orderId = order?['_orderId']?.toString();
    final pending = order?['status']?.toString() == 'in_progress';
    final remaining = cooldownUntil?.difference(DateTime.now());
    final orderMarker = _currentOrderMarker(order);
    return Scaffold(
      backgroundColor: const Color(0xFF0B0C0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0C0A),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ТехЗаказ', style: TextStyle(fontWeight: FontWeight.w800)),
            Text(
              'В РЕЙСЕ',
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
          FlutterMap(
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
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.techzakaz.app',
              ),
              if (orderMarker != null) MarkerLayer(markers: [orderMarker]),
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
          ),
          Positioned(
            right: 16,
            top: 16,
            child: _StatusChip(
              icon: Icons.lock_clock_outlined,
              label: remaining == null ? 'ЗАКАЗ В РЕЙСЕ' : 'РАДАР ПАУЗА',
              color: const Color(0xFFF3C622),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 238,
            child: SafeArea(
              bottom: true,
              child: FloatingActionButton.small(
                heroTag: 'center-on-driver-active-order',
                onPressed: _centerOnDriver,
                tooltip: 'Моё местоположение',
                backgroundColor: const Color(0xFF171914),
                foregroundColor: const Color(0xFFF3C622),
                child: const Icon(Icons.my_location),
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: SafeArea(
              bottom: true,
              child: Material(
                color: const Color(0xF5171914),
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.navigation_rounded,
                            color: Color(0xFFF3C622),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              type,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (remaining != null)
                            Text(
                              _formatRemaining(remaining),
                              style: const TextStyle(
                                color: Color(0xFFF3C622),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _CompactInfoRow(
                        icon: Icons.location_on_outlined,
                        text: destination?.isNotEmpty == true
                            ? '$address → $destination'
                            : address,
                      ),
                      if (comment.isNotEmpty)
                        _CompactInfoRow(
                          icon: Icons.notes_outlined,
                          text: comment,
                        ),
                      if (phone.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => _callClient(phone),
                                icon: const Icon(Icons.call_outlined),
                                label: const Text('Позвонить'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFF3C622),
                                  foregroundColor: const Color(0xFF11120E),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _openWhatsApp(phone),
                                icon: const Icon(Icons.chat_outlined),
                                label: const Text('WhatsApp'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(color: Colors.white30),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (pending && orderId != null) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: FilledButton.icon(
                            onPressed: () => _departedForOrder(orderId),
                            icon: const Icon(
                              Icons.directions_car_filled_outlined,
                            ),
                            label: const Text('Выехал на заказ'),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFF3C622),
                              foregroundColor: const Color(0xFF11120E),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          height: 44,
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
                      if (remaining != null) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Новые заявки скрыты до окончания текущего заказа',
                          style: TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleTypeScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0C0A),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.construction,
                    color: Color(0xFFF3C622),
                    size: 52,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Ваша техника',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Выберите тип техники — мы покажем только подходящие заявки и будем отправлять релевантные уведомления.',
                    style: TextStyle(color: Colors.white60, height: 1.4),
                  ),
                  const SizedBox(height: 28),
                  DropdownButtonFormField<String>(
                    initialValue: _vehicleType,
                    items: vehicleTypes
                        .map(
                          (type) => DropdownMenuItem(
                            value: type,
                            child: Text(vehicleTypeLabel(type)),
                          ),
                        )
                        .toList(),
                    onChanged: _savingVehicleType ? null : _saveVehicleType,
                    dropdownColor: const Color(0xFF171914),
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    decoration: InputDecoration(
                      labelText: 'Тип спецтехники',
                      labelStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: const Color(0xFF171914),
                      prefixIcon: const Icon(
                        Icons.local_shipping_outlined,
                        color: Color(0xFFF3C622),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFF3B3D34)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: Color(0xFFF3C622),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                  if (_savingVehicleType) ...[
                    const SizedBox(height: 18),
                    const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFFF3C622),
                      ),
                    ),
                  ],
                ],
              ),
            ),
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
        .where('status', whereIn: ['in_progress', 'accepted'])
        .limit(1);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: driverRef.snapshots(),
      builder: (context, driverSnapshot) {
        final profile = driverSnapshot.data?.data();
        final savedVehicleType = profile?['vehicleType']
            ?.toString()
            .toLowerCase();
        if (_vehicleType != savedVehicleType &&
            vehicleTypes.contains(savedVehicleType)) {
          _vehicleType = savedVehicleType;
        }
        if (!vehicleTypes.contains(_vehicleType)) {
          return _buildVehicleTypeScreen();
        }
        final cooldownUntil = _cooldownUntil(driverSnapshot.data?.data());
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: currentOrderQuery.snapshots(),
          builder: (context, orderSnapshot) {
            final hasCooldown =
                cooldownUntil != null && cooldownUntil.isAfter(DateTime.now());
            if (orderSnapshot.hasData && orderSnapshot.data!.docs.isNotEmpty) {
              final order = orderSnapshot.data!.docs.first;
              return _buildActiveOrderMap(
                order: {...order.data(), '_orderId': order.id},
                cooldownUntil: hasCooldown ? cooldownUntil : null,
              );
            }
            if (hasCooldown) {
              return _buildActiveOrderMap(cooldownUntil: cooldownUntil);
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
          if (_notificationMessage != null)
            Positioned(
              left: 16,
              right: 16,
              top: 70,
              child: SafeArea(
                bottom: false,
                child: _MapMessage(message: _notificationMessage!),
              ),
            ),
          if (_locationMessage != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 20,
              child: SafeArea(
                bottom: true,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF171914).withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.orangeAccent),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.location_off_outlined,
                        color: Colors.orangeAccent,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _locationMessage!,
                          style: const TextStyle(
                            color: Colors.white,
                            height: 1.3,
                          ),
                        ),
                      ),
                      if (_canOpenLocationSettings)
                        IconButton(
                          onPressed: Geolocator.openAppSettings,
                          tooltip: 'Открыть настройки',
                          icon: const Icon(
                            Icons.settings_outlined,
                            color: Color(0xFFF3C622),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            right: 16,
            bottom: _locationMessage == null ? 24 : 92,
            child: SafeArea(
              bottom: true,
              child: FloatingActionButton.small(
                heroTag: 'center-on-driver',
                onPressed: _centerOnDriver,
                tooltip: 'Моё местоположение',
                backgroundColor: const Color(0xFF171914),
                foregroundColor: const Color(0xFFF3C622),
                child: const Icon(Icons.my_location),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactInfoRow extends StatelessWidget {
  const _CompactInfoRow({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.white54, size: 17),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
      ],
    ),
  );
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
