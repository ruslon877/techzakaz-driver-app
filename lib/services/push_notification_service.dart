import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class PushNotificationService {
  PushNotificationService._();

  static final instance = PushNotificationService._();

  final _messaging = FirebaseMessaging.instance;
  final _firestore = FirebaseFirestore.instance;
  StreamSubscription<String>? _tokenSubscription;
  String? _initializedUid;

  Stream<RemoteMessage> get foregroundMessages => FirebaseMessaging.onMessage;

  Future<void> initializeForUser(User user) async {
    if (_initializedUid == user.uid) return;
    await _tokenSubscription?.cancel();
    _tokenSubscription = null;

    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    final token = await _messaging.getToken();
    if (token != null) await _saveToken(user.uid, token);

    _tokenSubscription = _messaging.onTokenRefresh.listen((token) => _saveToken(user.uid, token));
    _initializedUid = user.uid;
  }

  Future<void> updateDriverLocation({required User user, required double latitude, required double longitude}) async {
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
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}
