import 'package:latlong2/latlong.dart';

double? parseMapCoordinate(dynamic value) {
  if (value is num) {
    final parsed = value.toDouble();
    return parsed.isFinite ? parsed : null;
  }
  if (value is String) {
    final parsed = double.tryParse(value.trim());
    if (parsed == null || !parsed.isFinite) return null;
    return parsed;
  }
  return null;
}

bool isValidMapLatLng(double? lat, double? lon) {
  if (lat == null || lon == null) return false;
  if (!lat.isFinite || !lon.isFinite) return false;
  return lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180;
}

LatLng? tryMapLatLngFromPair(dynamic latValue, dynamic lonValue) {
  final lat = parseMapCoordinate(latValue);
  final lon = parseMapCoordinate(lonValue);
  if (!isValidMapLatLng(lat, lon)) return null;
  return LatLng(lat!, lon!);
}

LatLng? tryMapLatLng(dynamic value) {
  if (value is List && value.length >= 2) {
    return tryMapLatLngFromPair(value[0], value[1]);
  }
  if (value is Map) {
    return tryMapLatLngFromPair(
      value['lat'] ?? value['latitude'],
      value['lng'] ?? value['lon'] ?? value['longitude'],
    );
  }
  return null;
}
