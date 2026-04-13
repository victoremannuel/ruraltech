import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/device_model.dart';
import '../services/auth_service.dart';
import '../services/cloud_service.dart';
import '../services/map_filter_service.dart';
import '../utils/cloud_compat.dart';

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
  Future<List<Map<String, String>>>? _userOptionsFuture;

  void _initFromFilters(MapFilterService filters) {
    if (_initializedFromFilters) return;
    _selectedPropertyIds.addAll(filters.propertyIds);
    _selectedAreaIds.addAll(filters.areaIds);
    _selectedCollarIds.addAll(filters.collarIds);
    _selectedGatewayIds.addAll(filters.gatewayIds);
    _initializedFromFilters = true;
  }

  Future<List<Map<String, String>>> _safeLoadUserOptions(
      CloudService fb) async {
    try {
      return await fb.getUserOptions();
    } catch (_) {
      return const <Map<String, String>>[];
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _userOptionsFuture ??=
        _safeLoadUserOptions(context.read<CloudService>());
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final filters = context.watch<MapFilterService>();
    final fb = context.read<CloudService>();
    final uid = auth.user?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    _initFromFilters(filters);

    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: FutureBuilder<List<Map<String, String>>>(
        future: _userOptionsFuture,
        builder: (context, usersSnap) {
          final userOptions = usersSnap.data ?? const <Map<String, String>>[];
          return StreamBuilder<List<Map<String, dynamic>>>(
            stream: fb.streamRuralProperties(uid: uid, isAdmin: auth.isAdmin),
            builder: (context, propSnap) {
              if (propSnap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                        'Erro ao carregar propriedades: ${propSnap.error}'),
                  ),
                );
              }
              final properties = propSnap.data ?? const [];
              return StreamBuilder<List<DeviceModel>>(
                stream: fb.streamDevices(uid: uid, isAdmin: auth.isAdmin),
                builder: (context, deviceSnap) {
                  if (deviceSnap.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                            'Erro ao carregar coleiras: ${deviceSnap.error}'),
                      ),
                    );
                  }
                  final devices = deviceSnap.data ?? const <DeviceModel>[];
                  return StreamBuilder<List<Map<String, dynamic>>>(
                    stream: fb.streamAreas(uid: uid, isAdmin: auth.isAdmin),
                    builder: (context, areaSnap) {
                      if (areaSnap.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                                'Erro ao carregar areas: ${areaSnap.error}'),
                          ),
                        );
                      }
                      final areas = areaSnap.data ?? const [];
                      return StreamBuilder<List<Map<String, dynamic>>>(
                        stream:
                            fb.streamGateways(uid: uid, isAdmin: auth.isAdmin),
                        builder: (context, gatewaySnap) {
                          if (gatewaySnap.hasError) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                    'Erro ao carregar gateways: ${gatewaySnap.error}'),
                              ),
                            );
                          }
                          final gateways = gatewaySnap.data ?? const [];

                          String normalizeId(dynamic value) {
                            if (value is String) {
                              final raw = value.trim();
                              if (raw.isEmpty) return '';
                              if (!raw.contains('/')) return raw;
                              final parts = raw
                                  .split('/')
                                  .where((e) => e.isNotEmpty)
                                  .toList();
                              return parts.isEmpty ? raw : parts.last;
                            }
                            if (value is DocumentReference) return value.id;
                            if (value == null) return '';
                            return value.toString().trim();
                          }

                          final selectedPropertyIds = _selectedPropertyIds
                              .map(normalizeId)
                              .where((e) => e.isNotEmpty)
                              .toSet();
                          final selectedAreaIds = _selectedAreaIds
                              .map(normalizeId)
                              .where((e) => e.isNotEmpty)
                              .toSet();
                          final selectedCollarIds = _selectedCollarIds
                              .map(normalizeId)
                              .where((e) => e.isNotEmpty)
                              .toSet();
                          final selectedGatewayIds = _selectedGatewayIds
                              .map(normalizeId)
                              .where((e) => e.isNotEmpty)
                              .toSet();

                          Set<String> buildResolvedPropertyIds() {
                            final propertyIds = <String>{
                              ...selectedPropertyIds
                            };

                            final selectedAreas = areas.where(
                              (a) => selectedAreaIds
                                  .contains(normalizeId(a['id'])),
                            );
                            for (final a in selectedAreas) {
                              final pid = normalizeId(a['propertyId']);
                              if (pid.isNotEmpty) propertyIds.add(pid);
                            }

                            final selectedCollars = devices.where(
                              (d) =>
                                  selectedCollarIds.contains(normalizeId(d.id)),
                            );
                            for (final d in selectedCollars) {
                              final pid = normalizeId(d.propertyId);
                              if (pid.isNotEmpty) propertyIds.add(pid);
                            }

                            final selectedGateways = gateways.where(
                              (g) => selectedGatewayIds
                                  .contains(normalizeId(g['id'])),
                            );
                            for (final g in selectedGateways) {
                              final pid = normalizeId(g['propertyId']);
                              if (pid.isNotEmpty) propertyIds.add(pid);
                            }

                            return propertyIds;
                          }

                          Set<String> resolveAreasByProperties(
                              Set<String> pids) {
                            final out = <String>{...selectedAreaIds};
                            for (final a in areas) {
                              final pid = normalizeId(a['propertyId']);
                              if (pid.isNotEmpty && pids.contains(pid)) {
                                out.add(normalizeId(a['id']));
                              }
                            }
                            return out;
                          }

                          Set<String> resolveCollarsByProperties(
                              Set<String> pids) {
                            final out = <String>{...selectedCollarIds};
                            for (final d in devices) {
                              final pid = normalizeId(d.propertyId);
                              if (pid.isNotEmpty && pids.contains(pid)) {
                                out.add(normalizeId(d.id));
                              }
                            }
                            return out;
                          }

                          Set<String> resolveGatewaysByProperties(
                              Set<String> pids) {
                            final out = <String>{...selectedGatewayIds};
                            for (final g in gateways) {
                              final pid = normalizeId(g['propertyId']);
                              if (pid.isNotEmpty && pids.contains(pid)) {
                                out.add(normalizeId(g['id']));
                              }
                            }
                            return out;
                          }

                          final userEmailByUid = <String, String>{
                            for (final u in userOptions)
                              if ((u['uid'] ?? '').trim().isNotEmpty)
                                (u['uid'] ?? '').trim():
                                    ((u['email'] ?? '').trim().isEmpty
                                        ? (u['uid'] ?? '').trim()
                                        : (u['email'] ?? '').trim()),
                          };
                          final authUid = (auth.user?.uid ?? '').trim();
                          final authEmail = (auth.user?.email ?? '').trim();
                          if (authUid.isNotEmpty && authEmail.isNotEmpty) {
                            userEmailByUid.putIfAbsent(
                                authUid, () => authEmail);
                          }

                          final propertyById = <String, Map<String, dynamic>>{
                            for (final p in properties)
                              if (normalizeId(p['id']).isNotEmpty)
                                normalizeId(p['id']): p,
                          };

                          String userEmailFromUid(dynamic rawUid) {
                            final uid = normalizeId(rawUid);
                            if (uid.isEmpty) return '-';
                            return userEmailByUid[uid] ?? '-';
                          }

                          String propertyNameFromId(dynamic rawPropertyId) {
                            final propertyId = normalizeId(rawPropertyId);
                            if (propertyId.isEmpty) return '-';
                            final property = propertyById[propertyId];
                            if (property == null) return '-';
                            final name =
                                (property['name'] ?? '').toString().trim();
                            return name.isEmpty ? '-' : name;
                          }

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
                                  key: const Key('profile_properties_section'),
                                  leading: const Icon(Icons.landscape),
                                  title: const Text(
                                      'Selecionar propriedades no mapa'),
                                  subtitle: Text(
                                    _selectedPropertyIds.isEmpty
                                        ? 'Todas visiveis (${properties.length})'
                                        : '${_selectedPropertyIds.length} selecionada(s)',
                                  ),
                                  children: properties
                                      .map(
                                        (p) => CheckboxListTile(
                                          value: _selectedPropertyIds
                                              .contains(normalizeId(p['id'])),
                                          title: Text(
                                            (p['name'] ?? p['id']).toString(),
                                          ),
                                          subtitle: Text(
                                            'Proprietario: ${userEmailFromUid(p['createdByUid'])}',
                                          ),
                                          onChanged: (v) => setState(() {
                                            final id = normalizeId(p['id']);
                                            if (id.isEmpty) return;
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
                                  key: const Key('profile_areas_section'),
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
                                              .contains(normalizeId(a['id'])),
                                          title: Text(
                                            (() {
                                              final id = normalizeId(a['id']);
                                              final short = id.length <= 6
                                                  ? id
                                                  : id.substring(0, 6);
                                              return 'Area ${short.isEmpty ? '-' : short}';
                                            })(),
                                          ),
                                          subtitle: Text(
                                            'Fazenda: ${propertyNameFromId(a['propertyId'])}',
                                          ),
                                          onChanged: (v) => setState(() {
                                            final id = normalizeId(a['id']);
                                            if (id.isEmpty) return;
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
                                  key: const Key('profile_collars_section'),
                                  leading: const Icon(Icons.pets),
                                  title:
                                      const Text('Selecionar coleiras no mapa'),
                                  subtitle: Text(
                                    _selectedCollarIds.isEmpty
                                        ? 'Todas visiveis (${devices.length})'
                                        : '${_selectedCollarIds.length} selecionada(s)',
                                  ),
                                  children: devices
                                      .map(
                                        (d) => CheckboxListTile(
                                          value: _selectedCollarIds
                                              .contains(normalizeId(d.id)),
                                          title: Text(d.name),
                                          subtitle: Text(
                                            'Dono: ${userEmailFromUid(d.ownerUid)}',
                                          ),
                                          onChanged: (v) => setState(() {
                                            final id = normalizeId(d.id);
                                            if (id.isEmpty) return;
                                            if (v ?? false) {
                                              _selectedCollarIds.add(id);
                                            } else {
                                              _selectedCollarIds.remove(id);
                                            }
                                          }),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ),
                              Card(
                                child: ExpansionTile(
                                  key: const Key('profile_gateways_section'),
                                  leading: const Icon(Icons.wifi),
                                  title:
                                      const Text('Selecionar gateways no mapa'),
                                  subtitle: Text(
                                    _selectedGatewayIds.isEmpty
                                        ? 'Todos visiveis (${gateways.length})'
                                        : '${_selectedGatewayIds.length} selecionado(s)',
                                  ),
                                  children: gateways
                                      .map(
                                        (g) => CheckboxListTile(
                                          value: _selectedGatewayIds
                                              .contains(normalizeId(g['id'])),
                                          title: Text((g['name'] ?? g['id'])
                                              .toString()),
                                          subtitle: Text(
                                            'Fazenda: ${propertyNameFromId(g['propertyId'])}',
                                          ),
                                          onChanged: (v) => setState(() {
                                            final id = normalizeId(g['id']);
                                            if (id.isEmpty) return;
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
                                key: const Key('profile_apply_filters_button'),
                                onPressed: () {
                                  final resolvedPropertyIds =
                                      buildResolvedPropertyIds();
                                  final resolvedAreaIds =
                                      resolveAreasByProperties(
                                          resolvedPropertyIds);
                                  final resolvedCollarIds =
                                      resolveCollarsByProperties(
                                          resolvedPropertyIds);
                                  final resolvedGatewayIds =
                                      resolveGatewaysByProperties(
                                          resolvedPropertyIds);

                                  filters.applySelections(
                                    propertyIds: resolvedPropertyIds,
                                    areaIds: resolvedAreaIds,
                                    collarIds: resolvedCollarIds,
                                    gatewayIds: resolvedGatewayIds,
                                  );
                                  Navigator.pop(context);
                                },
                                icon: const Icon(Icons.filter_alt),
                                label: const Text('Filtrar'),
                              ),
                              const SizedBox(height: 6),
                              OutlinedButton.icon(
                                key: const Key('profile_clear_filters_button'),
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
          );
        },
      ),
    );
  }
}
