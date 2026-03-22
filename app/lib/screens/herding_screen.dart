import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/device_model.dart';
import '../models/herding_operation_model.dart';
import '../services/auth_service.dart';
import '../services/firebase_service.dart';
import '../services/gateway_service.dart';
import '../utils/top_feedback.dart';

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
  final MapController _mapController = MapController();
  final Set<String> _selectedDeviceIds = <String>{};
  final List<LatLng> _targetPolygon = <LatLng>[];
  String? _selectedPropertyId;
  String? _createdOperationId;
  bool _isSubmitting = false;
  bool _didSeedInitialDevice = false;
  int _lastViewportSignature = 0;

  @override
  void initState() {
    super.initState();
    final initialDeviceId = widget.initialDeviceId?.trim();
    if (initialDeviceId != null && initialDeviceId.isNotEmpty) {
      _selectedDeviceIds.add(initialDeviceId);
    }
    final initialPropertyId = widget.initialPropertyId?.trim();
    if (initialPropertyId != null && initialPropertyId.isNotEmpty) {
      _selectedPropertyId = initialPropertyId;
    }
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

  String _propertyLabel(Map<String, dynamic> property) {
    final name = (property['name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    final id = (property['id'] ?? '').toString().trim();
    return id.isEmpty ? 'Propriedade' : 'Propriedade $id';
  }

  HerdingOperationStatus? _statusFromOperation(HerdingOperationModel? operation) {
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
          properties.any((property) => property['id']?.toString() == preferred)) {
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

  List<Map<String, dynamic>> _areasForProperty(List<Map<String, dynamic>> areas) {
    final propertyId = _selectedPropertyId?.trim();
    if (propertyId == null || propertyId.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    return areas.where((area) => area['propertyId']?.toString() == propertyId).toList();
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
      _targetPolygon.clear();
      _createdOperationId = null;
    });
  }

  void _addPolygonPoint(LatLng point) {
    if (_targetPolygon.length >= GatewayService.maxPolygonPoints) {
      _showFeedback(
        'O poligono suporta no maximo ${GatewayService.maxPolygonPoints} pontos.',
        error: true,
      );
      return;
    }
    setState(() => _targetPolygon.add(point));
  }

  void _undoPoint() {
    if (_targetPolygon.isEmpty) return;
    setState(() => _targetPolygon.removeLast());
  }

  void _clearPolygon() {
    if (_targetPolygon.isEmpty) return;
    setState(_targetPolygon.clear);
  }

  void _fitViewport({
    required List<LatLng> propertyPolygon,
    required List<DeviceModel> propertyDevices,
  }) {
    final points = <LatLng>[
      ...propertyPolygon,
      ..._targetPolygon,
      ...propertyDevices.map(_devicePosition).whereType<LatLng>(),
      if (widget.initialLat != null && widget.initialLon != null)
        LatLng(widget.initialLat!, widget.initialLon!),
    ];
    if (points.isEmpty) return;

    final signature = Object.hashAll(
      points.map((point) => '${point.latitude.toStringAsFixed(5)}:${point.longitude.toStringAsFixed(5)}'),
    );
    if (_lastViewportSignature == signature) return;
    _lastViewportSignature = signature;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (points.length == 1) {
        _mapController.move(points.first, 16);
        return;
      }
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.all(42),
        ),
      );
    });
  }

  Future<void> _submitOperation(
    Map<String, dynamic> property,
    List<DeviceModel> propertyDevices,
    AuthService auth,
    FirebaseService firebase,
    GatewayService gateway,
  ) async {
    if (_isSubmitting) return;
    final propertyId = _selectedPropertyId?.trim();
    final uid = auth.user?.uid.trim();
    if (propertyId == null || propertyId.isEmpty || uid == null || uid.isEmpty) {
      _showFeedback('Nao foi possivel identificar a propriedade ou o usuario.', error: true);
      return;
    }

    final selectedDevices = propertyDevices
        .where((device) => _selectedDeviceIds.contains(device.loraDeviceId))
        .toList();
    if (selectedDevices.isEmpty) {
      _showFeedback('Selecione no mapa quais animais devem ser arrebanhados.', error: true);
      return;
    }
    if (_targetPolygon.length < 3) {
      _showFeedback('Desenhe no mapa o poligono de destino do arrebanhamento.', error: true);
      return;
    }

    final matrixGatewayId =
        await firebase.resolveMatrixGatewayIdForProperty(propertyId: propertyId);
    final matrixGatewayWsHost =
        await firebase.resolveMatrixGatewayWsHost(propertyId: propertyId);
    if (matrixGatewayId == null ||
        matrixGatewayId.isEmpty ||
        matrixGatewayWsHost == null ||
        matrixGatewayWsHost.isEmpty) {
      _showFeedback(
        'Nao encontrei um gateway matriz conectado para essa propriedade.',
        error: true,
      );
      return;
    }

    final notifyUserIds = await firebase.getLinkedUserIdsForProperty(propertyId);
    final ownerUid = _userIdFrom(property['ownerUid']) ??
        _userIdFrom(property['createdByUid']) ??
        uid;
    final selectedDeviceIds = selectedDevices
        .map((device) => device.loraDeviceId)
        .whereType<String>()
        .toList()
      ..sort();
    final targetPolygon =
        _targetPolygon.map((point) => <double>[point.latitude, point.longitude]).toList();

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

      final sent = await gateway.startHerdingOperationEnsuringConnection(
        hostOverride: matrixGatewayWsHost,
        payload: <String, dynamic>{
          'operation_id': operationId,
          'property_id': propertyId,
          'owner_uid': ownerUid,
          'matrix_gateway_id': matrixGatewayId,
          'requested_by_uid': uid,
          'requested_by_role': auth.role,
          'selected_device_ids': selectedDeviceIds,
          'notify_user_ids': notifyUserIds,
          'target_polygon': targetPolygon,
          'area_promotion_requested': true,
        },
      );

      if (!sent) {
        await firebase.markHerdingOperationSubmissionFailed(
          operationId: operationId,
          reason: gateway.lastError ?? 'gateway_not_connected',
        );
        if (!mounted) return;
        _showFeedback(
          'Operacao criada, mas o envio para a matriz falhou (${gateway.lastError ?? 'gateway_not_connected'}).',
          error: true,
        );
        return;
      }

      if (!mounted) return;
      setState(() => _createdOperationId = operationId);
      _showFeedback('Operacao enviada para o gateway matriz.');
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
              operation == null ? 'Ultima operacao' : 'Operacao ${operation.id}',
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
    final firebase = context.read<FirebaseService>();
    final gateway = context.read<GatewayService>();
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
              child: Text('Erro ao carregar propriedades: ${propertySnap.error}'),
            );
          }
          final properties = propertySnap.data ?? const <Map<String, dynamic>>[];
          if (properties.isEmpty) {
            return const Center(
              child: Text('Cadastre ou vincule uma propriedade para usar o arrebanhamento.'),
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

              final selectedProperty = properties.cast<Map<String, dynamic>?>().firstWhere(
                    (property) => property?['id']?.toString() == _selectedPropertyId,
                    orElse: () => null,
                  );
              final propertyPolygon = _decodePolygon(selectedProperty?['points']);
              final propertyDevices = _devicesForProperty(devices);

              return StreamBuilder<List<Map<String, dynamic>>>(
                stream: firebase.streamAreas(uid: uid, isAdmin: auth.isAdmin),
                builder: (context, areaSnap) {
                  if (areaSnap.hasError) {
                    return Center(
                      child: Text('Erro ao carregar areas: ${areaSnap.error}'),
                    );
                  }
                  final propertyAreas =
                      _areasForProperty(areaSnap.data ?? const <Map<String, dynamic>>[]);
                  _fitViewport(
                    propertyPolygon: propertyPolygon,
                    propertyDevices: propertyDevices,
                  );

                  return StreamBuilder<List<HerdingOperationModel>>(
                    stream: firebase.streamHerdingOperations(
                      uid: uid,
                      isAdmin: auth.isAdmin,
                    ),
                    builder: (context, operationsSnap) {
                      final operations =
                          operationsSnap.data ?? const <HerdingOperationModel>[];
                      final trackedOperation = _createdOperationId == null
                          ? operations.cast<HerdingOperationModel?>().firstWhere(
                                (operation) =>
                                    operation?.propertyId == _selectedPropertyId,
                                orElse: () => null,
                              )
                          : operations.cast<HerdingOperationModel?>().firstWhere(
                                (operation) => operation?.id == _createdOperationId,
                                orElse: () => null,
                              );

                      final polygons = <Polygon<Object>>[
                        if (propertyPolygon.length >= 3)
                          Polygon<Object>(
                            points: propertyPolygon,
                            color: Colors.green.withValues(alpha: 0.16),
                            borderColor: Colors.green.shade700,
                            borderStrokeWidth: 3,
                          ),
                        ...propertyAreas
                            .map((area) => _decodePolygon(area['perimeter']))
                            .where((points) => points.length >= 3)
                            .map(
                              (points) => Polygon<Object>(
                                points: points,
                                color: Colors.orange.withValues(alpha: 0.08),
                                borderColor: Colors.orange.shade700,
                                borderStrokeWidth: 2,
                              ),
                            ),
                        if (_targetPolygon.length >= 2)
                          Polygon<Object>(
                            points: _targetPolygon,
                            color: Colors.blue.withValues(alpha: 0.18),
                            borderColor: Colors.blue.shade700,
                            borderStrokeWidth: 3,
                          ),
                      ];

                      final markers = propertyDevices
                          .map((device) {
                            final deviceId = device.loraDeviceId;
                            final position = _devicePosition(device);
                            if (deviceId == null || position == null) return null;
                            final selected = _selectedDeviceIds.contains(deviceId);
                            return Marker(
                              point: position,
                              width: 78,
                              height: 78,
                              child: GestureDetector(
                                onTap: () => _toggleDevice(device),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      selected ? Icons.pets : Icons.pets_outlined,
                                      color: selected
                                          ? Colors.red.shade700
                                          : Colors.brown.shade700,
                                      size: 28,
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(999),
                                        boxShadow: const [
                                          BoxShadow(
                                            blurRadius: 8,
                                            color: Color(0x22000000),
                                          ),
                                        ],
                                      ),
                                      child: Text(
                                        device.name,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          })
                          .whereType<Marker>()
                          .toList();

                      final polygonVertices = _targetPolygon
                          .map(
                            (point) => Marker(
                              point: point,
                              width: 18,
                              height: 18,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade700,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                ),
                              ),
                            ),
                          )
                          .toList();

                      return Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
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
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Toque nas coleiras no mapa para selecionar os animais. Toque no mapa para desenhar o poligono destino.',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: _targetPolygon.isEmpty ? null : _undoPoint,
                                  icon: const Icon(Icons.undo),
                                  label: const Text('Desfazer'),
                                ),
                                TextButton.icon(
                                  onPressed: _targetPolygon.isEmpty ? null : _clearPolygon,
                                  icon: const Icon(Icons.delete_outline),
                                  label: const Text('Limpar'),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Wrap(
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
                                      '${_targetPolygon.length} pontos no poligono',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(24),
                                child: FlutterMap(
                                  mapController: _mapController,
                                  options: MapOptions(
                                    initialCenter: propertyPolygon.isNotEmpty
                                        ? propertyPolygon.first
                                        : LatLng(
                                            widget.initialLat ?? -23.0,
                                            widget.initialLon ?? -46.0,
                                          ),
                                    initialZoom: 15,
                                    onTap: (_, point) => _addPolygonPoint(point),
                                  ),
                                  children: [
                                    TileLayer(
                                      urlTemplate:
                                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                      userAgentPackageName: 'ruraltech_app',
                                    ),
                                    if (polygons.isNotEmpty) PolygonLayer(polygons: polygons),
                                    if (markers.isNotEmpty || polygonVertices.isNotEmpty)
                                      MarkerLayer(markers: <Marker>[...markers, ...polygonVertices]),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
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
                                    key: const Key('submit_herding_operation_button'),
                                    onPressed: _isSubmitting || selectedProperty == null
                                        ? null
                                        : () => _submitOperation(
                                              selectedProperty,
                                              propertyDevices,
                                              auth,
                                              firebase,
                                              gateway,
                                            ),
                                    icon: _isSubmitting
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
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
      ),
    );
  }
}
