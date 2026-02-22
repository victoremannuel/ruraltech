import 'package:cloud_firestore/cloud_firestore.dart';

class DeviceModel {
  final String id;
  final String? deviceId;
  final String name;
  final String status;
  final double? lat;
  final double? lon;
  final String? ownerUid;
  final String? propertyId;
  final bool wifiOtaEnabled;

  DeviceModel({
    required this.id,
    this.deviceId,
    required this.name,
    required this.status,
    this.lat,
    this.lon,
    this.ownerUid,
    this.propertyId,
    this.wifiOtaEnabled = true,
  });

  String get networkId {
    final v = deviceId?.trim();
    if (v == null || v.isEmpty) return id;
    return v;
  }

  factory DeviceModel.fromMap(String id, Map<String, dynamic> m) => DeviceModel(
        id: id,
        deviceId: (() {
          final d = m['deviceId'];
          if (d == null) return null;
          final raw = d.toString().trim();
          return raw.isEmpty ? null : raw;
        })(),
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
        ownerUid: (() {
          final owner = m['ownerUid'];
          if (owner is DocumentReference) return owner.id;
          if (owner is String) {
            final raw = owner.trim();
            if (raw.isEmpty) return null;
            if (!raw.contains('/')) return raw;
            final parts = raw.split('/').where((e) => e.isNotEmpty).toList();
            return parts.isEmpty ? raw : parts.last;
          }
          return null;
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
        wifiOtaEnabled: (() {
          final raw = m['wifi_ota_enabled'];
          if (raw is bool) return raw;
          return true;
        })(),
      );

  Map<String, dynamic> toMap() => {
        'deviceId': deviceId,
        'name': name,
        'status': status,
        'lat': lat,
        'lon': lon,
        'ownerUid': ownerUid,
        'propertyId': propertyId,
        'wifi_ota_enabled': wifiOtaEnabled,
      };
}
