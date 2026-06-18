import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../components/primitives/rt_button.dart';
import '../config/manual_settings.dart';
import '../design/colors.dart';
import '../design/tokens.dart';
import '../design/typography.dart';

/// Tela de seleção de ponto no mapa — RuralTech v2.
///
/// Layout full-bleed: o usuário arrasta o mapa e o crosshair
/// fixo no centro indica o ponto selecionado. Pressiona "Confirmar"
/// para retornar a posição atual do centro do mapa.
class MapPointPickerScreen extends StatefulWidget {
  const MapPointPickerScreen({
    super.key,
    this.initial,
    this.propertyPolygon = const [],
  });

  final LatLng? initial;
  final List<LatLng> propertyPolygon;

  @override
  State<MapPointPickerScreen> createState() => _MapPointPickerScreenState();
}

class _MapPointPickerScreenState extends State<MapPointPickerScreen> {
  late LatLng _center;
  final MapController _mapController = MapController();
  bool _fitted = false;
  bool _moving = false;

  @override
  void initState() {
    super.initState();
    _center = widget.initial ?? const LatLng(-23.0, -46.0);
  }

  void _fitToProperty() {
    if (_fitted || widget.propertyPolygon.length < 3) return;
    _fitted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final bounds = LatLngBounds.fromPoints(widget.propertyPolygon);
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(48),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    _fitToProperty();
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: RTColors.ink,
      body: Stack(
        children: [
          // ── Mapa full-bleed ──────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 15,
                onPositionChanged: (pos, hasGesture) {
                setState(() {
                  _center = pos.center;
                  _moving = hasGesture;
                });
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
              if (widget.propertyPolygon.length >= 3)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: widget.propertyPolygon,
                      color: RTColors.accent.withValues(alpha: 0.15),
                      borderColor: RTColors.accent.withValues(alpha: 0.8),
                      borderStrokeWidth: 2.5,
                    ),
                  ],
                ),
              const Scalebar(
                alignment: Alignment.bottomRight,
                padding: EdgeInsets.only(right: 16, bottom: 112),
                lineColor: Color(0xFF173120),
                textStyle: TextStyle(
                  color: Color(0xFF173120),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),

          // ── Banner instrução (topo) ──────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + RTSpacing.x3,
            left: RTSpacing.x4,
            right: RTSpacing.x4,
            child: _InstructionBanner(),
          ),

          // ── Crosshair central ───────────────────────────────
          Center(
            child: _Crosshair(moving: _moving),
          ),

          // ── Coordenadas flutuantes ───────────────────────────
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 60),
              child: _CoordBadge(center: _center),
            ),
          ),

          // ── Botões sticky (fundo) ────────────────────────────
          Positioned(
            left: RTSpacing.x4,
            right: RTSpacing.x4,
            bottom: bottomPad + RTSpacing.x4,
            child: Row(
              children: [
                Expanded(
                  child: RTButton(
                    label: 'Cancelar',
                    variant: RTButtonVariant.ghost,
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: RTSpacing.x3),
                Expanded(
                  flex: 2,
                  child: RTButton(
                    label: 'Confirmar posição',
                    variant: RTButtonVariant.primary,
                    icon: Icons.check_rounded,
                    onPressed: () => Navigator.pop(context, _center),
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

// ── Subwidgets ─────────────────────────────────────────────────

class _InstructionBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RTSpacing.x4,
        vertical: RTSpacing.x3,
      ),
      decoration: BoxDecoration(
        color: RTColors.ink.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(RTRadius.r3),
        boxShadow: const [
          BoxShadow(
            color: Color(0x28000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.open_with_rounded, size: 16, color: RTColors.heroInk),
          const SizedBox(width: RTSpacing.x2),
          Expanded(
            child: Text(
              'Arraste o mapa para posicionar o marcador no centro',
              style: RTTypography.bodySmall.copyWith(
                color: RTColors.heroInk,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Crosshair extends StatelessWidget {
  const _Crosshair({required this.moving});
  final bool moving;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: moving ? 1.15 : 1.0,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Halo
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: RTColors.primary.withValues(alpha: 0.15),
                border: Border.all(
                  color: RTColors.primary.withValues(alpha: 0.4),
                  width: 1.5,
                ),
              ),
            ),
            // Cruz horizontal
            Container(
              width: 24,
              height: 1.5,
              color: RTColors.primary,
            ),
            // Cruz vertical
            Container(
              width: 1.5,
              height: 24,
              color: RTColors.primary,
            ),
            // Ponto central
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: RTColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoordBadge extends StatelessWidget {
  const _CoordBadge({required this.center});
  final LatLng center;

  @override
  Widget build(BuildContext context) {
    final lat = center.latitude.toStringAsFixed(6);
    final lon = center.longitude.toStringAsFixed(6);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RTSpacing.x3,
        vertical: RTSpacing.x2,
      ),
      decoration: BoxDecoration(
        color: RTColors.ink.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(RTRadius.r1),
      ),
      child: Text(
        '$lat, $lon',
        style: RTTypography.mono.copyWith(
          color: RTColors.heroInk,
          fontSize: 11,
        ),
      ),
    );
  }
}
