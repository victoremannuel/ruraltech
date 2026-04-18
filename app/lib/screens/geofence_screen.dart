import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../components/primitives/rt_button.dart';
import '../config/manual_settings.dart';
import '../design/colors.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
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
  bool _isPublishing = false;

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
      AppFeedback.error('Adicione ao menos 3 pontos ao polígono.');
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

    setState(() => _isPublishing = true);
    final points =
        _polygonPoints.map((p) => <double>[p.latitude, p.longitude]).toList();
    try {
      await cloud.saveFence(widget.deviceId, uid, points);
      try {
        await cloud.enqueueScopedCommand(
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
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RTColors.bgAlt,
      appBar: AppBar(title: const Text('Geofence no mapa')),
      body: Column(
        children: [
          _buildHud(),
          if (_isLoadingSavedFence)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
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
                      urlTemplate:
                          'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                      subdomains: const ['a', 'b', 'c'],
                      userAgentPackageName:
                          ManualSettings.mapUserAgentPackageName,
                    ),
                    PolygonLayer(
                      polygons: [
                        if (_polygonPoints.length >= 3)
                          Polygon(
                            points: _polygonPoints,
                            color: RTColors.primary.withValues(alpha: 0.2),
                            borderColor: RTColors.primaryDeep,
                            borderStrokeWidth: 3,
                          ),
                      ],
                    ),
                    PolylineLayer(
                      polylines: [
                        if (_polygonPoints.length >= 2)
                          Polyline(
                            points: _polygonPoints,
                            strokeWidth: 2.5,
                            color: RTColors.primaryDeep,
                          ),
                      ],
                    ),
                    MarkerLayer(markers: _buildVertexMarkers()),
                    const Scalebar(
                      alignment: Alignment.bottomRight,
                      padding: EdgeInsets.only(right: 12, bottom: 12),
                      lineColor: Color(0xFF173120),
                      textStyle: TextStyle(
                        color: Color(0xFF173120),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _buildActionsBar(),
        ],
      ),
    );
  }

  Widget _buildHud() {
    final canPublish = _polygonPoints.length >= 3;
    final counterColor = _polygonPoints.length >= _maxFencePoints
        ? RTColors.warn
        : RTColors.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        RTSpacing.x4,
        RTSpacing.x3,
        RTSpacing.x4,
        RTSpacing.x3,
      ),
      decoration: BoxDecoration(
        color: RTColors.bg,
        border: Border(bottom: BorderSide(color: RTColors.hairSoft)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: RTColors.primarySoft,
              borderRadius: BorderRadius.circular(RTRadius.r2),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.crop_free, color: RTColors.primary, size: 18),
          ),
          const SizedBox(width: RTSpacing.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  canPublish
                      ? 'Polígono pronto para publicar'
                      : 'Toque no mapa para adicionar vértices',
                  style: RTTypography.bodyStrong,
                ),
                const SizedBox(height: 2),
                Text(
                  'Coleira ${widget.deviceId}',
                  style: RTTypography.bodySmall,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('VÉRTICES', style: RTTypography.eyebrow),
              const SizedBox(height: 2),
              Text(
                '${_polygonPoints.length}/$_maxFencePoints',
                style: RTTypography.monoLarge.copyWith(color: counterColor),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Marker> _buildVertexMarkers() {
    final markers = <Marker>[];
    for (var i = 0; i < _polygonPoints.length; i++) {
      final point = _polygonPoints[i];
      markers.add(
        Marker(
          point: point,
          width: 28,
          height: 28,
          child: Container(
            decoration: BoxDecoration(
              color: RTColors.primaryDeep,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: RTElevation.sh2,
            ),
            alignment: Alignment.center,
            child: Text(
              '${i + 1}',
              style: RTTypography.monoSmall.copyWith(
                color: RTColors.onPrimary,
                fontSize: 11,
                height: 1.0,
              ),
            ),
          ),
        ),
      );
    }
    return markers;
  }

  Widget _buildActionsBar() {
    final hasPoints = _polygonPoints.isNotEmpty;
    final canPublish = _polygonPoints.length >= 3 && !_isPublishing;
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: RTColors.bg,
          border: Border(top: BorderSide(color: RTColors.hairSoft)),
        ),
        padding: const EdgeInsets.fromLTRB(
          RTSpacing.x3,
          RTSpacing.x3,
          RTSpacing.x3,
          RTSpacing.x3,
        ),
        child: Row(
          children: [
            Expanded(
              child: RTButton(
                key: const Key('geofence_undo_button'),
                label: 'Desfazer',
                icon: Icons.undo,
                variant: RTButtonVariant.ghost,
                onPressed: hasPoints
                    ? () => setState(() => _polygonPoints.removeLast())
                    : null,
              ),
            ),
            const SizedBox(width: RTSpacing.x2),
            Expanded(
              child: RTButton(
                key: const Key('geofence_clear_button'),
                label: 'Limpar',
                icon: Icons.delete_outline,
                variant: RTButtonVariant.tonal,
                onPressed:
                    hasPoints ? () => setState(_polygonPoints.clear) : null,
              ),
            ),
            const SizedBox(width: RTSpacing.x2),
            Expanded(
              flex: 2,
              child: RTButton(
                key: const Key('geofence_publish_button'),
                label: 'Publicar',
                icon: Icons.cloud_upload_outlined,
                variant: RTButtonVariant.primary,
                loading: _isPublishing,
                onPressed: canPublish ? _publishFence : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
