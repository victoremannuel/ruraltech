import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:ruraltech_app/utils/polygon_edit_session.dart';

void main() {
  const a = LatLng(-16.10, -49.10);
  const b = LatLng(-16.20, -49.20);
  const c = LatLng(-16.30, -49.30);
  const d = LatLng(-16.40, -49.40);
  const e = LatLng(-16.50, -49.50);

  group('PolygonEditSessionController', () {
    test('starts empty for creation and undo stops at session start', () {
      final controller = PolygonEditSessionController();

      expect(controller.points, isEmpty);
      expect(controller.canUndo, isFalse);
      expect(controller.startedFromEmpty, isTrue);

      controller.addPoint(a);
      controller.addPoint(b);

      expect(controller.points, <LatLng>[a, b]);
      expect(controller.canUndo, isTrue);

      controller.undo();
      expect(controller.points, <LatLng>[a]);

      controller.undo();
      expect(controller.points, isEmpty);
      expect(controller.canUndo, isFalse);

      controller.undo();
      expect(controller.points, isEmpty);
    });

    test('restores persisted snapshot on undo during edit', () {
      final controller = PolygonEditSessionController(
        initialPoints: const <LatLng>[a, b, c],
      );

      controller.selectPoint(1);
      controller.moveSelectedPoint(d);

      expect(controller.points, <LatLng>[a, d, c]);
      expect(controller.canUndo, isTrue);

      controller.undo();

      expect(controller.points, <LatLng>[a, b, c]);
      expect(controller.canUndo, isFalse);
    });

    test('tracks insert, clear and replaceAll as undoable session actions', () {
      final controller = PolygonEditSessionController(
        initialPoints: const <LatLng>[a, b, c],
      );

      controller.insertPoint(1, d);
      expect(controller.points, <LatLng>[a, d, b, c]);

      controller.clear();
      expect(controller.points, isEmpty);

      controller.replaceAllPoints(const <LatLng>[e, d, c]);
      expect(controller.points, <LatLng>[e, d, c]);

      controller.undo();
      expect(controller.points, isEmpty);

      controller.undo();
      expect(controller.points, <LatLng>[a, d, b, c]);

      controller.undo();
      expect(controller.points, <LatLng>[a, b, c]);
      expect(controller.canUndo, isFalse);
    });

    test('consolidates drag preview into a single undo step', () {
      final controller = PolygonEditSessionController(
        initialPoints: const <LatLng>[a, b, c],
      );

      controller.beginDragPoint(1);
      controller.previewDragPoint(d);
      controller.previewDragPoint(e);
      controller.endDragPoint();

      expect(controller.points, <LatLng>[a, e, c]);
      expect(controller.canUndo, isTrue);

      controller.undo();
      expect(controller.points, <LatLng>[a, b, c]);
      expect(controller.canUndo, isFalse);
    });

    test('resetSession clears history and establishes a new undo boundary', () {
      final controller = PolygonEditSessionController(
        initialPoints: const <LatLng>[a, b, c],
      );

      controller.movePoint(0, d);
      expect(controller.canUndo, isTrue);

      controller.resetSession(const <LatLng>[e, d, c]);
      expect(controller.points, <LatLng>[e, d, c]);
      expect(controller.canUndo, isFalse);

      controller.movePoint(2, a);
      expect(controller.points, <LatLng>[e, d, a]);

      controller.undo();
      expect(controller.points, <LatLng>[e, d, c]);
      expect(controller.canUndo, isFalse);
    });
  });
}
