import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';

const _locationTaskIntervalMs = 45 * 1000;

@pragma('vm:entry-point')
void startLocationCallback() {
  FlutterForegroundTask.setTaskHandler(LocationTaskHandler());
}

class LocationTaskHandler extends TaskHandler {
  String? _driverUid;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    try {
      await Firebase.initializeApp();
    } catch (_) {
      // Firebase may already be initialized when the isolate is reused.
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    unawaited(_updateLocation());
  }

  Future<void> _updateLocation() async {
    final uid = _driverUid;
    if (uid == null || uid.isEmpty) return;

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
      await FirebaseFirestore.instance.collection('drivers').doc(uid).set({
        'lat': position.latitude,
        'lon': position.longitude,
        'locationUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      FlutterForegroundTask.sendDataToMain({
        'lat': position.latitude,
        'lon': position.longitude,
        'timestampMillis': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (_) {
      // The foreground task must stay alive if a single GPS read fails.
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onReceiveData(Object data) {
    if (data is Map && data['uid'] is String) {
      _driverUid = data['uid'] as String;
    }
  }
}

enum ForegroundLocationStartFailure {
  notificationPermission,
  locationPermission,
  backgroundLocationPermission,
  batteryOptimization,
  serviceStart,
}

class ForegroundLocationService {
  ForegroundLocationService._();

  static void initialize() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'foreground_location',
        channelName: 'Фоновая геолокация',
        channelDescription: 'Показывает, что ТехЗаказ ищет заявки рядом.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        enableVibration: false,
        playSound: false,
        showWhen: false,
        showBadge: false,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(_locationTaskIntervalMs),
        allowWakeLock: true,
        allowWifiLock: false,
        allowAutoRestart: true,
        stopWithTask: false,
      ),
    );
  }

  static Future<ForegroundLocationStartFailure?> start(String uid) async {
    final notificationPermission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermission != NotificationPermission.granted) {
      final result =
          await FlutterForegroundTask.requestNotificationPermission();
      if (result != NotificationPermission.granted) {
        return ForegroundLocationStartFailure.notificationPermission;
      }
    }

    var locationPermission = await Geolocator.checkPermission();
    if (locationPermission == LocationPermission.denied) {
      locationPermission = await Geolocator.requestPermission();
    }
    if (locationPermission == LocationPermission.denied ||
        locationPermission == LocationPermission.deniedForever) {
      return ForegroundLocationStartFailure.locationPermission;
    }

    if (locationPermission != LocationPermission.always) {
      return ForegroundLocationStartFailure.backgroundLocationPermission;
    }

    if (!await Geolocator.isLocationServiceEnabled()) {
      return ForegroundLocationStartFailure.locationPermission;
    }

    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      final accepted =
          await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      if (!accepted &&
          !await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        return ForegroundLocationStartFailure.batteryOptimization;
      }
    }

    if (await FlutterForegroundTask.isRunningService) {
      FlutterForegroundTask.sendDataToTask({'uid': uid});
      return null;
    }

    final result = await FlutterForegroundTask.startService(
      serviceId: 4101,
      serviceTypes: [ForegroundServiceTypes.location],
      notificationTitle: 'ТехЗаказ',
      notificationText: 'Поиск заявок рядом...',
      callback: startLocationCallback,
    );
    if (result is! ServiceRequestSuccess) {
      return ForegroundLocationStartFailure.serviceStart;
    }

    FlutterForegroundTask.sendDataToTask({'uid': uid});
    return null;
  }

  static Future<bool> stop() async {
    if (!await FlutterForegroundTask.isRunningService) return true;
    final result = await FlutterForegroundTask.stopService();
    return result is ServiceRequestSuccess;
  }
}
