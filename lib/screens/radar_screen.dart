import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/foreground_location_service.dart';
import '../services/push_notification_service.dart';
import '../widgets/driver_drawer.dart';

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
  bool _hasAccess = true;
  bool _suppressOrderNotifications = false;
  bool _savingVehicleType = false;
  bool _isOnline = true;
  bool _savingOnline = false;
  String? _onlineInitializedUid;
  String? _foregroundServiceUid;
  bool _startingForegroundService = false;
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<RemoteMessage>? _messageSubscription;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    FlutterForegroundTask.addTaskDataCallback(_onForegroundLocationData);
    _loadDriverLocation();
    _initializePushNotifications();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _onForegroundLocationData(Object data) {
    if (!mounted || data is! Map) return;
    final lat = double.tryParse(data['lat']?.toString() ?? '');
    final lon = double.tryParse(data['lon']?.toString() ?? '');
    if (lat == null || lon == null) return;
    setState(() => _driverLocation = LatLng(lat, lon));
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
        if (message.data['orderId'] != null && _suppressOrderNotifications) {
          return;
        }
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
    FlutterForegroundTask.removeTaskDataCallback(_onForegroundLocationData);
    _cooldownTimer?.cancel();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      unawaited(ForegroundLocationService.stop());
      unawaited(_pushNotifications.markOffline(user));
    }
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

  bool _isMatchingActiveOrder(Map<String, dynamic> data) {
    final orderType = (data['vehicleType'] ?? data['type'])
        ?.toString()
        .trim()
        .toLowerCase();
    return _isOnline &&
        data['status']?.toString() == 'active' &&
        orderType == _vehicleType?.toLowerCase();
  }

  bool _isVisibleOrder(Map<String, dynamic> data) {
    return _hasAccess && _isMatchingActiveOrder(data);
  }

  bool _profileHasAccess(Map<String, dynamic>? profile) {
    final freeOrdersLeft = (profile?['freeOrdersLeft'] as num?)?.toInt() ?? 0;
    final value = profile?['subscriptionEndsAt'];
    final subscriptionEndsAt = value is Timestamp
        ? value.toDate()
        : value is DateTime
            ? value
            : DateTime.tryParse(value?.toString() ?? '');
    return freeOrdersLeft > 0 ||
        (subscriptionEndsAt != null && subscriptionEndsAt.isAfter(DateTime.now()));
  }

  void _ensureOnlineStatus(User user, Map<String, dynamic>? profile) {
    if (_onlineInitializedUid == user.uid) return;
    _onlineInitializedUid = user.uid;
    final savedStatus = profile?['isOnline'];
    if (savedStatus is bool) {
      _isOnline = savedStatus;
      return;
    }
    _isOnline = true;
    unawaited(
      FirebaseFirestore.instance.collection('drivers').doc(user.uid).set({
        'driverId': user.uid,
        'isOnline': true,
        'onlineUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)),
    );
  }

  Future<void> _ensureForegroundServiceStarted(User user) async {
    if (_foregroundServiceUid == user.uid || _startingForegroundService) return;
    _startingForegroundService = true;
    final failure = await ForegroundLocationService.start(user.uid);
    if (!mounted) return;
    _startingForegroundService = false;
    if (failure != null) {
      await _showForegroundServiceFailure(failure);
      await _writeOnlineStatus(false, user);
      return;
    }
    setState(() => _foregroundServiceUid = user.uid);
  }

  Future<void> _showForegroundServiceFailure(
    ForegroundLocationStartFailure failure,
  ) async {
    if (!mounted) return;
    final needsBatterySettings =
        failure == ForegroundLocationStartFailure.batteryOptimization;
    final needsAppSettings = !needsBatterySettings;
    final message = switch (failure) {
      ForegroundLocationStartFailure.backgroundLocationPermission => 'Чтобы получать заявки при выключенном экране, разрешите для ТехЗаказ доступ к геопозиции «Всегда» в настройках приложения.',
      ForegroundLocationStartFailure.locationPermission => 'Без доступа к геопозиции приложение не сможет находить заявки рядом с вами. Включите GPS и разрешение для ТехЗаказ.',
      ForegroundLocationStartFailure.batteryOptimization => 'Чтобы координаты обновлялись при выключенном экране, разрешите ТехЗаказ работать без ограничений батареи.',
      ForegroundLocationStartFailure.notificationPermission => 'Постоянное уведомление нужно Android для фоновой геолокации. Разрешите уведомления для ТехЗаказ.',
      ForegroundLocationStartFailure.serviceStart => 'Не удалось запустить фоновое отслеживание. Проверьте разрешения и попробуйте ещё раз.',
    };
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Нужен доступ для режима «На линии»'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Позже'),
          ),
          if (needsAppSettings || needsBatterySettings)
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                if (needsBatterySettings) {
                  unawaited(
                    FlutterForegroundTask.openIgnoreBatteryOptimizationSettings(),
                  );
                } else {
                  unawaited(Geolocator.openAppSettings());
                }
              },
              child: const Text('Открыть настройки'),
            ),
        ],
      ),
    );
  }

  Future<void> _writeOnlineStatus(bool value, User user) async {
    await FirebaseFirestore.instance.collection('drivers').doc(user.uid).set({
      'driverId': user.uid,
      'isOnline': value,
      'onlineUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _setOnlineStatus(bool value) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _savingOnline) return;
    setState(() {
      _savingOnline = true;
    });
    try {
      if (value) {
        final failure = await ForegroundLocationService.start(user.uid);
        if (failure != null) {
          await _showForegroundServiceFailure(failure);
          return;
        }
        _foregroundServiceUid = user.uid;
      } else {
        final stopped = await ForegroundLocationService.stop();
        if (!stopped) {
          throw StateError('Не удалось остановить фоновую геолокацию');
        }
        _foregroundServiceUid = null;
      }
      await _writeOnlineStatus(value, user);
      if (mounted) setState(() => _isOnline = value);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось изменить статус: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingOnline = false);
    }
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
    final driverRef = FirebaseFirestore.instance
        .collection('drivers')
        .doc(driver.uid);
    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(orderRef);
        final driverSnapshot = await transaction.get(driverRef);
        final data = snapshot.data();
        final driverData = driverSnapshot.data();
        if (data == null) throw StateError('Заявка не найдена.');

        final currentStatus = data['status']?.toString() ?? 'active';
        if (currentStatus != 'active') {
          throw StateError('Эту заявку уже взял другой водитель.');
        }

        final freeOrdersLeft =
            (driverData?['freeOrdersLeft'] as num?)?.toInt() ?? 0;
        final subscriptionValue = driverData?['subscriptionEndsAt'];
        final subscriptionEndsAt = subscriptionValue is Timestamp
            ? subscriptionValue.toDate()
            : subscriptionValue is DateTime
                ? subscriptionValue
                : DateTime.tryParse(subscriptionValue?.toString() ?? '');
        final hasSubscription = subscriptionEndsAt != null &&
            subscriptionEndsAt.isAfter(DateTime.now());
        if (!hasSubscription && freeOrdersLeft <= 0) {
          throw StateError(
            'Бесплатные заявки закончились. Оформите подписку, чтобы брать заказы.',
          );
        }

        transaction.update(orderRef, {
          'status': 'in_progress',
          'driverId': driver.uid,
          'startedAt': FieldValue.serverTimestamp(),
        });
        if (!hasSubscription) {
          transaction.update(driverRef, {
            'freeOrdersLeft': freeOrdersLeft - 1,
          });
        }
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
          'lastDriverId': driver.uid,
          'declinedAt': FieldValue.serverTimestamp(),
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

  Future<void> _showOrderSheet(String orderId, Map<String, dynamic> data) async {
    final driver = FirebaseAuth.instance.currentUser;
    if (driver == null) return;

    Map<String, dynamic> profile;
    try {
      final profileSnapshot = await FirebaseFirestore.instance
          .collection('drivers')
          .doc(driver.uid)
          .get();
      profile = profileSnapshot.data() ?? <String, dynamic>{};
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось проверить доступ к заявке.')),
        );
      }
      return;
    }

    final freeOrdersLeft = (profile['freeOrdersLeft'] as num?)?.toInt() ?? 0;
    final subscriptionValue = profile['subscriptionEndsAt'];
    final subscriptionEndsAt = subscriptionValue is Timestamp
        ? subscriptionValue.toDate()
        : subscriptionValue is DateTime
            ? subscriptionValue
            : DateTime.tryParse(subscriptionValue?.toString() ?? '');
    final hasAccess = freeOrdersLeft > 0 ||
        (subscriptionEndsAt != null &&
            subscriptionEndsAt.isAfter(DateTime.now()));

    final type = data['type']?.toString() ?? 'Спецтехника';
    final phone = data['phone']?.toString() ?? 'не указан';
    final address = data['address']?.toString() ?? 'Адрес не указан';
    final destination = data['destinationAddress']?.toString();
    final status = data['status']?.toString() ?? 'active';
    final lat = _asDouble(data['lat']);
    final lon = _asDouble(data['lon']);
    final comment = data['comment']?.toString() ?? '';
    const maskedPhone = '+7 (***) ***-**-** 🔒';

    if (!mounted) return;
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
                      Expanded(
                        child: Text(
                          hasAccess ? 'Активная заявка' : 'Заявка доступна по подписке',
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
                            value: hasAccess ? phone : maskedPhone,
                            valueColor: hasAccess ? null : Colors.white38,
                          ),
                          _InfoRow(
                            icon: Icons.location_on_outlined,
                            label: 'Адрес',
                            value: hasAccess ? address : 'Точный адрес скрыт 🔒',
                            valueColor: hasAccess ? null : Colors.white38,
                          ),
                          if (hasAccess && destination != null && destination.isNotEmpty)
                            _InfoRow(
                              icon: Icons.flag_outlined,
                              label: 'Точка Б',
                              value: destination,
                            ),
                          if (hasAccess && lat != null && lon != null)
                            _InfoRow(
                              icon: Icons.gps_fixed,
                              label: 'Координаты',
                              value:
                                  '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}',
                            ),
                          if (hasAccess && comment.isNotEmpty)
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
                  if (!hasAccess)
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Модуль оплаты находится в разработке')),
                          );
                        },
                        icon: const Icon(Icons.lock_open_rounded),
                        label: const Text('Открыть контакты (Оплатить подписку)'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFF3C622),
                          foregroundColor: const Color(0xFF11120E),
                        ),
                      ),
                    )
                  else if (status == 'active')
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: () => _takeOrder(orderId),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(
                          freeOrdersLeft > 0
                              ? 'Взять в работу (осталось бесплатных: $freeOrdersLeft)'
                              : 'Взять в работу',
                        ),
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

  void _showInstructions() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF171914),
        title: const Text('Как брать заказы'),
        content: const Text(
          'Включите «На линии», откройте подходящую заявку на карте, свяжитесь с клиентом и нажмите «Взять в работу». После согласования нажмите «Выехал на заказ».',
          style: TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Понятно')),
        ],
      ),
    );
  }

  void _showAccessPaywall() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Модуль оплаты находится в разработке')),
      );
  }

  DateTime? _cooldownUntil(Map<String, dynamic>? data) {
    final value = data?['cooldownUntil'];
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  DateTime? _dateFromValue(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.tryParse(value?.toString() ?? '');
  }

  String _formatRemaining(Duration duration) {
    final totalSeconds = duration.inSeconds.clamp(0, 359999);
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatElapsed(Duration duration) {
    final safeSeconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
    final hours = safeSeconds ~/ 3600;
    final minutes = (safeSeconds % 3600) ~/ 60;
    final seconds = safeSeconds % 60;
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

  Future<void> _showActiveOrdersSheet() async {
    try {
      final snapshot = await _ordersQuery.get();
      final orders = snapshot.docs
          .where((document) => _isMatchingActiveOrder(document.data()))
          .toList();
      if (!mounted) return;
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: const Color(0xFF171914),
        showDragHandle: true,
        useSafeArea: true,
        builder: (sheetContext) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * 0.65,
            child: orders.isEmpty
                ? const Center(
                    child: Text('Подходящих активных заявок сейчас нет.', style: TextStyle(color: Colors.white60)),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                    itemCount: orders.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, index) {
                      final document = orders[index];
                      final data = document.data();
                      return ListTile(
                        tileColor: const Color(0xFF22241D),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        leading: const CircleAvatar(backgroundColor: Color(0xFFF3C622), foregroundColor: Colors.black, child: Icon(Icons.construction)),
                        title: Text(data['type']?.toString() ?? 'Спецтехника', style: const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text(
                          _hasAccess
                              ? (data['address']?.toString() ?? 'Адрес не указан')
                              : 'Контакты доступны по подписке 🔒',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white60),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _showOrderSheet(document.id, data);
                        },
                      );
                    },
                  ),
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось загрузить активные заявки.')),
        );
      }
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
    final workStartedAt = _dateFromValue(order?['startedAt']) ??
        _dateFromValue(order?['acceptedAt']);
    final elapsed = workStartedAt == null
        ? null
        : DateTime.now().difference(workStartedAt);
    final orderMarker = _currentOrderMarker(order);
    return Scaffold(
      backgroundColor: const Color(0xFF0B0C0A),
      drawer: DriverDrawer(onInstructions: _showInstructions),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: const Color(0xFF0B0C0A),
        title: const Row(
          children: [
            Icon(Icons.construction, color: Color(0xFFF3C622)),
            SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ТехЗаказ', style: TextStyle(fontWeight: FontWeight.w800)),
                Text('В РЕЙСЕ', style: TextStyle(color: Color(0xFFF3C622), fontSize: 10, letterSpacing: 1.5)),
              ],
            ),
          ],
        ),
        actions: [
          Builder(builder: (context) => IconButton(onPressed: () => Scaffold.of(context).openDrawer(), tooltip: 'Меню', icon: const Icon(Icons.menu_rounded))),
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
                      if (elapsed != null)
                        _CompactInfoRow(
                          icon: Icons.timer_outlined,
                          text: 'Время работы: ${_formatElapsed(elapsed)}',
                        ),
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
        if (driverSnapshot.hasData) {
          _ensureOnlineStatus(user, profile);
          _hasAccess = _profileHasAccess(profile);
        }
        final savedOnline = profile?['isOnline'];
        if (savedOnline is bool && savedOnline != _isOnline && !_savingOnline) {
          _isOnline = savedOnline;
        }
        if (savedOnline == true) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(_ensureForegroundServiceStarted(user));
          });
        } else if (savedOnline == false && _foregroundServiceUid == user.uid) {
          _foregroundServiceUid = null;
          unawaited(ForegroundLocationService.stop());
        }
        // Тип техники уже выбирается во время регистрации профиля.
        // Поддерживаем оба поля для совместимости со старыми профилями.
        final savedVehicleType = (profile?['vehicleType'] ?? profile?['equipmentType'])
            ?.toString()
            .trim()
            .toLowerCase();
        if (savedVehicleType != null && savedVehicleType.isNotEmpty &&
            _vehicleType != savedVehicleType) {
          _vehicleType = savedVehicleType;
        }
        final cooldownUntil = _cooldownUntil(driverSnapshot.data?.data());
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: currentOrderQuery.snapshots(),
          builder: (context, orderSnapshot) {
            final hasCooldown =
                cooldownUntil != null && cooldownUntil.isAfter(DateTime.now());
            _suppressOrderNotifications = hasCooldown ||
                (orderSnapshot.hasData && orderSnapshot.data!.docs.isNotEmpty);
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
            return _buildRadar(isOnline: _isOnline);
          },
        );
      },
    );
  }

  Widget _buildRadar({required bool isOnline}) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0C0A),
      drawer: DriverDrawer(onInstructions: _showInstructions),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: const Color(0xFF0B0C0A),
        title: const Row(
          children: [
            Icon(Icons.construction, color: Color(0xFFF3C622)),
            SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ТехЗаказ', style: TextStyle(fontWeight: FontWeight.w800)),
                Text('РАДАР ЗАЯВОК', style: TextStyle(color: Color(0xFFF3C622), fontSize: 10, letterSpacing: 1.5)),
              ],
            ),
          ],
        ),
        actions: [
          Builder(builder: (context) => IconButton(onPressed: () => Scaffold.of(context).openDrawer(), tooltip: 'Меню', icon: const Icon(Icons.menu_rounded))),
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
                  label: _isLocating
                      ? 'Определяем позицию'
                      : isOnline
                      ? 'Вы на линии'
                      : 'Не на линии',
                  color: _isLocating
                      ? Colors.orange
                      : isOnline
                      ? Colors.greenAccent
                      : Colors.redAccent,
                ),
                const Spacer(),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xEE171914),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white12),
                  ),
                  padding: const EdgeInsets.only(left: 8, right: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isOnline ? 'На линии' : 'Оффлайн',
                        style: TextStyle(
                          color: isOnline ? Colors.greenAccent : Colors.white54,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(
                        width: 42,
                        height: 32,
                        child: _savingOnline
                            ? const Padding(
                                padding: EdgeInsets.all(9),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFFF3C622),
                                ),
                              )
                            : Switch.adaptive(
                                value: isOnline,
                                onChanged: _setOnlineStatus,
                                activeThumbColor: const Color(0xFFF3C622),
                              ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _ordersQuery.snapshots(),
                  builder: (context, snapshot) {
                    final count =
                        snapshot.data?.docs
                            .where(
                              (document) => _isMatchingActiveOrder(document.data()),
                            )
                            .length ??
                        0;
                    return InkWell(
                      onTap: _showActiveOrdersSheet,
                      borderRadius: BorderRadius.circular(20),
                      child: _StatusChip(
                        icon: Icons.notifications_active_outlined,
                        label: '$count заявок',
                        color: const Color(0xFFF3C622),
                      ),
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
          if (isOnline && !_hasAccess)
            Positioned(
              left: 16,
              right: 16,
              bottom: 76,
              child: SafeArea(
                bottom: true,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
                  decoration: BoxDecoration(
                    color: const Color(0xF5171914),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xFFF3C622).withValues(alpha: 0.65),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_outline_rounded, color: Color(0xFFF3C622), size: 26),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Рядом есть заявки, но доступ к контактам закрыт.',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, height: 1.25),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: _showAccessPaywall,
                        style: TextButton.styleFrom(foregroundColor: const Color(0xFFF3C622)),
                        child: const Text('Получить доступ'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (!isOnline)
            Positioned(
              left: 16,
              right: 16,
              bottom: 20,
              child: SafeArea(
                bottom: true,
                child: _MapMessage(
                  message: 'Вы не на линии. Новые заказы не поступают.',
                ),
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
            bottom: _locationMessage == null && isOnline ? 24 : 92,
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
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

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
                  style: TextStyle(color: valueColor ?? Colors.white, fontSize: 15),
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
