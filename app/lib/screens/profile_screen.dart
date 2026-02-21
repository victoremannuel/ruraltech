import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/device_model.dart';
import '../services/auth_service.dart';
import '../services/firebase_service.dart';
import '../services/map_filter_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final Set<String> _selectedPropertyIds = {};
  final Set<String> _selectedAreaIds = {};
  final Set<String> _selectedCollarIds = {};
  final Set<String> _selectedGatewayIds = {};
  bool _initializedFromFilters = false;

  void _initFromFilters(MapFilterService filters) {
    if (_initializedFromFilters) return;
    _selectedPropertyIds.addAll(filters.propertyIds);
    _selectedAreaIds.addAll(filters.areaIds);
    _selectedCollarIds.addAll(filters.collarIds);
    _selectedGatewayIds.addAll(filters.gatewayIds);
    _initializedFromFilters = true;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final filters = context.watch<MapFilterService>();
    final fb = context.read<FirebaseService>();
    final uid = auth.user?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    _initFromFilters(filters);

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
              return StreamBuilder<List<Map<String, dynamic>>>(
                stream: fb.streamAreas(uid: uid, isAdmin: auth.isAdmin),
                builder: (context, areaSnap) {
                  final areas = areaSnap.data ?? const [];
                  return StreamBuilder<List<Map<String, dynamic>>>(
                    stream: fb.streamGateways(uid: uid, isAdmin: auth.isAdmin),
                    builder: (context, gatewaySnap) {
                      final gateways = gatewaySnap.data ?? const [];

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
                                _selectedPropertyIds.isEmpty
                                    ? 'Todas visiveis (${properties.length})'
                                    : '${_selectedPropertyIds.length} selecionada(s)',
                              ),
                              children: properties
                                  .map(
                                    (p) => CheckboxListTile(
                                      value: _selectedPropertyIds
                                          .contains(p['id'].toString()),
                                      title: Text(
                                        (p['name'] ?? p['id']).toString(),
                                      ),
                                      onChanged: (v) => setState(() {
                                        final id = p['id'].toString();
                                        if (v ?? false) {
                                          _selectedPropertyIds.add(id);
                                        } else {
                                          _selectedPropertyIds.remove(id);
                                        }
                                      }),
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
                                _selectedAreaIds.isEmpty
                                    ? 'Todas visiveis (${areas.length})'
                                    : '${_selectedAreaIds.length} selecionada(s)',
                              ),
                              children: areas
                                  .map(
                                    (a) => CheckboxListTile(
                                      value: _selectedAreaIds
                                          .contains(a['id'].toString()),
                                      title: Text(
                                        'Area ${a['id'].toString().substring(0, 6)}',
                                      ),
                                      subtitle: Text(
                                        'Prop: ${(a['propertyId'] ?? '-').toString()}',
                                      ),
                                      onChanged: (v) => setState(() {
                                        final id = a['id'].toString();
                                        if (v ?? false) {
                                          _selectedAreaIds.add(id);
                                        } else {
                                          _selectedAreaIds.remove(id);
                                        }
                                      }),
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
                                _selectedCollarIds.isEmpty
                                    ? 'Todas visiveis (${devices.length})'
                                    : '${_selectedCollarIds.length} selecionada(s)',
                              ),
                              children: devices
                                  .map(
                                    (d) => CheckboxListTile(
                                      value: _selectedCollarIds.contains(d.id),
                                      title: Text(d.name),
                                      subtitle: Text(d.id),
                                      onChanged: (v) => setState(() {
                                        if (v ?? false) {
                                          _selectedCollarIds.add(d.id);
                                        } else {
                                          _selectedCollarIds.remove(d.id);
                                        }
                                      }),
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
                                _selectedGatewayIds.isEmpty
                                    ? 'Todos visiveis (${gateways.length})'
                                    : '${_selectedGatewayIds.length} selecionado(s)',
                              ),
                              children: gateways
                                  .map(
                                    (g) => CheckboxListTile(
                                      value: _selectedGatewayIds
                                          .contains(g['id'].toString()),
                                      title: Text(
                                          (g['name'] ?? g['id']).toString()),
                                      subtitle: Text(g['id'].toString()),
                                      onChanged: (v) => setState(() {
                                        final id = g['id'].toString();
                                        if (v ?? false) {
                                          _selectedGatewayIds.add(id);
                                        } else {
                                          _selectedGatewayIds.remove(id);
                                        }
                                      }),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: () {
                              filters.applySelections(
                                propertyIds: _selectedPropertyIds,
                                areaIds: _selectedAreaIds,
                                collarIds: _selectedCollarIds,
                                gatewayIds: _selectedGatewayIds,
                              );
                              Navigator.pop(context);
                            },
                            icon: const Icon(Icons.filter_alt),
                            label: const Text('Filtrar'),
                          ),
                          const SizedBox(height: 6),
                          OutlinedButton.icon(
                            onPressed: () {
                              setState(() {
                                _selectedPropertyIds.clear();
                                _selectedAreaIds.clear();
                                _selectedCollarIds.clear();
                                _selectedGatewayIds.clear();
                              });
                              filters.clearAll();
                              Navigator.pop(context);
                            },
                            icon: const Icon(Icons.filter_alt_off),
                            label: const Text('Limpar filtros'),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Selecione os itens e toque em "Filtrar na Home" para aplicar.',
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
