import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../config/manual_settings.dart';
import '../services/auth_service.dart';
import '../services/firebase_service.dart';
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

  @override
  void initState() {
    super.initState();
    _center = LatLng(widget.initialLat ?? -23.0, widget.initialLon ?? -46.0);
    _loadSavedFence();
  }

  Future<void> _loadSavedFence() async {
    try {
      final savedPoints =
          await context.read<FirebaseService>().getFence(widget.deviceId);
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
    final firebase = context.read<FirebaseService>();

    final points =
        _polygonPoints.map((p) => <double>[p.latitude, p.longitude]).toList();
    await firebase.saveFence(widget.deviceId, uid, points);
    try {
      await firebase.enqueueScopedCommand(
        command: 'SET_FENCE',
        propertyId: propertyId,
        requestedByUid: uid,
        requestedByRole: auth.role,
        targetDeviceIds: <String>[widget.deviceId],
        payload: {'points': points},
      );
      if (!mounted) return;
      AppFeedback.success('Cerca salva e enfileirada para a matriz.');
    } catch (e) {
      if (!mounted) return;
      AppFeedback.warning(
        'Cerca salva, mas falhou o enfileiramento para envio LoRa ($e).',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
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
