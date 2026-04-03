import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../config/manual_settings.dart';
import '../models/polygon_map_context.dart';
import '../utils/polygon_edit_session.dart';
import '../utils/top_feedback.dart';

class PolygonEditingMap extends StatefulWidget {
  const PolygonEditingMap({
    super.key,
    required this.controller,
    this.contextData = const PolygonMapContext(),
    this.enforceBoundary = false,
    this.maxPoints,
    this.allowFreeAdd = true,
    this.fallbackCenter = const LatLng(-23.0, -46.0),
    this.initialZoom = 15,
    this.viewportSignature,
    this.showBaseTiles = true,
    this.outOfBoundaryMessage = 'Ponto fora do limite permitido.',
    this.idleTapMessage =
        'Toque em um ponto para mover, no perimetro para inserir ou em uma area livre para adicionar.',
    this.boundaryFillColor = const Color(0x33FB8C00),
    this.boundaryBorderColor = const Color(0xFFF57C00),
    this.areaFillColor = const Color(0x26009688),
    this.areaBorderColor = const Color(0xFF00897B),
    this.draftFillColor = const Color(0x4D00897B),
    this.draftBorderColor = const Color(0xFF00897B),
    this.vertexColor = const Color(0xFF00695C),
    this.selectedVertexColor = const Color(0xFFC62828),
  });

  final PolygonEditSessionController controller;
  final PolygonMapContext contextData;
  final bool enforceBoundary;
  final int? maxPoints;
  final bool allowFreeAdd;
  final LatLng fallbackCenter;
  final double initialZoom;
  final Object? viewportSignature;
  final bool showBaseTiles;
  final String outOfBoundaryMessage;
  final String idleTapMessage;
  final Color boundaryFillColor;
  final Color boundaryBorderColor;
  final Color areaFillColor;
  final Color areaBorderColor;
  final Color draftFillColor;
  final Color draftBorderColor;
  final Color vertexColor;
  final Color selectedVertexColor;

  @override
  State<PolygonEditingMap> createState() => _PolygonEditingMapState();
}

class _PolygonEditingMapState extends State<PolygonEditingMap> {
  final MapController _mapController = MapController();
  Offset? _dragScreenOffset;
  bool _userPinnedViewport = false;
  Object? _lastAppliedViewportSignature;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChange);
  }

  @override
  void didUpdateWidget(covariant PolygonEditingMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_handleControllerChange);
      widget.controller.addListener(_handleControllerChange);
      _dragScreenOffset = null;
    }
    if (oldWidget.viewportSignature != widget.viewportSignature) {
      _userPinnedViewport = false;
      _lastAppliedViewportSignature = null;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChange);
    _mapController.dispose();
    super.dispose();
  }

  void _handleControllerChange() {
    if (!mounted) return;
    setState(() {});
  }

  bool _isInsidePolygon(LatLng point, List<LatLng> polygon) {
    if (polygon.length < 3) return false;
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final xi = polygon[i].longitude;
      final yi = polygon[i].latitude;
      final xj = polygon[j].longitude;
      final yj = polygon[j].latitude;
      final intersects = ((yi > point.latitude) != (yj > point.latitude)) &&
          (point.longitude <
              (xj - xi) * (point.latitude - yi) / ((yj - yi) + 1e-12) + xi);
      if (intersects) inside = !inside;
    }
    return inside;
  }

  bool _isPointAllowed(LatLng point) {
    final boundary = widget.contextData.boundaryPolygon;
    if (!widget.enforceBoundary || boundary.length < 3) return true;
    return _isInsidePolygon(point, boundary);
  }

  double _distancePointToSegment(LatLng p, LatLng a, LatLng b) {
    final px = p.longitude;
    final py = p.latitude;
    final ax = a.longitude;
    final ay = a.latitude;
    final bx = b.longitude;
    final by = b.latitude;

    final dx = bx - ax;
    final dy = by - ay;
    if (dx == 0 && dy == 0) {
      final lx = px - ax;
      final ly = py - ay;
      return math.sqrt(lx * lx + ly * ly);
    }
    final t = (((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy))
        .clamp(0.0, 1.0);
    final cx = ax + t * dx;
    final cy = ay + t * dy;
    final lx = px - cx;
    final ly = py - cy;
    return math.sqrt(lx * lx + ly * ly);
  }

  int? _nearestEdgeIndex(LatLng point, List<LatLng> polygon) {
    if (polygon.length < 2) return null;
    var bestIndex = -1;
    var bestDistance = double.maxFinite;
    for (var i = 0; i < polygon.length; i++) {
      final nextIndex = (i + 1) % polygon.length;
      final distance =
          _distancePointToSegment(point, polygon[i], polygon[nextIndex]);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }
    const threshold = 0.00045;
    return bestDistance <= threshold ? bestIndex : null;
  }

  String _maxPointsMessage() {
    final maxPoints = widget.maxPoints;
    if (maxPoints == null) return 'Limite de pontos atingido.';
    return 'Permitido apenas $maxPoints pontos.';
  }

  bool _canAddMorePoints() {
    final maxPoints = widget.maxPoints;
    return maxPoints == null || widget.controller.points.length < maxPoints;
  }

  void _onMapTap(LatLng point) {
    if (!_isPointAllowed(point)) {
      AppFeedback.error(widget.outOfBoundaryMessage);
      return;
    }

    final selectedIndex = widget.controller.selectedPointIndex;
    if (selectedIndex != null) {
      widget.controller.moveSelectedPoint(point);
      return;
    }

    final edge = _nearestEdgeIndex(point, widget.controller.points);
    if (edge != null) {
      if (!_canAddMorePoints()) {
        AppFeedback.error(_maxPointsMessage());
        return;
      }
      widget.controller.insertPoint(edge + 1, point);
      return;
    }

    final canAppendFreely =
        widget.allowFreeAdd || widget.controller.points.length < 2;
    if (canAppendFreely) {
      if (!_canAddMorePoints()) {
        AppFeedback.error(_maxPointsMessage());
        return;
      }
      widget.controller.addPoint(point);
      return;
    }

    AppFeedback.warning(widget.idleTapMessage);
  }

  void _startDraggingPoint(int index) {
    final points = widget.controller.points;
    if (index < 0 || index >= points.length) return;
    final screenPoint =
        _mapController.camera.latLngToScreenPoint(points[index]);
    widget.controller.beginDragPoint(index);
    setState(() {
      _dragScreenOffset = Offset(screenPoint.x, screenPoint.y);
    });
  }

  void _updateDraggingPoint(int index, Offset delta) {
    if (_dragScreenOffset == null ||
        widget.controller.draggingPointIndex != index) {
      return;
    }

    final nextOffset = Offset(
      _dragScreenOffset!.dx + delta.dx,
      _dragScreenOffset!.dy + delta.dy,
    );
    final nextPoint = _mapController.camera.offsetToCrs(nextOffset);
    if (!_isPointAllowed(nextPoint)) {
      return;
    }

    _dragScreenOffset = nextOffset;
    widget.controller.previewDragPoint(nextPoint);
  }

  void _endDraggingPoint() {
    widget.controller.endDragPoint();
    if (!mounted) return;
    setState(() => _dragScreenOffset = null);
  }

  void _cancelDraggingPoint() {
    widget.controller.cancelDragPoint();
    if (!mounted) return;
    setState(() => _dragScreenOffset = null);
  }

  void _applyViewportIfNeeded() {
    if (_userPinnedViewport) return;
    final signature = widget.viewportSignature ?? widget.key ?? 'initial';
    if (_lastAppliedViewportSignature == signature) return;

    final fitPoints = <LatLng>[
      ...widget.contextData.viewportPoints,
      ...widget.controller.points,
    ];
    if (fitPoints.isEmpty) return;

    _lastAppliedViewportSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (fitPoints.length == 1) {
        _mapController.move(fitPoints.first, math.max(widget.initialZoom, 16));
        return;
      }
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(fitPoints),
          padding: const EdgeInsets.all(42),
        ),
      );
    });
  }

  Widget _buildLabeledMarker({
    required Key key,
    required IconData icon,
    required Color color,
    required String label,
    VoidCallback? onTap,
  }) {
    final child = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: color, size: 28),
        if (label.trim().isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
          ),
      ],
    );

    if (onTap == null) {
      return SizedBox(key: key, child: child);
    }

    return GestureDetector(
      key: key,
      onTap: onTap,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    _applyViewportIfNeeded();

    final polygons = <Polygon>[
      if (widget.contextData.boundaryPolygon.length >= 3)
        Polygon(
          points: widget.contextData.boundaryPolygon,
          color: widget.boundaryFillColor,
          borderColor: widget.boundaryBorderColor,
          borderStrokeWidth: 3,
        ),
      ...widget.contextData.areaPolygons
          .where((polygon) => polygon.length >= 3)
          .map(
            (polygon) => Polygon(
              points: polygon,
              color: widget.areaFillColor,
              borderColor: widget.areaBorderColor,
              borderStrokeWidth: 2,
            ),
          ),
      if (widget.controller.points.length >= 3)
        Polygon(
          points: widget.controller.points,
          color: widget.draftFillColor,
          borderColor: widget.draftBorderColor,
          borderStrokeWidth: 3,
        ),
    ];

    final markers = <Marker>[
      ...widget.contextData.devices.map(
        (device) => Marker(
          point: device.point,
          width: 90,
          height: 74,
          child: _buildLabeledMarker(
            key: ValueKey('polygon_device_marker_${device.id}'),
            icon: device.selected ? Icons.pets : Icons.pets_outlined,
            color:
                device.selected ? Colors.red.shade700 : Colors.brown.shade700,
            label: device.label,
            onTap: device.onTap,
          ),
        ),
      ),
      ...widget.contextData.gateways.map(
        (gateway) => Marker(
          point: gateway.point,
          width: 90,
          height: 74,
          child: _buildLabeledMarker(
            key: ValueKey('polygon_gateway_marker_${gateway.id}'),
            icon: Icons.wifi,
            color: Colors.blue.shade700,
            label: gateway.label,
            onTap: gateway.onTap,
          ),
        ),
      ),
      ...widget.controller.points.asMap().entries.map(
            (entry) => Marker(
              point: entry.value,
              width: 28,
              height: 28,
              child: GestureDetector(
                key: ValueKey('polygon_vertex_gesture_${entry.key}'),
                onTap: () => widget.controller.selectPoint(entry.key),
                onPanStart: (_) => _startDraggingPoint(entry.key),
                onPanUpdate: (details) =>
                    _updateDraggingPoint(entry.key, details.delta),
                onPanEnd: (_) => _endDraggingPoint(),
                onPanCancel: _cancelDraggingPoint,
                child: Container(
                  key: ValueKey(
                    'polygon_vertex_${entry.key}_${widget.controller.selectedPointIndex == entry.key ? 'selected' : 'idle'}',
                  ),
                  decoration: BoxDecoration(
                    color: widget.controller.selectedPointIndex == entry.key
                        ? widget.selectedVertexColor
                        : widget.vertexColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ),
          ),
    ];

    return FlutterMap(
      key: const Key('polygon_editing_map'),
      mapController: _mapController,
      options: MapOptions(
        initialCenter: widget.controller.points.isNotEmpty
            ? widget.controller.points.first
            : widget.fallbackCenter,
        initialZoom: widget.initialZoom,
        interactionOptions: InteractionOptions(
          flags: widget.controller.isDragging
              ? InteractiveFlag.all &
                  ~InteractiveFlag.drag &
                  ~InteractiveFlag.flingAnimation
              : InteractiveFlag.all,
        ),
        onPositionChanged: (position, hasGesture) {
          if (!hasGesture || _userPinnedViewport) return;
          setState(() => _userPinnedViewport = true);
        },
        onTap: (_, point) => _onMapTap(point),
      ),
      children: [
        if (widget.showBaseTiles)
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: ManualSettings.mapUserAgentPackageName,
          ),
        if (polygons.isNotEmpty) PolygonLayer(polygons: polygons),
        if (markers.isNotEmpty) MarkerLayer(markers: markers),
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
    );
  }
}
