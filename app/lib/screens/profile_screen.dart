import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/device_model.dart';
import '../services/auth_service.dart';
import '../services/firebase_service.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final fb = context.read<FirebaseService>();
    final uid = auth.user?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: fb.streamRuralProperties(uid: uid, isAdmin: auth.isAdmin),
        builder: (context, propSnap) {
          final properties = propSnap.data ?? const [];
          final propertyIds = properties.map((e) => e['id'].toString()).toSet();

          return StreamBuilder<List<DeviceModel>>(
            stream: fb.streamDevices(uid: uid, isAdmin: auth.isAdmin),
            builder: (context, deviceSnap) {
              final devices = deviceSnap.data ?? const <DeviceModel>[];
              final deviceCount = devices
                  .where((d) =>
                      propertyIds.isEmpty ||
                      propertyIds.contains((d.propertyId ?? '').toString()))
                  .length;

              return StreamBuilder<List<Map<String, dynamic>>>(
                stream: fb.streamGateways(uid: uid, isAdmin: auth.isAdmin),
                builder: (context, gatewaySnap) {
                  final gateways = gatewaySnap.data ?? const [];
                  final gatewayCount = gateways
                      .where(
                        (g) =>
                            propertyIds.isEmpty ||
                            propertyIds
                                .contains((g['propertyId'] ?? '').toString()),
                      )
                      .length;

                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.person),
                          title: Text(auth.user?.email ?? 'Sem email'),
                          subtitle: Text('Perfil: ${auth.role}'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.landscape),
                          title: const Text('Propriedades rurais vinculadas'),
                          trailing: Text('${properties.length}'),
                        ),
                      ),
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.pets),
                          title: const Text('Coleiras vinculadas'),
                          trailing: Text('$deviceCount'),
                        ),
                      ),
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.wifi),
                          title: const Text('Gateways vinculados'),
                          trailing: Text('$gatewayCount'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Resumo em tempo real de recursos vinculados as propriedades rurais visiveis para seu perfil.',
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
