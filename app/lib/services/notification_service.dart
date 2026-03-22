import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'firebase_service.dart';

class NotificationService extends ChangeNotifier {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  StreamSubscription<String>? _tokenSub;
  StreamSubscription<RemoteMessage>? _messageSub;
  bool _initialized = false;
  String? _currentUid;
  RemoteMessage? _lastForegroundMessage;

  RemoteMessage? get lastForegroundMessage => _lastForegroundMessage;

  Future<void> initialize({
    required String uid,
    required FirebaseService firebase,
  }) async {
    if (_initialized && _currentUid == uid) return;

    _currentUid = uid;
    _initialized = true;

    try {
      await _messaging.setAutoInitEnabled(true);
      await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      final token = await _messaging.getToken();
      if (token != null && token.trim().isNotEmpty) {
        await firebase.registerPushToken(uid: uid, token: token.trim());
      }

      await _tokenSub?.cancel();
      _tokenSub = FirebaseMessaging.instance.onTokenRefresh.listen((token) {
        final currentUid = _currentUid;
        if (currentUid == null || token.trim().isEmpty) return;
        unawaited(
          firebase.registerPushToken(uid: currentUid, token: token.trim()),
        );
      });

      await _messageSub?.cancel();
      _messageSub = FirebaseMessaging.onMessage.listen((message) {
        _lastForegroundMessage = message;
        notifyListeners();
      });
    } catch (_) {
      // Push registration is best-effort to avoid blocking the app bootstrap.
    }
  }

  @override
  void dispose() {
    _tokenSub?.cancel();
    _messageSub?.cancel();
    super.dispose();
  }
}
