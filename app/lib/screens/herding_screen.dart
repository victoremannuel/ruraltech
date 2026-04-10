import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/device_model.dart';
import '../models/herding_operation_model.dart';
import '../models/polygon_map_context.dart';
import '../services/auth_service.dart';
import '../services/cloud_service.dart';
import '../utils/polygon_edit_session.dart';
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

  final Set<String> _selectedDeviceIds = <String>{};
  late final PolygonEditSessionController _polygonController;
  String? _selectedPropertyId;
  String? _createdOperationId;
  bool _isSubmitting = false;
  bool _didSeedInitialDevice = false;

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
    _polygonController.dispose();
    super.dispose();
  }

  String _idFromRefOrPath(dynamic value) {
    if (value == null) return '';
    final raw = value.toString().trim();
    if (raw.isEmpty) return '';
    if (!raw.contains('/')) return raw;
    final parts = raw.split('/').where((entry) => entry.isNotEmpty).toList();
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
    final id = (property['id'] ?? '').toString().trim();
    return id.isEmpty ? 'Propriedade' : 'Propriedade $id';
  }

  String _gatewayLabel(Map<String, dynamic> gateway) {
    final name = (gateway['name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    final id = _idFromRefOrPath(gateway['id'] ?? gateway['gatewayId']);
    return id.isEmpty ? 'Gateway' : id;
  }

  HerdingOperationStatus? _statusFromOperation(
    HerdingOperationModel? operation,
  ) {
    if (operation == null) return null;
    return operation.status;
  }

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
        return 'Arrebanhamento concluido';
      case HerdingOperationStatus.failed:
        return 'Falhou';
      case HerdingOperationStatus.superseded:
        return 'Substituido por outra operacao';
      case null:
        return 'Nenhuma operacao selecionada';
    }
  }

  Color _statusColor(HerdingOperationStatus? status, ThemeData theme) {
    switch (status) {
      case HerdingOperationStatus.completed:
        return Colors.green.shade700;
      case HerdingOperationStatus.failed:
        return theme.colorScheme.error;
      case HerdingOperationStatus.superseded:
        return Colors.orange.shade700;
      case HerdingOperationStatus.requested:
        return Colors.teal.shade700;
      case HerdingOperationStatus.dispatching:
      case HerdingOperationStatus.awaitingAssembly:
      case HerdingOperationStatus.submitted:
      case null:
        return theme.colorScheme.primary;
    }
  }

  void _showFeedback(String message, {bool error = false}) {
    if (error) {
      AppFeedback.error(message);
      return;
    }
    AppFeedback.show(message);
  }

  void _syncInitialPropertyAndSelection(
    List<Map<String, dynamic>> properties,
    List<DeviceModel> devices,
  ) {
    if (_selectedPropertyId == null || _selectedPropertyId!.trim().isEmpty) {
      final preferred = widget.initialPropertyId?.trim();
      if (preferred != null &&
          preferred.isNotEmpty &&
          properties
              .any((property) => property['id']?.toString() == preferred)) {
        _selectedPropertyId = preferred;
      } else if (properties.isNotEmpty) {
        _selectedPropertyId = properties.first['id']?.toString();
      }
    }

    if (_didSeedInitialDevice) return;
    _didSeedInitialDevice = true;

    final initialDeviceId = widget.initialDeviceId?.trim();
    if (initialDeviceId == null || initialDeviceId.isEmpty) return;
    final matchingDevice = devices.cast<DeviceModel?>().firstWhere(
          (device) => device?.loraDeviceId == initialDeviceId,
          orElse: () => null,
        );
    final propertyId = matchingDevice?.propertyId?.trim();
    if (propertyId != null && propertyId.isNotEmpty) {
      _selectedPropertyId = propertyId;
    }
  }

  List<DeviceModel> _devicesForProperty(List<DeviceModel> devices) {
    final propertyId = _selectedPropertyId?.trim();
    if (propertyId == null || propertyId.isEmpty) return const <DeviceModel>[];
    return devices
        .where((device) => device.propertyId?.trim() == propertyId)
        .where((device) => device.loraDeviceId != null)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  List<Map<String, dynamic>> _areasForProperty(
      List<Map<String, dynamic>> areas) {
    final propertyId = _selectedPropertyId?.trim();
    if (propertyId == null || propertyId.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    return areas
        .where((area) => area['propertyId']?.toString() == propertyId)
        .toList();
  }

  List<Map<String, dynamic>> _gatewaysForProperty(
    List<Map<String, dynamic>> gateways,
  ) {
    final propertyId = _selectedPropertyId?.trim();
    if (propertyId == null || propertyId.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    return gateways
        .where(
            (gateway) => _idFromRefOrPath(gateway['propertyId']) == propertyId)
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

  Future<void> _submitOperation(
    Map<String, dynamic> property,
    List<DeviceModel> propertyDevices,
    AuthService auth,
    CloudService firebase,
  ) async {
    if (_isSubmitting) return;
    final propertyId = _selectedPropertyId?.trim();
    final uid = auth.user?.uid.trim();
    if (propertyId == null ||
        propertyId.isEmpty ||
        uid == null ||
        uid.isEmpty) {
      _showFeedback(
        'Nao foi possivel identificar a propriedade ou o usuario.',
        error: true,
      );
      return;
    }

    final selectedDevices = propertyDevices
        .where((device) => _selectedDeviceIds.contains(device.loraDeviceId))
        .toList();
    if (selectedDevices.isEmpty) {
      _showFeedback(
        'Selecione no mapa quais animais devem ser arrebanhados.',
        error: true,
      );
      return;
    }
    if (_polygonController.points.length < 3) {
      _showFeedback(
        'Desenhe no mapa o poligono de destino do arrebanhamento.',
        error: true,
      );
      return;
    }

    final matrixGatewayId = await firebase.resolveMatrixGatewayIdForProperty(
        propertyId: propertyId);
    if (matrixGatewayId == null || matrixGatewayId.isEmpty) {
      _showFeedback(
        'Nao encontrei um gateway matriz conectado para essa propriedade.',
        error: true,
      );
      return;
    }

    final notifyUserIds =
        await firebase.getLinkedUserIdsForProperty(propertyId);
    final ownerUid = _userIdFrom(property['ownerUid']) ??
        _userIdFrom(property['createdByUid']) ??
        uid;
    final selectedDeviceIds = selectedDevices
        .map((device) => device.loraDeviceId)
        .whereType<String>()
        .toList()
      ..sort();
    final targetPolygon = _polygonController.points
        .map((point) => <double>[point.latitude, point.longitude])
        .toList();

    setState(() => _isSubmitting = true);
    String? operationId;
    try {
      operationId = await firebase.createHerdingOperation(
        ownerUid: ownerUid,
        requestedByUid: uid,
        requestedByRole: auth.role,
        propertyId: propertyId,
        targetPolygon: targetPolygon,
        selectedDeviceIds: selectedDeviceIds,
        notifyUserIds: notifyUserIds,
        matrixGatewayId: matrixGatewayId,
      );

      final loraCommandId = await firebase.enqueueScopedCommand(
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
      await firebase.attachLoraCommandToHerdingOperation(
        operationId: operationId,
        loraCommandId: loraCommandId,
      );

      if (!mounted) return;
      setState(() => _createdOperationId = operationId);
      _showFeedback('Operacao criada e enfileirada para a matriz.');
    } catch (e) {
      if (operationId != null) {
        await firebase.markHerdingOperationSubmissionFailed(
          operationId: operationId,
          reason: e.toString(),
        );
      }
      if (!mounted) return;
      _showFeedback('Falha ao criar o arrebanhamento: $e', error: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Widget _buildOperationStatusCard(
    ThemeData theme,
    HerdingOperationModel? operation,
  ) {
    final status = _statusFromOperation(operation);
    final color = _statusColor(status, theme);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              operation == null
                  ? 'Ultima operacao'
                  : 'Operacao ${operation.id}',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              _statusLabel(status),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (operation != null) ...[
              const SizedBox(height: 8),
              Text(
                'Coleiras montadas: ${operation.assembledCount}/${operation.selectedDeviceIds.length}',
              ),
              Text(
                'Coleiras concluidas: ${operation.completedCount}/${operation.selectedDeviceIds.length}',
              ),
            ] else
              const Text(
                'Acompanhe aqui a distribuicao para as coleiras e a conclusao do arrebanhamento.',
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final firebase = context.read<CloudService>();
    final uid = auth.user?.uid;
    if (uid == null || uid.trim().isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Solicitar arrebanhamento')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: firebase.streamRuralProperties(uid: uid, isAdmin: auth.isAdmin),
        builder: (context, propertySnap) {
          if (propertySnap.hasError) {
            return Center(
              child:
                  Text('Erro ao carregar propriedades: ${propertySnap.error}'),
            );
          }
          final properties =
              propertySnap.data ?? const <Map<String, dynamic>>[];
          if (properties.isEmpty) {
            return const Center(
              child: Text(
                'Cadastre ou vincule uma propriedade para usar o arrebanhamento.',
              ),
            );
          }

          return StreamBuilder<List<DeviceModel>>(
            stream: firebase.streamDevices(uid: uid, isAdmin: auth.isAdmin),
            builder: (context, deviceSnap) {
              if (deviceSnap.hasError) {
                return Center(
                  child: Text('Erro ao carregar coleiras: ${deviceSnap.error}'),
                );
              }
              final devices = deviceSnap.data ?? const <DeviceModel>[];
              _syncInitialPropertyAndSelection(properties, devices);

              final selectedProperty =
                  properties.cast<Map<String, dynamic>?>().firstWhere(
                        (property) =>
                            property?['id']?.toString() == _selectedPropertyId,
                        orElse: () => null,
                      );
              final propertyPolygon =
                  _decodePolygon(selectedProperty?['points']);
              final propertyDevices = _devicesForProperty(devices);

              return StreamBuilder<List<Map<String, dynamic>>>(
                stream: firebase.streamAreas(uid: uid, isAdmin: auth.isAdmin),
                builder: (context, areaSnap) {
                  if (areaSnap.hasError) {
                    return Center(
                      child: Text('Erro ao carregar areas: ${areaSnap.error}'),
                    );
                  }
                  final propertyAreas = _areasForProperty(
                      areaSnap.data ?? const <Map<String, dynamic>>[]);

                  return StreamBuilder<List<Map<String, dynamic>>>(
                    stream: firebase.streamGateways(
                      uid: uid,
                      isAdmin: auth.isAdmin,
                    ),
                    builder: (context, gatewaySnap) {
                      if (gatewaySnap.hasError) {
                        return Center(
                          child: Text(
                            'Erro ao carregar gateways: ${gatewaySnap.error}',
                          ),
                        );
                      }
                      final propertyGateways = _gatewaysForProperty(
                        gatewaySnap.data ?? const <Map<String, dynamic>>[],
                      );

                      return StreamBuilder<List<HerdingOperationModel>>(
                        stream: firebase.streamHerdingOperations(
                          uid: uid,
                          isAdmin: auth.isAdmin,
                        ),
                        builder: (context, operationsSnap) {
                          final operations = operationsSnap.data ??
                              const <HerdingOperationModel>[];
                          final trackedOperation = _createdOperationId == null
                              ? operations
                                  .cast<HerdingOperationModel?>()
                                  .firstWhere(
                                    (operation) =>
                                        operation?.propertyId ==
                                        _selectedPropertyId,
                                    orElse: () => null,
                                  )
                              : operations
                                  .cast<HerdingOperationModel?>()
                                  .firstWhere(
                                    (operation) =>
                                        operation?.id == _createdOperationId,
                                    orElse: () => null,
                                  );

                          final mapContext = PolygonMapContext(
                            boundaryPolygon: propertyPolygon,
                            areaPolygons: propertyAreas
                                .map(
                                    (area) => _decodePolygon(area['perimeter']))
                                .where((points) => points.length >= 3)
                                .toList(),
                            devices: propertyDevices
                                .map((device) {
                                  final deviceId = device.loraDeviceId;
                                  final point = _devicePosition(device);
                                  if (deviceId == null || point == null) {
                                    return null;
                                  }
                                  return PolygonMapDeviceOverlay(
                                    id: deviceId,
                                    label: device.name,
                                    point: point,
                                    selected:
                                        _selectedDeviceIds.contains(deviceId),
                                    onTap: () => _toggleDevice(device),
                                  );
                                })
                                .whereType<PolygonMapDeviceOverlay>()
                                .toList(),
                            gateways: propertyGateways
                                .map((gateway) {
                                  final point = _gatewayPosition(gateway);
                                  if (point == null) return null;
                                  return PolygonMapGatewayOverlay(
                                    id: _idFromRefOrPath(
                                      gateway['id'] ?? gateway['gatewayId'],
                                    ),
                                    label: _gatewayLabel(gateway),
                                    point: point,
                                  );
                                })
                                .whereType<PolygonMapGatewayOverlay>()
                                .toList(),
                          );

                          return Column(
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 12, 12, 8),
                                child: DropdownButtonFormField<String>(
                                  initialValue: _selectedPropertyId,
                                  decoration: const InputDecoration(
                                    labelText: 'Propriedade',
                                  ),
                                  items: properties
                                      .map(
                                        (property) => DropdownMenuItem<String>(
                                          value: property['id']?.toString(),
                                          child: Text(_propertyLabel(property)),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: _setProperty,
                                ),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Toque nas coleiras no mapa para selecionar os animais. Toque no mapa para desenhar o poligono destino.',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ),
                                    AnimatedBuilder(
                                      animation: _polygonController,
                                      builder: (context, _) {
                                        return TextButton.icon(
                                          onPressed: _polygonController.canUndo
                                              ? _polygonController.undo
                                              : null,
                                          icon: const Icon(Icons.undo),
                                          label: const Text('Desfazer'),
                                        );
                                      },
                                    ),
                                    AnimatedBuilder(
                                      animation: _polygonController,
                                      builder: (context, _) {
                                        return TextButton.icon(
                                          onPressed:
                                              _polygonController.points.isEmpty
                                                  ? null
                                                  : _polygonController.clear,
                                          icon:
                                              const Icon(Icons.delete_outline),
                                          label: const Text('Limpar'),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 0, 12, 8),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: AnimatedBuilder(
                                    animation: _polygonController,
                                    builder: (context, _) {
                                      return Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          Chip(
                                            label: Text(
                                              '${_selectedDeviceIds.length} animais selecionados',
                                            ),
                                          ),
                                          Chip(
                                            label: Text(
                                              '${_polygonController.points.length} pontos no poligono',
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(24),
                                    child: PolygonEditingMap(
                                      controller: _polygonController,
                                      contextData: mapContext,
                                      enforceBoundary: true,
                                      maxPoints: _maxTargetPolygonPoints,
                                      allowFreeAdd: true,
                                      viewportSignature:
                                          'herding:${_selectedPropertyId ?? ''}',
                                      fallbackCenter: propertyPolygon.isNotEmpty
                                          ? propertyPolygon.first
                                          : LatLng(
                                              widget.initialLat ?? -23.0,
                                              widget.initialLon ?? -46.0,
                                            ),
                                      boundaryFillColor:
                                          const Color(0x291B5E20),
                                      boundaryBorderColor:
                                          const Color(0xFF2E7D32),
                                      areaFillColor: const Color(0x14FB8C00),
                                      areaBorderColor: const Color(0xFFF57C00),
                                      draftFillColor: const Color(0x2D1565C0),
                                      draftBorderColor: const Color(0xFF1565C0),
                                      vertexColor: const Color(0xFF1565C0),
                                      selectedVertexColor:
                                          const Color(0xFFC62828),
                                      outOfBoundaryMessage:
                                          'Ponto fora do limite da propriedade selecionada.',
                                      idleTapMessage:
                                          'Toque em um ponto para mover, no perimetro para inserir ou em uma area livre para adicionar.',
                                    ),
                                  ),
                                ),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 12, 12, 12),
                                child: Column(
                                  children: [
                                    _buildOperationStatusCard(
                                      Theme.of(context),
                                      trackedOperation,
                                    ),
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        key: const Key(
                                          'submit_herding_operation_button',
                                        ),
                                        onPressed: _isSubmitting ||
                                                selectedProperty == null
                                            ? null
                                            : () => _submitOperation(
                                                  selectedProperty,
                                                  propertyDevices,
                                                  auth,
                                                  firebase,
                                                ),
                                        icon: _isSubmitting
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                ),
                                              )
                                            : const Icon(Icons.alt_route),
                                        label: Text(
                                          _isSubmitting
                                              ? 'Enviando para a matriz...'
                                              : 'Solicitar arrebanhamento',
                                        ),
                                      ),
                                    ),
                                  ],
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
}
