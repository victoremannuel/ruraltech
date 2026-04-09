import 'package:flutter/material.dart';

import 'firebase_service.dart';

class RemoteMessage {
  const RemoteMessage({
    this.data = const <String, dynamic>{},
  });

  final Map<String, dynamic> data;
}

class NotificationService extends ChangeNotifier {
  RemoteMessage? _lastForegroundMessage;

  RemoteMessage? get lastForegroundMessage => _lastForegroundMessage;

  Future<void> initialize({
    required String uid,
    required FirebaseService firebase,
  }) async {
    // O transporte nativo de push sera conectado sobre tokens salvos no Supabase.
    // Por enquanto a inicializacao nao bloqueia o bootstrap do app.
    final userId = uid;
    final firebaseService = firebase;
    if (userId.isEmpty) return;
    firebaseService.hashCode;
  }
}
