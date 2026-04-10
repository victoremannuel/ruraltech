import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'firebase_service.dart';

class RemoteMessage {
  const RemoteMessage({
    this.data = const <String, dynamic>{},
  });

  final Map<String, dynamic> data;
}

class NotificationService extends ChangeNotifier {
  static const _channel = MethodChannel('com.victor.ruraltechapp/push');

  RemoteMessage? _lastForegroundMessage;
  String? _currentToken;
  RemoteMessage? get lastForegroundMessage => _lastForegroundMessage;
  String? get currentToken => _currentToken;

  Future<void> initialize({
    required String uid,
    required FirebaseService firebase,
  }) async {
    if (uid.isEmpty) return;

    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onTokenRefresh':
          final newToken = call.arguments as String?;
          if (newToken != null && newToken.isNotEmpty) {
            _currentToken = newToken;
            await _registerToken(uid: uid, token: newToken, firebase: firebase);
          }
        case 'onMessage':
          final payload = call.arguments;
          final data = payload is Map
              ? Map<String, dynamic>.from(payload)
              : <String, dynamic>{};
          _lastForegroundMessage = RemoteMessage(data: data);
          notifyListeners();
      }
    });

    try {
      final token = await _channel.invokeMethod<String>('getToken');
      if (token != null && token.isNotEmpty) {
        _currentToken = token;
        await _registerToken(uid: uid, token: token, firebase: firebase);
      }
    } on MissingPluginException {
      debugPrint('Push: canal nativo nao disponivel nesta plataforma.');
    } catch (e) {
      debugPrint('Push: erro ao obter token: $e');
    }
  }

  Future<void> _registerToken({
    required String uid,
    required String token,
    required FirebaseService firebase,
  }) async {
    try {
      final platform = Platform.isIOS ? 'ios' : 'android';
      await firebase.registerPushToken(uid: uid, token: token, platform: platform);
    } catch (e) {
      debugPrint('Push: erro ao registrar token: $e');
    }
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }
}
