import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';

class PushNotificationService {
  PushNotificationService._();

  static final instance = PushNotificationService._();

  final _messaging = FirebaseMessaging.instance;
  final _firestore = FirebaseFirestore.instance;
  final _localNotifications = FlutterLocalNotificationsPlugin();
  StreamSubscription<String>? _tokenSubscription;
  String? _initializedUid;
  bool _localNotificationsInitialized = false;

  Stream<RemoteMessage> get foregroundMessages => FirebaseMessaging.onMessage;

  Future<bool> initializeForUser(User user) async {
    if (_initializedUid == user.uid) return true;
    await _tokenSubscription?.cancel();
    _tokenSubscription = null;

    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('FCM permission denied for ${user.uid}');
      return false;
    }

    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
    await _initializeLocalNotifications();
    final androidImplementation = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidImplementation?.requestNotificationsPermission();

    final token = await _messaging.getToken();
    if (token == null || token.isEmpty) {
      debugPrint('FCM token is empty for ${user.uid}');
      return false;
    }
    await _saveToken(user.uid, token);

    _tokenSubscription = _messaging.onTokenRefresh.listen(
      (token) => _saveToken(user.uid, token),
    );
    _initializedUid = user.uid;
    debugPrint('FCM registered for ${user.uid}: ${token.substring(0, 12)}...');
    return true;
  }

  Future<void> _initializeLocalNotifications() async {
    if (_localNotificationsInitialized) return;

    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _localNotifications.initialize(settings: initializationSettings);
    final androidImplementation = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidImplementation?.createNotificationChannel(
      const AndroidNotificationChannel(
        'orders',
        'Новые заявки',
        description: 'Уведомления о новых заявках рядом с водителем',
        importance: Importance.max,
        playSound: true,
      ),
    );
    _localNotificationsInitialized = true;
  }

  Future<void> showForegroundNotification(RemoteMessage message) async {
    await _initializeLocalNotifications();
    final notification = message.notification;
    final title =
        notification?.title ??
        message.data['title']?.toString() ??
        'Новая заявка рядом';
    final body =
        notification?.body ??
        message.data['body']?.toString() ??
        'Проверьте Радар заявок';
    await _localNotifications.show(
      id: message.hashCode,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'orders',
          'Новые заявки',
          channelDescription: 'Уведомления о новых заявках рядом с водителем',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        ),
      ),
      payload: message.data['orderId']?.toString(),
    );
  }

  Future<void> updateDriverLocation({
    required User user,
    required double latitude,
    required double longitude,
  }) async {
    await _firestore.collection('drivers').doc(user.uid).set({
      'driverId': user.uid,
      'fcmToken': await _messaging.getToken(),
      'lat': latitude,
      'lon': longitude,
      'locationUpdatedAt': FieldValue.serverTimestamp(),
      'isOnline': true,
    }, SetOptions(merge: true));
  }

  Future<void> markOffline(User user) async {
    await _firestore.collection('drivers').doc(user.uid).set({
      'isOnline': false,
      'locationUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _saveToken(String uid, String token) async {
    await _firestore.collection('drivers').doc(uid).set({
      'driverId': uid,
      'fcmToken': token,
      'isOnline': true,
      'tokenUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> dispose() async {
    await _tokenSubscription?.cancel();
    _tokenSubscription = null;
    _initializedUid = null;
    _localNotificationsInitialized = false;
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}
