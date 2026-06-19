import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../components/domain/rt_confirm_lora.dart';
import '../components/primitives/rt_button.dart';
import '../components/primitives/rt_stepper.dart';
import '../config/manual_settings.dart';
import '../design/colors.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../services/auth_service.dart';
import '../services/bluetooth_discovery_service.dart';
import '../services/cloud_service.dart';
import '../services/gateway_service.dart';
import '../utils/cloud_compat.dart';
import '../utils/onboarding_gateway_utils.dart';
import '../utils/top_feedback.dart';
import 'map_point_picker_screen.dart';

/// Wizard de cadastro de coleira — 3 etapas.
///
/// Etapa 1: Identidade (nome, propriedade, gateway, dono)
/// Etapa 2: Vinculação (descoberta BLE/Wi-Fi, ID LoRa, posição)
/// Etapa 3: Confirmar (preview + salvar)
class AddCollarScreen extends StatefulWidget {
  const AddCollarScreen({super.key});

  @override
  State<AddCollarScreen> createState() => _AddCollarScreenState();
}

class _AddCollarScreenState extends State<AddCollarScreen> {
  final _pageController = PageController();
  int _step = 0;

  // ── Dados carregados async ──────────────────────────────────
  List<Map<String, dynamic>> _properties = [];
  List<Map<String, dynamic>> _gateways = [];
  List<Map<String, String>> _ownerOptions = [];
  bool _loading = true;

  // ── Estado do formulário ────────────────────────────────────
  String? _propertyId;
  String? _selectedGatewayId;
  LatLng? _selectedPosition;
  String? _selectedDetectedDeviceId;
  bool _manualPositionChosen = false;
  String? _selectedOwnerUid;

  final _ownerCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _statusCtrl = TextEditingController(text: 'active');
  final _loraIdCtrl = TextEditingController();

  // ── Erros de validação por etapa ───────────────────────────
  String? _nameError;
  String? _loraIdError;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _ownerCtrl.dispose();
    _nameCtrl.dispose();
    _statusCtrl.dispose();
    _loraIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final auth = context.read<AuthService>();
    final fb = context.read<CloudService>();
    final bleService = context.read<BluetoothDiscoveryService>();
    final uid = auth.user?.uid;
    if (uid == null) return;

    unawaited(bleService.startScan());

    final properties = await fb.getRuralProperties(uid: uid, isAdmin: auth.isAdmin);
    final gateways = await fb.streamGateways(uid: uid, isAdmin: auth.isAdmin).first;
    final users = auth.isAdmin ? await fb.getUserOptions() : const <Map<String, String>>[];

    if (!mounted) return;

    final ownerOptions = users
        .where((u) => (u['uid'] ?? '').isNotEmpty)
        .map((u) => Map<String, String>.from(u))
        .toList();

    final selfOwner = auth.isAdmin
        ? ownerOptions.firstWhere(
            (u) => (u['uid'] ?? '') == uid,
            orElse: () => ownerOptions.isNotEmpty ? ownerOptions.first : {'uid': uid, 'email': auth.user?.email ?? uid},
          )
        : {'uid': uid, 'email': (auth.user?.email ?? '').trim().isNotEmpty ? auth.user!.email!.trim() : uid};

    setState(() {
      _properties = properties;
      _gateways = gateways;
      _ownerOptions = ownerOptions;
      _propertyId = properties.isNotEmpty ? properties.first['id'].toString() : null;
      _selectedOwnerUid = (selfOwner['uid'] ?? '').trim().isEmpty ? uid : selfOwner['uid'];
      _ownerCtrl.text = (selfOwner['email'] ?? selfOwner['uid'] ?? uid);
      _loading = false;
    });
  }

  // ── Helpers ─────────────────────────────────────────────────

  String _normalizeRefId(dynamic value) {
    if (value is DocumentReference) return value.id;
    if (value is String) {
      final raw = value.trim();
      if (raw.isEmpty) return '';
      if (!raw.contains('/')) return raw;
      final parts = raw.split('/').where((e) => e.isNotEmpty).toList();
      return parts.isEmpty ? raw : parts.last;
    }
    if (value == null) return '';
    return value.toString().trim();
  }

  String? _normalizeLoraDeviceId(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final parsed = int.tryParse(trimmed);
    if (parsed == null || parsed <= 0) return null;
    return parsed.toString();
  }

  List<Map<String, dynamic>> _gatewaysForProperty(String? propertyId) {
    final normalized = _normalizeRefId(propertyId);
    if (normalized.isEmpty) return _gateways;
    return _gateways.where((g) => _normalizeRefId(g['propertyId']) == normalized).toList();
  }

  String _gatewayLabel(Map<String, dynamic> g) {
    final id = _normalizeRefId(g['id']);
    final name = (g['name'] ?? '').toString().trim();
    return name.isEmpty ? id : '$name ($id)';
  }

  List<Map<String, dynamic>> _mergedDiscoveredCollars() {
    final gateway = context.read<GatewayService>();
    final ble = context.read<BluetoothDiscoveryService>();
    final byId = <String, Map<String, dynamic>>{};

    for (final lora in gateway.discoveredCollars.where((c) => matchesSelectedGatewayId(
          selectedGatewayId: _selectedGatewayId,
          candidateGatewayId: c['gateway_id'],
          normalizeRefId: _normalizeRefId,
        ))) {
      final id = lora['device_id_str']?.toString();
      if (id == null || id.isEmpty) continue;
      byId[id] = {...lora, 'device_id_str': id, 'source_type': 'wifi'};
    }

    for (final b in ble.discoveredCollars) {
      final id = b['device_id_str']?.toString();
      if (id == null || id.isEmpty) continue;
      final current = byId[id];
      if (current == null) {
        byId[id] = {...b, 'device_id_str': id, 'source_type': 'ble'};
      } else {
        current['source_type'] = '${current['source_type']}+ble';
        current['lat'] ??= b['lat'];
        current['lon'] ??= b['lon'];
        byId[id] = current;
      }
    }

    final out = byId.values.toList();
    out.sort((a, b) => (a['device_id_str'] as String).compareTo(b['device_id_str'] as String));
    return out;
  }

  void _applyDetectedCollar(Map<String, dynamic> detected) {
    final id = detected['device_id_str']?.toString();
    if (id == null || id.isEmpty) return;
    _selectedDetectedDeviceId = id;
    _loraIdCtrl.text = id;
    if (_nameCtrl.text.trim().isEmpty || _nameCtrl.text.startsWith('Coleira ')) {
      final suggested = detected['name']?.toString().trim();
      _nameCtrl.text = (suggested == null || suggested.isEmpty) ? 'Coleira $id' : suggested;
    }
    final lat = _toDouble(detected['lat']);
    final lon = _toDouble(detected['lon']);
    if (lat != null && lon != null && lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180) {
      _selectedPosition = LatLng(lat, lon);
      _manualPositionChosen = false;
    }
  }

  double? _toDouble(dynamic v) {
    if (v is num) return v.isFinite ? v.toDouble() : null;
    if (v is String) {
      final d = double.tryParse(v.trim());
      return (d != null && d.isFinite) ? d : null;
    }
    return null;
  }

  List<LatLng> _polygonFromProperty(String? id) {
    if (id == null || id.isEmpty) return const [];
    final prop = _properties.cast<Map<String, dynamic>?>().firstWhere(
          (p) => p?['id'].toString() == id,
          orElse: () => null,
        );
    if (prop == null) return const [];
    final points = (prop['points'] as List?) ?? const [];
    return points
        .map((pt) {
          if (pt is Map) {
            final lat = _toDouble(pt['lat'] ?? pt['latitude']);
            final lon = _toDouble(pt['lon'] ?? pt['lng'] ?? pt['longitude']);
            if (lat != null && lon != null) return LatLng(lat, lon);
          }
          return null;
        })
        .whereType<LatLng>()
        .toList();
  }

  // ── Validação por etapa ──────────────────────────────────────

  bool _validateStep1() {
    bool ok = true;
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _nameError = 'Informe o nome da coleira');
      ok = false;
    } else {
      setState(() => _nameError = null);
    }
    if (_propertyId == null || _propertyId!.trim().isEmpty) {
      AppFeedback.error('Selecione a propriedade rural.');
      ok = false;
    }
    return ok;
  }

  bool _validateStep2() {
    final normalized = _normalizeLoraDeviceId(_loraIdCtrl.text);
    if (normalized == null) {
      setState(() => _loraIdError = 'Informe um ID LoRa numérico maior que zero');
      return false;
    }
    setState(() => _loraIdError = null);

    final hasBinding = (_selectedDetectedDeviceId ?? '').isNotEmpty;
    if (!hasBinding && _selectedPosition == null) {
      AppFeedback.error(
        'Selecione o ponto no mapa ou vincule uma coleira detectada.',
      );
      return false;
    }
    return true;
  }

  void _goNext() {
    if (_step == 0 && !_validateStep1()) return;
    if (_step == 1 && !_validateStep2()) return;
    if (_step < 2) {
      setState(() => _step++);
      _pageController.animateToPage(
        _step,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _goBack() {
    if (_step > 0) {
      setState(() => _step--);
      _pageController.animateToPage(
        _step,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _save() async {
    final auth = context.read<AuthService>();
    final fb = context.read<CloudService>();

    final normalizedLoraId = _normalizeLoraDeviceId(_loraIdCtrl.text);
    if (normalizedLoraId == null) {
      AppFeedback.error('ID LoRa inválido.');
      return;
    }

    final ownerUid = _selectedOwnerUid ?? auth.user?.uid;
    if (ownerUid == null || ownerUid.trim().isEmpty) {
      AppFeedback.error('Selecione um dono válido.');
      return;
    }

    try {
      await fb.addDevice(
        ownerUid: ownerUid,
        name: _nameCtrl.text.trim(),
        status: _statusCtrl.text.trim(),
        deviceId: normalizedLoraId,
        lat: _selectedPosition?.latitude,
        lon: _selectedPosition?.longitude,
        propertyId: _propertyId,
        gatewayId: _selectedGatewayId,
      );
      if (!mounted) return;
      Navigator.pop(context);
      AppFeedback.success('Coleira incluída com sucesso.');
    } catch (e) {
      if (!mounted) return;
      AppFeedback.error('Erro ao salvar coleira: $e');
    }
  }

  // ── UI ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: RTColors.bg,
      appBar: AppBar(
        backgroundColor: RTColors.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _goBack,
          color: RTColors.ink,
        ),
        title: Column(
          children: [
            Text(
              'Incluir coleira',
              style: RTTypography.eyebrow.copyWith(color: RTColors.inkSoft),
            ),
            const SizedBox(height: 6),
            RTStepper(
              steps: const ['Identidade', 'Vinculação', 'Confirmar'],
              currentStep: _step,
            ),
          ],
        ),
        centerTitle: true,
        toolbarHeight: 72,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                const Divider(height: 1),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _StepIdentidade(
                        auth: context.read<AuthService>(),
                        properties: _properties,
                        gateways: _gateways,
                        ownerOptions: _ownerOptions,
                        ownerCtrl: _ownerCtrl,
                        nameCtrl: _nameCtrl,
                        statusCtrl: _statusCtrl,
                        nameError: _nameError,
                        propertyId: _propertyId,
                        selectedGatewayId: _selectedGatewayId,
                        gatewaysForProperty: _gatewaysForProperty,
                        gatewayLabel: _gatewayLabel,
                        onPropertyChanged: (v) => setState(() {
                          _propertyId = v;
                          final stillAvail = _gatewaysForProperty(v).any(
                            (g) => _normalizeRefId(g['id']) == _normalizeRefId(_selectedGatewayId),
                          );
                          if (!stillAvail) _selectedGatewayId = null;
                        }),
                        onGatewayChanged: (v) => setState(() => _selectedGatewayId =
                            (v == null || v.trim().isEmpty) ? null : v),
                        onOwnerSelected: (owner) => setState(() {
                          _selectedOwnerUid = owner['uid'];
                          _ownerCtrl.text = (owner['email'] ?? owner['uid'] ?? '').trim();
                        }),
                        normalizeRefId: _normalizeRefId,
                      ),
                      AnimatedBuilder(
                        animation: Listenable.merge([
                          context.read<GatewayService>(),
                          context.read<BluetoothDiscoveryService>(),
                        ]),
                        builder: (ctx, _) => _StepVinculacao(
                          loraIdCtrl: _loraIdCtrl,
                          loraIdError: _loraIdError,
                          selectedDetectedDeviceId: _selectedDetectedDeviceId,
                          selectedPosition: _selectedPosition,
                          manualPositionChosen: _manualPositionChosen,
                          discoveredCollars: _mergedDiscoveredCollars(),
                          onDetectedChanged: (v) => setState(() {
                            if (v == null || v.isEmpty) {
                              _selectedDetectedDeviceId = null;
                              if (!_manualPositionChosen) _selectedPosition = null;
                              return;
                            }
                            final found = _mergedDiscoveredCollars()
                                .cast<Map<String, dynamic>?>()
                                .firstWhere(
                                  (d) => d?['device_id_str']?.toString() == v,
                                  orElse: () => null,
                                );
                            if (found != null) _applyDetectedCollar(found);
                          }),
                          onPickPosition: () async {
                            final picked = await Navigator.push<LatLng>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => MapPointPickerScreen(
                                  initial: _selectedPosition,
                                  propertyPolygon: _polygonFromProperty(_propertyId),
                                ),
                              ),
                            );
                            if (picked != null) {
                              setState(() {
                                _selectedPosition = picked;
                                _manualPositionChosen = true;
                              });
                            }
                          },
                          onScanBle: () => context.read<BluetoothDiscoveryService>().startScan(),
                          onScanWifi: () => context.read<GatewayService>().requestCollarDiscovery(),
                          bleScanning: context.read<BluetoothDiscoveryService>().isScanning,
                          wifiScanning: context.read<GatewayService>().isDiscoveringCollars,
                          bleError: context.read<BluetoothDiscoveryService>().lastError,
                          gatewayError: context.read<GatewayService>().lastError,
                        ),
                      ),
                      _StepConfirmar(
                        name: _nameCtrl.text.trim(),
                        loraId: _loraIdCtrl.text.trim(),
                        propertyLabel: _propertyId == null
                            ? '—'
                            : (_properties.cast<Map<String, dynamic>?>().firstWhere(
                                  (p) => p?['id'].toString() == _propertyId,
                                  orElse: () => null,
                                )?['name'] ??
                                _propertyId!),
                        gatewayLabel: _selectedGatewayId == null
                            ? 'Sem gateway'
                            : _gatewayLabel(_gateways
                                .cast<Map<String, dynamic>?>()
                                .firstWhere(
                                  (g) => _normalizeRefId(g?['id']) == _normalizeRefId(_selectedGatewayId),
                                  orElse: () => null,
                                ) ??
                                {'id': _selectedGatewayId}),
                        position: _selectedPosition,
                        onSave: _save,
                      ),
                    ],
                  ),
                ),
                // ── Barra de navegação ───────────────────────────────
                Container(
                  color: RTColors.bg,
                  padding: EdgeInsets.fromLTRB(
                    RTSpacing.x4,
                    RTSpacing.x3,
                    RTSpacing.x4,
                    bottomPad + RTSpacing.x3,
                  ),
                  child: Row(
                    children: [
                      if (_step > 0) ...[
                        RTButton(
                          label: 'Voltar',
                          variant: RTButtonVariant.ghost,
                          onPressed: _goBack,
                        ),
                        const SizedBox(width: RTSpacing.x3),
                      ],
                      Expanded(
                        child: _step < 2
                            ? RTButton(
                                label: 'Continuar',
                                variant: RTButtonVariant.primary,
                                trailing: Icons.arrow_forward_rounded,
                                onPressed: _goNext,
                                fullWidth: true,
                              )
                            : RTButton(
                                label: 'Salvar coleira',
                                variant: RTButtonVariant.accent,
                                icon: Icons.check_rounded,
                                onPressed: _save,
                                fullWidth: true,
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Etapa 1: Identidade
// ─────────────────────────────────────────────────────────────────────────────

class _StepIdentidade extends StatelessWidget {
  const _StepIdentidade({
    required this.auth,
    required this.properties,
    required this.gateways,
    required this.ownerOptions,
    required this.ownerCtrl,
    required this.nameCtrl,
    required this.statusCtrl,
    required this.nameError,
    required this.propertyId,
    required this.selectedGatewayId,
    required this.gatewaysForProperty,
    required this.gatewayLabel,
    required this.onPropertyChanged,
    required this.onGatewayChanged,
    required this.onOwnerSelected,
    required this.normalizeRefId,
  });

  final AuthService auth;
  final List<Map<String, dynamic>> properties;
  final List<Map<String, dynamic>> gateways;
  final List<Map<String, String>> ownerOptions;
  final TextEditingController ownerCtrl;
  final TextEditingController nameCtrl;
  final TextEditingController statusCtrl;
  final String? nameError;
  final String? propertyId;
  final String? selectedGatewayId;
  final List<Map<String, dynamic>> Function(String?) gatewaysForProperty;
  final String Function(Map<String, dynamic>) gatewayLabel;
  final ValueChanged<String?> onPropertyChanged;
  final ValueChanged<String?> onGatewayChanged;
  final ValueChanged<Map<String, String>> onOwnerSelected;
  final String Function(dynamic) normalizeRefId;

  Future<void> _showOwnerPicker(BuildContext context) async {
    var query = '';
    final selected = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, pickerSetState) {
          final matches = ownerOptions.where((u) {
            final email = (u['email'] ?? '').trim().toLowerCase();
            return query.isEmpty || email.contains(query);
          }).toList();
          return AlertDialog(
            title: const Text('Selecionar dono da coleira'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Buscar por email',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (v) => pickerSetState(() => query = v.trim().toLowerCase()),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: matches.isEmpty
                        ? const Text('Nenhum email encontrado.')
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: matches.length,
                            itemBuilder: (_, i) {
                              final owner = matches[i];
                              return ListTile(
                                dense: true,
                                title: Text(owner['email'] ?? owner['uid'] ?? ''),
                                onTap: () => Navigator.pop(ctx, owner),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
            ],
          );
        },
      ),
    );
    if (selected != null) onOwnerSelected(selected);
  }

  @override
  Widget build(BuildContext context) {
    final availableGateways = gatewaysForProperty(propertyId);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(RTSpacing.screen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Identidade da coleira', style: RTTypography.h3),
          const SizedBox(height: RTSpacing.x2),
          Text(
            'Defina nome, propriedade e a conta responsável.',
            style: RTTypography.body.copyWith(color: RTColors.inkSoft),
          ),
          const SizedBox(height: RTSpacing.x6),

          // Nome
          _FieldLabel('Nome da coleira'),
          const SizedBox(height: RTSpacing.x2),
          TextFormField(
            key: const Key('add_device_name_input'),
            controller: nameCtrl,
            decoration: InputDecoration(
              hintText: 'Ex: Coleira 042',
              errorText: nameError,
              filled: true,
              fillColor: RTColors.bgAlt,
              border: _border(RTColors.hair),
              enabledBorder: _border(nameError != null ? RTColors.danger : RTColors.hair),
              focusedBorder: _border(RTColors.primary, width: 1.6),
            ),
          ),
          const SizedBox(height: RTSpacing.x4),

          // Propriedade
          _FieldLabel('Propriedade rural'),
          const SizedBox(height: RTSpacing.x2),
          DropdownButtonFormField<String>(
            key: const Key('add_device_property_dropdown'),
            value: propertyId,
            items: properties
                .map((p) => DropdownMenuItem<String>(
                      value: p['id'].toString(),
                      child: Text((p['name'] ?? p['id']).toString()),
                    ))
                .toList(),
            onChanged: onPropertyChanged,
            decoration: InputDecoration(
              filled: true,
              fillColor: RTColors.bgAlt,
              border: _border(RTColors.hair),
              enabledBorder: _border(RTColors.hair),
              focusedBorder: _border(RTColors.primary, width: 1.6),
            ),
          ),
          const SizedBox(height: RTSpacing.x4),

          // Gateway
          _FieldLabel('Gateway vinculado'),
          const SizedBox(height: RTSpacing.x2),
          DropdownButtonFormField<String>(
            key: const Key('add_device_gateway_dropdown'),
            value: selectedGatewayId,
            items: [
              const DropdownMenuItem<String>(
                value: '',
                child: Text('Sem gateway vinculado'),
              ),
              ...availableGateways.map(
                (g) => DropdownMenuItem<String>(
                  value: normalizeRefId(g['id']),
                  child: Text(gatewayLabel(g)),
                ),
              ),
            ],
            onChanged: onGatewayChanged,
            decoration: InputDecoration(
              filled: true,
              fillColor: RTColors.bgAlt,
              border: _border(RTColors.hair),
              enabledBorder: _border(RTColors.hair),
              focusedBorder: _border(RTColors.primary, width: 1.6),
            ),
          ),
          const SizedBox(height: RTSpacing.x4),

          // Dono (admin only)
          if (auth.isAdmin) ...[
            _FieldLabel('Dono da coleira'),
            const SizedBox(height: RTSpacing.x2),
            TextFormField(
              key: const Key('add_device_owner_picker'),
              controller: ownerCtrl,
              readOnly: true,
              onTap: () => _showOwnerPicker(context),
              decoration: InputDecoration(
                hintText: 'Toque para selecionar',
                filled: true,
                fillColor: RTColors.bgAlt,
                border: _border(RTColors.hair),
                enabledBorder: _border(RTColors.hair),
                focusedBorder: _border(RTColors.primary, width: 1.6),
                suffixIcon: const Icon(Icons.arrow_drop_down),
              ),
            ),
            const SizedBox(height: RTSpacing.x4),
          ],

          // Status
          _FieldLabel('Status'),
          const SizedBox(height: RTSpacing.x2),
          TextFormField(
            key: const Key('add_device_status_input'),
            controller: statusCtrl,
            decoration: InputDecoration(
              filled: true,
              fillColor: RTColors.bgAlt,
              border: _border(RTColors.hair),
              enabledBorder: _border(RTColors.hair),
              focusedBorder: _border(RTColors.primary, width: 1.6),
            ),
          ),
        ],
      ),
    );
  }

  OutlineInputBorder _border(Color c, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(RTRadius.r3),
        borderSide: BorderSide(color: c, width: width),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Etapa 2: Vinculação
// ─────────────────────────────────────────────────────────────────────────────

class _StepVinculacao extends StatelessWidget {
  const _StepVinculacao({
    required this.loraIdCtrl,
    required this.loraIdError,
    required this.selectedDetectedDeviceId,
    required this.selectedPosition,
    required this.manualPositionChosen,
    required this.discoveredCollars,
    required this.onDetectedChanged,
    required this.onPickPosition,
    required this.onScanBle,
    required this.onScanWifi,
    required this.bleScanning,
    required this.wifiScanning,
    required this.bleError,
    required this.gatewayError,
  });

  final TextEditingController loraIdCtrl;
  final String? loraIdError;
  final String? selectedDetectedDeviceId;
  final LatLng? selectedPosition;
  final bool manualPositionChosen;
  final List<Map<String, dynamic>> discoveredCollars;
  final ValueChanged<String?> onDetectedChanged;
  final VoidCallback onPickPosition;
  final VoidCallback onScanBle;
  final VoidCallback onScanWifi;
  final bool bleScanning;
  final bool wifiScanning;
  final String? bleError;
  final String? gatewayError;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(RTSpacing.screen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Vinculação', style: RTTypography.h3),
          const SizedBox(height: RTSpacing.x2),
          Text(
            'Informe o ID LoRa e vincule a coleira detectada ou selecione a posição no mapa.',
            style: RTTypography.body.copyWith(color: RTColors.inkSoft),
          ),
          const SizedBox(height: RTSpacing.x6),

          // ID LoRa
          _FieldLabel('ID LoRa da coleira'),
          const SizedBox(height: RTSpacing.x2),
          TextFormField(
            key: const Key('add_device_lora_id_input'),
            controller: loraIdCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              hintText: 'Ex: 42',
              errorText: loraIdError,
              helperText: 'Número inteiro positivo único da coleira',
              filled: true,
              fillColor: RTColors.bgAlt,
              border: _border(RTColors.hair),
              enabledBorder: _border(loraIdError != null ? RTColors.danger : RTColors.hair),
              focusedBorder: _border(RTColors.primary, width: 1.6),
            ),
          ),
          const SizedBox(height: RTSpacing.x6),

          // Descoberta BLE/Wi-Fi
          Text('Descoberta automática', style: RTTypography.eyebrow.copyWith(color: RTColors.inkSoft)),
          const SizedBox(height: RTSpacing.x3),
          _ScanButtons(
            bleScanning: bleScanning,
            wifiScanning: wifiScanning,
            onScanBle: onScanBle,
            onScanWifi: onScanWifi,
            bleError: bleError,
            gatewayError: gatewayError,
          ),
          const SizedBox(height: RTSpacing.x4),

          // Coleira detectada
          _FieldLabel('Coleira detectada'),
          const SizedBox(height: RTSpacing.x2),
          DropdownButtonFormField<String>(
            key: const Key('add_device_detected_dropdown'),
            value: selectedDetectedDeviceId ?? '',
            items: [
              const DropdownMenuItem<String>(
                value: '',
                child: Text('Não vincular agora (usar mapa manual)'),
              ),
              ...discoveredCollars.map((d) => DropdownMenuItem<String>(
                    value: d['device_id_str']?.toString() ?? '',
                    child: Text(
                      'Coleira ${d['device_id_str']}'
                      '${(d['source_type'] ?? '').toString().isNotEmpty ? ' (${_sourceLabel(d['source_type'])})' : ''}',
                    ),
                  )),
            ],
            onChanged: onDetectedChanged,
            decoration: InputDecoration(
              filled: true,
              fillColor: RTColors.bgAlt,
              border: _border(RTColors.hair),
              enabledBorder: _border(RTColors.hair),
              focusedBorder: _border(RTColors.primary, width: 1.6),
            ),
          ),
          if (discoveredCollars.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: RTSpacing.x2),
              child: Text(
                'Nenhuma coleira detectada ainda. Tente BLE ou Wi-Fi, ou use o mapa.',
                style: RTTypography.bodySmall.copyWith(color: RTColors.inkMute),
              ),
            ),
          const SizedBox(height: RTSpacing.x6),

          // Posição
          Text('Posição', style: RTTypography.eyebrow.copyWith(color: RTColors.inkSoft)),
          const SizedBox(height: RTSpacing.x3),
          _PositionCard(
            position: selectedPosition,
            onPick: onPickPosition,
          ),
        ],
      ),
    );
  }

  String _sourceLabel(dynamic src) {
    switch (src?.toString()) {
      case 'wifi': return 'Wi-Fi';
      case 'ble': return 'BLE';
      case 'wifi+ble':
      case 'ble+wifi': return 'Wi-Fi+BLE';
      case 'telemetry': return 'Telemetria';
      default: return src?.toString() ?? '';
    }
  }

  OutlineInputBorder _border(Color c, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(RTRadius.r3),
        borderSide: BorderSide(color: c, width: width),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Etapa 3: Confirmar
// ─────────────────────────────────────────────────────────────────────────────

class _StepConfirmar extends StatelessWidget {
  const _StepConfirmar({
    required this.name,
    required this.loraId,
    required this.propertyLabel,
    required this.gatewayLabel,
    required this.position,
    required this.onSave,
  });

  final String name;
  final String loraId;
  final String propertyLabel;
  final String gatewayLabel;
  final LatLng? position;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(RTSpacing.screen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Confirmar', style: RTTypography.h3),
          const SizedBox(height: RTSpacing.x2),
          Text(
            'Revise os dados antes de salvar.',
            style: RTTypography.body.copyWith(color: RTColors.inkSoft),
          ),
          const SizedBox(height: RTSpacing.x6),

          // Preview card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(RTSpacing.card),
            decoration: BoxDecoration(
              color: RTColors.bgAlt,
              borderRadius: BorderRadius.circular(RTRadius.r4),
              border: Border.all(color: RTColors.hair),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: RTColors.primarySoft,
                        borderRadius: BorderRadius.circular(RTRadius.r3),
                      ),
                      child: Icon(Icons.pets, color: RTColors.primary, size: 20),
                    ),
                    const SizedBox(width: RTSpacing.x3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name.isNotEmpty ? name : '—',
                            style: RTTypography.h3.copyWith(fontSize: 18),
                          ),
                          Text(
                            'ID LoRa: $loraId',
                            style: RTTypography.mono.copyWith(
                              fontSize: 12,
                              color: RTColors.inkSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: RTSpacing.x4),
                _PreviewRow(icon: Icons.landscape_outlined, label: 'Propriedade', value: propertyLabel),
                _PreviewRow(icon: Icons.wifi, label: 'Gateway', value: gatewayLabel),
                _PreviewRow(
                  icon: Icons.location_on_outlined,
                  label: 'Posição',
                  value: position == null
                      ? 'A ser determinada via telemetria'
                      : '${position!.latitude.toStringAsFixed(6)}, ${position!.longitude.toStringAsFixed(6)}',
                  valueMono: position != null,
                ),
              ],
            ),
          ),
          const SizedBox(height: RTSpacing.x6),

          const RTConfirmLoRa(
            message:
                'A coleira será vinculada à propriedade e ficará visível no mapa assim que enviar telemetria.',
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Subwidgets compartilhados
// ─────────────────────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: RTTypography.eyebrow.copyWith(color: RTColors.inkSoft),
    );
  }
}

class _ScanButtons extends StatelessWidget {
  const _ScanButtons({
    required this.bleScanning,
    required this.wifiScanning,
    required this.onScanBle,
    required this.onScanWifi,
    required this.bleError,
    required this.gatewayError,
  });

  final bool bleScanning;
  final bool wifiScanning;
  final VoidCallback onScanBle;
  final VoidCallback onScanWifi;
  final String? bleError;
  final String? gatewayError;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: RTSpacing.x2,
          runSpacing: RTSpacing.x2,
          children: [
            OutlinedButton.icon(
              key: const Key('add_device_scan_ble_button'),
              onPressed: bleScanning ? null : onScanBle,
              icon: Icon(bleScanning ? Icons.bluetooth_connected : Icons.bluetooth_searching),
              label: Text(bleScanning ? 'Buscando BLE...' : 'Buscar por Bluetooth'),
            ),
            OutlinedButton.icon(
              key: const Key('add_device_scan_wifi_button'),
              onPressed: wifiScanning ? null : onScanWifi,
              icon: Icon(wifiScanning ? Icons.wifi_tethering : Icons.wifi),
              label: Text(wifiScanning ? 'Buscando Wi-Fi...' : 'Buscar por Wi-Fi'),
            ),
          ],
        ),
        if ((bleError ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: RTSpacing.x2),
            child: Text(
              'BLE: $bleError',
              style: RTTypography.bodySmall.copyWith(color: RTColors.danger),
            ),
          ),
        if ((gatewayError ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: RTSpacing.x2),
            child: Text(
              'Wi-Fi: $gatewayError',
              style: RTTypography.bodySmall.copyWith(color: RTColors.danger),
            ),
          ),
      ],
    );
  }
}

class _PositionCard extends StatelessWidget {
  const _PositionCard({required this.position, required this.onPick});
  final LatLng? position;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(RTSpacing.x4),
      decoration: BoxDecoration(
        color: RTColors.bgAlt,
        borderRadius: BorderRadius.circular(RTRadius.r3),
        border: Border.all(color: RTColors.hair),
      ),
      child: Row(
        children: [
          Icon(
            position != null ? Icons.location_on : Icons.location_off_outlined,
            color: position != null ? RTColors.ok : RTColors.inkMute,
            size: 22,
          ),
          const SizedBox(width: RTSpacing.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  position == null ? 'Posição não definida' : 'Posição selecionada',
                  style: RTTypography.body.copyWith(
                    color: position != null ? RTColors.ink : RTColors.inkSoft,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (position != null)
                  Text(
                    '${position!.latitude.toStringAsFixed(6)}, ${position!.longitude.toStringAsFixed(6)}',
                    style: RTTypography.mono.copyWith(
                      fontSize: 11,
                      color: RTColors.inkSoft,
                    ),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: onPick,
            child: Text(
              position != null ? 'Alterar' : 'Selecionar',
              style: RTTypography.body.copyWith(color: RTColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueMono = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool valueMono;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: RTSpacing.x3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: RTColors.inkMute),
          const SizedBox(width: RTSpacing.x2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: RTTypography.eyebrow.copyWith(color: RTColors.inkMute, fontSize: 10),
                ),
                Text(
                  value,
                  style: valueMono
                      ? RTTypography.mono.copyWith(fontSize: 12)
                      : RTTypography.body.copyWith(fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
