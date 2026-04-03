import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

@immutable
class PolygonEditSnapshot {
  const PolygonEditSnapshot._(this.points);

  factory PolygonEditSnapshot.fromPoints(List<LatLng> points) {
    return PolygonEditSnapshot._(
      List<LatLng>.unmodifiable(
        points.map((point) => LatLng(point.latitude, point.longitude)),
      ),
    );
  }

  final List<LatLng> points;
}

class PolygonEditSessionController extends ChangeNotifier {
  PolygonEditSessionController({
    List<LatLng> initialPoints = const <LatLng>[],
  })  : _initialSnapshot = PolygonEditSnapshot.fromPoints(initialPoints),
        _points = List<LatLng>.from(initialPoints);

  PolygonEditSnapshot _initialSnapshot;
  final List<LatLng> _points;
  final List<PolygonEditSnapshot> _history = <PolygonEditSnapshot>[];
  int? _selectedPointIndex;
  int? _draggingPointIndex;
  PolygonEditSnapshot? _dragBaseline;

  List<LatLng> get points => List<LatLng>.unmodifiable(_points);
  PolygonEditSnapshot get initialSnapshot => _initialSnapshot;
  int? get selectedPointIndex => _selectedPointIndex;
  int? get draggingPointIndex => _draggingPointIndex;
  bool get canUndo => _history.isNotEmpty;
  bool get isDragging => _draggingPointIndex != null;
  bool get startedFromEmpty => _initialSnapshot.points.isEmpty;

  bool get hasChanges => !_samePoints(_initialSnapshot.points, _points);

  void resetSession(List<LatLng> points) {
    final normalized = _clonePoints(points);
    final shouldNotify = !_samePoints(_points, normalized) ||
        _history.isNotEmpty ||
        _selectedPointIndex != null ||
        _draggingPointIndex != null ||
        !_samePoints(_initialSnapshot.points, normalized);

    _initialSnapshot = PolygonEditSnapshot.fromPoints(normalized);
    _history.clear();
    _points
      ..clear()
      ..addAll(normalized);
    _selectedPointIndex = null;
    _draggingPointIndex = null;
    _dragBaseline = null;

    if (shouldNotify) {
      notifyListeners();
    }
  }

  void selectPoint(int? index) {
    final normalizedIndex = _normalizeIndex(index);
    if (_selectedPointIndex == normalizedIndex) return;
    _selectedPointIndex = normalizedIndex;
    notifyListeners();
  }

  void clearSelection() => selectPoint(null);

  void addPoint(LatLng point) {
    final next = _clonePoints(_points)..add(point);
    _applyCommittedPoints(next, nextSelectedPointIndex: null);
  }

  void insertPoint(int index, LatLng point) {
    final safeIndex = index.clamp(0, _points.length);
    final next = _clonePoints(_points)..insert(safeIndex, point);
    _applyCommittedPoints(next, nextSelectedPointIndex: null);
  }

  void moveSelectedPoint(LatLng point) {
    final index = _normalizeIndex(_selectedPointIndex);
    if (index == null) return;
    movePoint(index, point, keepSelected: false);
  }

  void movePoint(
    int index,
    LatLng point, {
    bool keepSelected = false,
  }) {
    final safeIndex = _normalizeIndex(index);
    if (safeIndex == null) return;
    final next = _clonePoints(_points);
    next[safeIndex] = point;
    _applyCommittedPoints(
      next,
      nextSelectedPointIndex: keepSelected ? safeIndex : null,
    );
  }

  void replaceAllPoints(List<LatLng> points) {
    final next = _clonePoints(points);
    _applyCommittedPoints(next, nextSelectedPointIndex: null);
  }

  void clear() {
    if (_points.isEmpty) return;
    _applyCommittedPoints(const <LatLng>[], nextSelectedPointIndex: null);
  }

  void undo() {
    if (_history.isEmpty) return;
    final previous = _history.removeLast();
    _points
      ..clear()
      ..addAll(previous.points);
    _selectedPointIndex = null;
    _draggingPointIndex = null;
    _dragBaseline = null;
    notifyListeners();
  }

  void beginDragPoint(int index) {
    final safeIndex = _normalizeIndex(index);
    if (safeIndex == null) return;
    _draggingPointIndex = safeIndex;
    _dragBaseline = PolygonEditSnapshot.fromPoints(_points);
    final shouldNotify = _selectedPointIndex != safeIndex;
    _selectedPointIndex = safeIndex;
    if (shouldNotify) {
      notifyListeners();
    }
  }

  void previewDragPoint(LatLng point) {
    final index = _normalizeIndex(_draggingPointIndex);
    if (index == null) return;
    if (_points[index].latitude == point.latitude &&
        _points[index].longitude == point.longitude) {
      return;
    }
    _points[index] = point;
    notifyListeners();
  }

  void endDragPoint() {
    final draggingIndex = _normalizeIndex(_draggingPointIndex);
    final baseline = _dragBaseline;
    final changed = draggingIndex != null &&
        baseline != null &&
        !_samePoints(baseline.points, _points);

    if (changed) {
      _history.add(baseline);
    }

    final shouldNotify = _draggingPointIndex != null || changed;
    _draggingPointIndex = null;
    _dragBaseline = null;

    if (shouldNotify) {
      notifyListeners();
    }
  }

  void cancelDragPoint() {
    final baseline = _dragBaseline;
    final shouldNotify = _draggingPointIndex != null || baseline != null;
    if (baseline != null) {
      _points
        ..clear()
        ..addAll(baseline.points);
    }
    _draggingPointIndex = null;
    _dragBaseline = null;
    if (shouldNotify) {
      notifyListeners();
    }
  }

  void _applyCommittedPoints(
    List<LatLng> next, {
    required int? nextSelectedPointIndex,
  }) {
    if (_samePoints(_points, next) &&
        _selectedPointIndex == _normalizeIndex(nextSelectedPointIndex)) {
      return;
    }
    _history.add(PolygonEditSnapshot.fromPoints(_points));
    _points
      ..clear()
      ..addAll(next);
    _selectedPointIndex = _normalizeIndex(nextSelectedPointIndex);
    _draggingPointIndex = null;
    _dragBaseline = null;
    notifyListeners();
  }

  int? _normalizeIndex(int? index) {
    if (index == null) return null;
    if (index < 0 || index >= _points.length) return null;
    return index;
  }

  static List<LatLng> _clonePoints(List<LatLng> points) {
    return points
        .map((point) => LatLng(point.latitude, point.longitude))
        .toList();
  }

  static bool _samePoints(List<LatLng> a, List<LatLng> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].latitude != b[i].latitude || a[i].longitude != b[i].longitude) {
        return false;
      }
    }
    return true;
  }
}
