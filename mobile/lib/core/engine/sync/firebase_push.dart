import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'push_service.dart';

class FirebasePushPlatform implements PushPlatform {
  FirebasePushPlatform._(this._messaging);

  final FirebaseMessaging _messaging;

  static Future<FirebasePushPlatform?> start() async {
    try {
      await Firebase.initializeApp();
      return FirebasePushPlatform._(FirebaseMessaging.instance);
    } catch (_) {
      return null;
    }
  }

  static bool _granted(NotificationSettings settings) =>
      settings.authorizationStatus == AuthorizationStatus.authorized ||
      settings.authorizationStatus == AuthorizationStatus.provisional;

  @override
  Future<bool> isAllowed() async {
    try {
      return _granted(await _messaging.getNotificationSettings());
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      return _granted(await _messaging.requestPermission());
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> address() async {
    try {
      final registered = _messaging.onRegistered.first.timeout(const Duration(seconds: 30));
      await _messaging.register();
      return await registered;
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<String> get addressChanges => _messaging.onRegistered;

  @override
  Stream<void> get rings => FirebaseMessaging.onMessage.map((_) {});
}
