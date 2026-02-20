import 'package:cloud_firestore/cloud_firestore.dart';

class DeviceModel {
  final String id;
  final String name;
  final String status;
  final double? lat;
  final double? lon;
  final String? propertyId;

  DeviceModel({
    required this.id,
    required this.name,
    required this.status,
    this.lat,
    this.lon,
    this.propertyId,
  });

  factory DeviceModel.fromMap(String id, Map<String, dynamic> m) => DeviceModel(
        id: id,
        name: m['name'] ?? 'Coleira',
        status: m['status'] ?? 'unknown',
        lat: (() {
          final pos = m['position'];
          if (pos is GeoPoint) return pos.latitude;
          if (pos is List && pos.length >= 2 && pos[0] is num) {
            return (pos[0] as num).toDouble();
          }
          if (pos is List && pos.isNotEmpty && pos[0] is GeoPoint) {
            return (pos[0] as GeoPoint).latitude;
          }
          return (m['lat'] as num?)?.toDouble();
        })(),
        lon: (() {
          final pos = m['position'];
          if (pos is GeoPoint) return pos.longitude;
          if (pos is List && pos.length >= 2 && pos[1] is num) {
            return (pos[1] as num).toDouble();
          }
          if (pos is List && pos.isNotEmpty && pos[0] is GeoPoint) {
            return (pos[0] as GeoPoint).longitude;
          }
          return (m['lon'] as num?)?.toDouble();
        })(),
        propertyId: (() {
          final prop = m['propertyId'];
          if (prop is DocumentReference) return prop.id;
          if (prop is String) {
            final raw = prop.trim();
            if (raw.isEmpty) return null;
            if (!raw.contains('/')) return raw;
            final parts = raw.split('/').where((e) => e.isNotEmpty).toList();
            return parts.isEmpty ? raw : parts.last;
          }
          return null;
        })(),
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'status': status,
        'lat': lat,
        'lon': lon,
        'propertyId': propertyId,
      };
}
