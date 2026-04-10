import '../utils/cloud_compat.dart';

class DeviceModel {
  static const int healthFlagWifiOtaEnabled = 1 << 0;
  static const int healthFlagOtaModeActive = 1 << 1;
  static const int healthFlagGpsUartReady = 1 << 2;
  static const int healthFlagGpsNmeaSeen = 1 << 3;
  static const int healthFlagGpsFixValid = 1 << 4;
  static const int healthFlagMpuReady = 1 << 5;
  static const int healthFlagMlxReady = 1 << 6;
  static const int healthFlagStorageReady = 1 << 7;
  static const int healthFlagLoRaReady = 1 << 8;
  static const int healthFlagLastLoRaTxOk = 1 << 9;
  static const int healthFlagFallbackSchedule = 1 << 10;

  final String id;
  final String? deviceId;
  final String name;
  final String status;
  final double? lat;
  final double? lon;
  final String? ownerUid;
  final String? propertyId;
  final String? gatewayId;
  final bool wifiOtaEnabled;
  final int? telemetryReceivedAtMs;
  final int? positionReceivedAtMs;
  final int? healthReceivedAtMs;
  final int? healthGpsDayKey;
  final int? healthFlags;
  final int? healthUptimeSec;
  final int? healthTemperatureDeciC;
  final int? healthSatellites;
  final int? healthHdopCenti;
  final int? healthI2cDevices;

  DeviceModel({
    required this.id,
    this.deviceId,
    required this.name,
    required this.status,
    this.lat,
    this.lon,
    this.ownerUid,
    this.propertyId,
    this.gatewayId,
    this.wifiOtaEnabled = true,
    this.telemetryReceivedAtMs,
    this.positionReceivedAtMs,
    this.healthReceivedAtMs,
    this.healthGpsDayKey,
    this.healthFlags,
    this.healthUptimeSec,
    this.healthTemperatureDeciC,
    this.healthSatellites,
    this.healthHdopCenti,
    this.healthI2cDevices,
  });

  String? get loraDeviceId {
    final preferred = deviceId?.trim();
    final candidate =
        (preferred == null || preferred.isEmpty) ? id.trim() : preferred;
    if (candidate.isEmpty) return null;
    final parsed = int.tryParse(candidate);
    if (parsed == null || parsed <= 0) return null;
    return parsed.toString();
  }

  String get networkId {
    final lora = loraDeviceId;
    if (lora != null) return lora;
    final v = deviceId?.trim();
    if (v == null || v.isEmpty) return id;
    return v;
  }

  bool get hasDailyHealth =>
      healthReceivedAtMs != null ||
      healthFlags != null ||
      healthGpsDayKey != null;

  bool _hasHealthFlag(int flag) => ((healthFlags ?? 0) & flag) != 0;

  bool get healthGpsUartReady => _hasHealthFlag(healthFlagGpsUartReady);
  bool get healthGpsNmeaSeen => _hasHealthFlag(healthFlagGpsNmeaSeen);
  bool get healthGpsFixValid => _hasHealthFlag(healthFlagGpsFixValid);
  bool get healthMpuReady => _hasHealthFlag(healthFlagMpuReady);
  bool get healthMlxReady => _hasHealthFlag(healthFlagMlxReady);
  bool get healthStorageReady => _hasHealthFlag(healthFlagStorageReady);
  bool get healthLoRaReady => _hasHealthFlag(healthFlagLoRaReady);
  bool get healthLastLoRaTxOk => _hasHealthFlag(healthFlagLastLoRaTxOk);
  bool get healthFallbackSchedule => _hasHealthFlag(healthFlagFallbackSchedule);

  DateTime? get healthReceivedAt {
    final ms = healthReceivedAtMs;
    if (ms == null || ms <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  DateTime? get telemetryReceivedAt {
    final ms = telemetryReceivedAtMs;
    if (ms == null || ms <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  DateTime? get positionReceivedAt {
    final ms = positionReceivedAtMs ?? telemetryReceivedAtMs;
    if (ms == null || ms <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  double? get healthTemperatureC {
    final deci = healthTemperatureDeciC;
    if (deci == null) return null;
    return deci / 10.0;
  }

  double? get healthHdop {
    final centi = healthHdopCenti;
    if (centi == null) return null;
    return centi / 100.0;
  }

  bool get isHealthOk {
    if (!hasDailyHealth) return false;
    return healthGpsUartReady &&
        healthGpsNmeaSeen &&
        healthMpuReady &&
        healthMlxReady &&
        healthStorageReady &&
        healthLoRaReady &&
        healthLastLoRaTxOk &&
        !healthFallbackSchedule;
  }

  String get healthSummary {
    if (!hasDailyHealth) return 'Sem relatorio diario';
    if (isHealthOk) return 'OK';
    return 'Atencao';
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
        gatewayId: (() {
          final gateway = m['gatewayId'];
          if (gateway is DocumentReference) return gateway.id;
          if (gateway is String) {
            final raw = gateway.trim();
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
        telemetryReceivedAtMs: (() {
          final raw = m['telemetryReceivedAtMs'];
          if (raw is int) return raw;
          if (raw is num) return raw.toInt();
          if (raw is String) return int.tryParse(raw.trim());
          return null;
        })(),
        positionReceivedAtMs: (() {
          final raw = m['positionReceivedAtMs'];
          if (raw is int) return raw;
          if (raw is num) return raw.toInt();
          if (raw is String) return int.tryParse(raw.trim());
          return null;
        })(),
        healthReceivedAtMs: (() {
          final raw = m['healthReceivedAtMs'];
          if (raw is int) return raw;
          if (raw is num) return raw.toInt();
          if (raw is String) return int.tryParse(raw.trim());
          return null;
        })(),
        healthGpsDayKey: (() {
          final raw = m['healthGpsDayKey'];
          if (raw is int) return raw;
          if (raw is num) return raw.toInt();
          if (raw is String) return int.tryParse(raw.trim());
          return null;
        })(),
        healthFlags: (() {
          final raw = m['healthFlags'];
          if (raw is int) return raw;
          if (raw is num) return raw.toInt();
          if (raw is String) return int.tryParse(raw.trim());
          return null;
        })(),
        healthUptimeSec: (() {
          final raw = m['healthUptimeSec'];
          if (raw is int) return raw;
          if (raw is num) return raw.toInt();
          if (raw is String) return int.tryParse(raw.trim());
          return null;
        })(),
        healthTemperatureDeciC: (() {
          final raw = m['healthTemperatureDeciC'];
          if (raw is int) return raw;
          if (raw is num) return raw.toInt();
          if (raw is String) return int.tryParse(raw.trim());
          return null;
        })(),
        healthSatellites: (() {
          final raw = m['healthSatellites'];
          if (raw is int) return raw;
          if (raw is num) return raw.toInt();
          if (raw is String) return int.tryParse(raw.trim());
          return null;
        })(),
        healthHdopCenti: (() {
          final raw = m['healthHdopCenti'];
          if (raw is int) return raw;
          if (raw is num) return raw.toInt();
          if (raw is String) return int.tryParse(raw.trim());
          return null;
        })(),
        healthI2cDevices: (() {
          final raw = m['healthI2cDevices'];
          if (raw is int) return raw;
          if (raw is num) return raw.toInt();
          if (raw is String) return int.tryParse(raw.trim());
          return null;
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
        'gatewayId': gatewayId,
        'wifi_ota_enabled': wifiOtaEnabled,
        'telemetryReceivedAtMs': telemetryReceivedAtMs,
        'positionReceivedAtMs': positionReceivedAtMs,
      };
}
