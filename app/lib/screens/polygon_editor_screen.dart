import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math' as math;

import '../config/manual_settings.dart';
import '../utils/polygon_metrics.dart';
import '../utils/top_feedback.dart';

class PolygonEditorScreen extends StatefulWidget {
  const PolygonEditorScreen({
    super.key,
    required this.title,
    required this.initialPoints,
    required this.onSave,
    this.boundary = const [],
    this.maxPoints,
    this.onDelete,
    this.deleteLabel = 'Apagar',
  });

  final String title;
  final List<LatLng> initialPoints;
  final List<LatLng> boundary;
  final int? maxPoints;
  final Future<void> Function()? onDelete;
  final String deleteLabel;
  final Future<void> Function(List<List<double>> points) onSave;

  @override
  State<PolygonEditorScreen> createState() => _PolygonEditorScreenState();
}

class _PolygonEditorScreenState extends State<PolygonEditorScreen> {
  late final List<LatLng> _points = List<LatLng>.from(widget.initialPoints);
  final MapController _mapController = MapController();
  int? _selectedPointIndex;
  int? _draggingPointIndex;
  Offset? _dragScreenOffset;
  bool _saving = false;
  bool _deleting = false;

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

  int? _nearestEdgeIndex(LatLng p, List<LatLng> polygon) {
    if (polygon.length < 2) return null;
    var bestIndex = -1;
    var bestDist = double.maxFinite;
    for (var i = 0; i < polygon.length; i++) {
      final j = (i + 1) % polygon.length;
      final d = _distancePointToSegment(p, polygon[i], polygon[j]);
      if (d < bestDist) {
        bestDist = d;
        bestIndex = i;
      }
    }
    const threshold = 0.00045;
    return bestDist <= threshold ? bestIndex : null;
  }

  void _startDraggingPoint(int index) {
    final point = _points[index];
    final screen = _mapController.camera.latLngToScreenPoint(point);
    setState(() {
      _selectedPointIndex = index;
      _draggingPointIndex = index;
      _dragScreenOffset = Offset(screen.x, screen.y);
    });
  }

  void _updateDraggingPoint(int index, Offset delta) {
    if (_draggingPointIndex != index || _dragScreenOffset == null) return;
    final nextOffset = Offset(
      _dragScreenOffset!.dx + delta.dx,
      _dragScreenOffset!.dy + delta.dy,
    );
    final nextPoint = _mapController.camera.offsetToCrs(nextOffset);
    final mustStayInside = widget.boundary.length >= 3;
    if (mustStayInside && !_isInsidePolygon(nextPoint, widget.boundary)) {
      return;
    }

    setState(() {
      _dragScreenOffset = nextOffset;
      _points[index] = nextPoint;
    });
  }

  void _endDraggingPoint() {
    setState(() {
      _draggingPointIndex = null;
      _dragScreenOffset = null;
    });
  }

  Future<void> _save() async {
    if (_saving || _deleting) return;
    if (_points.length < 3) {
      AppFeedback.error('O poligono precisa de pelo menos 3 pontos.');
      return;
    }
    if (widget.maxPoints != null && _points.length > widget.maxPoints!) {
      AppFeedback.error('Permitido apenas ${widget.maxPoints} pontos.');
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onSave(
        _points.map((p) => [p.latitude, p.longitude]).toList(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      AppFeedback.error('Erro ao salvar poligono: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final onDelete = widget.onDelete;
    if (onDelete == null || _saving || _deleting) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirmar exclusao'),
        content: Text('Deseja realmente ${widget.deleteLabel.toLowerCase()}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _deleting = true);
    try {
      await onDelete();
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      AppFeedback.error('Erro ao apagar: $e');
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  void _onMapTap(LatLng p) {
    final mustStayInside = widget.boundary.length >= 3;
    if (mustStayInside && !_isInsidePolygon(p, widget.boundary)) {
      AppFeedback.error('Ponto fora do limite permitido.');
      return;
    }

    if (_selectedPointIndex != null) {
      setState(() {
        _points[_selectedPointIndex!] = p;
        _selectedPointIndex = null;
      });
      return;
    }

    final edge = _nearestEdgeIndex(p, _points);
    if (edge != null) {
      if (widget.maxPoints != null && _points.length >= widget.maxPoints!) {
        AppFeedback.error('Permitido apenas ${widget.maxPoints} pontos.');
        return;
      }
      setState(() => _points.insert(edge + 1, p));
      return;
    }

    AppFeedback.warning(
      'Toque em um ponto para mover, ou no perimetro para inserir.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final fitPoints = [
      ...widget.boundary,
      ..._points,
    ];
    final fit = fitPoints.length >= 2
        ? CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(fitPoints),
            padding: const EdgeInsets.all(40),
          )
        : null;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Colors.green.withValues(alpha: 0.08),
            child: const Text(
              'Toque no ponto vermelho e arraste para mover. '
              'Toque no perimetro para inserir novo ponto.',
            ),
          ),
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter:
                    _points.isNotEmpty ? _points.first : const LatLng(-23, -46),
                initialZoom: 15,
                initialCameraFit: fit,
                interactionOptions: InteractionOptions(
                  flags: _draggingPointIndex == null
                      ? InteractiveFlag.all
                      : InteractiveFlag.all &
                          ~InteractiveFlag.drag &
                          ~InteractiveFlag.flingAnimation,
                ),
                onTap: (_, p) => _onMapTap(p),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                  userAgentPackageName: ManualSettings.mapUserAgentPackageName,
                ),
                PolygonLayer(
                  polygons: [
                    if (widget.boundary.length >= 3)
                      Polygon(
                        points: widget.boundary,
                        color: Colors.orange.withValues(alpha: 0.18),
                        borderColor: Colors.orange.shade700,
                        borderStrokeWidth: 3,
                      ),
                    if (_points.length >= 3)
                      Polygon(
                        points: _points,
                        color: Colors.teal.withValues(alpha: 0.25),
                        borderColor: Colors.teal,
                        borderStrokeWidth: 3,
                      ),
                  ],
                ),
                MarkerLayer(
                  markers: _points
                      .asMap()
                      .entries
                      .map(
                        (entry) => Marker(
                          point: entry.value,
                          width: 24,
                          height: 24,
                          child: GestureDetector(
                            onTap: () =>
                                setState(() => _selectedPointIndex = entry.key),
                            onPanStart: (_) => _startDraggingPoint(entry.key),
                            onPanUpdate: (details) =>
                                _updateDraggingPoint(entry.key, details.delta),
                            onPanEnd: (_) => _endDraggingPoint(),
                            onPanCancel: _endDraggingPoint,
                            child: Container(
                              decoration: BoxDecoration(
                                color: _selectedPointIndex == entry.key
                                    ? Colors.red
                                    : Colors.teal.shade700,
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: Colors.white, width: 2),
                              ),
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
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            color: Colors.green.withValues(alpha: 0.08),
            child: Text(
              'Area da edicao: ${PolygonMetrics.areaTextInline(_points)}'
              '${widget.maxPoints == null ? '' : ' | Pontos: ${_points.length}/${widget.maxPoints}'}',
              textAlign: TextAlign.center,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                if (widget.onDelete != null) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving || _deleting ? null : _delete,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                      ),
                      child: _deleting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(widget.deleteLabel),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: OutlinedButton(
                    onPressed: _points.isEmpty || _saving || _deleting
                        ? null
                        : () => setState(() => _points.removeLast()),
                    child: const Text('Desfazer'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _saving || _deleting ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Salvar'),
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
