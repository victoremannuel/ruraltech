import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

import '../models/device_model.dart';

class DeviceMapTelemetrySample {
  const DeviceMapTelemetrySample({
    required this.deviceId,
    required this.lat,
    required this.lon,
    required this.receivedAtMs,
    this.propertyId,
    this.gatewayId,
    this.source,
  });

  final String deviceId;
  final double lat;
  final double lon;
  final int receivedAtMs;
  final String? propertyId;
  final String? gatewayId;
  final String? source;

  LatLng get point => LatLng(lat, lon);
}

String normalizeMapRefId(dynamic value) {
  if (value is DocumentReference) return value.id;
  if (value is String) {
    final raw = value.trim();
    if (raw.isEmpty) return '';
    if (!raw.contains('/')) return raw;
    final parts = raw.split('/').where((entry) => entry.isNotEmpty).toList();
    return parts.isEmpty ? raw : parts.last;
  }
  if (value == null) return '';
  return value.toString().trim();
}

String normalizeMapNumericDeviceId(String? raw) {
  if (raw == null) return '';
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  final parsed = int.tryParse(trimmed);
  if (parsed == null || parsed <= 0) return '';
  return parsed.toString();
}

String sanitizeMapRtdbKey(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  return trimmed.replaceAll(RegExp(r'[.#$\[\]/]'), '_');
}

bool isValidMapCoordinatePair(double? lat, double? lon) {
  if (lat == null || lon == null) return false;
  if (!lat.isFinite || !lon.isFinite) return false;
  return lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180;
}

DeviceMapTelemetrySample? deviceMapTelemetrySampleFromDevice(
  DeviceModel device, {
  String source = 'firebase',
}) {
  final normalizedDeviceId = normalizeMapNumericDeviceId(
    device.loraDeviceId ?? device.deviceId ?? device.id,
  );
  if (normalizedDeviceId.isEmpty) return null;
  if (!isValidMapCoordinatePair(device.lat, device.lon)) return null;
  return DeviceMapTelemetrySample(
    deviceId: normalizedDeviceId,
    lat: device.lat!,
    lon: device.lon!,
    receivedAtMs:
        device.positionReceivedAtMs ?? device.telemetryReceivedAtMs ?? 0,
    propertyId: normalizeMapRefId(device.propertyId),
    gatewayId: normalizeMapRefId(device.gatewayId),
    source: source,
  );
}

bool shouldReplaceDeviceMapTelemetrySample(
  DeviceMapTelemetrySample? current,
  DeviceMapTelemetrySample candidate,
) {
  if (current == null) return true;
  return candidate.receivedAtMs > current.receivedAtMs;
}

bool didDeviceMapPointChange(
  DeviceMapTelemetrySample? previous,
  DeviceMapTelemetrySample? next,
) {
  if (identical(previous, next)) return false;
  if (previous == null || next == null) return previous != next;
  return previous.lat != next.lat || previous.lon != next.lon;
}

DeviceMapTelemetrySample? resolveLocalTelemetrySampleForDevice({
  required DeviceModel device,
  required List<DeviceModel> devices,
  required Map<String, DeviceMapTelemetrySample> localSamplesByDeviceId,
}) {
  final normalizedDeviceId = normalizeMapNumericDeviceId(
    device.loraDeviceId ?? device.deviceId ?? device.id,
  );
  if (normalizedDeviceId.isEmpty) return null;

  final localSample = localSamplesByDeviceId[normalizedDeviceId];
  if (localSample == null) return null;

  final candidates = devices.where((candidate) {
    final candidateId = normalizeMapNumericDeviceId(
      candidate.loraDeviceId ?? candidate.deviceId ?? candidate.id,
    );
    return candidateId == normalizedDeviceId;
  }).toList(growable: false);
  if (candidates.isEmpty) return null;

  if (candidates.length == 1) {
    return candidates.single.id == device.id ? localSample : null;
  }

  final gatewayId = normalizeMapRefId(localSample.gatewayId);
  if (gatewayId.isEmpty) return null;

  final gatewayMatches = candidates.where((candidate) {
    return normalizeMapRefId(candidate.gatewayId) == gatewayId;
  }).toList(growable: false);
  if (gatewayMatches.length != 1) return null;
  return gatewayMatches.single.id == device.id ? localSample : null;
}

DeviceMapTelemetrySample? resolvePreferredMapTelemetryForDevice({
  required DeviceModel device,
  required List<DeviceModel> devices,
  required Map<String, DeviceMapTelemetrySample> localSamplesByDeviceId,
}) {
  final persisted = deviceMapTelemetrySampleFromDevice(device);
  final local = resolveLocalTelemetrySampleForDevice(
    device: device,
    devices: devices,
    localSamplesByDeviceId: localSamplesByDeviceId,
  );
  if (persisted == null) return local;
  if (local == null) return persisted;
  if (local.receivedAtMs > persisted.receivedAtMs) return local;
  return persisted;
}

List<DeviceModel> mergeDevicesWithScopedLiveTelemetry({
  required List<DeviceModel> devices,
  required Map<String, Map<String, Map<String, dynamic>>> liveByPropertyId,
  required Map<String, Map<String, Map<String, dynamic>>> healthByPropertyId,
  required Map<String, Map<String, Map<String, dynamic>>> eventByPropertyId,
}) {
  return devices.map((device) {
    final propertyKey =
        sanitizeMapRtdbKey(normalizeMapRefId(device.propertyId));
    final deviceKey = sanitizeMapRtdbKey(device.networkId);
    final live =
        propertyKey.isEmpty ? null : liveByPropertyId[propertyKey]?[deviceKey];
    final health = propertyKey.isEmpty
        ? null
        : healthByPropertyId[propertyKey]?[deviceKey];
    final event =
        propertyKey.isEmpty ? null : eventByPropertyId[propertyKey]?[deviceKey];
    if (live == null && health == null && event == null) return device;

    final liveReceivedAtMs = live?['telemetryReceivedAtMs'] as int? ?? 0;
    final eventReceivedAtMs = event?['positionReceivedAtMs'] as int? ?? 0;
    final eventWins = event != null && eventReceivedAtMs > liveReceivedAtMs;
    final eventLat = event == null ? null : event['lat'];
    final eventLon = event == null ? null : event['lon'];
    final liveLat = live == null ? null : live['lat'];
    final liveLon = live == null ? null : live['lon'];
    final lat = eventWins
        ? eventLat ?? liveLat ?? device.lat
        : liveLat ?? eventLat ?? device.lat;
    final lon = eventWins
        ? eventLon ?? liveLon ?? device.lon
        : liveLon ?? eventLon ?? device.lon;
    final positionReceivedAtMs = eventWins
        ? eventReceivedAtMs
        : (liveReceivedAtMs > 0
            ? liveReceivedAtMs
            : eventReceivedAtMs > 0
                ? eventReceivedAtMs
                : device.positionReceivedAtMs ?? device.telemetryReceivedAtMs);
    return DeviceModel(
      id: device.id,
      deviceId: device.deviceId,
      name: device.name,
      status: device.status,
      lat: lat,
      lon: lon,
      ownerUid: device.ownerUid,
      propertyId: device.propertyId,
      gatewayId: device.gatewayId,
      wifiOtaEnabled: device.wifiOtaEnabled,
      telemetryReceivedAtMs: live?['telemetryReceivedAtMs'] as int? ??
          device.telemetryReceivedAtMs,
      positionReceivedAtMs: positionReceivedAtMs,
      healthReceivedAtMs:
          health?['healthReceivedAtMs'] as int? ?? device.healthReceivedAtMs,
      healthGpsDayKey:
          health?['healthGpsDayKey'] as int? ?? device.healthGpsDayKey,
      healthFlags: health?['healthFlags'] as int? ?? device.healthFlags,
      healthUptimeSec:
          health?['healthUptimeSec'] as int? ?? device.healthUptimeSec,
      healthTemperatureDeciC: health?['healthTemperatureDeciC'] as int? ??
          device.healthTemperatureDeciC,
      healthSatellites:
          health?['healthSatellites'] as int? ?? device.healthSatellites,
      healthHdopCenti:
          health?['healthHdopCenti'] as int? ?? device.healthHdopCenti,
      healthI2cDevices:
          health?['healthI2cDevices'] as int? ?? device.healthI2cDevices,
    );
  }).toList(growable: false);
}
