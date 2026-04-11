import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:ruraltech_app/utils/map_coordinates.dart';

void main() {
  group('map coordinates', () {
    test('accepts valid pair from map payload', () {
      final point = tryMapLatLng({
        'lat': -15.78,
        'lon': -47.93,
      });

      expect(point, isA<LatLng>());
      expect(point!.latitude, -15.78);
      expect(point.longitude, -47.93);
    });

    test('rejects out of range coordinates', () {
      expect(tryMapLatLngFromPair(120, -47.93), isNull);
      expect(tryMapLatLngFromPair(-15.78, -190), isNull);
    });

    test('parses numeric strings and rejects invalid values', () {
      final valid = tryMapLatLngFromPair('-15.78', '-47.93');
      final invalid = tryMapLatLngFromPair('nan', '-47.93');

      expect(valid, isA<LatLng>());
      expect(invalid, isNull);
    });
  });
}
