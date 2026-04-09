import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:ruraltech_app/utils/polygon_log_preview.dart';

void main() {
  group('PolygonLogPreview', () {
    test('kind label maps supported polygon kinds', () {
      expect(polygonLogPreviewKindLabel('property'), 'Fazenda');
      expect(polygonLogPreviewKindLabel('area'), 'Piquete');
      expect(polygonLogPreviewKindLabel('herding'), 'Conducao');
      expect(polygonLogPreviewKindLabel('other'), 'Poligono');
    });

    test('builds svg with polygon, metadata and collar marker', () {
      final svg = buildPolygonLogPreviewSvg(
        PolygonLogPreviewData(
          polygonKind: 'area',
          originDocType: 'area',
          originDocId: 'area-9',
          eventReceivedAtMs:
              DateTime(2026, 4, 9, 10, 30).millisecondsSinceEpoch,
          polygonPoints: const <LatLng>[
            LatLng(-16.0, -49.0),
            LatLng(-16.1, -49.0),
            LatLng(-16.1, -49.1),
          ],
          collarPosition: const LatLng(-16.05, -49.03),
        ),
      );

      expect(svg, contains('<svg'));
      expect(svg, contains('<polygon'));
      expect(svg, contains('Piquete | area |'));
      expect(svg, contains('Pontos: 3'));
      expect(svg, contains('#C65102'));
    });
  });
}
