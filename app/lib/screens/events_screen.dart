import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/firebase_service.dart';

class EventsScreen extends StatelessWidget {
  const EventsScreen({super.key});

  String _subtitle(Map<String, dynamic> event) {
    final deviceId = (event['deviceId'] ?? '').toString();
    final eventType = (event['eventType'] ?? '').toString();
    final gatewayId = (event['gatewayId'] ?? '').toString();
    final parts = <String>[
      if (deviceId.isNotEmpty) 'Coleira $deviceId',
      if (eventType.isNotEmpty) eventType,
      if (gatewayId.isNotEmpty) 'GW $gatewayId',
    ];
    if (parts.isEmpty) return event.toString();
    return parts.join(' | ');
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final uid = auth.user?.uid;
    if (uid == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Eventos e Telemetria')),
        body: const Center(child: Text('Usuario nao autenticado.')),
      );
    }

    final fb = context.read<FirebaseService>();
    return Scaffold(
      appBar: AppBar(title: const Text('Eventos e Telemetria')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: fb.streamCriticalEvents(uid: uid, isAdmin: auth.isAdmin),
        builder: (context, snapshot) {
          final events = snapshot.data ?? const <Map<String, dynamic>>[];
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Falha ao carregar eventos do backend:\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting &&
              events.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (events.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Sem eventos persistidos ainda. Conecte ao gateway para receber novos eventos.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView.builder(
            itemCount: events.length,
            itemBuilder: (_, i) => ListTile(
              title: Text(events[i]['type']?.toString() ?? 'event'),
              subtitle: Text(_subtitle(events[i])),
            ),
          );
        },
      ),
    );
  }
}
