import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'cloud_service.dart';

class RemoteMessage {
  const RemoteMessage({
    this.data = const <String, dynamic>{},
  });

  final Map<String, dynamic> data;
}

class NotificationService extends ChangeNotifier {
  static const _channel = MethodChannel('com.victor.ruraltechapp/push');

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  RemoteMessage? _lastForegroundMessage;
  String? _currentToken;

  RemoteMessage? get lastForegroundMessage => _lastForegroundMessage;
  String? get currentToken => _currentToken;

  StreamSubscription<List<Map<String, dynamic>>>? _realtimeSub;

  Future<void> initialize({
    required String uid,
    required CloudService cloud,
  }) async {
    if (uid.isEmpty) return;

    await _initLocalNotifications();

    // iOS APNs: capturar token via canal nativo
    if (Platform.isIOS) {
      _channel.setMethodCallHandler((call) async {
        switch (call.method) {
          case 'onTokenRefresh':
            final newToken = call.arguments as String?;
            if (newToken != null && newToken.isNotEmpty) {
              _currentToken = newToken;
              await cloud.registerPushToken(
                uid: uid,
                token: newToken,
                platform: 'ios',
              );
            }
          case 'onMessage':
            final payload = call.arguments;
            final data = payload is Map
                ? Map<String, dynamic>.from(payload)
                : <String, dynamic>{};
            _handleIncomingData(data);
        }
      });

      try {
        final token = await _channel.invokeMethod<String>('getToken');
        if (token != null && token.isNotEmpty) {
          _currentToken = token;
          await cloud.registerPushToken(
            uid: uid,
            token: token,
            platform: 'ios',
          );
        }
      } on MissingPluginException {
        debugPrint('Push: canal nativo iOS nao disponivel.');
      } catch (e) {
        debugPrint('Push: erro ao obter token APNs: $e');
      }
    } else {
      // Android: UUID estável como device ID
      try {
        final deviceId = await _channel.invokeMethod<String>('getToken');
        if (deviceId != null && deviceId.isNotEmpty) {
          _currentToken = deviceId;
          await cloud.registerPushToken(
            uid: uid,
            token: deviceId,
            platform: 'android',
          );
        }
      } on MissingPluginException {
        debugPrint('Push: canal nativo Android nao disponivel.');
      } catch (e) {
        debugPrint('Push: erro ao obter device ID: $e');
      }
    }

    // Supabase Realtime: inscrever em pending_notifications filtrado por legacy_uid
    _subscribeRealtime(uid);
  }

  void _subscribeRealtime(String uid) {
    try {
      final stream = Supabase.instance.client
          .from('pending_notifications')
          .stream(primaryKey: ['id'])
          .eq('legacy_uid', uid)
          .order('created_at', ascending: false)
          .limit(20);

      _realtimeSub = stream.listen((rows) {
        for (final row in rows) {
          if (row['delivered'] == true) continue;
          _showLocalNotification(
            title: row['title'] as String? ?? '',
            body: row['body'] as String? ?? '',
            data: row['data'] is Map
                ? Map<String, dynamic>.from(row['data'] as Map)
                : <String, dynamic>{},
          );
          // Marcar como entregue
          Supabase.instance.client
              .from('pending_notifications')
              .update({'delivered': true}).eq('id', row['id'] as String).then(
            (_) {},
            onError: (e) =>
                debugPrint('Push: erro ao marcar delivered: $e'),
          );
        }
      });
    } catch (e) {
      debugPrint('Push: erro ao inscrever Realtime: $e');
    }
  }

  void _handleIncomingData(Map<String, dynamic> data) {
    _lastForegroundMessage = RemoteMessage(data: data);
    notifyListeners();
    if (data['title'] != null || data['body'] != null) {
      _showLocalNotification(
        title: data['title'] as String? ?? '',
        body: data['body'] as String? ?? '',
        data: data,
      );
    }
  }

  Future<void> _initLocalNotifications() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
    );
    await _localNotifications.initialize(settings);

    // Solicitar permissão de notificação no Android 13+
    if (Platform.isAndroid) {
      final plugin = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await plugin?.requestNotificationsPermission();
    }
  }

  Future<void> _showLocalNotification({
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'ruraltech_push',
      'RuralTech',
      channelDescription: 'Notificacoes do RuralTech',
      importance: Importance.high,
      priority: Priority.high,
    );
    const darwinDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
    );
    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title.isEmpty ? 'RuralTech' : title,
      body.isEmpty ? null : body,
      details,
    );
    _lastForegroundMessage = RemoteMessage(data: data);
    notifyListeners();
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    _channel.setMethodCallHandler(null);
    super.dispose();
  }
}
