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
      body: gateway.messages.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Sem eventos recebidos ainda.',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      gateway.lastError == null
                          ? 'Toque no icone de Wi-Fi no dashboard para conectar ao gateway.'
                          : 'Falha na conexao com o gateway:\n${gateway.lastError}',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              itemCount: gateway.messages.length,
              itemBuilder: (_, i) => ListTile(
                title: Text(gateway.messages[i]['type']?.toString() ?? 'msg'),
                subtitle: Text(gateway.messages[i].toString()),
              ),
            ),
    );
  }
}
