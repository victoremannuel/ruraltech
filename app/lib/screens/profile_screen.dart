import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/device_model.dart';
import '../services/auth_service.dart';
import '../services/firebase_service.dart';
import '../services/map_filter_service.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final filters = context.watch<MapFilterService>();
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

          return StreamBuilder<List<DeviceModel>>(
            stream: fb.streamDevices(uid: uid, isAdmin: auth.isAdmin),
            builder: (context, deviceSnap) {
              final devices = deviceSnap.data ?? const <DeviceModel>[];
              final deviceCount = devices.length;

              return StreamBuilder<List<Map<String, dynamic>>>(
                stream: fb.streamAreas(uid: uid, isAdmin: auth.isAdmin),
                builder: (context, areaSnap) {
                  final areas = areaSnap.data ?? const [];
                  final areaCount = areas.length;

                  return StreamBuilder<List<Map<String, dynamic>>>(
                    stream: fb.streamGateways(uid: uid, isAdmin: auth.isAdmin),
                    builder: (context, gatewaySnap) {
                      final gateways = gatewaySnap.data ?? const [];
                      final gatewayCount = gateways.length;

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
                            child: ExpansionTile(
                              leading: const Icon(Icons.landscape),
                              title:
                                  const Text('Selecionar propriedades no mapa'),
                              subtitle: Text(
                                filters.propertyIds.isEmpty
                                    ? 'Todas visiveis (${properties.length})'
                                    : '${filters.propertyIds.length} selecionada(s)',
                              ),
                              children: properties
                                  .map(
                                    (p) => CheckboxListTile(
                                      value: filters.isPropertySelected(
                                          p['id'].toString()),
                                      title: Text(
                                        (p['name'] ?? p['id']).toString(),
                                      ),
                                      onChanged: (v) => filters.toggleProperty(
                                        p['id'].toString(),
                                        v ?? false,
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                          Card(
                            child: ExpansionTile(
                              leading: const Icon(Icons.polyline),
                              title: const Text('Selecionar areas no mapa'),
                              subtitle: Text(
                                filters.areaIds.isEmpty
                                    ? 'Todas visiveis ($areaCount)'
                                    : '${filters.areaIds.length} selecionada(s)',
                              ),
                              children: areas
                                  .map(
                                    (a) => CheckboxListTile(
                                      value: filters
                                          .isAreaSelected(a['id'].toString()),
                                      title: Text(
                                        'Area ${a['id'].toString().substring(0, 6)}',
                                      ),
                                      subtitle: Text(
                                        'Prop: ${(a['propertyId'] ?? '-').toString()}',
                                      ),
                                      onChanged: (v) => filters.toggleArea(
                                        a['id'].toString(),
                                        v ?? false,
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                          Card(
                            child: ExpansionTile(
                              leading: const Icon(Icons.pets),
                              title: const Text('Selecionar coleiras no mapa'),
                              subtitle: Text(
                                filters.collarIds.isEmpty
                                    ? 'Todas visiveis ($deviceCount)'
                                    : '${filters.collarIds.length} selecionada(s)',
                              ),
                              children: devices
                                  .map(
                                    (d) => CheckboxListTile(
                                      value: filters.isCollarSelected(d.id),
                                      title: Text(d.name),
                                      subtitle: Text(d.id),
                                      onChanged: (v) => filters.toggleCollar(
                                          d.id, v ?? false),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                          Card(
                            child: ExpansionTile(
                              leading: const Icon(Icons.wifi),
                              title: const Text('Selecionar gateways no mapa'),
                              subtitle: Text(
                                filters.gatewayIds.isEmpty
                                    ? 'Todos visiveis ($gatewayCount)'
                                    : '${filters.gatewayIds.length} selecionado(s)',
                              ),
                              children: gateways
                                  .map(
                                    (g) => CheckboxListTile(
                                      value: filters.isGatewaySelected(
                                          g['id'].toString()),
                                      title: Text(
                                          (g['name'] ?? g['id']).toString()),
                                      subtitle: Text(g['id'].toString()),
                                      onChanged: (v) => filters.toggleGateway(
                                        g['id'].toString(),
                                        v ?? false,
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                          const SizedBox(height: 6),
                          OutlinedButton.icon(
                            onPressed:
                                filters.hasAnyFilter ? filters.clearAll : null,
                            icon: const Icon(Icons.filter_alt_off),
                            label: const Text('Limpar filtros da Home'),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Esses filtros controlam em tempo real o que aparece no mapa da Home.',
                          ),
                        ],
                      );
                    },
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
