import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../components/domain/rt_confirm_lora.dart';
import '../components/primitives/rt_button.dart';
import '../components/primitives/rt_card.dart';
import '../components/primitives/rt_chip.dart';
import '../components/primitives/rt_stepper.dart';
import '../design/colors.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../models/device_model.dart';
import '../models/herding_operation_model.dart';
import '../models/polygon_map_context.dart';
import '../services/auth_service.dart';
import '../services/cloud_service.dart';
import '../utils/polygon_edit_session.dart';
import '../utils/polygon_metrics.dart';
import '../utils/top_feedback.dart';
import '../widgets/polygon_editing_map.dart';

class HerdingScreen extends StatefulWidget {
  final String? initialDeviceId;
  final String? initialPropertyId;
  final double? initialLat;
  final double? initialLon;

  const HerdingScreen({
    super.key,
    this.initialDeviceId,
    this.initialPropertyId,
    this.initialLat,
    this.initialLon,
  });

  @override
  State<HerdingScreen> createState() => _HerdingScreenState();
}

class _HerdingScreenState extends State<HerdingScreen> {
  static const int _maxTargetPolygonPoints = 32;
  static const _steps = ['Coleiras', 'Área-alvo', 'Revisar'];

  final PageController _pageController = PageController();
  final Set<String> _selectedDeviceIds = <String>{};
  late final PolygonEditSessionController _polygonController;
  String? _selectedPropertyId;
  String? _createdOperationId;
  bool _isSubmitting = false;
  bool _didSeedInitialDevice = false;
  int _currentStep = 0;

  @override
  void initState() {
    super.initState();
    _polygonController = PolygonEditSessionController();
    final initialDeviceId = widget.initialDeviceId?.trim();
    if (initialDeviceId != null && initialDeviceId.isNotEmpty) {
      _selectedDeviceIds.add(initialDeviceId);
    }
    final initialPropertyId = widget.initialPropertyId?.trim();
    if (initialPropertyId != null && initialPropertyId.isNotEmpty) {
      _selectedPropertyId = initialPropertyId;
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _polygonController.dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _idFromRefOrPath(dynamic value) {
    if (value == null) return '';
    final raw = value.toString().trim();
    if (raw.isEmpty) return '';
    if (!raw.contains('/')) return raw;
    final parts = raw.split('/').where((e) => e.isNotEmpty).toList();
    return parts.isEmpty ? raw : parts.last;
  }

  String? _userIdFrom(dynamic value) {
    final id = _idFromRefOrPath(value);
    return id.isEmpty ? null : id;
  }

  List<LatLng> _decodePolygon(dynamic raw) {
    if (raw is! List) return const <LatLng>[];
    final points = <LatLng>[];
    for (final entry in raw) {
      if (entry is Map) {
        final lat = entry['lat'];
        final lon = entry['lon'] ?? entry['lng'];
        if (lat is num && lon is num) {
          points.add(LatLng(lat.toDouble(), lon.toDouble()));
        }
        continue;
      }
      if (entry is List && entry.length >= 2) {
        final lat = entry[0];
        final lon = entry[1];
        if (lat is num && lon is num) {
          points.add(LatLng(lat.toDouble(), lon.toDouble()));
        }
      }
    }
    return points;
  }

  LatLng? _devicePosition(DeviceModel device) {
    final lat = device.lat;
    final lon = device.lon;
    if (lat == null || lon == null) return null;
    if (!lat.isFinite || !lon.isFinite) return null;
    if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return null;
    return LatLng(lat, lon);
  }

  LatLng? _gatewayPosition(Map<String, dynamic> gateway) {
    final lat = gateway['lat'];
    final lon = gateway['lon'];
    if (lat is! num || lon is! num) return null;
    final parsedLat = lat.toDouble();
    final parsedLon = lon.toDouble();
    if (!parsedLat.isFinite || !parsedLon.isFinite) return null;
    if (parsedLat < -90 || parsedLat > 90 || parsedLon < -180 || parsedLon > 180) return null;
    return LatLng(parsedLat, parsedLon);
  }

  String _propertyLabel(Map<String, dynamic> property) {
    final name = (property['name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    final id = (property['id'] ?? '').toString().trim();
    return id.isEmpty ? 'Propriedade' : 'Propriedade $id';
  }

  String _gatewayLabel(Map<String, dynamic> gateway) {
    final name = (gateway['name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    final id = _idFromRefOrPath(gateway['id'] ?? gateway['gatewayId']);
    return id.isEmpty ? 'Gateway' : id;
  }

  void _syncInitialPropertyAndSelection(
    List<Map<String, dynamic>> properties,
    List<DeviceModel> devices,
  ) {
    if (_selectedPropertyId == null || _selectedPropertyId!.trim().isEmpty) {
      final preferred = widget.initialPropertyId?.trim();
      if (preferred != null &&
          preferred.isNotEmpty &&
          properties.any((p) => p['id']?.toString() == preferred)) {
        _selectedPropertyId = preferred;
      } else if (properties.isNotEmpty) {
        _selectedPropertyId = properties.first['id']?.toString();
      }
    }

    if (_didSeedInitialDevice) return;
    _didSeedInitialDevice = true;

    final initialDeviceId = widget.initialDeviceId?.trim();
    if (initialDeviceId == null || initialDeviceId.isEmpty) return;
    final matching = devices.cast<DeviceModel?>().firstWhere(
          (d) => d?.loraDeviceId == initialDeviceId,
          orElse: () => null,
        );
    final propertyId = matching?.propertyId?.trim();
    if (propertyId != null && propertyId.isNotEmpty) {
      _selectedPropertyId = propertyId;
    }
  }

  List<DeviceModel> _devicesForProperty(List<DeviceModel> devices) {
    final propertyId = _selectedPropertyId?.trim();
    if (propertyId == null || propertyId.isEmpty) return const <DeviceModel>[];
    return devices
        .where((d) => d.propertyId?.trim() == propertyId)
        .where((d) => d.loraDeviceId != null)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  List<Map<String, dynamic>> _areasForProperty(List<Map<String, dynamic>> areas) {
    final propertyId = _selectedPropertyId?.trim();
    if (propertyId == null || propertyId.isEmpty) return const [];
    return areas.where((a) => a['propertyId']?.toString() == propertyId).toList();
  }

  List<Map<String, dynamic>> _gatewaysForProperty(List<Map<String, dynamic>> gateways) {
    final propertyId = _selectedPropertyId?.trim();
    if (propertyId == null || propertyId.isEmpty) return const [];
    return gateways
        .where((g) => _idFromRefOrPath(g['propertyId']) == propertyId)
        .toList();
  }

  void _toggleDevice(DeviceModel device) {
    final deviceId = device.loraDeviceId;
    if (deviceId == null) return;
    setState(() {
      if (_selectedDeviceIds.contains(deviceId)) {
        _selectedDeviceIds.remove(deviceId);
      } else {
        _selectedDeviceIds.add(deviceId);
      }
    });
  }

  void _setProperty(String? propertyId) {
    if (propertyId == null || propertyId.trim().isEmpty) return;
    setState(() {
      _selectedPropertyId = propertyId;
      _selectedDeviceIds.clear();
      _polygonController.resetSession(const <LatLng>[]);
      _createdOperationId = null;
    });
  }

  void _goToStep(int step) {
    setState(() => _currentStep = step);
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
    );
  }

  void _nextStep() {
    if (_currentStep < _steps.length - 1) _goToStep(_currentStep + 1);
  }

  void _prevStep() {
    if (_currentStep > 0) _goToStep(_currentStep - 1);
  }

  // ── Submit ─────────────────────────────────────────────────────────────────

  Future<void> _submitOperation(
    Map<String, dynamic> property,
    List<DeviceModel> propertyDevices,
    AuthService auth,
    CloudService cloud,
  ) async {
    if (_isSubmitting) return;
    final propertyId = _selectedPropertyId?.trim();
    final uid = auth.user?.uid.trim();
    if (propertyId == null || propertyId.isEmpty || uid == null || uid.isEmpty) {
      AppFeedback.error('Não foi possível identificar a propriedade ou o usuário.');
      return;
    }

    final selectedDevices = propertyDevices
        .where((d) => _selectedDeviceIds.contains(d.loraDeviceId))
        .toList();
    if (selectedDevices.isEmpty) {
      AppFeedback.error('Selecione pelo menos uma coleira na etapa 1.');
      return;
    }
    if (_polygonController.points.length < 3) {
      AppFeedback.error('Desenhe o polígono de destino na etapa 2.');
      return;
    }

    final matrixGatewayId =
        await cloud.resolveMatrixGatewayIdForProperty(propertyId: propertyId);
    if (matrixGatewayId == null || matrixGatewayId.isEmpty) {
      AppFeedback.error('Nenhum gateway matriz conectado a essa propriedade.');
      return;
    }

    final notifyUserIds = await cloud.getLinkedUserIdsForProperty(propertyId);
    final ownerUid = _userIdFrom(property['ownerUid']) ??
        _userIdFrom(property['createdByUid']) ??
        uid;
    final selectedDeviceIds = selectedDevices
        .map((d) => d.loraDeviceId)
        .whereType<String>()
        .toList()
      ..sort();
    final targetPolygon = _polygonController.points
        .map((p) => <double>[p.latitude, p.longitude])
        .toList();

    setState(() => _isSubmitting = true);
    String? operationId;
    try {
      operationId = await cloud.createHerdingOperation(
        ownerUid: ownerUid,
        requestedByUid: uid,
        requestedByRole: auth.role,
        propertyId: propertyId,
        targetPolygon: targetPolygon,
        selectedDeviceIds: selectedDeviceIds,
        notifyUserIds: notifyUserIds,
        matrixGatewayId: matrixGatewayId,
      );

      final loraCommandId = await cloud.enqueueScopedCommand(
        command: 'SET_HERDING_PLAN',
        propertyId: propertyId,
        requestedByUid: uid,
        requestedByRole: auth.role,
        matrixGatewayId: matrixGatewayId,
        targetDeviceIds: selectedDeviceIds,
        payload: <String, dynamic>{
          'operation_id': operationId,
          'polygon_kind': 'herding',
          'origin_doc_type': 'herdingOperation',
          'origin_doc_id': operationId,
          'property_id': propertyId,
          'owner_uid': ownerUid,
          'matrix_gateway_id': matrixGatewayId,
          'requested_by_uid': uid,
          'requested_by_role': auth.role,
          'selected_device_ids': selectedDeviceIds,
          'notify_user_ids': notifyUserIds,
          'target_polygon': targetPolygon,
          'area_promotion_requested': true,
          'phases': <List<List<double>>>[targetPolygon],
        },
        businessRef: <String, dynamic>{
          'type': 'herdingOperation',
          'id': operationId,
        },
        ttl: const Duration(minutes: 20),
      );
      await cloud.attachLoraCommandToHerdingOperation(
        operationId: operationId,
        loraCommandId: loraCommandId,
      );

      if (!mounted) return;
      setState(() => _createdOperationId = operationId);
      AppFeedback.show('Operação criada e enfileirada para a matriz.');
    } catch (e) {
      if (operationId != null) {
        await cloud.markHerdingOperationSubmissionFailed(
          operationId: operationId,
          reason: e.toString(),
        );
      }
      if (!mounted) return;
      AppFeedback.error('Falha ao criar o arrebanhamento: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final cloud = context.read<CloudService>();
    final uid = auth.user?.uid;
    if (uid == null || uid.trim().isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: RTColors.bgAlt,
      appBar: AppBar(
        title: const Text('Solicitar arrebanhamento'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              RTSpacing.x4,
              0,
              RTSpacing.x4,
              RTSpacing.x3,
            ),
            child: RTStepper(steps: _steps, currentStep: _currentStep),
          ),
        ),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: cloud.streamRuralProperties(uid: uid, isAdmin: auth.isAdmin),
        builder: (context, propertySnap) {
          if (propertySnap.hasError) {
            return _buildError('Erro ao carregar propriedades: ${propertySnap.error}');
          }
          final properties = propertySnap.data ?? const <Map<String, dynamic>>[];
          if (properties.isEmpty &&
              propertySnap.connectionState == ConnectionState.done) {
            return _buildEmpty(
              'Nenhuma propriedade cadastrada',
              'Cadastre ou vincule uma propriedade para usar o arrebanhamento.',
            );
          }

          return StreamBuilder<List<DeviceModel>>(
            stream: cloud.streamDevices(uid: uid, isAdmin: auth.isAdmin),
            builder: (context, deviceSnap) {
              if (deviceSnap.hasError) {
                return _buildError('Erro ao carregar coleiras: ${deviceSnap.error}');
              }
              final devices = deviceSnap.data ?? const <DeviceModel>[];
              _syncInitialPropertyAndSelection(properties, devices);

              final selectedProperty =
                  properties.cast<Map<String, dynamic>?>().firstWhere(
                        (p) => p?['id']?.toString() == _selectedPropertyId,
                        orElse: () => null,
                      );
              final propertyPolygon = _decodePolygon(selectedProperty?['points']);
              final propertyDevices = _devicesForProperty(devices);

              return StreamBuilder<List<Map<String, dynamic>>>(
                stream: cloud.streamAreas(uid: uid, isAdmin: auth.isAdmin),
                builder: (context, areaSnap) {
                  final propertyAreas =
                      _areasForProperty(areaSnap.data ?? const []);

                  return StreamBuilder<List<Map<String, dynamic>>>(
                    stream: cloud.streamGateways(uid: uid, isAdmin: auth.isAdmin),
                    builder: (context, gatewaySnap) {
                      final propertyGateways =
                          _gatewaysForProperty(gatewaySnap.data ?? const []);

                      return StreamBuilder<List<HerdingOperationModel>>(
                        stream: cloud.streamHerdingOperations(
                          uid: uid,
                          isAdmin: auth.isAdmin,
                        ),
                        builder: (context, operationsSnap) {
                          final operations =
                              operationsSnap.data ?? const <HerdingOperationModel>[];
                          final trackedOperation = _createdOperationId == null
                              ? operations.cast<HerdingOperationModel?>().firstWhere(
                                    (op) => op?.propertyId == _selectedPropertyId,
                                    orElse: () => null,
                                  )
                              : operations.cast<HerdingOperationModel?>().firstWhere(
                                    (op) => op?.id == _createdOperationId,
                                    orElse: () => null,
                                  );

                          final mapContext = _buildMapContext(
                            propertyPolygon,
                            propertyAreas,
                            propertyDevices,
                            propertyGateways,
                          );

                          return PageView(
                            controller: _pageController,
                            physics: const NeverScrollableScrollPhysics(),
                            children: [
                              _Step1Page(
                                properties: properties,
                                selectedPropertyId: _selectedPropertyId,
                                propertyDevices: propertyDevices,
                                selectedDeviceIds: _selectedDeviceIds,
                                onPropertyChanged: _setProperty,
                                onToggleDevice: _toggleDevice,
                                onNext: _nextStep,
                              ),
                              _Step2Page(
                                polygonController: _polygonController,
                                mapContext: mapContext,
                                propertyPolygon: propertyPolygon,
                                initialLat: widget.initialLat,
                                initialLon: widget.initialLon,
                                selectedPropertyId: _selectedPropertyId,
                                maxPoints: _maxTargetPolygonPoints,
                                onBack: _prevStep,
                                onNext: _nextStep,
                              ),
                              _Step3Page(
                                propertyLabel: selectedProperty != null
                                    ? _propertyLabel(selectedProperty)
                                    : 'Sem propriedade',
                                propertyDevices: propertyDevices,
                                selectedDeviceIds: _selectedDeviceIds,
                                polygonController: _polygonController,
                                trackedOperation: trackedOperation,
                                isSubmitting: _isSubmitting,
                                onBack: _prevStep,
                                onSubmit: selectedProperty == null
                                    ? null
                                    : () => _submitOperation(
                                          selectedProperty,
                                          propertyDevices,
                                          auth,
                                          cloud,
                                        ),
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

  PolygonMapContext _buildMapContext(
    List<LatLng> propertyPolygon,
    List<Map<String, dynamic>> propertyAreas,
    List<DeviceModel> propertyDevices,
    List<Map<String, dynamic>> propertyGateways,
  ) {
    return PolygonMapContext(
      boundaryPolygon: propertyPolygon,
      areaPolygons: propertyAreas
          .map((a) => _decodePolygon(a['perimeter']))
          .where((pts) => pts.length >= 3)
          .toList(),
      devices: propertyDevices
          .map((device) {
            final deviceId = device.loraDeviceId;
            final point = _devicePosition(device);
            if (deviceId == null || point == null) return null;
            return PolygonMapDeviceOverlay(
              id: deviceId,
              label: device.name,
              point: point,
              selected: _selectedDeviceIds.contains(deviceId),
              onTap: () => _toggleDevice(device),
            );
          })
          .whereType<PolygonMapDeviceOverlay>()
          .toList(),
      gateways: propertyGateways
          .map((g) {
            final point = _gatewayPosition(g);
            if (point == null) return null;
            return PolygonMapGatewayOverlay(
              id: _idFromRefOrPath(g['id'] ?? g['gatewayId']),
              label: _gatewayLabel(g),
              point: point,
            );
          })
          .whereType<PolygonMapGatewayOverlay>()
          .toList(),
    );
  }

  Widget _buildEmpty(String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RTSpacing.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: RTColors.primarySoft,
                borderRadius: BorderRadius.circular(RTRadius.r3),
              ),
              child: Icon(Icons.landscape_outlined, color: RTColors.primary, size: 32),
            ),
            const SizedBox(height: RTSpacing.x4),
            Text(title,
                style: RTTypography.h3.copyWith(fontSize: 18),
                textAlign: TextAlign.center),
            const SizedBox(height: RTSpacing.x2),
            Text(subtitle,
                style: RTTypography.bodySmall, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RTSpacing.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: RTColors.danger, size: 32),
            const SizedBox(height: RTSpacing.x3),
            Text(message,
                style: RTTypography.bodySmall, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

// ── Etapa 1: Seleção de coleiras ─────────────────────────────────────────────

class _Step1Page extends StatelessWidget {
  const _Step1Page({
    required this.properties,
    required this.selectedPropertyId,
    required this.propertyDevices,
    required this.selectedDeviceIds,
    required this.onPropertyChanged,
    required this.onToggleDevice,
    required this.onNext,
  });

  final List<Map<String, dynamic>> properties;
  final String? selectedPropertyId;
  final List<DeviceModel> propertyDevices;
  final Set<String> selectedDeviceIds;
  final ValueChanged<String?> onPropertyChanged;
  final ValueChanged<DeviceModel> onToggleDevice;
  final VoidCallback onNext;

  String _propertyLabel(Map<String, dynamic> p) {
    final name = (p['name'] ?? '').toString().trim();
    return name.isNotEmpty ? name : 'Propriedade ${p['id'] ?? ''}';
  }

  @override
  Widget build(BuildContext context) {
    final canAdvance = selectedDeviceIds.isNotEmpty;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              RTSpacing.x4,
              RTSpacing.x4,
              RTSpacing.x4,
              RTSpacing.x8,
            ),
            children: [
              // Property selector
              RTCard(
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                          RTSpacing.x4, RTSpacing.x3, RTSpacing.x4, 0),
                      child: Text('PROPRIEDADE', style: RTTypography.eyebrow),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                          RTSpacing.x4, RTSpacing.x2, RTSpacing.x4, RTSpacing.x3),
                      child: DropdownButtonFormField<String>(
                        initialValue: selectedPropertyId,
                        style: RTTypography.body.copyWith(fontSize: 14),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(RTRadius.r2),
                            borderSide: BorderSide(color: RTColors.hair),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(RTRadius.r2),
                            borderSide: BorderSide(color: RTColors.hair),
                          ),
                          filled: true,
                          fillColor: RTColors.bgAlt,
                        ),
                        items: properties
                            .map((p) => DropdownMenuItem<String>(
                                  value: p['id']?.toString(),
                                  child: Text(_propertyLabel(p)),
                                ))
                            .toList(),
                        onChanged: onPropertyChanged,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: RTSpacing.x4),

              // Collar list
              RTCard(
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                          RTSpacing.x4, RTSpacing.x3, RTSpacing.x4, 0),
                      child: Row(
                        children: [
                          Text('COLEIRAS', style: RTTypography.eyebrow),
                          const SizedBox(width: RTSpacing.x2),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: selectedDeviceIds.isNotEmpty
                                  ? RTColors.primarySoft
                                  : RTColors.bgSubtle,
                              borderRadius:
                                  BorderRadius.circular(RTRadius.rFull),
                            ),
                            child: Text(
                              '${selectedDeviceIds.length} selecionadas',
                              style: RTTypography.monoSmall.copyWith(
                                color: selectedDeviceIds.isNotEmpty
                                    ? RTColors.primary
                                    : RTColors.inkMute,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (propertyDevices.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(RTSpacing.x4),
                        child: Text(
                          'Nenhuma coleira vinculada a esta propriedade.',
                          style: RTTypography.bodySmall,
                        ),
                      )
                    else
                      for (var i = 0; i < propertyDevices.length; i++) ...[
                        if (i > 0)
                          Divider(height: 1, color: RTColors.hairSoft),
                        _DeviceRow(
                          device: propertyDevices[i],
                          selected: selectedDeviceIds
                              .contains(propertyDevices[i].loraDeviceId),
                          onToggle: () => onToggleDevice(propertyDevices[i]),
                        ),
                      ],
                    const SizedBox(height: RTSpacing.x2),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Bottom bar
        _BottomBar(
          onBack: null,
          onNext: canAdvance ? onNext : null,
          nextLabel: 'Próximo: Área-alvo',
          nextDisabledHint:
              canAdvance ? null : 'Selecione pelo menos uma coleira',
        ),
      ],
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.device,
    required this.selected,
    required this.onToggle,
  });

  final DeviceModel device;
  final bool selected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final loraId = device.loraDeviceId ?? '';

    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: RTSpacing.x4,
          vertical: RTSpacing.x3,
        ),
        child: Row(
          children: [
            // Selection indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: selected ? RTColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(RTRadius.r1),
                border: Border.all(
                  color: selected ? RTColors.primary : RTColors.hair,
                  width: 1.5,
                ),
              ),
              child: selected
                  ? Icon(Icons.check, color: RTColors.onPrimary, size: 14)
                  : null,
            ),
            const SizedBox(width: RTSpacing.x3),

            // Dot de status
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: device.telemetryReceivedAtMs != null
                    ? RTColors.ok
                    : RTColors.hair,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: RTSpacing.x2),

            // Nome + ID
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(device.name, style: RTTypography.label),
                  if (loraId.isNotEmpty)
                    Text(
                      'ID $loraId',
                      style: RTTypography.mono.copyWith(
                        fontSize: 11,
                        color: RTColors.inkMute,
                      ),
                    ),
                ],
              ),
            ),

            // Status chip
            RTChip(
              label: device.telemetryReceivedAtMs != null ? 'Online' : 'Offline',
              variant: RTChipVariant.status,
              dotColor: device.telemetryReceivedAtMs != null
                  ? RTColors.ok
                  : RTColors.inkMute,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Etapa 2: Mapa com polígono-alvo ──────────────────────────────────────────

class _Step2Page extends StatelessWidget {
  const _Step2Page({
    required this.polygonController,
    required this.mapContext,
    required this.propertyPolygon,
    required this.initialLat,
    required this.initialLon,
    required this.selectedPropertyId,
    required this.maxPoints,
    required this.onBack,
    required this.onNext,
  });

  final PolygonEditSessionController polygonController;
  final PolygonMapContext mapContext;
  final List<LatLng> propertyPolygon;
  final double? initialLat;
  final double? initialLon;
  final String? selectedPropertyId;
  final int maxPoints;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Map HUD
        Padding(
          padding: const EdgeInsets.fromLTRB(
              RTSpacing.x4, RTSpacing.x3, RTSpacing.x4, 0),
          child: AnimatedBuilder(
            animation: polygonController,
            builder: (context, _) {
              final pts = polygonController.points.length;
              final area = pts >= 3
                  ? _formatArea(PolygonMetrics.areaSquareMeters(polygonController.points) / 1e6)
                  : null;
              return RTCard(
                color: RTColors.ink.withValues(alpha: 0.85),
                borderColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(
                  horizontal: RTSpacing.x4,
                  vertical: RTSpacing.x2,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: pts >= 3 ? RTColors.ok : RTColors.warn,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: RTSpacing.x2),
                    Text(
                      '$pts / $maxPoints vértices',
                      style: RTTypography.mono.copyWith(
                        color: RTColors.onPrimary,
                        fontSize: 12,
                      ),
                    ),
                    if (area != null) ...[
                      const SizedBox(width: RTSpacing.x2),
                      Text('·',
                          style: RTTypography.mono
                              .copyWith(color: RTColors.onPrimary, fontSize: 12)),
                      const SizedBox(width: RTSpacing.x2),
                      Text(
                        area,
                        style: RTTypography.mono.copyWith(
                          color: RTColors.onPrimary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: RTSpacing.x3),

        // Map
        Expanded(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: RTSpacing.x4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(RTRadius.r4),
              child: PolygonEditingMap(
                controller: polygonController,
                contextData: mapContext,
                enforceBoundary: true,
                maxPoints: maxPoints,
                allowFreeAdd: true,
                viewportSignature: 'herding:${selectedPropertyId ?? ''}',
                fallbackCenter: propertyPolygon.isNotEmpty
                    ? propertyPolygon.first
                    : LatLng(initialLat ?? -23.0, initialLon ?? -46.0),
                boundaryFillColor: const Color(0x291B5E20),
                boundaryBorderColor: const Color(0xFF2E7D32),
                areaFillColor: const Color(0x14FB8C00),
                areaBorderColor: const Color(0xFFF57C00),
                draftFillColor: const Color(0x2D1565C0),
                draftBorderColor: const Color(0xFF1565C0),
                vertexColor: const Color(0xFF1565C0),
                selectedVertexColor: const Color(0xFFC62828),
                outOfBoundaryMessage:
                    'Ponto fora do limite da propriedade selecionada.',
                idleTapMessage:
                    'Toque no mapa para adicionar vértices. Toque num vértice para mover.',
              ),
            ),
          ),
        ),
        const SizedBox(height: RTSpacing.x3),

        // Controls
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: RTSpacing.x4),
          child: AnimatedBuilder(
            animation: polygonController,
            builder: (context, _) {
              return Row(
                children: [
                  Expanded(
                    child: RTButton(
                      label: 'Desfazer',
                      variant: RTButtonVariant.ghost,
                      icon: Icons.undo,
                      onPressed: polygonController.canUndo
                          ? polygonController.undo
                          : null,
                    ),
                  ),
                  const SizedBox(width: RTSpacing.x2),
                  Expanded(
                    child: RTButton(
                      label: 'Limpar',
                      variant: RTButtonVariant.ghost,
                      icon: Icons.delete_outline,
                      onPressed: polygonController.points.isEmpty
                          ? null
                          : polygonController.clear,
                    ),
                  ),
                ],
              );
            },
          ),
        ),

        // Bottom nav
        AnimatedBuilder(
          animation: polygonController,
          builder: (context, _) {
            final canAdvance = polygonController.points.length >= 3;
            return _BottomBar(
              onBack: onBack,
              onNext: canAdvance ? onNext : null,
              nextLabel: 'Revisar e publicar',
              nextDisabledHint: canAdvance ? null : 'Adicione ≥ 3 vértices no mapa',
            );
          },
        ),
      ],
    );
  }

  String _formatArea(double km2) {
    if (km2 < 0.01) return '< 0.01 km²';
    return '${km2.toStringAsFixed(2)} km²';
  }
}

// ── Etapa 3: Revisão e publicação ────────────────────────────────────────────

class _Step3Page extends StatelessWidget {
  const _Step3Page({
    required this.propertyLabel,
    required this.propertyDevices,
    required this.selectedDeviceIds,
    required this.polygonController,
    required this.trackedOperation,
    required this.isSubmitting,
    required this.onBack,
    required this.onSubmit,
  });

  final String propertyLabel;
  final List<DeviceModel> propertyDevices;
  final Set<String> selectedDeviceIds;
  final PolygonEditSessionController polygonController;
  final HerdingOperationModel? trackedOperation;
  final bool isSubmitting;
  final VoidCallback onBack;
  final VoidCallback? onSubmit;

  String _statusLabel(HerdingOperationStatus? status) {
    switch (status) {
      case HerdingOperationStatus.submitted:
        return 'Enviado pelo app';
      case HerdingOperationStatus.dispatching:
        return 'Distribuindo para as coleiras';
      case HerdingOperationStatus.awaitingAssembly:
        return 'Aguardando montagem completa';
      case HerdingOperationStatus.requested:
        return 'Arrebanhamento solicitado';
      case HerdingOperationStatus.completed:
        return 'Arrebanhamento concluído';
      case HerdingOperationStatus.failed:
        return 'Falhou';
      case HerdingOperationStatus.superseded:
        return 'Substituído por outra operação';
      case null:
        return '';
    }
  }

  Color _statusColor(HerdingOperationStatus? status) {
    switch (status) {
      case HerdingOperationStatus.completed:
        return RTColors.ok;
      case HerdingOperationStatus.failed:
        return RTColors.danger;
      case HerdingOperationStatus.superseded:
        return RTColors.warn;
      case HerdingOperationStatus.requested:
      case HerdingOperationStatus.dispatching:
      case HerdingOperationStatus.awaitingAssembly:
      case HerdingOperationStatus.submitted:
        return RTColors.primary;
      case null:
        return RTColors.inkMute;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedDevices = propertyDevices
        .where((d) => selectedDeviceIds.contains(d.loraDeviceId))
        .toList();

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                RTSpacing.x4, RTSpacing.x4, RTSpacing.x4, RTSpacing.x8),
            children: [
              // Summary card
              RTCard(
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                          RTSpacing.x4, RTSpacing.x3, RTSpacing.x4, 0),
                      child: Text('RESUMO', style: RTTypography.eyebrow),
                    ),
                    const SizedBox(height: RTSpacing.x2),

                    // Property
                    _ReviewRow(
                      icon: Icons.landscape_outlined,
                      label: 'Propriedade',
                      value: propertyLabel,
                    ),
                    Divider(height: 1, color: RTColors.hairSoft),

                    // Collars count
                    _ReviewRow(
                      icon: Icons.pets_outlined,
                      label: 'Coleiras',
                      value: '${selectedDevices.length} selecionadas',
                    ),
                    Divider(height: 1, color: RTColors.hairSoft),

                    // Polygon
                    AnimatedBuilder(
                      animation: polygonController,
                      builder: (context, _) {
                        final pts = polygonController.points.length;
                        final area = pts >= 3
                            ? PolygonMetrics.areaSquareMeters(polygonController.points) / 1e6
                            : 0.0;
                        final areaStr = area < 0.01
                            ? '< 0.01 km²'
                            : '${area.toStringAsFixed(2)} km²';
                        return _ReviewRow(
                          icon: Icons.crop_free,
                          label: 'Área-alvo',
                          value: '$pts vértices · $areaStr',
                        );
                      },
                    ),
                    const SizedBox(height: RTSpacing.x2),
                  ],
                ),
              ),
              const SizedBox(height: RTSpacing.x4),

              // Selected collars chips
              if (selectedDevices.isNotEmpty) ...[
                Text('COLEIRAS SELECIONADAS', style: RTTypography.eyebrow),
                const SizedBox(height: RTSpacing.x2),
                Wrap(
                  spacing: RTSpacing.x2,
                  runSpacing: RTSpacing.x2,
                  children: selectedDevices
                      .map(
                        (d) => RTChip(
                          label: d.name,
                          variant: RTChipVariant.status,
                          dotColor: d.telemetryReceivedAtMs != null
                              ? RTColors.ok
                              : RTColors.inkMute,
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: RTSpacing.x4),
              ],

              // Operation status (if already submitted)
              if (trackedOperation != null) ...[
                RTCard(
                  color: RTColors.primarySoft,
                  borderColor: RTColors.primary.withValues(alpha: 0.2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('STATUS DA OPERAÇÃO', style: RTTypography.eyebrow),
                      const SizedBox(height: RTSpacing.x2),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _statusColor(trackedOperation!.status),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: RTSpacing.x2),
                          Text(
                            _statusLabel(trackedOperation!.status),
                            style: RTTypography.bodyStrong.copyWith(
                              color: _statusColor(trackedOperation!.status),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: RTSpacing.x2),
                      Text(
                        'Montadas: ${trackedOperation!.assembledCount} / ${trackedOperation!.selectedDeviceIds.length}',
                        style: RTTypography.mono.copyWith(fontSize: 12),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Concluídas: ${trackedOperation!.completedCount} / ${trackedOperation!.selectedDeviceIds.length}',
                        style: RTTypography.mono.copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: RTSpacing.x4),
              ],

              // Confirmation banner
              const RTConfirmLoRa(),
            ],
          ),
        ),

        // Bottom bar
        _BottomBar(
          onBack: onBack,
          onNext: onSubmit,
          nextLabel: 'Publicar via LoRa',
          nextVariant: RTButtonVariant.accent,
          nextIcon: Icons.alt_route,
          loading: isSubmitting,
          nextDisabledHint:
              onSubmit == null ? 'Propriedade inválida' : null,
        ),
      ],
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: RTSpacing.x4, vertical: RTSpacing.x3),
      child: Row(
        children: [
          Icon(icon, size: 20, color: RTColors.inkSoft),
          const SizedBox(width: RTSpacing.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: RTTypography.eyebrow.copyWith(fontSize: 11)),
                const SizedBox(height: 2),
                Text(value,
                    style: RTTypography.bodyStrong.copyWith(fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bottom bar compartilhada ──────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.onBack,
    required this.onNext,
    required this.nextLabel,
    this.nextVariant = RTButtonVariant.primary,
    this.nextIcon,
    this.loading = false,
    this.nextDisabledHint,
  });

  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final String nextLabel;
  final RTButtonVariant nextVariant;
  final IconData? nextIcon;
  final bool loading;
  final String? nextDisabledHint;

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(
        RTSpacing.x4,
        RTSpacing.x3,
        RTSpacing.x4,
        RTSpacing.x3 + bottomPadding,
      ),
      decoration: BoxDecoration(
        color: RTColors.bg,
        border: Border(top: BorderSide(color: RTColors.hairSoft)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (nextDisabledHint != null && onNext == null) ...[
            Text(
              nextDisabledHint!,
              style: RTTypography.bodySmall.copyWith(color: RTColors.inkMute),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: RTSpacing.x2),
          ],
          Row(
            children: [
              if (onBack != null) ...[
                RTButton(
                  label: 'Voltar',
                  variant: RTButtonVariant.ghost,
                  icon: Icons.arrow_back,
                  onPressed: onBack,
                ),
                const SizedBox(width: RTSpacing.x3),
              ],
              Expanded(
                child: RTButton(
                  label: nextLabel,
                  variant: nextVariant,
                  trailing: nextIcon ?? Icons.arrow_forward,
                  fullWidth: true,
                  size: RTButtonSize.lg,
                  loading: loading,
                  onPressed: onNext,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
