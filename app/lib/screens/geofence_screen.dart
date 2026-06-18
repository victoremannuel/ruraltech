import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../components/domain/rt_confirm_lora.dart';
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

  Future<bool> _confirmDiscard(BuildContext context) async {
    if (_polygonPoints.isEmpty) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Descartar alterações?'),
        content: const Text(
            'Você tem vértices não publicados. Deseja sair sem publicar a cerca?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Continuar editando'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                TextButton.styleFrom(foregroundColor: RTColors.danger),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await _confirmDiscard(context);
        if (ok && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.45),
        foregroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle:
            RTTypography.h3.copyWith(color: Colors.white, fontSize: 17),
        title: Text('Geofence · ${widget.deviceId}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            final ok = await _confirmDiscard(context);
            if (ok && context.mounted) Navigator.pop(context);
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSavedFence,
            tooltip: 'Recarregar',
          ),
          IconButton(
            icon: const Icon(Icons.more_horiz),
            tooltip: 'Mais',
            onPressed: () {
              HapticFeedback.selectionClick();
              showModalBottomSheet<void>(
                context: context,
                builder: (ctx) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.file_upload_outlined),
                        title: const Text('Importar GPX'),
                        onTap: () {
                          Navigator.pop(ctx);
                          AppFeedback.warning(
                              'Importação GPX disponível em breve.');
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.file_download_outlined),
                        title: const Text('Exportar'),
                        onTap: () {
                          Navigator.pop(ctx);
                          AppFeedback.warning(
                              'Exportação disponível em breve.');
                        },
                      ),
                      ListTile(
                        leading:
                            Icon(Icons.delete_sweep_outlined, color: RTColors.danger),
                        title: Text('Limpar tudo',
                            style: TextStyle(color: RTColors.danger)),
                        onTap: () async {
                          Navigator.pop(ctx);
                          if (_polygonPoints.isEmpty) return;
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (d) => AlertDialog(
                              title: const Text('Limpar todos os vértices?'),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(d, false),
                                  child: const Text('Cancelar'),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(d, true),
                                  style: TextButton.styleFrom(
                                      foregroundColor: RTColors.danger),
                                  child: const Text('Limpar'),
                                ),
                              ],
                            ),
                          );
                          if (ok == true && mounted) {
                            HapticFeedback.mediumImpact();
                            setState(_polygonPoints.clear);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(color: Colors.transparent),
          ),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
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
                  urlTemplate:
                      'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
                  userAgentPackageName: ManualSettings.mapUserAgentPackageName,
                ),
                PolygonLayer(
                  polygons: [
                    if (_polygonPoints.length >= 3)
                      Polygon(
                        points: _polygonPoints,
                        color: RTColors.accent.withValues(alpha: 0.18),
                        borderColor: RTColors.accent,
                        borderStrokeWidth: 2,
                      ),
                  ],
                ),
                PolylineLayer(
                  polylines: [
                    if (_polygonPoints.length >= 2)
                      Polyline(
                        points: _polygonPoints,
                        strokeWidth: 2,
                        color: RTColors.accent.withValues(alpha: 0.7),
                      ),
                  ],
                ),
                MarkerLayer(markers: _buildVertexMarkers()),
                const Scalebar(
                  alignment: Alignment.bottomRight,
                  padding: EdgeInsets.only(right: 12, bottom: 12),
                  lineColor: Colors.white54,
                  textStyle: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (_isLoadingSavedFence)
            Positioned(
              top: kToolbarHeight + topPad,
              left: 0,
              right: 0,
              child: const LinearProgressIndicator(minHeight: 2),
            ),
          Positioned(
            top: kToolbarHeight + topPad + 12,
            left: 0,
            right: 0,
            child: Center(
              child: _HudPill(
                vertices: _polygonPoints.length,
                maxVertices: _maxFencePoints,
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildActionsBar(),
          ),
        ],
      ),
    ),  // Scaffold
    );  // PopScope
  }


  List<Marker> _buildVertexMarkers() {
    final markers = <Marker>[];
    for (var i = 0; i < _polygonPoints.length; i++) {
      final point = _polygonPoints[i];
      final idx = i;
      markers.add(
        Marker(
          point: point,
          width: 28,
          height: 28,
          child: GestureDetector(
            onLongPress: () {
              HapticFeedback.mediumImpact();
              setState(() => _polygonPoints.removeAt(idx));
            },
            child: Container(
              decoration: BoxDecoration(
                color: RTColors.primaryDeep,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: RTElevation.sh2,
              ),
              alignment: Alignment.center,
              child: Text(
                '${idx + 1}',
                style: RTTypography.monoSmall.copyWith(
                  color: RTColors.onPrimary,
                  fontSize: 11,
                  height: 1.0,
                ),
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Row(children: [
                Expanded(
                  child: _GhostBtn(
                    key: const Key('geofence_undo_button'),
                    icon: Icons.undo,
                    label: 'Desfazer',
                    onPressed: hasPoints
                        ? () => setState(() => _polygonPoints.removeLast())
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _GhostBtn(
                    key: const Key('geofence_clear_button'),
                    icon: Icons.delete_outline,
                    label: 'Limpar',
                    onPressed: hasPoints
                        ? () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (d) => AlertDialog(
                                title:
                                    const Text('Limpar todos os vértices?'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(d, false),
                                    child: const Text('Cancelar'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(d, true),
                                    style: TextButton.styleFrom(
                                        foregroundColor: RTColors.danger),
                                    child: const Text('Limpar'),
                                  ),
                                ],
                              ),
                            );
                            if (ok == true && mounted) {
                              HapticFeedback.mediumImpact();
                              setState(_polygonPoints.clear);
                            }
                          }
                        : null,
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            const RTConfirmLoRa(
                message: 'Comandos LoRa são irreversíveis'),
            const SizedBox(height: 12),
            RTButton(
              key: const Key('geofence_publish_button'),
              label: 'Publicar cerca via LoRa',
              variant: RTButtonVariant.accent,
              size: RTButtonSize.lg,
              fullWidth: true,
              trailing: Icons.arrow_forward,
              loading: _isPublishing,
              onPressed: canPublish ? _publishFence : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _HudPill extends StatelessWidget {
  const _HudPill({required this.vertices, required this.maxVertices});

  final int vertices;
  final int maxVertices;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(999),
            border:
                Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: RTColors.accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$vertices / $maxVertices vértices',
                style: RTTypography.mono
                    .copyWith(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GhostBtn extends StatelessWidget {
  const _GhostBtn({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: enabled ? 0.08 : 0.03),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: Colors.white.withValues(alpha: enabled ? 0.15 : 0.05)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 16,
                color: Colors.white
                    .withValues(alpha: enabled ? 0.9 : 0.3)),
            const SizedBox(width: 6),
            Text(
              label,
              style: RTTypography.label.copyWith(
                fontSize: 13,
                color: Colors.white.withValues(alpha: enabled ? 0.9 : 0.3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
