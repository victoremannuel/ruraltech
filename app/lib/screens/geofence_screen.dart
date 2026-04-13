import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../config/manual_settings.dart';
import '../services/auth_service.dart';
import '../services/cloud_service.dart';
import '../utils/top_feedback.dart';

class GeofenceScreen extends StatefulWidget {
  final String deviceId;
  final String? propertyId;
  final String? gatewayId;
  final double? initialLat;
  final double? initialLon;

  const GeofenceScreen({
    super.key,
    required this.deviceId,
    this.propertyId,
    this.gatewayId,
    this.initialLat,
    this.initialLon,
  });

  @override
  State<GeofenceScreen> createState() => _GeofenceScreenState();
}

class _GeofenceScreenState extends State<GeofenceScreen> {
  static const int _maxFencePoints = 32;
  late LatLng _center;
  final List<LatLng> _polygonPoints = [];
  bool _isLoadingSavedFence = true;
  String? _lastCommandId;
  String? _commandStatus;

  @override
  void initState() {
    super.initState();
    _center = LatLng(widget.initialLat ?? -23.0, widget.initialLon ?? -46.0);
    _loadSavedFence();
  }

  Future<void> _loadSavedFence() async {
    try {
      final savedPoints =
          await context.read<CloudService>().getFence(widget.deviceId);
      if (!mounted) return;
      if (_polygonPoints.isEmpty && savedPoints.isNotEmpty) {
        final loaded = savedPoints
            .where((p) => p.length >= 2)
            .map((p) => LatLng(p[0], p[1]))
            .toList();
        if (loaded.isNotEmpty) {
          setState(() {
            _polygonPoints
              ..clear()
              ..addAll(loaded);
            _center = loaded.first;
          });
        }
      }
    } finally {
      if (mounted) setState(() => _isLoadingSavedFence = false);
    }
  }

  Future<void> _publishFence() async {
    if (_polygonPoints.length < 3) {
      AppFeedback.error('Adicione ao menos 3 pontos ao poligono.');
      return;
    }

    final uid = context.read<AuthService>().user?.uid;
    final auth = context.read<AuthService>();
    if (uid == null) return;
    final propertyId = widget.propertyId?.trim();
    if (propertyId == null || propertyId.isEmpty) {
      AppFeedback.error(
        'A coleira precisa estar vinculada a uma propriedade para receber comandos LoRa.',
      );
      return;
    }
    final cloud = context.read<CloudService>();

    final points =
        _polygonPoints.map((p) => <double>[p.latitude, p.longitude]).toList();
    await cloud.saveFence(widget.deviceId, uid, points);

    setState(() => _commandStatus = 'queued');

    try {
      final commandId = await cloud.enqueueScopedCommand(
        command: 'SET_FENCE',
        propertyId: propertyId,
        requestedByUid: uid,
        requestedByRole: auth.role,
        targetDeviceIds: <String>[widget.deviceId],
        payload: {
          'points': points,
          'polygon_kind': 'manualFence',
          'origin_doc_type': 'manualFence',
          'origin_doc_id': widget.deviceId,
        },
        businessRef: {
          'type': 'manualFence',
          'id': widget.deviceId,
        },
      );
      if (!mounted) return;
      setState(() => _lastCommandId = commandId);
      AppFeedback.success('Cerca salva e enfileirada para a matriz.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _commandStatus = 'failed');
      AppFeedback.warning(
        'Cerca salva, mas falhou o enfileiramento para envio LoRa ($e).',
      );
    }
  }

  String? _buildCommandStatusText() {
    final propertyId = widget.propertyId?.trim();
    if (propertyId == null || propertyId.isEmpty) return null;
    if (_lastCommandId == null && _commandStatus == null) return null;
    if (_lastCommandId != null) {
      // Acompanhar via stream (resolvido abaixo no build)
      return null;
    }
    if (_commandStatus != null) {
      return CloudService.commandStatusLabel(_commandStatus)['label'] as String?;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final propertyId = widget.propertyId?.trim() ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Geofence no mapa')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Colors.green.withValues(alpha: 0.08),
            child: Text(
              'Toque no mapa para adicionar vertices. Pontos: ${_polygonPoints.length}/$_maxFencePoints',
            ),
          ),
          if (_isLoadingSavedFence) const LinearProgressIndicator(minHeight: 2),
          if (_lastCommandId != null && propertyId.isNotEmpty)
            StreamBuilder<Map<String, dynamic>?>(
              stream: context.read<CloudService>().streamCommandStatus(
                    propertyId: propertyId,
                    commandId: _lastCommandId!,
                  ),
              builder: (context, snapshot) {
                final data = snapshot.data;
                final status = data?['status'] as String?;
                final label = CloudService.commandStatusLabel(status);
                final text = label['label'] as String;
                final isTerminal = label['isTerminal'] as bool;
                final color = isTerminal
                    ? (status == 'applied' || status == 'success'
                        ? Colors.green.shade700
                        : Colors.orange.shade700)
                    : Colors.blue.shade700;
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  color: color.withValues(alpha: 0.08),
                  child: Row(
                    children: [
                      if (!isTerminal)
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      if (!isTerminal) const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          text,
                          style: TextStyle(
                            color: color,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          Expanded(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: _center,
                initialZoom: 16,
                onTap: (_, point) {
                  if (_polygonPoints.length >= _maxFencePoints) {
                    AppFeedback.error(
                      'Limite da coleira: máximo de $_maxFencePoints pontos na geofence.',
                    );
                    return;
                  }
                  setState(() => _polygonPoints.add(point));
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                  userAgentPackageName: ManualSettings.mapUserAgentPackageName,
                ),
                PolygonLayer(
                  polygons: [
                    if (_polygonPoints.length >= 3)
                      Polygon(
                        points: _polygonPoints,
                        color: Colors.green.withValues(alpha: 0.25),
                        borderColor: Colors.green,
                        borderStrokeWidth: 3,
                      ),
                  ],
                ),
                PolylineLayer(
                  polylines: [
                    if (_polygonPoints.length >= 2)
                      Polyline(
                        points: _polygonPoints,
                        strokeWidth: 2,
                        color: Colors.green.shade700,
                      ),
                  ],
                ),
                MarkerLayer(
                  markers: _polygonPoints
                      .map(
                        (p) => Marker(
                          point: p,
                          width: 18,
                          height: 18,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.green.shade800,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const Scalebar(
                  alignment: Alignment.bottomRight,
                  padding: EdgeInsets.only(
                    right: 12,
                    bottom: 12,
                  ),
                  lineColor: Color(0xFF173120),
                  textStyle: TextStyle(
                    color: Color(0xFF173120),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('geofence_undo_button'),
                    onPressed: _polygonPoints.isEmpty
                        ? null
                        : () {
                            setState(() => _polygonPoints.removeLast());
                          },
                    child: const Text('Desfazer'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    key: const Key('geofence_clear_button'),
                    onPressed: _polygonPoints.isEmpty
                        ? null
                        : () {
                            setState(_polygonPoints.clear);
                          },
                    child: const Text('Limpar'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    key: const Key('geofence_publish_button'),
                    onPressed: _publishFence,
                    child: const Text('Publicar'),
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
