import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/gateway_service.dart';

class EventsScreen extends StatelessWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final gateway = context.watch<GatewayService>();
    return Scaffold(
      appBar: AppBar(title: const Text('Eventos e Telemetria')),
      body: ListView.builder(
        itemCount: gateway.messages.length,
        itemBuilder: (_, i) => ListTile(title: Text(gateway.messages[i]['type']?.toString() ?? 'msg'), subtitle: Text(gateway.messages[i].toString())),
      ),
    );
  }
}
