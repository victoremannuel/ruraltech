import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/firebase_service.dart';
import '../services/gateway_service.dart';
import 'device_details_screen.dart';
import 'events_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final fb = context.read<FirebaseService>();
    final gateway = context.watch<GatewayService>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard RuralTech'),
        actions: [
          IconButton(icon: const Icon(Icons.wifi), onPressed: gateway.connect),
          IconButton(icon: const Icon(Icons.list), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EventsScreen()))),
          IconButton(icon: const Icon(Icons.logout), onPressed: () => context.read<AuthService>().signOut()),
        ],
      ),
      body: StreamBuilder(
        stream: fb.streamDevices(),
        builder: (context, snapshot) {
          final devices = snapshot.data ?? [];
          return ListView.builder(
            itemCount: devices.length,
            itemBuilder: (_, i) => ListTile(
              title: Text(devices[i].name),
              subtitle: Text('Status: ${devices[i].status}'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DeviceDetailsScreen(device: devices[i]))),
            ),
          );
        },
      ),
    );
  }
}
