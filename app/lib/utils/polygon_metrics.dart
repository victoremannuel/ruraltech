import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

class PolygonLabelPlacement {
  const PolygonLabelPlacement({
    required this.anchor,
    required this.angleRadians,
  });

  final LatLng anchor;
  final double angleRadians;
}

class PolygonMetrics {
  static const double _earthRadiusMeters = 6378137.0;

  static double areaSquareMeters(List<LatLng> polygon) {
    if (polygon.length < 3) return 0;
    var sum = 0.0;
    for (var i = 0; i < polygon.length; i++) {
      final a = polygon[i];
      final b = polygon[(i + 1) % polygon.length];
      final lonA = _degToRad(a.longitude);
      final lonB = _degToRad(b.longitude);
      final latA = _degToRad(a.latitude);
      final latB = _degToRad(b.latitude);
      sum += (lonB - lonA) * (2 + math.sin(latA) + math.sin(latB));
    }
    return (sum.abs() * _earthRadiusMeters * _earthRadiusMeters) / 2.0;
  }

  static String areaTextInline(List<LatLng> polygon) {
    final areaM2 = areaSquareMeters(polygon);
    return '${_formatMeters(areaM2)} m² | ${_formatHectares(areaM2)} ha';
  }

  static String areaTextMultiline(List<LatLng> polygon) {
    final areaM2 = areaSquareMeters(polygon);
    return '${_formatMeters(areaM2)} m²\n${_formatHectares(areaM2)} ha';
  }

  static PolygonLabelPlacement labelPlacement(List<LatLng> polygon) {
    final c = centroid(polygon);
    if (polygon.length < 2) {
      return PolygonLabelPlacement(anchor: c, angleRadians: 0);
    }

    var bestIndex = 0;
    var bestMeters = -1.0;
    for (var i = 0; i < polygon.length; i++) {
      final j = (i + 1) % polygon.length;
      final edgeMeters = _haversineMeters(polygon[i], polygon[j]);
      if (edgeMeters > bestMeters) {
        bestMeters = edgeMeters;
        bestIndex = i;
      }
    }

    final a = polygon[bestIndex];
    final b = polygon[(bestIndex + 1) % polygon.length];
    final mid = LatLng(
      (a.latitude + b.latitude) / 2,
      (a.longitude + b.longitude) / 2,
    );
    final anchor = LatLng(
      mid.latitude + (c.latitude - mid.latitude) * 0.25,
      mid.longitude + (c.longitude - mid.longitude) * 0.25,
    );

    var angle = math.atan2(
      b.latitude - a.latitude,
      b.longitude - a.longitude,
    );
    if (angle > math.pi / 2) angle -= math.pi;
    if (angle < -math.pi / 2) angle += math.pi;

    return PolygonLabelPlacement(anchor: anchor, angleRadians: angle);
  }

  static LatLng centroid(List<LatLng> polygon) {
    if (polygon.isEmpty) return const LatLng(0, 0);
    var lat = 0.0;
    var lon = 0.0;
    for (final p in polygon) {
      lat += p.latitude;
      lon += p.longitude;
    }
    return LatLng(lat / polygon.length, lon / polygon.length);
  }

  static String _formatMeters(double areaM2) {
    return _formatLocalizedNumber(
      areaM2,
      decimals: areaM2 >= 100 ? 0 : 2,
    );
  }

  static String _formatHectares(double areaM2) {
    return _formatLocalizedNumber(areaM2 / 10000.0, decimals: 2);
  }

  static String _formatLocalizedNumber(
    double value, {
    required int decimals,
  }) {
    final negative = value.isNegative;
    final fixed = value.abs().toStringAsFixed(decimals);
    final parts = fixed.split('.');
    final integerPart = parts.first.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );
    if (decimals == 0) {
      return negative ? '-$integerPart' : integerPart;
    }
    final decimalPart =
        parts.length > 1 ? parts[1] : ''.padRight(decimals, '0');
    final formatted = '$integerPart,$decimalPart';
    return negative ? '-$formatted' : formatted;
  }

  static double _haversineMeters(LatLng a, LatLng b) {
    final dLat = _degToRad(b.latitude - a.latitude);
    final dLon = _degToRad(b.longitude - a.longitude);
    final lat1 = _degToRad(a.latitude);
    final lat2 = _degToRad(b.latitude);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
    return _earthRadiusMeters * c;
  }

  static double _degToRad(double value) => value * math.pi / 180.0;
}
