import 'dart:async';

import 'package:flutter/material.dart';
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
import '../utils/top_feedback.dart';
import 'map_point_picker_screen.dart';

/// Wizard de cadastro de gateway — 3 etapas.
///
/// Etapa 1: Identidade (nome, propriedade, tipo)
/// Etapa 2: Vinculação (descoberta rede/BLE, ID gateway, host)
/// Etapa 3: Confirmar (preview + posição + salvar)
class AddGatewayScreen extends StatefulWidget {
  const AddGatewayScreen({super.key});

  @override
  State<AddGatewayScreen> createState() => _AddGatewayScreenState();
}

class _AddGatewayScreenState extends State<AddGatewayScreen> {
  final _pageController = PageController();
  int _step = 0;

  // ── Dados carregados async ──────────────────────────────────
  List<Map<String, dynamic>> _properties = [];
  bool _loading = true;

  // ── Estado do formulário ────────────────────────────────────
  String? _propertyId;
  bool _isMatrix = false;
  LatLng? _selectedPosition;
  String? _selectedDetectedGatewayId;
  bool _scanningNetwork = false;
  List<Map<String, dynamic>> _networkDiscoveredGateways = [];

  final _nameCtrl = TextEditingController();
  final _statusCtrl = TextEditingController(text: 'active');
  final _gatewayIdCtrl = TextEditingController();
  final _hostCtrl = TextEditingController(text: ManualSettings.defaultGatewayWsHost);

  // ── Erros de validação ─────────────────────────────────────
  String? _nameError;
  String? _gatewayIdError;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameCtrl.dispose();
    _statusCtrl.dispose();
    _gatewayIdCtrl.dispose();
    _hostCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final auth = context.read<AuthService>();
    final fb = context.read<CloudService>();
    final gatewayService = context.read<GatewayService>();
    final bleService = context.read<BluetoothDiscoveryService>();
    final uid = auth.user?.uid;
    if (uid == null) return;

    if (!gatewayService.isConnected) gatewayService.connect();
    unawaited(bleService.startScan());

    final properties = await fb.getRuralProperties(uid: uid, isAdmin: auth.isAdmin);
    if (!mounted) return;

    List<Map<String, dynamic>> networkGateways = [];
    final connected = gatewayService.connectedGatewayCandidate;
    if (connected != null) networkGateways = [connected];

    setState(() {
      _properties = properties;
      _propertyId = properties.isNotEmpty ? properties.first['id'].toString() : null;
      _networkDiscoveredGateways = networkGateways;
      _loading = false;
    });

    // Pre-fill se gateway já detectado
    final initial = _mergedDiscoveredGateways();
    if (initial.isNotEmpty) {
      setState(() => _applyDetectedGateway(initial.first));
    }
  }

  // ── Helpers ─────────────────────────────────────────────────

  List<Map<String, dynamic>> _mergedDiscoveredGateways() {
    final bleService = context.read<BluetoothDiscoveryService>();
    final byId = <String, Map<String, dynamic>>{};

    for (final net in _networkDiscoveredGateways) {
      final id = net['gateway_id']?.toString();
      if (id == null || id.isEmpty) continue;
      byId[id] = {...net, 'gateway_id': id, 'source_type': 'network'};
    }

    for (final ble in bleService.discoveredGateways) {
      final id = ble['gateway_id']?.toString();
      if (id == null || id.isEmpty) continue;
      final current = byId[id];
      if (current == null) {
        byId[id] = {...ble, 'gateway_id': id, 'source_type': 'ble'};
      } else {
        current['source_type'] = '${current['source_type']}+ble';
        final ws = ble['host_ws']?.toString();
        if ((current['host_ws']?.toString().trim() ?? '').isEmpty && ws != null && ws.isNotEmpty) {
          current['host_ws'] = ws;
        }
        byId[id] = current;
      }
    }

    final out = byId.values.toList();
    out.sort((a, b) => (a['gateway_id'] as String).compareTo(b['gateway_id'] as String));
    return out;
  }

  void _applyDetectedGateway(Map<String, dynamic> detected) {
    final id = detected['gateway_id']?.toString();
    if (id == null || id.isEmpty) return;
    _selectedDetectedGatewayId = id;
    _gatewayIdCtrl.text = id;
    final ws = detected['host_ws']?.toString();
    if (ws != null && ws.isNotEmpty) _hostCtrl.text = ws;
    if (_nameCtrl.text.trim().isEmpty || _nameCtrl.text.startsWith('Gateway')) {
      _nameCtrl.text = detected['name']?.toString() ?? 'Gateway $id';
    }
    final explicit = detected['is_matrix'] ?? detected['isMatrix'];
    if (explicit is bool) {
      _isMatrix = explicit;
    } else {
      final kind = (detected['kind'] ?? '').toString().toLowerCase();
      if (kind == 'gateway_matrix' || kind == 'matrix' || id.toUpperCase().startsWith('RT-M-')) {
        _isMatrix = true;
      }
    }
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

  double? _toDouble(dynamic v) {
    if (v is num) return v.isFinite ? v.toDouble() : null;
    if (v is String) {
      final d = double.tryParse(v.trim());
      return (d != null && d.isFinite) ? d : null;
    }
    return null;
  }

  Future<void> _scanNetwork() async {
    final gatewayService = context.read<GatewayService>();
    setState(() => _scanningNetwork = true);
    final found = await gatewayService.discoverGatewaysOnLocalNetwork();
    if (!mounted) return;
    final connected = gatewayService.connectedGatewayCandidate;
    final merged = [...found];
    if (connected != null &&
        connected['gateway_id'] != null &&
        merged.every((g) => g['gateway_id']?.toString() != connected['gateway_id']?.toString())) {
      merged.insert(0, connected);
    }
    setState(() {
      _networkDiscoveredGateways = merged;
      _scanningNetwork = false;
      final discovered = _mergedDiscoveredGateways();
      if (discovered.isEmpty) return;
      final current = discovered.cast<Map<String, dynamic>?>().firstWhere(
            (g) => g?['gateway_id']?.toString() == _selectedDetectedGatewayId,
            orElse: () => null,
          );
      _applyDetectedGateway(current ?? discovered.first);
    });
  }

  // ── Validação por etapa ──────────────────────────────────────

  bool _validateStep1() {
    bool ok = true;
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _nameError = 'Informe o nome do gateway');
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
    final id = (_selectedDetectedGatewayId ?? _gatewayIdCtrl.text).trim();
    if (id.isEmpty) {
      setState(() => _gatewayIdError = 'Informe o ID do gateway');
      return false;
    }
    setState(() => _gatewayIdError = null);
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
    final fb = context.read<CloudService>();
    final hasBinding = (_selectedDetectedGatewayId ?? '').isNotEmpty;

    if (!hasBinding && _selectedPosition == null) {
      AppFeedback.error(
        'Selecione o ponto no mapa ou vincule um gateway detectado.',
      );
      return;
    }

    final effectiveId = hasBinding
        ? _selectedDetectedGatewayId!.trim()
        : _gatewayIdCtrl.text.trim();

    if (effectiveId.isEmpty) {
      AppFeedback.error('Informe o ID do gateway.');
      return;
    }

    try {
      await fb.addGateway(
        name: _nameCtrl.text.trim(),
        status: _statusCtrl.text.trim(),
        isMatrix: _isMatrix,
        gatewayId: effectiveId,
        host: _hostCtrl.text.trim().isEmpty ? null : _hostCtrl.text.trim(),
        propertyId: _propertyId,
        lat: _selectedPosition?.latitude,
        lon: _selectedPosition?.longitude,
      );
      if (!mounted) return;
      Navigator.pop(context);
      AppFeedback.success('Gateway incluído com sucesso.');
    } catch (e) {
      if (!mounted) return;
      AppFeedback.error('Erro ao salvar gateway: $e');
    }
  }

  // ── UI ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
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
              'Incluir gateway',
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
                      // ── Etapa 1: Identidade ──────────────────────────
                      SingleChildScrollView(
                        padding: const EdgeInsets.all(RTSpacing.screen),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Identidade do gateway', style: RTTypography.h3),
                            const SizedBox(height: RTSpacing.x2),
                            Text(
                              'Defina nome, propriedade e tipo do gateway.',
                              style: RTTypography.body.copyWith(color: RTColors.inkSoft),
                            ),
                            const SizedBox(height: RTSpacing.x6),

                            _FieldLabel('Nome do gateway'),
                            const SizedBox(height: RTSpacing.x2),
                            TextFormField(
                              key: const Key('add_gateway_name_input'),
                              controller: _nameCtrl,
                              decoration: InputDecoration(
                                hintText: 'Ex: Gateway Fazenda Norte',
                                errorText: _nameError,
                                filled: true,
                                fillColor: RTColors.bgAlt,
                                border: _border(RTColors.hair),
                                enabledBorder: _border(_nameError != null ? RTColors.danger : RTColors.hair),
                                focusedBorder: _border(RTColors.primary, width: 1.6),
                              ),
                            ),
                            const SizedBox(height: RTSpacing.x4),

                            _FieldLabel('Propriedade rural'),
                            const SizedBox(height: RTSpacing.x2),
                            DropdownButtonFormField<String>(
                              key: const Key('add_gateway_property_dropdown'),
                              value: _propertyId,
                              items: _properties
                                  .map((p) => DropdownMenuItem<String>(
                                        value: p['id'].toString(),
                                        child: Text((p['name'] ?? p['id']).toString()),
                                      ))
                                  .toList(),
                              onChanged: (v) => setState(() => _propertyId = v),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: RTColors.bgAlt,
                                border: _border(RTColors.hair),
                                enabledBorder: _border(RTColors.hair),
                                focusedBorder: _border(RTColors.primary, width: 1.6),
                              ),
                            ),
                            const SizedBox(height: RTSpacing.x4),

                            _FieldLabel('Status'),
                            const SizedBox(height: RTSpacing.x2),
                            TextFormField(
                              key: const Key('add_gateway_status_input'),
                              controller: _statusCtrl,
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: RTColors.bgAlt,
                                border: _border(RTColors.hair),
                                enabledBorder: _border(RTColors.hair),
                                focusedBorder: _border(RTColors.primary, width: 1.6),
                              ),
                            ),
                            const SizedBox(height: RTSpacing.x4),

                            // Tipo de gateway
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: RTSpacing.x4,
                                vertical: RTSpacing.x2,
                              ),
                              decoration: BoxDecoration(
                                color: RTColors.bgAlt,
                                borderRadius: BorderRadius.circular(RTRadius.r3),
                                border: Border.all(color: RTColors.hair),
                              ),
                              child: auth.isAdmin
                                  ? SwitchListTile(
                                      contentPadding: EdgeInsets.zero,
                                      value: _isMatrix,
                                      activeColor: RTColors.primary,
                                      onChanged: (v) => setState(() => _isMatrix = v),
                                      title: Text('Gateway matriz', style: RTTypography.body),
                                      subtitle: Text(
                                        'Ative para cadastrar como gateway matriz (hub central).',
                                        style: RTTypography.bodySmall.copyWith(color: RTColors.inkSoft),
                                      ),
                                    )
                                  : ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text('Tipo de gateway', style: RTTypography.body),
                                      trailing: Text(
                                        _isMatrix ? 'Matriz' : 'Comum',
                                        style: RTTypography.body.copyWith(color: RTColors.inkSoft),
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),

                      // ── Etapa 2: Vinculação ──────────────────────────
                      AnimatedBuilder(
                        animation: Listenable.merge([
                          context.read<GatewayService>(),
                          context.read<BluetoothDiscoveryService>(),
                        ]),
                        builder: (ctx, _) {
                          final gatewayService = context.read<GatewayService>();
                          final bleService = context.read<BluetoothDiscoveryService>();
                          final discovered = _mergedDiscoveredGateways();
                          return SingleChildScrollView(
                            padding: const EdgeInsets.all(RTSpacing.screen),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Vinculação', style: RTTypography.h3),
                                const SizedBox(height: RTSpacing.x2),
                                Text(
                                  'Informe o ID do gateway e conecte via rede ou Bluetooth.',
                                  style: RTTypography.body.copyWith(color: RTColors.inkSoft),
                                ),
                                const SizedBox(height: RTSpacing.x6),

                                // Descoberta
                                Text('Descoberta automática', style: RTTypography.eyebrow.copyWith(color: RTColors.inkSoft)),
                                const SizedBox(height: RTSpacing.x3),
                                Wrap(
                                  spacing: RTSpacing.x2,
                                  runSpacing: RTSpacing.x2,
                                  children: [
                                    OutlinedButton.icon(
                                      key: const Key('add_gateway_connect_button'),
                                      onPressed: gatewayService.connect,
                                      icon: Icon(gatewayService.isConnected ? Icons.wifi : Icons.wifi_off),
                                      label: Text(gatewayService.isConnected ? 'Reconectar' : 'Conectar gateway'),
                                    ),
                                    OutlinedButton.icon(
                                      key: const Key('add_gateway_scan_ble_button'),
                                      onPressed: bleService.isScanning ? null : () => bleService.startScan(),
                                      icon: Icon(bleService.isScanning ? Icons.bluetooth_connected : Icons.bluetooth_searching),
                                      label: Text(bleService.isScanning ? 'Buscando BLE...' : 'Bluetooth'),
                                    ),
                                    OutlinedButton.icon(
                                      key: const Key('add_gateway_scan_network_button'),
                                      onPressed: _scanningNetwork ? null : _scanNetwork,
                                      icon: _scanningNetwork
                                          ? const SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            )
                                          : const Icon(Icons.search),
                                      label: Text(_scanningNetwork ? 'Buscando...' : 'Buscar na rede'),
                                    ),
                                  ],
                                ),
                                if ((bleService.lastError ?? '').isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: RTSpacing.x2),
                                    child: Text(
                                      'BLE: ${bleService.lastError}',
                                      style: RTTypography.bodySmall.copyWith(color: RTColors.danger),
                                    ),
                                  ),
                                const SizedBox(height: RTSpacing.x4),

                                // Gateway detectado
                                _FieldLabel('Gateway detectado'),
                                const SizedBox(height: RTSpacing.x2),
                                DropdownButtonFormField<String>(
                                  key: const Key('add_gateway_detected_dropdown'),
                                  value: _selectedDetectedGatewayId ?? '',
                                  items: [
                                    const DropdownMenuItem<String>(
                                      value: '',
                                      child: Text('Não vincular agora (modo manual)'),
                                    ),
                                    ...discovered.map((g) => DropdownMenuItem<String>(
                                          value: g['gateway_id']?.toString() ?? '',
                                          child: Text(
                                            '${g['name'] ?? 'Gateway'} (${g['source_type'] ?? ''})',
                                          ),
                                        )),
                                  ],
                                  onChanged: (v) => setState(() {
                                    if (v == null || v.isEmpty) {
                                      _selectedDetectedGatewayId = null;
                                      return;
                                    }
                                    final found = discovered.cast<Map<String, dynamic>?>().firstWhere(
                                          (g) => g?['gateway_id']?.toString() == v,
                                          orElse: () => null,
                                        );
                                    if (found != null) _applyDetectedGateway(found);
                                  }),
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor: RTColors.bgAlt,
                                    border: _border(RTColors.hair),
                                    enabledBorder: _border(RTColors.hair),
                                    focusedBorder: _border(RTColors.primary, width: 1.6),
                                  ),
                                ),
                                if (discovered.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: RTSpacing.x2),
                                    child: Text(
                                      'Nenhum gateway detectado ainda. Tente Wi-Fi ou Bluetooth.',
                                      style: RTTypography.bodySmall.copyWith(color: RTColors.inkMute),
                                    ),
                                  ),
                                const SizedBox(height: RTSpacing.x4),

                                // ID manual
                                _FieldLabel('ID do gateway'),
                                const SizedBox(height: RTSpacing.x2),
                                TextFormField(
                                  key: const Key('add_gateway_id_input'),
                                  controller: _gatewayIdCtrl,
                                  decoration: InputDecoration(
                                    hintText: 'Ex: RT-M-001',
                                    errorText: _gatewayIdError,
                                    helperText: 'Preenchido automaticamente ao detectar',
                                    filled: true,
                                    fillColor: RTColors.bgAlt,
                                    border: _border(RTColors.hair),
                                    enabledBorder: _border(_gatewayIdError != null ? RTColors.danger : RTColors.hair),
                                    focusedBorder: _border(RTColors.primary, width: 1.6),
                                  ),
                                ),
                                const SizedBox(height: RTSpacing.x4),

                                // Host
                                _FieldLabel('Host WebSocket (opcional)'),
                                const SizedBox(height: RTSpacing.x2),
                                TextFormField(
                                  key: const Key('add_gateway_host_input'),
                                  controller: _hostCtrl,
                                  keyboardType: TextInputType.url,
                                  decoration: InputDecoration(
                                    hintText: 'Ex: ws://192.168.4.1:81',
                                    filled: true,
                                    fillColor: RTColors.bgAlt,
                                    border: _border(RTColors.hair),
                                    enabledBorder: _border(RTColors.hair),
                                    focusedBorder: _border(RTColors.primary, width: 1.6),
                                  ),
                                ),
                                const SizedBox(height: RTSpacing.x6),

                                // Posição
                                Text('Posição', style: RTTypography.eyebrow.copyWith(color: RTColors.inkSoft)),
                                const SizedBox(height: RTSpacing.x3),
                                _PositionCard(
                                  position: _selectedPosition,
                                  onPick: () async {
                                    final picked = await Navigator.push<LatLng>(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => MapPointPickerScreen(
                                          initial: _selectedPosition,
                                          propertyPolygon: _polygonFromProperty(_propertyId),
                                        ),
                                      ),
                                    );
                                    if (picked != null) setState(() => _selectedPosition = picked);
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),

                      // ── Etapa 3: Confirmar ────────────────────────────
                      SingleChildScrollView(
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
                                          color: RTColors.accentSoft,
                                          borderRadius: BorderRadius.circular(RTRadius.r3),
                                        ),
                                        child: Icon(Icons.wifi, color: RTColors.accent, size: 20),
                                      ),
                                      const SizedBox(width: RTSpacing.x3),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _nameCtrl.text.isNotEmpty ? _nameCtrl.text : '—',
                                              style: RTTypography.h3.copyWith(fontSize: 18),
                                            ),
                                            Text(
                                              _isMatrix ? 'Matriz' : 'Gateway comum',
                                              style: RTTypography.bodySmall.copyWith(color: RTColors.inkSoft),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: RTSpacing.x4),
                                  _PreviewRow(
                                    icon: Icons.tag,
                                    label: 'ID',
                                    value: (_selectedDetectedGatewayId ?? _gatewayIdCtrl.text).trim().isEmpty
                                        ? '—'
                                        : (_selectedDetectedGatewayId ?? _gatewayIdCtrl.text).trim(),
                                    valueMono: true,
                                  ),
                                  _PreviewRow(
                                    icon: Icons.landscape_outlined,
                                    label: 'Propriedade',
                                    value: _propertyId == null
                                        ? '—'
                                        : (_properties.cast<Map<String, dynamic>?>().firstWhere(
                                              (p) => p?['id'].toString() == _propertyId,
                                              orElse: () => null,
                                            )?['name'] ??
                                            _propertyId!),
                                  ),
                                  _PreviewRow(
                                    icon: Icons.lan_outlined,
                                    label: 'Host',
                                    value: _hostCtrl.text.trim().isEmpty ? '—' : _hostCtrl.text.trim(),
                                    valueMono: true,
                                  ),
                                  _PreviewRow(
                                    icon: Icons.location_on_outlined,
                                    label: 'Posição',
                                    value: _selectedPosition == null
                                        ? 'Não definida'
                                        : '${_selectedPosition!.latitude.toStringAsFixed(6)}, ${_selectedPosition!.longitude.toStringAsFixed(6)}',
                                    valueMono: _selectedPosition != null,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: RTSpacing.x6),

                            const RTConfirmLoRa(
                              message:
                                  'O gateway será vinculado à propriedade e ficará visível no mapa após conexão.',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Barra de navegação ─────────────────────────────────
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
                                label: 'Salvar gateway',
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

  OutlineInputBorder _border(Color c, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(RTRadius.r3),
        borderSide: BorderSide(color: c, width: width),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Subwidgets compartilhados (duplicados no arquivo por isolamento)
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
