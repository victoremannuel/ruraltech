import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../components/primitives/rt_badge.dart';
import '../components/primitives/rt_button.dart';
import '../components/primitives/rt_card.dart';
import '../design/colors.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../models/device_model.dart';
import '../services/auth_service.dart';
import '../services/cloud_service.dart';
import '../services/map_filter_service.dart';
import '../utils/cloud_compat.dart';
import '../utils/top_feedback.dart';

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

  String _normalizeId(dynamic value) {
    if (value is String) {
      final raw = value.trim();
      if (raw.isEmpty) return '';
      if (!raw.contains('/')) return raw;
      final parts = raw.split('/').where((e) => e.isNotEmpty).toList();
      return parts.isEmpty ? raw : parts.last;
    }
    if (value is DocumentReference) return value.id;
    if (value == null) return '';
    return value.toString().trim();
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
      backgroundColor: RTColors.bgAlt,
      appBar: AppBar(title: const Text('Perfil')),
      body: FutureBuilder<List<Map<String, String>>>(
        future: _userOptionsFuture,
        builder: (context, usersSnap) {
          final userOptions = usersSnap.data ?? const <Map<String, String>>[];
          return StreamBuilder<List<Map<String, dynamic>>>(
            stream: fb.streamRuralProperties(uid: uid, isAdmin: auth.isAdmin),
            builder: (context, propSnap) {
              if (propSnap.hasError) {
                return _errorCenter('propriedades', propSnap.error);
              }
              final properties = propSnap.data ?? const [];
              return StreamBuilder<List<DeviceModel>>(
                stream: fb.streamDevices(uid: uid, isAdmin: auth.isAdmin),
                builder: (context, deviceSnap) {
                  if (deviceSnap.hasError) {
                    return _errorCenter('coleiras', deviceSnap.error);
                  }
                  final devices = deviceSnap.data ?? const <DeviceModel>[];
                  return StreamBuilder<List<Map<String, dynamic>>>(
                    stream: fb.streamAreas(uid: uid, isAdmin: auth.isAdmin),
                    builder: (context, areaSnap) {
                      if (areaSnap.hasError) {
                        return _errorCenter('áreas', areaSnap.error);
                      }
                      final areas = areaSnap.data ?? const [];
                      return StreamBuilder<List<Map<String, dynamic>>>(
                        stream:
                            fb.streamGateways(uid: uid, isAdmin: auth.isAdmin),
                        builder: (context, gatewaySnap) {
                          if (gatewaySnap.hasError) {
                            return _errorCenter('gateways', gatewaySnap.error);
                          }
                          final gateways = gatewaySnap.data ?? const [];
                          return _buildBody(
                            auth: auth,
                            filters: filters,
                            userOptions: userOptions,
                            properties: properties,
                            devices: devices,
                            areas: areas,
                            gateways: gateways,
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

  Widget _errorCenter(String section, Object? error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RTSpacing.x4),
        child: Text(
          'Erro ao carregar $section: $error',
          style: RTTypography.bodySmall.copyWith(color: RTColors.danger),
        ),
      ),
    );
  }

  Widget _buildBody({
    required AuthService auth,
    required MapFilterService filters,
    required List<Map<String, String>> userOptions,
    required List<Map<String, dynamic>> properties,
    required List<DeviceModel> devices,
    required List<Map<String, dynamic>> areas,
    required List<Map<String, dynamic>> gateways,
  }) {
    final selectedPropertyIds = _selectedPropertyIds
        .map(_normalizeId)
        .where((e) => e.isNotEmpty)
        .toSet();
    final selectedAreaIds = _selectedAreaIds
        .map(_normalizeId)
        .where((e) => e.isNotEmpty)
        .toSet();
    final selectedCollarIds = _selectedCollarIds
        .map(_normalizeId)
        .where((e) => e.isNotEmpty)
        .toSet();
    final selectedGatewayIds = _selectedGatewayIds
        .map(_normalizeId)
        .where((e) => e.isNotEmpty)
        .toSet();

    Set<String> buildResolvedPropertyIds() {
      final propertyIds = <String>{...selectedPropertyIds};
      for (final a in areas.where(
          (a) => selectedAreaIds.contains(_normalizeId(a['id'])))) {
        final pid = _normalizeId(a['propertyId']);
        if (pid.isNotEmpty) propertyIds.add(pid);
      }
      for (final d
          in devices.where((d) => selectedCollarIds.contains(_normalizeId(d.id)))) {
        final pid = _normalizeId(d.propertyId);
        if (pid.isNotEmpty) propertyIds.add(pid);
      }
      for (final g in gateways.where(
          (g) => selectedGatewayIds.contains(_normalizeId(g['id'])))) {
        final pid = _normalizeId(g['propertyId']);
        if (pid.isNotEmpty) propertyIds.add(pid);
      }
      return propertyIds;
    }

    Set<String> resolveAreasByProperties(Set<String> pids) {
      final out = <String>{...selectedAreaIds};
      for (final a in areas) {
        final pid = _normalizeId(a['propertyId']);
        if (pid.isNotEmpty && pids.contains(pid)) {
          out.add(_normalizeId(a['id']));
        }
      }
      return out;
    }

    Set<String> resolveCollarsByProperties(Set<String> pids) {
      final out = <String>{...selectedCollarIds};
      for (final d in devices) {
        final pid = _normalizeId(d.propertyId);
        if (pid.isNotEmpty && pids.contains(pid)) {
          out.add(_normalizeId(d.id));
        }
      }
      return out;
    }

    Set<String> resolveGatewaysByProperties(Set<String> pids) {
      final out = <String>{...selectedGatewayIds};
      for (final g in gateways) {
        final pid = _normalizeId(g['propertyId']);
        if (pid.isNotEmpty && pids.contains(pid)) {
          out.add(_normalizeId(g['id']));
        }
      }
      return out;
    }

    final userEmailByUid = <String, String>{
      for (final u in userOptions)
        if ((u['uid'] ?? '').trim().isNotEmpty)
          (u['uid'] ?? '').trim(): ((u['email'] ?? '').trim().isEmpty
              ? (u['uid'] ?? '').trim()
              : (u['email'] ?? '').trim()),
    };
    final authUid = (auth.user?.uid ?? '').trim();
    final authEmail = (auth.user?.email ?? '').trim();
    if (authUid.isNotEmpty && authEmail.isNotEmpty) {
      userEmailByUid.putIfAbsent(authUid, () => authEmail);
    }

    final propertyById = <String, Map<String, dynamic>>{
      for (final p in properties)
        if (_normalizeId(p['id']).isNotEmpty) _normalizeId(p['id']): p,
    };

    String userEmailFromUid(dynamic rawUid) {
      final id = _normalizeId(rawUid);
      if (id.isEmpty) return '—';
      return userEmailByUid[id] ?? '—';
    }

    String propertyNameFromId(dynamic rawPropertyId) {
      final id = _normalizeId(rawPropertyId);
      if (id.isEmpty) return '—';
      final property = propertyById[id];
      if (property == null) return '—';
      final name = (property['name'] ?? '').toString().trim();
      return name.isEmpty ? '—' : name;
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        RTSpacing.x4,
        RTSpacing.x3,
        RTSpacing.x4,
        RTSpacing.x8,
      ),
      children: [
        _identityCard(auth),
        const SizedBox(height: RTSpacing.x4),
        _sectionLabel('Filtros do mapa'),
        const SizedBox(height: RTSpacing.x2),
        _filterCard(
          sectionKey: const Key('profile_properties_section'),
          icon: Icons.landscape_outlined,
          title: 'Propriedades',
          selectedCount: _selectedPropertyIds.length,
          totalCount: properties.length,
          children: properties
              .map((p) => _filterTile(
                    id: _normalizeId(p['id']),
                    selected: _selectedPropertyIds,
                    title: (p['name'] ?? p['id']).toString(),
                    subtitle:
                        'Proprietário: ${userEmailFromUid(p['createdByUid'])}',
                  ))
              .toList(),
        ),
        const SizedBox(height: RTSpacing.x2),
        _filterCard(
          sectionKey: const Key('profile_areas_section'),
          icon: Icons.polyline_outlined,
          title: 'Áreas',
          selectedCount: _selectedAreaIds.length,
          totalCount: areas.length,
          children: areas.map((a) {
            final id = _normalizeId(a['id']);
            final short = id.length <= 6 ? id : id.substring(0, 6);
            return _filterTile(
              id: id,
              selected: _selectedAreaIds,
              title: 'Área ${short.isEmpty ? '—' : short}',
              subtitle: 'Fazenda: ${propertyNameFromId(a['propertyId'])}',
            );
          }).toList(),
        ),
        const SizedBox(height: RTSpacing.x2),
        _filterCard(
          sectionKey: const Key('profile_collars_section'),
          icon: Icons.pets_outlined,
          title: 'Coleiras',
          selectedCount: _selectedCollarIds.length,
          totalCount: devices.length,
          children: devices
              .map((d) => _filterTile(
                    id: _normalizeId(d.id),
                    selected: _selectedCollarIds,
                    title: d.name,
                    subtitle: 'Dono: ${userEmailFromUid(d.ownerUid)}',
                  ))
              .toList(),
        ),
        const SizedBox(height: RTSpacing.x2),
        _filterCard(
          sectionKey: const Key('profile_gateways_section'),
          icon: Icons.wifi,
          title: 'Gateways',
          selectedCount: _selectedGatewayIds.length,
          totalCount: gateways.length,
          children: gateways
              .map((g) => _filterTile(
                    id: _normalizeId(g['id']),
                    selected: _selectedGatewayIds,
                    title: (g['name'] ?? g['id']).toString(),
                    subtitle:
                        'Fazenda: ${propertyNameFromId(g['propertyId'])}',
                  ))
              .toList(),
        ),
        const SizedBox(height: RTSpacing.x4),
        RTButton(
          key: const Key('profile_apply_filters_button'),
          label: 'Aplicar filtros',
          icon: Icons.filter_alt_outlined,
          fullWidth: true,
          onPressed: () {
            final resolvedPropertyIds = buildResolvedPropertyIds();
            final resolvedAreaIds =
                resolveAreasByProperties(resolvedPropertyIds);
            final resolvedCollarIds =
                resolveCollarsByProperties(resolvedPropertyIds);
            final resolvedGatewayIds =
                resolveGatewaysByProperties(resolvedPropertyIds);
            filters.applySelections(
              propertyIds: resolvedPropertyIds,
              areaIds: resolvedAreaIds,
              collarIds: resolvedCollarIds,
              gatewayIds: resolvedGatewayIds,
            );
            AppFeedback.success('Filtros aplicados ao mapa.');
          },
        ),
        const SizedBox(height: RTSpacing.x2),
        RTButton(
          key: const Key('profile_clear_filters_button'),
          label: 'Limpar filtros',
          icon: Icons.filter_alt_off_outlined,
          variant: RTButtonVariant.ghost,
          fullWidth: true,
          onPressed: () {
            setState(() {
              _selectedPropertyIds.clear();
              _selectedAreaIds.clear();
              _selectedCollarIds.clear();
              _selectedGatewayIds.clear();
            });
            filters.clearAll();
            AppFeedback.success('Filtros removidos.');
          },
        ),
        const SizedBox(height: RTSpacing.x6),
        _sectionLabel('Conta'),
        const SizedBox(height: RTSpacing.x2),
        RTButton(
          key: const Key('profile_sign_out_button'),
          label: 'Sair da conta',
          icon: Icons.logout,
          variant: RTButtonVariant.danger,
          fullWidth: true,
          onPressed: () => auth.signOut(),
        ),
      ],
    );
  }

  Widget _identityCard(AuthService auth) {
    final email = auth.user?.email ?? 'Sem email';
    final roleLabel = auth.isAdmin ? 'ADMIN' : 'OPERADOR';
    return RTCard(
      padding: const EdgeInsets.all(RTSpacing.x4),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: RTColors.primarySoft,
              borderRadius: BorderRadius.circular(RTRadius.rFull),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.person_outline,
                color: RTColors.primary, size: 28),
          ),
          const SizedBox(width: RTSpacing.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  email,
                  style: RTTypography.h3.copyWith(fontSize: 18),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                RTBadge(
                  label: roleLabel,
                  tone: auth.isAdmin ? RTTone.accent : RTTone.neutral,
                  mono: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: RTSpacing.x1),
      child: Text(label.toUpperCase(), style: RTTypography.eyebrow),
    );
  }

  Widget _filterCard({
    required Key sectionKey,
    required IconData icon,
    required String title,
    required int selectedCount,
    required int totalCount,
    required List<Widget> children,
  }) {
    final summary = selectedCount == 0
        ? 'Todos visíveis ($totalCount)'
        : '$selectedCount de $totalCount selecionados';
    return RTCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: ExpansionTile(
          key: sectionKey,
          tilePadding: const EdgeInsets.symmetric(
            horizontal: RTSpacing.x3,
            vertical: RTSpacing.x1,
          ),
          childrenPadding: const EdgeInsets.only(
            left: RTSpacing.x2,
            right: RTSpacing.x2,
            bottom: RTSpacing.x2,
          ),
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: RTColors.bgSubtle,
              borderRadius: BorderRadius.circular(RTRadius.r2),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: RTColors.inkSoft),
          ),
          title: Text(title, style: RTTypography.bodyStrong),
          subtitle: Text(summary, style: RTTypography.bodySmall),
          children: children,
        ),
      ),
    );
  }

  Widget _filterTile({
    required String id,
    required Set<String> selected,
    required String title,
    required String subtitle,
  }) {
    if (id.isEmpty) return const SizedBox.shrink();
    final isSelected = selected.contains(id);
    return CheckboxListTile(
      value: isSelected,
      title: Text(title, style: RTTypography.body),
      subtitle: Text(subtitle, style: RTTypography.bodySmall),
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: RTSpacing.x2),
      onChanged: (v) => setState(() {
        if (v ?? false) {
          selected.add(id);
        } else {
          selected.remove(id);
        }
      }),
    );
  }
}
