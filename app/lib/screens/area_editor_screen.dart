import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/device_model.dart';
import '../models/polygon_map_context.dart';
import '../services/auth_service.dart';
import '../services/cloud_service.dart';
import '../services/gateway_service.dart';
import '../utils/polygon_edit_session.dart';
import '../utils/linked_device_selection.dart';
import '../utils/polygon_metrics.dart';
import '../utils/top_feedback.dart';
import '../widgets/polygon_editing_map.dart';

class AreaEditorScreen extends StatefulWidget {
  const AreaEditorScreen({
    super.key,
    this.initialArea,
  });

  final Map<String, dynamic>? initialArea;

  @override
  State<AreaEditorScreen> createState() => _AreaEditorScreenState();
}

class _AreaEditorScreenState extends State<AreaEditorScreen> {
  static const int _maxAreaPoints = GatewayService.maxPolygonPoints;

  late final PolygonEditSessionController _draftController;
  late final LinkedDeviceSelectionController _linkedDeviceController;
  String? _selectedPropertyId;
  bool _loadingProperties = true;
  bool _saving = false;
  List<Map<String, dynamic>> _properties = const <Map<String, dynamic>>[];

  bool get _isEditMode => widget.initialArea != null;

  String? get _editingAreaId {
    final raw = widget.initialArea?['id'];
    if (raw == null) return null;
    final id = _normalizeId(raw);
    return id.isEmpty ? null : id;
  }

  @override
  void initState() {
    super.initState();
    _selectedPropertyId = _normalizeId(widget.initialArea?['propertyId']);
    _draftController = PolygonEditSessionController(
      initialPoints: _decodePolygon(widget.initialArea?['perimeter']),
    );
    _linkedDeviceController = LinkedDeviceSelectionController(
      initialDeviceIds:
          normalizeLinkedDeviceIds(widget.initialArea?['linkedDeviceIds']),
    );
    _loadProperties();
  }

  @override
  void dispose() {
    _draftController.dispose();
    _linkedDeviceController.dispose();
    super.dispose();
  }

  String _normalizeId(dynamic value) {
    if (value == null) return '';
    final raw = value.toString().trim();
    if (raw.isEmpty) return '';
    if (!raw.contains('/')) return raw;
    final parts = raw.split('/').where((entry) => entry.isNotEmpty).toList();
    return parts.isEmpty ? raw : parts.last;
  }

  LatLng? _toLatLng(dynamic value) {
    if (value is LatLng) return value;
    if (value is List && value.length >= 2) {
      final lat = value[0];
      final lon = value[1];
      if (lat is num && lon is num) {
        return LatLng(lat.toDouble(), lon.toDouble());
      }
    }
    if (value is Map) {
      final lat = value['lat'] ?? value['latitude'];
      final lon = value['lon'] ?? value['lng'] ?? value['longitude'];
      if (lat is num && lon is num) {
        return LatLng(lat.toDouble(), lon.toDouble());
      }
    }
    return null;
  }

  List<LatLng> _decodePolygon(dynamic raw) {
    if (raw is! List) return const <LatLng>[];
    return raw.map(_toLatLng).whereType<LatLng>().toList();
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
    if (parsedLat < -90 ||
        parsedLat > 90 ||
        parsedLon < -180 ||
        parsedLon > 180) {
      return null;
    }
    return LatLng(parsedLat, parsedLon);
  }

  String _propertyLabel(Map<String, dynamic> property) {
    final name = (property['name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    final id = _normalizeId(property['id']);
    return id.isEmpty ? 'Propriedade rural' : id;
  }

  String _gatewayLabel(Map<String, dynamic> gateway) {
    final name = (gateway['name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    final id = _normalizeId(gateway['id'] ?? gateway['gatewayId']);
    return id.isEmpty ? 'Gateway' : id;
  }

  Map<String, dynamic>? get _selectedProperty {
    final propertyId = _selectedPropertyId;
    if (propertyId == null || propertyId.isEmpty) return null;
    return _properties.cast<Map<String, dynamic>?>().firstWhere(
          (property) => _normalizeId(property?['id']) == propertyId,
          orElse: () => null,
        );
  }

  List<LatLng> get _selectedPropertyPolygon {
    final raw = (_selectedProperty?['points'] as List?) ?? const <dynamic>[];
    return raw.map(_toLatLng).whereType<LatLng>().toList();
  }

  Future<void> _loadProperties() async {
    final auth = context.read<AuthService>();
    final uid = auth.user?.uid;
    if (uid == null) return;

    final properties = await context
        .read<CloudService>()
        .getRuralProperties(uid: uid, isAdmin: auth.isAdmin);

    if (!mounted) return;
    setState(() {
      _properties = properties;
      final requestedPropertyId = _selectedPropertyId;
      final propertyExists = requestedPropertyId != null &&
          requestedPropertyId.isNotEmpty &&
          properties.any((property) =>
              _normalizeId(property['id']) == requestedPropertyId);
      _selectedPropertyId = propertyExists
          ? requestedPropertyId
          : (properties.isNotEmpty
              ? _normalizeId(properties.first['id'])
              : null);
      _loadingProperties = false;
    });
  }

  void _handlePropertyChanged(String? propertyId) {
    final normalized = _normalizeId(propertyId);
    if (_isEditMode ||
        normalized.isEmpty ||
        normalized == _selectedPropertyId) {
      return;
    }
    setState(() => _selectedPropertyId = normalized);
    _draftController.resetSession(const <LatLng>[]);
    _linkedDeviceController.clear();
  }

  Future<void> _delete() async {
    final areaId = _editingAreaId;
    if (areaId == null || areaId.isEmpty || _saving) return;

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Apagar area'),
            content: const Text('Deseja apagar esta area?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                ),
                child: const Text('Apagar'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed || !mounted) return;

    setState(() => _saving = true);
    try {
      await context.read<CloudService>().deleteArea(id: areaId);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      AppFeedback.error('Erro ao apagar area: $e');
      setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;

    final propertyId = _selectedPropertyId?.trim();
    if (propertyId == null || propertyId.isEmpty) {
      AppFeedback.error('Selecione uma propriedade rural.');
      return;
    }

    final points = _draftController.points;
    if (points.length < 3) {
      AppFeedback.error('Desenhe ao menos 3 pontos no poligono.');
      return;
    }
    if (points.length > _maxAreaPoints) {
      AppFeedback.error('Permitido apenas $_maxAreaPoints pontos por area.');
      return;
    }

    final uid = context.read<AuthService>().user?.uid;
    if (uid == null) return;

    setState(() => _saving = true);
    final perimeter = points
        .map((point) => <double>[point.latitude, point.longitude])
        .toList();

    try {
      final cloud = context.read<CloudService>();
      if (_isEditMode) {
        final areaId = _editingAreaId;
        if (areaId == null || areaId.isEmpty) {
          throw Exception('id_da_area_invalido');
        }
        await cloud.updateAreaPerimeter(
          id: areaId,
          perimeter: perimeter,
          linkedDeviceIds: _linkedDeviceController.selectedDeviceIds,
          updatedByUid: uid,
        );
      } else {
        await cloud.addArea(
          ownerUid: uid,
          ruralPropertyId: propertyId,
          perimeter: perimeter,
          linkedDeviceIds: _linkedDeviceController.selectedDeviceIds,
          updatedByUid: uid,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      AppFeedback.error('Erro ao salvar area: $e');
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final uid = auth.user?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final selectedProperty = _selectedProperty;
    final selectedPropertyLabel =
        selectedProperty == null ? '-' : _propertyLabel(selectedProperty);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? 'Editar area' : 'Nova area (poligono)'),
        actions: [
          if (_isEditMode)
            IconButton(
              key: const Key('area_delete_button'),
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Apagar area',
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: _loadingProperties
                ? const LinearProgressIndicator()
                : _isEditMode
                    ? InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Propriedade rural',
                        ),
                        child: Text(selectedPropertyLabel),
                      )
                    : DropdownButtonFormField<String>(
                        key: const Key('area_property_dropdown'),
                        initialValue: _selectedPropertyId,
                        items: _properties
                            .map(
                              (property) => DropdownMenuItem<String>(
                                value: _normalizeId(property['id']),
                                child: Text(_propertyLabel(property)),
                              ),
                            )
                            .toList(),
                        onChanged: _saving ? null : _handlePropertyChanged,
                        decoration: const InputDecoration(
                          labelText: 'Propriedade rural',
                        ),
                      ),
          ),
          AnimatedBuilder(
            animation: Listenable.merge(
              <Listenable>[_draftController, _linkedDeviceController],
            ),
            builder: (context, _) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: Colors.green.withValues(alpha: 0.08),
                child: Text(
                  'Toque no mapa para adicionar os primeiros pontos. Toque em um ponto para mover e no perimetro para inserir novos pontos. '
                  'Pontos: ${_draftController.points.length}/$_maxAreaPoints'
                  ' | Coleiras vinculadas: ${_linkedDeviceController.selectedCount}',
                ),
              );
            },
          ),
          Expanded(
            child: _loadingProperties
                ? const Center(child: CircularProgressIndicator())
                : StreamBuilder<List<DeviceModel>>(
                    stream: context
                        .read<CloudService>()
                        .streamDevices(uid: uid, isAdmin: auth.isAdmin),
                    builder: (context, deviceSnap) {
                      if (deviceSnap.hasError) {
                        return Center(
                          child: Text(
                            'Erro ao carregar coleiras: ${deviceSnap.error}',
                          ),
                        );
                      }
                      final propertyDevices =
                          (deviceSnap.data ?? const <DeviceModel>[])
                              .where(
                                (device) =>
                                    device.propertyId?.trim() ==
                                    _selectedPropertyId,
                              )
                              .map((device) {
                                final point = _devicePosition(device);
                                if (point == null) return null;
                                final overlayId =
                                    device.loraDeviceId ?? device.id;
                                return PolygonMapDeviceOverlay(
                                  id: overlayId,
                                  label: device.name,
                                  point: point,
                                  selected: _linkedDeviceController
                                      .isSelected(overlayId),
                                  onTap: _saving || device.loraDeviceId == null
                                      ? null
                                      : () => _linkedDeviceController.toggle(
                                            device.loraDeviceId,
                                          ),
                                );
                              })
                              .whereType<PolygonMapDeviceOverlay>()
                              .toList();

                      return StreamBuilder<List<Map<String, dynamic>>>(
                        stream: context
                            .read<CloudService>()
                            .streamGateways(uid: uid, isAdmin: auth.isAdmin),
                        builder: (context, gatewaySnap) {
                          if (gatewaySnap.hasError) {
                            return Center(
                              child: Text(
                                'Erro ao carregar gateways: ${gatewaySnap.error}',
                              ),
                            );
                          }

                          final propertyGateways = (gatewaySnap.data ??
                                  const <Map<String, dynamic>>[])
                              .where(
                                (gateway) =>
                                    _normalizeId(gateway['propertyId']) ==
                                    _selectedPropertyId,
                              )
                              .map((gateway) {
                                final point = _gatewayPosition(gateway);
                                if (point == null) return null;
                                return PolygonMapGatewayOverlay(
                                  id: _normalizeId(
                                    gateway['id'] ?? gateway['gatewayId'],
                                  ),
                                  label: _gatewayLabel(gateway),
                                  point: point,
                                );
                              })
                              .whereType<PolygonMapGatewayOverlay>()
                              .toList();

                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: PolygonEditingMap(
                                controller: _draftController,
                                contextData: PolygonMapContext(
                                  boundaryPolygon: _selectedPropertyPolygon,
                                  devices: propertyDevices,
                                  gateways: propertyGateways,
                                ),
                                enforceBoundary: true,
                                maxPoints: _maxAreaPoints,
                                allowFreeAdd: true,
                                viewportSignature:
                                    'area-property:${_selectedPropertyId ?? ''}',
                                outOfBoundaryMessage:
                                    'Ponto fora do perimetro da propriedade selecionada.',
                                idleTapMessage:
                                    'Toque em um ponto para mover, no perimetro para inserir ou em uma area livre para adicionar.',
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
          AnimatedBuilder(
            animation: Listenable.merge(
              <Listenable>[_draftController, _linkedDeviceController],
            ),
            builder: (context, _) {
              return Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                color: Colors.green.withValues(alpha: 0.08),
                child: Text(
                  'Area da edicao: ${PolygonMetrics.areaTextInline(_draftController.points)}'
                  ' | Pontos: ${_draftController.points.length}/$_maxAreaPoints'
                  ' | Vinculos: ${_linkedDeviceController.selectedCount}',
                  textAlign: TextAlign.center,
                ),
              );
            },
          ),
          AnimatedBuilder(
            animation: _draftController,
            builder: (context, _) {
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        key: const Key('area_undo_button'),
                        onPressed: _saving || !_draftController.canUndo
                            ? null
                            : _draftController.undo,
                        child: const Text('Desfazer'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        key: const Key('area_clear_button'),
                        onPressed: _saving || _draftController.points.isEmpty
                            ? null
                            : _draftController.clear,
                        child: const Text('Limpar'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        key: const Key('area_save_button'),
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Salvar'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
