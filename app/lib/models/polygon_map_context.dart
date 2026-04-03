import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

@immutable
class PolygonMapDeviceOverlay {
  const PolygonMapDeviceOverlay({
    required this.id,
    required this.label,
    required this.point,
    this.selected = false,
    this.onTap,
  });

  final String id;
  final String label;
  final LatLng point;
  final bool selected;
  final VoidCallback? onTap;
}

@immutable
class PolygonMapGatewayOverlay {
  const PolygonMapGatewayOverlay({
    required this.id,
    required this.label,
    required this.point,
    this.onTap,
  });

  final String id;
  final String label;
  final LatLng point;
  final VoidCallback? onTap;
}

@immutable
class PolygonMapContext {
  const PolygonMapContext({
    this.boundaryPolygon = const <LatLng>[],
    this.areaPolygons = const <List<LatLng>>[],
    this.devices = const <PolygonMapDeviceOverlay>[],
    this.gateways = const <PolygonMapGatewayOverlay>[],
  });

  final List<LatLng> boundaryPolygon;
  final List<List<LatLng>> areaPolygons;
  final List<PolygonMapDeviceOverlay> devices;
  final List<PolygonMapGatewayOverlay> gateways;

  Iterable<LatLng> get viewportPoints sync* {
    yield* boundaryPolygon;
    for (final polygon in areaPolygons) {
      yield* polygon;
    }
    for (final device in devices) {
      yield device.point;
    }
    for (final gateway in gateways) {
      yield gateway.point;
    }
  }
}
