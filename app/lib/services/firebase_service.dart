import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/manual_settings.dart';
import '../models/device_model.dart';
import '../models/herding_operation_model.dart';
import '../utils/legacy_firebase_compat.dart';
import '../utils/polygon_log_preview.dart';

class FirebaseService {
  FirebaseService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  static const String _supabaseUrl = ManualSettings.supabaseUrl;
  static const String _supabasePublishableKey =
      ManualSettings.supabasePublishableKey;

  final SupabaseClient _client;

  List<Map<String, double>> _encodeLatLonPoints(List<List<double>> points) {
    return points
        .where((p) => p.length >= 2)
        .map((p) => {'lat': p[0], 'lon': p[1]})
        .toList();
  }

  List<Map<String, dynamic>> _encodeHerdingPhases(
    List<List<List<double>>> phases,
  ) {
    return phases.asMap().entries.map((entry) {
      return {
        'phase': entry.key,
        'points': _encodeLatLonPoints(entry.value),
      };
    }).toList();
  }

  List<List<double>> _decodeLatLonPoints(dynamic points) {
    if (points is! List) return const [];
    final out = <List<double>>[];
    for (final raw in points) {
      double? lat;
      double? lon;
      if (raw is List && raw.length >= 2) {
        final pLat = raw[0];
        final pLon = raw[1];
        if (pLat is num && pLon is num) {
          lat = pLat.toDouble();
          lon = pLon.toDouble();
        }
      } else if (raw is Map) {
        final pLat = raw['lat'] ?? raw['latitude'];
        final pLon = raw['lon'] ?? raw['lng'] ?? raw['longitude'];
        if (pLat is num && pLon is num) {
          lat = pLat.toDouble();
          lon = pLon.toDouble();
        }
      }
      if (lat == null || lon == null) continue;
      if (lat < -90 || lat > 90 || lon < -180 || lon > 180) continue;
      out.add(<double>[lat, lon]);
    }
    return out;
  }

  List<List<List<double>>> _decodeHerdingPhases(dynamic phases) {
    if (phases is! List) return const [];
    final indexed = <MapEntry<int, List<List<double>>>>[];
    for (var i = 0; i < phases.length; i++) {
      final rawPhase = phases[i];
      if (rawPhase is Map) {
        final phaseIndex = rawPhase['phase'];
        final order = phaseIndex is num ? phaseIndex.toInt() : i;
        final points = _decodeLatLonPoints(rawPhase['points']);
        if (points.isNotEmpty) indexed.add(MapEntry(order, points));
        continue;
      }
      final points = _decodeLatLonPoints(rawPhase);
      if (points.isNotEmpty) indexed.add(MapEntry(i, points));
    }
    indexed.sort((a, b) => a.key.compareTo(b.key));
    return indexed.map((entry) => entry.value).toList();
  }

  String _idFromRefOrPath(dynamic value) {
    if (value is DocumentReference) return value.id;
    if (value is String) {
      final raw = value.trim();
      if (raw.isEmpty) return '';
      if (!raw.contains('/')) return raw;
      final parts = raw.split('/').where((e) => e.isNotEmpty).toList();
      return parts.isEmpty ? raw : parts.last;
    }
    if (value is Map) {
      if (value['id'] is String) return _idFromRefOrPath(value['id']);
      if (value['path'] is String) return _idFromRefOrPath(value['path']);
    }
    if (value == null) return '';
    return value.toString().trim();
  }

  String? _normalizeLoraDeviceId(dynamic value, {bool allowZero = false}) {
    final raw = _idFromRefOrPath(value);
    if (raw.isEmpty) return null;
    final parsed = int.tryParse(raw);
    if (parsed == null) return null;
    if (allowZero) {
      if (parsed < 0) return null;
    } else if (parsed <= 0) {
      return null;
    }
    return parsed.toString();
  }

  List<String> _normalizeLoraDeviceIds(dynamic raw) {
    if (raw is! Iterable) return const <String>[];
    return raw.map(_normalizeLoraDeviceId).whereType<String>().toSet().toList()
      ..sort();
  }

  String _normalizeText(dynamic value) => value?.toString().trim() ?? '';

  String _normalizeRoleValue(String value) {
    final raw = value.trim().toLowerCase();
    return raw.isEmpty ? 'user' : raw;
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  double? _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  DateTime? _toDateTime(dynamic value) {
    if (value is DateTime) return value;
    if (value is Timestamp) return value.toDate();
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value.trim())?.toLocal();
    }
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    return null;
  }

  Timestamp? _toTimestamp(dynamic value) {
    final dt = _toDateTime(value);
    if (dt == null) return null;
    return Timestamp.fromDate(dt);
  }

  Uri _supabaseFunctionUri(String functionName) {
    final normalizedName = functionName.trim();
    final base = _supabaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base/functions/v1/$normalizedName');
  }

  String _computePropertyScopeId(String propertyId) {
    final normalized = _idFromRefOrPath(propertyId).trim().toLowerCase();
    if (normalized.isEmpty) return '';
    return sha256
        .convert(utf8.encode(normalized))
        .toString()
        .substring(0, 16)
        .toUpperCase();
  }

  String _sanitizeCloudKey(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.replaceAll(RegExp(r'[.#$\[\]/]'), '_');
  }

  String? _normalizeWsHost(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return null;
    if (value.startsWith('ws://') || value.startsWith('wss://')) return value;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      final uri = Uri.tryParse(value);
      if (uri == null || uri.host.isEmpty) return null;
      return 'ws://${uri.host}:81';
    }
    if (value.contains('://')) return null;
    if (value.contains(':')) return 'ws://$value';
    return 'ws://$value:81';
  }

  Future<Map<String, dynamic>> _postSupabaseFunction(
    String functionName, {
    Map<String, dynamic>? body,
  }) async {
    final accessToken = _client.auth.currentSession?.accessToken;
    if (accessToken == null || accessToken.trim().isEmpty) {
      throw Exception('missing_supabase_access_token');
    }
    final response = await http.post(
      _supabaseFunctionUri(functionName),
      headers: <String, String>{
        'content-type': 'application/json',
        'apikey': _supabasePublishableKey,
        'authorization': 'Bearer $accessToken',
      },
      body: jsonEncode(body ?? const <String, dynamic>{}),
    );
    final decoded = response.body.trim().isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }
    throw Exception(decoded['reason'] ?? 'supabase_${response.statusCode}');
  }

  Map<String, dynamic> _ruralPropertyFromRow(Map<String, dynamic> row) {
    return {
      'id': _idFromRefOrPath(row['id']),
      'name': row['name'] ?? '',
      'points': row['points'] ?? const <dynamic>[],
      'ownerUid': _idFromRefOrPath(row['owner_uid']),
      'createdByUid': _idFromRefOrPath(row['created_by_uid']),
      'updatedByUid': _idFromRefOrPath(row['updated_by_uid']),
      'userUids': (row['user_uids'] as List?) ?? const <dynamic>[],
      'propertyScopeId': _normalizeText(row['property_scope_id']),
      'createdAt': _toTimestamp(row['created_at']),
      'updatedAt': _toTimestamp(row['updated_at']),
    };
  }

  Map<String, dynamic> _areaFromRow(Map<String, dynamic> row) {
    return {
      'id': _idFromRefOrPath(row['id']),
      'ownerUid': _idFromRefOrPath(row['owner_uid']),
      'propertyId': _idFromRefOrPath(row['property_id']),
      'userUids': (row['user_uids'] as List?) ?? const <dynamic>[],
      'perimeter': row['perimeter'] ?? const <dynamic>[],
      'linkedDeviceIds':
          (row['linked_device_ids'] as List?) ?? const <dynamic>[],
      'updatedByUid': _idFromRefOrPath(row['updated_by_uid']),
      'createdAt': _toTimestamp(row['created_at']),
      'updatedAt': _toTimestamp(row['updated_at']),
    };
  }

  Map<String, dynamic> _gatewayFromRow(Map<String, dynamic> row) {
    final position = row['position'];
    double? lat;
    double? lon;
    if (position is List && position.length >= 2) {
      lat = _toDouble(position[0]);
      lon = _toDouble(position[1]);
    } else if (position is Map) {
      lat = _toDouble(position['lat']);
      lon = _toDouble(position['lon'] ?? position['lng']);
    }
    return {
      'id': _idFromRefOrPath(row['id']),
      'gatewayId': _idFromRefOrPath(row['gateway_id']) == ''
          ? _idFromRefOrPath(row['id'])
          : _idFromRefOrPath(row['gateway_id']),
      'name': row['name'] ?? '',
      'status': row['status'] ?? 'offline',
      'host': row['host'],
      'lat': lat,
      'lon': lon,
      'position': position,
      'propertyId': _idFromRefOrPath(row['property_id']),
      'userUids': (row['user_uids'] as List?) ?? const <dynamic>[],
      'wifi_ota_enabled':
          row['wifi_ota_enabled'] is bool ? row['wifi_ota_enabled'] : true,
      'is_matrix': row['is_matrix'] == true,
      'isMatrix': row['is_matrix'] == true,
      'propertyScopeId': _normalizeText(row['property_scope_id']),
      'bindingReady': row['binding_ready'] == true,
      'supportsScopedLora': row['supports_scoped_lora'] == true,
      'runtimeStatus': row['runtime_status'] is Map
          ? row['runtime_status']
          : const <String, dynamic>{},
      'createdAt': _toTimestamp(row['created_at']),
      'updatedAt': _toTimestamp(row['updated_at']),
    };
  }

  Map<String, dynamic> _deviceMapFromRow(Map<String, dynamic> row) {
    return {
      'deviceId': _normalizeLoraDeviceId(row['device_id'] ?? row['id']),
      'name': row['name'] ?? 'Coleira',
      'status': row['status'] ?? 'unknown',
      'position': row['position'],
      'ownerUid': _idFromRefOrPath(row['owner_uid']),
      'propertyId': _idFromRefOrPath(row['property_id']),
      'gatewayId': _idFromRefOrPath(row['gateway_id']),
      'wifi_ota_enabled':
          row['wifi_ota_enabled'] is bool ? row['wifi_ota_enabled'] : true,
      'telemetryReceivedAtMs': _toInt(row['telemetry_received_at_ms']),
      'positionReceivedAtMs': _toInt(row['position_received_at_ms']),
      'healthReceivedAtMs': _toInt(row['health_received_at_ms']),
      'healthGpsDayKey': _toInt(row['health_gps_day_key']),
      'healthFlags': _toInt(row['health_flags']),
      'healthUptimeSec': _toInt(row['health_uptime_sec']),
      'healthTemperatureDeciC': _toInt(row['health_temperature_deci_c']),
      'healthSatellites': _toInt(row['health_satellites']),
      'healthHdopCenti': _toInt(row['health_hdop_centi']),
      'healthI2cDevices': _toInt(row['health_i2c_devices']),
      'propertyScopeId': _normalizeText(row['property_scope_id']),
      'bindingReady': row['binding_ready'] == true,
      'supportsScopedLora': row['supports_scoped_lora'] == true,
      'runtimeStatus': row['runtime_status'] is Map
          ? row['runtime_status']
          : const <String, dynamic>{},
    };
  }

  Map<String, dynamic> _herdingOperationFromRow(Map<String, dynamic> row) {
    return {
      'id': _idFromRefOrPath(row['id']),
      'propertyId': _idFromRefOrPath(row['property_id']),
      'ownerUid': _idFromRefOrPath(row['owner_uid']),
      'requestedByUid': _idFromRefOrPath(row['requested_by_uid']),
      'requestedByRole': row['requested_by_role'] ?? 'user',
      'status': row['status'] ?? 'submitted',
      'targetPolygon': row['target_polygon'] ?? const <dynamic>[],
      'selectedDeviceIds':
          (row['selected_device_ids'] as List?) ?? const <dynamic>[],
      'notifyUserIds': (row['notify_user_ids'] as List?) ?? const <dynamic>[],
      'deviceStatuses': row['device_statuses'] is Map
          ? row['device_statuses']
          : const <String, dynamic>{},
      'matrixGatewayId': _idFromRefOrPath(row['matrix_gateway_id']),
      'createdAreaId': _idFromRefOrPath(row['created_area_id']),
      'loraCommandId': _idFromRefOrPath(row['lora_command_id']),
      'clientFailureReason': row['client_failure_reason'],
      'propertyScopeId': _normalizeText(row['property_scope_id']),
      'createdAt': _toTimestamp(row['created_at']),
      'updatedAt': _toTimestamp(row['updated_at']),
    };
  }

  Map<String, dynamic> _eventFromRow(Map<String, dynamic> row) {
    final payload =
        row['payload'] is Map ? Map<String, dynamic>.from(row['payload']) : {};
    return {
      'id': _idFromRefOrPath(row['id']),
      'type': _normalizeText(row['type']).isEmpty
          ? _normalizeText(row['event_type'])
          : _normalizeText(row['type']),
      'eventType': _normalizeText(row['event_type']),
      'ownerUid': _idFromRefOrPath(row['owner_uid']),
      'propertyId': _idFromRefOrPath(row['property_id']),
      'deviceId': _idFromRefOrPath(row['device_id']),
      'gatewayId': _idFromRefOrPath(row['gateway_id']),
      'polygonKind': _normalizeText(row['polygon_kind']),
      'originDocType': _normalizeText(row['origin_doc_type']),
      'originDocId': _idFromRefOrPath(row['origin_doc_id']),
      'receivedAtMs': _toInt(row['received_at_ms']),
      'createdAt': _toTimestamp(row['created_at']),
      'raw': payload.isEmpty ? row : payload,
      ...payload,
    };
  }

  Map<String, dynamic> _propertyCommandFromRow(Map<String, dynamic> row) {
    final raw = row['raw'] is Map ? Map<String, dynamic>.from(row['raw']) : {};
    return {
      'id': _idFromRefOrPath(row['command_id']),
      'commandId': _idFromRefOrPath(row['command_id']),
      'command': row['command'],
      'status': row['status'],
      'propertyId': _idFromRefOrPath(row['property_id']),
      'propertyScopeId': _normalizeText(row['property_scope_id']),
      'matrixGatewayId': _idFromRefOrPath(row['matrix_gateway_id']),
      'requestedByUid': _idFromRefOrPath(row['requested_by_uid']),
      'requestedByRole': _normalizeText(row['requested_by_role']),
      'createdAtMs': _toInt(row['created_at_ms']),
      'updatedAtMs': _toInt(row['updated_at_ms']),
      'expiresAtMs': _toInt(row['expires_at_ms']),
      'polygonKind': _normalizeText(row['polygon_kind']),
      'originDocType': _normalizeText(row['origin_doc_type']),
      'originDocId': _idFromRefOrPath(row['origin_doc_id']),
      'targetDeviceIds':
          (row['target_device_ids'] as List?) ?? const <dynamic>[],
      'targetGatewayIds':
          (row['target_gateway_ids'] as List?) ?? const <dynamic>[],
      'deviceResults': row['device_results'] is Map
          ? row['device_results']
          : const <String, dynamic>{},
      'reason': row['reason'],
      'payload':
          row['payload'] is Map ? row['payload'] : const <String, dynamic>{},
      'raw': raw.isEmpty
          ? {
              'commandId': _idFromRefOrPath(row['command_id']),
              'status': row['status'],
              'command': row['command'],
              'propertyId': _idFromRefOrPath(row['property_id']),
            }
          : raw,
    };
  }

  Map<String, dynamic> _propertyCommandEventFromRow(Map<String, dynamic> row) {
    final raw = row['raw'] is Map ? Map<String, dynamic>.from(row['raw']) : {};
    return {
      'id': _normalizeText(row['event_id']),
      'commandId': _idFromRefOrPath(row['command_id']),
      'status': _normalizeText(row['status']),
      'deviceId': _idFromRefOrPath(row['device_id']),
      'receivedAtMs': _toInt(row['received_at_ms']),
      'raw': raw.isEmpty ? row : raw,
      ...raw,
    };
  }

  Map<String, dynamic> _propertyEventFromRow(Map<String, dynamic> row) {
    final payload =
        row['payload'] is Map ? Map<String, dynamic>.from(row['payload']) : {};
    return {
      'id': _normalizeText(row['event_id']),
      'eventId': _normalizeText(row['event_id']),
      'dayKey': _normalizeText(row['day_key']),
      'deviceId': _idFromRefOrPath(row['device_id']),
      'gatewayId': _idFromRefOrPath(row['gateway_id']),
      'eventType': _normalizeText(row['event_type']),
      'type': _normalizeText(payload['type'] ?? row['event_type']),
      'lat': _toDouble(row['lat']) ?? _toDouble(payload['lat']),
      'lon': _toDouble(row['lon']) ?? _toDouble(payload['lon']),
      'positionReceivedAtMs': _toInt(row['position_received_at_ms']) ??
          _toInt(payload['positionReceivedAtMs']),
      'receivedAtMs':
          _toInt(row['received_at_ms']) ?? _toInt(payload['receivedAtMs']),
      'raw': payload.isEmpty ? row : payload,
      ...payload,
    };
  }

  Stream<List<Map<String, dynamic>>> _streamMappedTable(
    String table,
    List<String> primaryKey,
    Map<String, dynamic> Function(Map<String, dynamic>) mapper,
  ) {
    return _client.from(table).stream(primaryKey: primaryKey).map(
          (rows) => rows
              .map((row) => mapper(Map<String, dynamic>.from(row)))
              .toList(growable: false),
        );
  }

  Future<String?> _resolveGatewayWsHostByGatewayId(String? gatewayId) async {
    final normalizedGatewayId = _idFromRefOrPath(gatewayId);
    if (normalizedGatewayId.isEmpty) return null;
    final gateway = await _client
        .from('gateways')
        .select('host')
        .eq('id', normalizedGatewayId)
        .maybeSingle();
    if (gateway == null) return null;
    return _normalizeWsHost(gateway['host']?.toString());
  }

  Future<String?> resolveGatewayWsHostForDevice({
    required String deviceId,
    String? fallbackGatewayId,
  }) async {
    final fromFallback =
        await _resolveGatewayWsHostByGatewayId(fallbackGatewayId);
    if (fromFallback != null) return fromFallback;
    final normalizedDeviceId = _normalizeLoraDeviceId(deviceId);
    final candidateIds = <String>{
      _idFromRefOrPath(deviceId),
      if (normalizedDeviceId != null) normalizedDeviceId,
    }.where((id) => id.isNotEmpty);
    for (final docId in candidateIds) {
      final collar = await _client
          .from('collars')
          .select('gateway_id')
          .eq('id', docId)
          .maybeSingle();
      if (collar == null) continue;
      final wsHost =
          await _resolveGatewayWsHostByGatewayId(collar['gateway_id']);
      if (wsHost != null) return wsHost;
    }
    if (normalizedDeviceId != null) {
      final byDeviceId = await _client
          .from('collars')
          .select('gateway_id')
          .eq('device_id', normalizedDeviceId)
          .limit(1);
      final rows = (byDeviceId as List?) ?? const [];
      if (rows.isNotEmpty) {
        final wsHost =
            await _resolveGatewayWsHostByGatewayId(rows.first['gateway_id']);
        if (wsHost != null) return wsHost;
      }
    }
    return null;
  }

  Future<String?> resolveMatrixGatewayIdForProperty({
    required String propertyId,
  }) async {
    final normalizedPropertyId = _idFromRefOrPath(propertyId);
    if (normalizedPropertyId.isEmpty) return null;
    final rows = await _client
        .from('gateways')
        .select('id')
        .eq('property_id', normalizedPropertyId)
        .eq('is_matrix', true);
    final gateways = (rows as List?) ?? const [];
    if (gateways.isEmpty) return null;
    final ids = gateways
        .map((row) => _idFromRefOrPath(row['id']))
        .where((id) => id.isNotEmpty)
        .toList()
      ..sort();
    return ids.isEmpty ? null : ids.first;
  }

  Future<String?> resolveMatrixGatewayWsHost({
    required String propertyId,
  }) async {
    final matrixGatewayId =
        await resolveMatrixGatewayIdForProperty(propertyId: propertyId);
    if (matrixGatewayId == null || matrixGatewayId.isEmpty) return null;
    return _resolveGatewayWsHostByGatewayId(matrixGatewayId);
  }

  Future<Map<String, dynamic>?> _loadProperty(String propertyId) async {
    final row = await _client
        .from('rural_properties')
        .select('*')
        .eq('id', _idFromRefOrPath(propertyId))
        .maybeSingle();
    if (row == null) return null;
    return Map<String, dynamic>.from(row);
  }

  Future<Map<String, dynamic>> getScopedCommandReadiness({
    required String propertyId,
    required List<String> targetDeviceIds,
    List<String> targetGatewayIds = const [],
    String? matrixGatewayId,
  }) async {
    final normalizedPropertyId = _idFromRefOrPath(propertyId);
    if (normalizedPropertyId.isEmpty) {
      return {'ok': false, 'reason': 'invalid_property_id'};
    }
    final propertyData = await _loadProperty(normalizedPropertyId);
    if (propertyData == null) {
      return {'ok': false, 'reason': 'property_not_found'};
    }
    final propertyScopeId =
        _normalizeText(propertyData['property_scope_id']).toUpperCase();
    if (propertyScopeId.isEmpty) {
      return {'ok': false, 'reason': 'property_scope_not_ready'};
    }

    final resolvedMatrixGatewayId = _idFromRefOrPath(matrixGatewayId).isNotEmpty
        ? _idFromRefOrPath(matrixGatewayId)
        : await resolveMatrixGatewayIdForProperty(
            propertyId: normalizedPropertyId);
    if (resolvedMatrixGatewayId == null || resolvedMatrixGatewayId.isEmpty) {
      return {'ok': false, 'reason': 'no_matrix_for_property'};
    }

    final matrix = await _client
        .from('gateways')
        .select('*')
        .eq('id', resolvedMatrixGatewayId)
        .maybeSingle();
    if (matrix == null) {
      return {'ok': false, 'reason': 'matrix_not_found'};
    }
    final matrixData = Map<String, dynamic>.from(matrix);
    if (matrixData['is_matrix'] != true ||
        _idFromRefOrPath(matrixData['property_id']) != normalizedPropertyId ||
        matrixData['binding_ready'] != true ||
        matrixData['supports_scoped_lora'] != true ||
        _normalizeText(matrixData['property_scope_id']).toUpperCase() !=
            propertyScopeId) {
      return {'ok': false, 'reason': 'matrix_not_ready'};
    }

    final normalizedDeviceIds = targetDeviceIds
        .map(_normalizeLoraDeviceId)
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();
    final normalizedGatewayIds = targetGatewayIds
        .map(_idFromRefOrPath)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    if (normalizedDeviceIds.isEmpty && normalizedGatewayIds.isEmpty) {
      return {'ok': false, 'reason': 'no_targets'};
    }

    for (final deviceId in normalizedDeviceIds) {
      final collar = await _client
          .from('collars')
          .select(
              'property_id, binding_ready, supports_scoped_lora, property_scope_id')
          .eq('id', deviceId)
          .maybeSingle();
      if (collar == null) {
        return {'ok': false, 'reason': 'unknown_target_device:$deviceId'};
      }
      if (_idFromRefOrPath(collar['property_id']) != normalizedPropertyId) {
        return {
          'ok': false,
          'reason': 'target_device_property_mismatch:$deviceId',
        };
      }
      if (collar['binding_ready'] != true ||
          collar['supports_scoped_lora'] != true ||
          _normalizeText(collar['property_scope_id']).toUpperCase() !=
              propertyScopeId) {
        return {'ok': false, 'reason': 'target_device_not_ready:$deviceId'};
      }
    }

    for (final gatewayId in normalizedGatewayIds) {
      final gateway = await _client
          .from('gateways')
          .select(
              'property_id, binding_ready, supports_scoped_lora, property_scope_id')
          .eq('id', gatewayId)
          .maybeSingle();
      if (gateway == null) {
        return {'ok': false, 'reason': 'unknown_target_gateway:$gatewayId'};
      }
      if (_idFromRefOrPath(gateway['property_id']) != normalizedPropertyId) {
        return {
          'ok': false,
          'reason': 'target_gateway_property_mismatch:$gatewayId',
        };
      }
      if (gateway['binding_ready'] != true ||
          gateway['supports_scoped_lora'] != true ||
          _normalizeText(gateway['property_scope_id']).toUpperCase() !=
              propertyScopeId) {
        return {'ok': false, 'reason': 'target_gateway_not_ready:$gatewayId'};
      }
    }

    return {
      'ok': true,
      'reason': null,
      'propertyId': normalizedPropertyId,
      'propertyScopeId': propertyScopeId,
      'matrixGatewayId': resolvedMatrixGatewayId,
      'matrixRuntimeId': _sanitizeCloudKey(resolvedMatrixGatewayId),
      'targetDeviceIds': normalizedDeviceIds,
      'targetGatewayIds': normalizedGatewayIds,
    };
  }

  Future<String> enqueueScopedCommand({
    required String command,
    required String propertyId,
    required String requestedByUid,
    required String requestedByRole,
    required Map<String, dynamic> payload,
    List<String> targetDeviceIds = const [],
    List<String> targetGatewayIds = const [],
    String? matrixGatewayId,
    Map<String, dynamic>? businessRef,
    Duration? ttl,
  }) async {
    final normalizedCommand = command.trim().toUpperCase();
    final readiness = await getScopedCommandReadiness(
      propertyId: propertyId,
      targetDeviceIds: targetDeviceIds,
      targetGatewayIds: targetGatewayIds,
      matrixGatewayId: matrixGatewayId,
    );
    if (readiness['ok'] != true) {
      throw Exception(readiness['reason'] ?? 'command_not_ready');
    }
    final response = await _postSupabaseFunction(
      'queue-lora-command',
      body: <String, dynamic>{
        'command': normalizedCommand,
        'propertyId': readiness['propertyId'],
        'propertyScopeId': readiness['propertyScopeId'],
        'matrixGatewayId': readiness['matrixGatewayId'],
        'targetDeviceIds': readiness['targetDeviceIds'],
        'targetGatewayIds': readiness['targetGatewayIds'],
        'payload': payload,
        'requestedByRole': _normalizeRoleValue(requestedByRole),
        'requestedByUid': _idFromRefOrPath(requestedByUid),
        if (ttl != null) 'ttlMs': ttl.inMilliseconds,
        if (businessRef != null) 'businessRef': businessRef,
      },
    );
    final commandId = _idFromRefOrPath(response['commandId']);
    if (commandId.isEmpty) {
      throw Exception(response['reason'] ?? 'supabase_queue_failed');
    }
    return commandId;
  }

  Future<void> attachLoraCommandToHerdingOperation({
    required String operationId,
    required String loraCommandId,
  }) async {
    await _client.from('herding_operations').update({
      'lora_command_id': _idFromRefOrPath(loraCommandId),
    }).eq('id', _idFromRefOrPath(operationId));
  }

  Stream<Map<String, dynamic>?> streamCommandStatus({
    required String propertyId,
    required String commandId,
  }) {
    final normalizedPropertyId = _idFromRefOrPath(propertyId);
    final normalizedCommandId = _idFromRefOrPath(commandId);
    if (normalizedPropertyId.isEmpty || normalizedCommandId.isEmpty) {
      return Stream.value(null);
    }
    return _client
        .from('property_commands')
        .stream(primaryKey: ['property_id', 'command_id']).map((rows) {
      final filtered = rows.where((raw) {
        final row = Map<String, dynamic>.from(raw);
        return _idFromRefOrPath(row['property_id']) == normalizedPropertyId &&
            _idFromRefOrPath(row['command_id']) == normalizedCommandId;
      }).toList(growable: false);
      if (filtered.isEmpty) return null;
      return _propertyCommandFromRow(Map<String, dynamic>.from(filtered.first));
    });
  }

  Future<void> registerPushToken({
    required String uid,
    required String token,
    required String platform,
  }) async {
    final normalizedUid = _idFromRefOrPath(uid);
    final normalizedToken = token.trim();
    if (normalizedUid.isEmpty || normalizedToken.isEmpty) return;
    await _client.from('user_push_tokens').upsert({
      'legacy_uid': normalizedUid,
      'platform': platform,
      'token': normalizedToken,
      'metadata': const <String, dynamic>{},
    });
  }

  Future<Map<String, dynamic>> repairCloudState({
    bool apply = true,
    String? propertyId,
    String? gatewayId,
  }) {
    return _postSupabaseFunction(
      'admin-repair-cloud-state',
      body: <String, dynamic>{
        'apply': apply,
        if (propertyId != null && propertyId.trim().isNotEmpty)
          'propertyId': _idFromRefOrPath(propertyId),
        if (gatewayId != null && gatewayId.trim().isNotEmpty)
          'gatewayId': _idFromRefOrPath(gatewayId),
      },
    );
  }

  Future<List<String>> getLinkedUserIdsForProperty(String propertyId) async {
    final property = await _loadProperty(propertyId);
    if (property == null) return const <String>[];
    final ids = <String>{
      _idFromRefOrPath(property['owner_uid']),
      _idFromRefOrPath(property['created_by_uid']),
      ...((property['user_uids'] as List?) ?? const <dynamic>[])
          .map(_idFromRefOrPath),
    }.where((id) => id.isNotEmpty).toList()
      ..sort();
    return ids;
  }

  Future<Map<String, double>?> getLatestTelemetryPositionForDevice(
    String rawDeviceId,
  ) async {
    final normalizedDeviceId = _normalizeLoraDeviceId(rawDeviceId);
    if (normalizedDeviceId == null) return null;
    final collar = await _client
        .from('collars')
        .select('position')
        .eq('id', normalizedDeviceId)
        .maybeSingle();
    if (collar == null) return null;
    final position = collar['position'];
    if (position is List && position.length >= 2) {
      final lat = _toDouble(position[0]);
      final lon = _toDouble(position[1]);
      if (lat != null && lon != null) {
        return {'lat': lat, 'lon': lon};
      }
    }
    if (position is Map) {
      final lat = _toDouble(position['lat']);
      final lon = _toDouble(position['lon'] ?? position['lng']);
      if (lat != null && lon != null) {
        return {'lat': lat, 'lon': lon};
      }
    }
    return null;
  }

  Stream<Map<String, dynamic>?> streamLatestTelemetryEntryForDevice({
    required String propertyId,
    required String deviceId,
  }) {
    final normalizedPropertyId = _idFromRefOrPath(propertyId);
    final normalizedDeviceId = _normalizeLoraDeviceId(deviceId);
    if (normalizedPropertyId.isEmpty || normalizedDeviceId == null) {
      return Stream.value(null);
    }
    return _client
        .from('property_telemetry_latest')
        .stream(primaryKey: ['property_id', 'device_id']).map((rows) {
      final filtered = rows.where((raw) {
        final row = Map<String, dynamic>.from(raw);
        return _idFromRefOrPath(row['property_id']) == normalizedPropertyId &&
            _normalizeLoraDeviceId(row['device_id']) == normalizedDeviceId;
      }).toList(growable: false);
      if (filtered.isEmpty) return null;
      final row = Map<String, dynamic>.from(filtered.first);
      final payload = row['payload'] is Map
          ? Map<String, dynamic>.from(row['payload'])
          : {};
      return {
        'lat': _toDouble(row['lat']) ?? _toDouble(payload['lat']),
        'lon': _toDouble(row['lon']) ?? _toDouble(payload['lon']),
        'telemetryReceivedAtMs':
            _toInt(row['received_at_ms']) ?? _toInt(payload['receivedAtMs']),
      };
    });
  }

  Future<void> registerLiveTelemetry({
    required String deviceId,
    required double lat,
    required double lon,
    int? sourceTimestampSec,
    int? seq,
    String? gatewayId,
    String? gatewayRole,
    bool? gatewayWifiOtaEnabled,
    String sourceType = 'telemetry',
    String writer = 'app',
    int? receivedAtMs,
  }) async {}

  Future<void> registerDailyHealthReport({
    required String deviceId,
    required Map<String, dynamic> payload,
    int? sourceTimestampSec,
    int? seq,
    String? gatewayId,
    String? gatewayRole,
    bool? gatewayWifiOtaEnabled,
    String writer = 'app',
    int? receivedAtMs,
  }) async {}

  Future<void> cleanupTelemetryRetentionForDevices(
    Iterable<String> rawDeviceIds, {
    int? nowMs,
  }) async {}

  Stream<List<DeviceModel>> streamDevices({
    required String uid,
    required bool isAdmin,
  }) {
    return _streamMappedTable(
      'collars',
      const ['id'],
      _deviceMapFromRow,
    ).map(
      (rows) => rows
          .map((row) => DeviceModel.fromMap(
              _idFromRefOrPath(row['deviceId'] ?? row['id']), row))
          .toList(growable: false),
    );
  }

  Stream<List<Map<String, dynamic>>> streamGateways({
    required String uid,
    required bool isAdmin,
  }) {
    return _streamMappedTable(
      'gateways',
      const ['id'],
      _gatewayFromRow,
    );
  }

  Stream<Map<String, Map<String, double>>> streamPropertyTelemetry(
    String propertyId,
  ) {
    final normalizedPropertyId = _idFromRefOrPath(propertyId);
    if (normalizedPropertyId.isEmpty) {
      return Stream.value(const <String, Map<String, double>>{});
    }
    return _client
        .from('property_telemetry_latest')
        .stream(primaryKey: ['property_id', 'device_id'])
        .eq('property_id', normalizedPropertyId)
        .map((rows) {
          final out = <String, Map<String, double>>{};
          for (final raw in rows) {
            final row = Map<String, dynamic>.from(raw);
            final deviceId = _normalizeLoraDeviceId(row['device_id']);
            final lat = _toDouble(row['lat']);
            final lon = _toDouble(row['lon']);
            if (deviceId == null || lat == null || lon == null) continue;
            out[_sanitizeCloudKey(deviceId)] = {'lat': lat, 'lon': lon};
          }
          return out;
        });
  }

  Stream<Map<String, Map<String, dynamic>>> streamPropertyHealth(
    String propertyId,
  ) {
    final normalizedPropertyId = _idFromRefOrPath(propertyId);
    if (normalizedPropertyId.isEmpty) {
      return Stream.value(const <String, Map<String, dynamic>>{});
    }
    return _client
        .from('property_health_latest')
        .stream(primaryKey: ['property_id', 'device_id'])
        .eq('property_id', normalizedPropertyId)
        .map((rows) {
          final out = <String, Map<String, dynamic>>{};
          for (final raw in rows) {
            final row = Map<String, dynamic>.from(raw);
            final deviceId = _normalizeLoraDeviceId(row['device_id']);
            if (deviceId == null) continue;
            final payload = row['payload'] is Map
                ? Map<String, dynamic>.from(row['payload'])
                : {};
            out[_sanitizeCloudKey(deviceId)] = {
              'healthReceivedAtMs': _toInt(row['health_received_at_ms']) ??
                  _toInt(payload['receivedAtMs']),
              'healthGpsDayKey':
                  _toInt(payload['gpsDayKey'] ?? payload['healthGpsDayKey']),
              'healthFlags': _toInt(payload['healthFlags']),
              'healthUptimeSec':
                  _toInt(payload['uptimeSec'] ?? payload['healthUptimeSec']),
              'healthTemperatureDeciC': _toInt(
                payload['temperatureDeciC'] ??
                    payload['healthTemperatureDeciC'],
              ),
              'healthSatellites':
                  _toInt(payload['sat'] ?? payload['healthSatellites']),
              'healthHdopCenti':
                  _toInt(payload['hdopCenti'] ?? payload['healthHdopCenti']),
              'healthI2cDevices':
                  _toInt(payload['i2cDevices'] ?? payload['healthI2cDevices']),
            };
          }
          return out;
        });
  }

  Stream<List<Map<String, dynamic>>> streamPropertyEvents(
    String propertyId, {
    int limit = 200,
  }) {
    final normalizedPropertyId = _idFromRefOrPath(propertyId);
    if (normalizedPropertyId.isEmpty) {
      return Stream.value(const <Map<String, dynamic>>[]);
    }
    return _client
        .from('property_events')
        .stream(primaryKey: ['property_id', 'day_key', 'event_id'])
        .eq('property_id', normalizedPropertyId)
        .map((rows) {
          final items = rows
              .map((row) =>
                  _propertyEventFromRow(Map<String, dynamic>.from(row)))
              .toList()
            ..sort((a, b) => (_toInt(b['receivedAtMs']) ?? 0)
                .compareTo(_toInt(a['receivedAtMs']) ?? 0));
          if (items.length <= limit) return items;
          return items.take(limit).toList(growable: false);
        });
  }

  bool _commandEventMatchesDevice(
    Map<String, dynamic> row,
    String normalizedDeviceId,
  ) {
    final direct = _normalizeLoraDeviceId(row['deviceId']);
    if (direct == normalizedDeviceId) return true;
    final raw = row['raw'];
    if (raw is Map) {
      final payload = Map<String, dynamic>.from(raw);
      final targetDeviceIds = _normalizeLoraDeviceIds(
          payload['targetDeviceIds'] ?? payload['target_device_ids']);
      if (targetDeviceIds.contains(normalizedDeviceId)) return true;
      final deviceResults = payload['deviceResults'];
      if (deviceResults is Map &&
          deviceResults.containsKey(normalizedDeviceId)) {
        return true;
      }
    }
    return false;
  }

  List<Map<String, dynamic>> _mergeCollarLogItems({
    required String propertyId,
    required String normalizedDeviceId,
    Map<String, dynamic>? latestTelemetry,
    required List<Map<String, dynamic>> telemetryHistory,
    required List<Map<String, dynamic>> healthHistory,
    required List<Map<String, dynamic>> events,
    required List<Map<String, dynamic>> commandEvents,
  }) {
    final out = <Map<String, dynamic>>[];
    if (latestTelemetry != null) {
      out.add({
        'id': 'latest_$normalizedDeviceId',
        'kind': 'telemetry_latest',
        'type': 'telemetry',
        'deviceId': normalizedDeviceId,
        'lat': _toDouble(latestTelemetry['lat']),
        'lon': _toDouble(latestTelemetry['lon']),
        'receivedAtMs': _toInt(latestTelemetry['receivedAtMs']),
        'gatewayId': _normalizeText(latestTelemetry['gatewayId']),
        'gatewayRole': _normalizeText(latestTelemetry['gatewayRole']),
        'raw': latestTelemetry,
      });
    }
    for (final entry in telemetryHistory) {
      out.add({
        'id': entry['id'],
        'kind': 'telemetry_history',
        'type': 'telemetry',
        'deviceId': normalizedDeviceId,
        'lat': _toDouble(entry['lat']),
        'lon': _toDouble(entry['lon']),
        'receivedAtMs': _toInt(entry['receivedAtMs']),
        'gatewayId': _normalizeText(entry['gatewayId']),
        'gatewayRole': _normalizeText(entry['gatewayRole']),
        'raw': entry['raw'],
      });
    }
    for (final entry in healthHistory) {
      out.add({
        'id': entry['id'],
        'kind': 'health_history',
        'type': 'health_daily',
        'deviceId': normalizedDeviceId,
        'receivedAtMs': _toInt(entry['receivedAtMs']),
        'temperatureDeciC': _toInt(entry['temperatureDeciC']),
        'sat': _toInt(entry['sat']),
        'gatewayId': _normalizeText(entry['gatewayId']),
        'gatewayRole': _normalizeText(entry['gatewayRole']),
        'raw': entry['raw'],
      });
    }
    for (final entry in events) {
      out.add({
        ...entry,
        'kind': 'event',
        'raw': entry['raw'],
      });
    }
    for (final entry in commandEvents) {
      out.add({
        'id': entry['id'],
        'kind': 'command_event',
        'type': 'command_event',
        'cmdId': _idFromRefOrPath(entry['commandId']),
        'command': _normalizeText(entry['command']),
        'status': _normalizeText(entry['status']),
        'receivedAtMs': _toInt(entry['receivedAtMs']),
        'eventType': _normalizeText(entry['eventType']),
        'polygonKind': _normalizeText(entry['polygonKind']),
        'originDocType': _normalizeText(entry['originDocType']),
        'originDocId': _idFromRefOrPath(entry['originDocId']),
        'errorCode': _normalizeText(entry['errorCode']),
        'errorStage': _normalizeText(entry['errorStage']),
        'gatewayId': _normalizeText(entry['gatewayId']),
        'gatewayRole': _normalizeText(entry['gatewayRole']),
        'raw': entry['raw'],
      });
    }
    out.sort((a, b) => (_toInt(b['receivedAtMs']) ?? 0)
        .compareTo(_toInt(a['receivedAtMs']) ?? 0));
    return out;
  }

  Future<List<Map<String, dynamic>>> getCollarFirebaseLog({
    required String propertyId,
    required String deviceId,
  }) async {
    final normalizedPropertyId = _idFromRefOrPath(propertyId);
    final normalizedDeviceId = _normalizeLoraDeviceId(deviceId);
    if (normalizedPropertyId.isEmpty || normalizedDeviceId == null) {
      return const <Map<String, dynamic>>[];
    }

    final latest = await _client
        .from('property_telemetry_latest')
        .select('payload,lat,lon,received_at_ms')
        .eq('property_id', normalizedPropertyId)
        .eq('device_id', normalizedDeviceId)
        .maybeSingle();
    final telemetryRows = await _client
        .from('property_telemetry_history')
        .select('history_id,payload,lat,lon,received_at_ms')
        .eq('property_id', normalizedPropertyId)
        .eq('device_id', normalizedDeviceId);
    final healthRows = await _client
        .from('property_health_history')
        .select('history_id,payload,health_received_at_ms')
        .eq('property_id', normalizedPropertyId)
        .eq('device_id', normalizedDeviceId);
    final eventRows = await _client
        .from('property_events')
        .select('*')
        .eq('property_id', normalizedPropertyId)
        .eq('device_id', normalizedDeviceId);
    final commandEventRows = await _client
        .from('property_command_events')
        .select('*')
        .eq('property_id', normalizedPropertyId);

    final telemetry = ((telemetryRows as List?) ?? const []).map((raw) {
      final row = Map<String, dynamic>.from(raw);
      final payload = row['payload'] is Map
          ? Map<String, dynamic>.from(row['payload'])
          : {};
      return {
        'id': _normalizeText(row['history_id']),
        'lat': _toDouble(row['lat']) ?? _toDouble(payload['lat']),
        'lon': _toDouble(row['lon']) ?? _toDouble(payload['lon']),
        'receivedAtMs':
            _toInt(row['received_at_ms']) ?? _toInt(payload['receivedAtMs']),
        'gatewayId': _normalizeText(payload['gatewayId']),
        'gatewayRole': _normalizeText(payload['gatewayRole']),
        'raw': payload.isEmpty ? row : payload,
      };
    }).toList(growable: false);
    final health = ((healthRows as List?) ?? const []).map((raw) {
      final row = Map<String, dynamic>.from(raw);
      final payload = row['payload'] is Map
          ? Map<String, dynamic>.from(row['payload'])
          : {};
      return {
        'id': _normalizeText(row['history_id']),
        'receivedAtMs': _toInt(row['health_received_at_ms']) ??
            _toInt(payload['receivedAtMs']),
        'temperatureDeciC': _toInt(payload['temperatureDeciC']),
        'sat': _toInt(payload['sat']),
        'gatewayId': _normalizeText(payload['gatewayId']),
        'gatewayRole': _normalizeText(payload['gatewayRole']),
        'raw': payload.isEmpty ? row : payload,
      };
    }).toList(growable: false);
    final events = ((eventRows as List?) ?? const [])
        .map((raw) => _propertyEventFromRow(Map<String, dynamic>.from(raw)))
        .toList(growable: false);
    final commandEvents = ((commandEventRows as List?) ?? const [])
        .map((raw) =>
            _propertyCommandEventFromRow(Map<String, dynamic>.from(raw)))
        .where((row) => _commandEventMatchesDevice(row, normalizedDeviceId))
        .toList(growable: false);
    final latestPayload = latest == null
        ? null
        : <String, dynamic>{
            ...(latest['payload'] is Map
                ? Map<String, dynamic>.from(latest['payload'])
                : const <String, dynamic>{}),
            'lat': latest['lat'],
            'lon': latest['lon'],
            'receivedAtMs': latest['received_at_ms'],
          };

    return _mergeCollarLogItems(
      propertyId: normalizedPropertyId,
      normalizedDeviceId: normalizedDeviceId,
      latestTelemetry: latestPayload,
      telemetryHistory: telemetry,
      healthHistory: health,
      events: events,
      commandEvents: commandEvents,
    );
  }

  Stream<List<Map<String, dynamic>>> streamCollarFirebaseLog({
    required String propertyId,
    required String deviceId,
  }) {
    final normalizedPropertyId = _idFromRefOrPath(propertyId);
    final normalizedDeviceId = _normalizeLoraDeviceId(deviceId);
    if (normalizedPropertyId.isEmpty || normalizedDeviceId == null) {
      return Stream.value(const <Map<String, dynamic>>[]);
    }

    return Stream.multi((controller) {
      Map<String, dynamic>? latestTelemetry;
      List<Map<String, dynamic>> telemetryHistory = const [];
      List<Map<String, dynamic>> healthHistory = const [];
      List<Map<String, dynamic>> events = const [];
      List<Map<String, dynamic>> commandEvents = const [];

      void emit() {
        controller.add(
          _mergeCollarLogItems(
            propertyId: normalizedPropertyId,
            normalizedDeviceId: normalizedDeviceId,
            latestTelemetry: latestTelemetry,
            telemetryHistory: telemetryHistory,
            healthHistory: healthHistory,
            events: events,
            commandEvents: commandEvents,
          ),
        );
      }

      final latestSub = _client
          .from('property_telemetry_latest')
          .stream(primaryKey: ['property_id', 'device_id']).listen((rows) {
        final filtered = rows.where((raw) {
          final row = Map<String, dynamic>.from(raw);
          return _idFromRefOrPath(row['property_id']) == normalizedPropertyId &&
              _normalizeLoraDeviceId(row['device_id']) == normalizedDeviceId;
        }).toList(growable: false);
        if (filtered.isEmpty) {
          latestTelemetry = null;
        } else {
          final row = Map<String, dynamic>.from(filtered.first);
          final payload = row['payload'] is Map
              ? Map<String, dynamic>.from(row['payload'])
              : <String, dynamic>{};
          latestTelemetry = {
            ...payload,
            'lat': row['lat'],
            'lon': row['lon'],
            'receivedAtMs': row['received_at_ms'],
          };
        }
        emit();
      }, onError: controller.addError);

      final telemetrySub = _client.from('property_telemetry_history').stream(
          primaryKey: [
            'property_id',
            'device_id',
            'history_id'
          ]).listen((rows) {
        telemetryHistory = rows.where((raw) {
          final row = Map<String, dynamic>.from(raw);
          return _idFromRefOrPath(row['property_id']) == normalizedPropertyId &&
              _normalizeLoraDeviceId(row['device_id']) == normalizedDeviceId;
        }).map((raw) {
          final row = Map<String, dynamic>.from(raw);
          final payload = row['payload'] is Map
              ? Map<String, dynamic>.from(row['payload'])
              : <String, dynamic>{};
          return {
            'id': _normalizeText(row['history_id']),
            'lat': _toDouble(row['lat']) ?? _toDouble(payload['lat']),
            'lon': _toDouble(row['lon']) ?? _toDouble(payload['lon']),
            'receivedAtMs': _toInt(row['received_at_ms']) ??
                _toInt(payload['receivedAtMs']),
            'gatewayId': _normalizeText(payload['gatewayId']),
            'gatewayRole': _normalizeText(payload['gatewayRole']),
            'raw': payload.isEmpty ? row : payload,
          };
        }).toList(growable: false);
        emit();
      }, onError: controller.addError);

      final healthSub = _client.from('property_health_history').stream(
          primaryKey: [
            'property_id',
            'device_id',
            'history_id'
          ]).listen((rows) {
        healthHistory = rows.where((raw) {
          final row = Map<String, dynamic>.from(raw);
          return _idFromRefOrPath(row['property_id']) == normalizedPropertyId &&
              _normalizeLoraDeviceId(row['device_id']) == normalizedDeviceId;
        }).map((raw) {
          final row = Map<String, dynamic>.from(raw);
          final payload = row['payload'] is Map
              ? Map<String, dynamic>.from(row['payload'])
              : <String, dynamic>{};
          return {
            'id': _normalizeText(row['history_id']),
            'receivedAtMs': _toInt(row['health_received_at_ms']) ??
                _toInt(payload['receivedAtMs']),
            'temperatureDeciC': _toInt(payload['temperatureDeciC']),
            'sat': _toInt(payload['sat']),
            'gatewayId': _normalizeText(payload['gatewayId']),
            'gatewayRole': _normalizeText(payload['gatewayRole']),
            'raw': payload.isEmpty ? row : payload,
          };
        }).toList(growable: false);
        emit();
      }, onError: controller.addError);

      final eventSub = _client.from('property_events').stream(
          primaryKey: ['property_id', 'day_key', 'event_id']).listen((rows) {
        events = rows
            .where((raw) {
              final row = Map<String, dynamic>.from(raw);
              return _idFromRefOrPath(row['property_id']) ==
                      normalizedPropertyId &&
                  _normalizeLoraDeviceId(row['device_id']) ==
                      normalizedDeviceId;
            })
            .map((raw) => _propertyEventFromRow(Map<String, dynamic>.from(raw)))
            .toList(growable: false);
        emit();
      }, onError: controller.addError);

      final commandEventSub = _client.from('property_command_events').stream(
          primaryKey: ['property_id', 'day_key', 'event_id']).listen((rows) {
        commandEvents = rows
            .where((raw) {
              final row = Map<String, dynamic>.from(raw);
              return _idFromRefOrPath(row['property_id']) ==
                  normalizedPropertyId;
            })
            .map((raw) =>
                _propertyCommandEventFromRow(Map<String, dynamic>.from(raw)))
            .where((row) => _commandEventMatchesDevice(row, normalizedDeviceId))
            .toList(growable: false);
        emit();
      }, onError: controller.addError);

      controller.onCancel = () async {
        await latestSub.cancel();
        await telemetrySub.cancel();
        await healthSub.cancel();
        await eventSub.cancel();
        await commandEventSub.cancel();
      };
    });
  }

  List<LatLng> _latLngsFromPoints(dynamic rawPoints) {
    return _decodeLatLonPoints(rawPoints)
        .map((point) => LatLng(point[0], point[1]))
        .toList(growable: false);
  }

  LatLng? _positionFromDevice(DeviceModel device) {
    final lat = device.lat;
    final lon = device.lon;
    if (lat == null || lon == null) return null;
    if (!lat.isFinite || !lon.isFinite) return null;
    if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return null;
    return LatLng(lat, lon);
  }

  Future<PolygonLogPreviewResolution> resolvePolygonLogPreview({
    required String propertyId,
    required DeviceModel device,
    required Map<String, dynamic> entry,
  }) async {
    final status = _normalizeText(entry['status']).toLowerCase();
    if (_normalizeText(entry['eventType']).toLowerCase() !=
            'polygon_apply_result' ||
        status != 'success') {
      return const PolygonLogPreviewResolution.error(
        'Esse item do log nao possui preview de poligono disponivel.',
      );
    }
    final originDocType = _normalizeText(entry['originDocType']);
    final originDocId =
        _idFromRefOrPath(entry['originDocId'] ?? entry['operationId']);
    if (originDocType.isEmpty || originDocId.isEmpty) {
      return const PolygonLogPreviewResolution.error(
        'Nao foi possivel identificar o documento de origem do poligono.',
      );
    }

    List<LatLng> polygonPoints;
    switch (originDocType) {
      case 'ruralProperty':
      case 'rural_property':
        final row = await _client
            .from('rural_properties')
            .select('points')
            .eq('id', originDocId)
            .maybeSingle();
        if (row == null) {
          return const PolygonLogPreviewResolution.error(
            'A fazenda vinculada a esse evento nao existe mais no banco.',
          );
        }
        polygonPoints = _latLngsFromPoints(row['points']);
        break;
      case 'area':
        final row = await _client
            .from('areas')
            .select('perimeter')
            .eq('id', originDocId)
            .maybeSingle();
        if (row == null) {
          return const PolygonLogPreviewResolution.error(
            'O piquete vinculado a esse evento nao existe mais no banco.',
          );
        }
        polygonPoints = _latLngsFromPoints(row['perimeter']);
        break;
      case 'herdingOperation':
        final row = await _client
            .from('herding_operations')
            .select('target_polygon')
            .eq('id', originDocId)
            .maybeSingle();
        if (row == null) {
          return const PolygonLogPreviewResolution.error(
            'A conducao vinculada a esse evento nao existe mais no banco.',
          );
        }
        polygonPoints = _latLngsFromPoints(row['target_polygon']);
        break;
      default:
        return PolygonLogPreviewResolution.error(
          'Tipo de origem nao suportado para preview: $originDocType',
        );
    }

    if (polygonPoints.length < 3) {
      return const PolygonLogPreviewResolution.error(
        'O documento atual do poligono nao possui pontos suficientes para montar o mapa.',
      );
    }

    LatLng? collarPosition = _positionFromDevice(device);
    if (collarPosition == null) {
      final latest =
          await getLatestTelemetryPositionForDevice(device.networkId);
      if (latest != null) {
        collarPosition = LatLng(latest['lat']!, latest['lon']!);
      }
    }

    return PolygonLogPreviewResolution.success(
      PolygonLogPreviewData(
        polygonKind: _normalizeText(entry['polygonKind']),
        originDocType: originDocType,
        originDocId: originDocId,
        eventReceivedAtMs: _toInt(entry['receivedAtMs']),
        polygonPoints: polygonPoints,
        collarPosition: collarPosition,
      ),
    );
  }

  Stream<List<Map<String, dynamic>>> streamRuralProperties({
    required String uid,
    required bool isAdmin,
  }) {
    return _streamMappedTable(
      'rural_properties',
      const ['id'],
      _ruralPropertyFromRow,
    );
  }

  Stream<List<Map<String, dynamic>>> streamAreas({
    required String uid,
    required bool isAdmin,
  }) {
    return _streamMappedTable(
      'areas',
      const ['id'],
      _areaFromRow,
    );
  }

  Stream<List<Map<String, dynamic>>> streamCriticalEvents({
    required String uid,
    required bool isAdmin,
  }) {
    return _streamMappedTable(
      'events',
      const ['id'],
      _eventFromRow,
    ).map((items) {
      items.sort((a, b) => (_toInt(b['receivedAtMs']) ?? 0)
          .compareTo(_toInt(a['receivedAtMs']) ?? 0));
      return items;
    });
  }

  int _herdingOperationSortKeyMs(HerdingOperationModel value) {
    return value.updatedAt?.millisecondsSinceEpoch ??
        value.createdAt?.millisecondsSinceEpoch ??
        0;
  }

  Stream<List<HerdingOperationModel>> streamHerdingOperations({
    required String uid,
    required bool isAdmin,
  }) {
    return _client
        .from('herding_operations')
        .stream(primaryKey: ['id']).map((rows) {
      final operations = rows
          .map((row) => HerdingOperationModel.fromMap(
                _idFromRefOrPath(row['id']),
                _herdingOperationFromRow(Map<String, dynamic>.from(row)),
              ))
          .toList()
        ..sort((a, b) => _herdingOperationSortKeyMs(b)
            .compareTo(_herdingOperationSortKeyMs(a)));
      return operations;
    });
  }

  Stream<HerdingOperationModel?> streamHerdingOperation(String operationId) {
    final normalizedId = _idFromRefOrPath(operationId);
    if (normalizedId.isEmpty) return Stream.value(null);
    return _client
        .from('herding_operations')
        .stream(primaryKey: ['id'])
        .eq('id', normalizedId)
        .map((rows) {
          if (rows.isEmpty) return null;
          final row = Map<String, dynamic>.from(rows.first);
          return HerdingOperationModel.fromMap(
            normalizedId,
            _herdingOperationFromRow(row),
          );
        });
  }

  Future<List<Map<String, dynamic>>> getRuralProperties({
    required String uid,
    required bool isAdmin,
  }) async {
    final rows = await _client.from('rural_properties').select('*');
    return ((rows as List?) ?? const [])
        .map((row) => _ruralPropertyFromRow(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<Map<String, String>>> getUserOptions() async {
    final rows = await _client.from('profiles').select('legacy_uid,email');
    final users = ((rows as List?) ?? const [])
        .map((row) {
          final data = Map<String, dynamic>.from(row);
          final uid = _idFromRefOrPath(data['legacy_uid']);
          final email = _normalizeText(data['email']).toLowerCase();
          return <String, String>{
            'uid': uid,
            'email': email.isEmpty ? uid : email,
          };
        })
        .where((row) => row['uid']!.isNotEmpty)
        .toList();
    users.sort((a, b) => a['email']!.compareTo(b['email']!));
    return users;
  }

  Future<List<String>> _resolveUserIdsByEmailsStrict(
      List<String> emails) async {
    final normalized = emails
        .map((email) => email.trim().toLowerCase())
        .where((email) => email.isNotEmpty)
        .toSet();
    if (normalized.isEmpty) return const <String>[];
    final rows = await _client.from('profiles').select('legacy_uid,email');
    final found = <String, String>{};
    for (final raw in (rows as List?) ?? const []) {
      final row = Map<String, dynamic>.from(raw);
      final email = _normalizeText(row['email']).toLowerCase();
      final uid = _idFromRefOrPath(row['legacy_uid']);
      if (email.isEmpty || uid.isEmpty) continue;
      if (normalized.contains(email)) found[email] = uid;
    }
    final missing =
        normalized.where((email) => !found.containsKey(email)).toList();
    if (missing.isNotEmpty) {
      throw Exception(
        'Usuarios nao encontrados para os emails: ${missing.join(', ')}',
      );
    }
    return found.values.toSet().toList()..sort();
  }

  Future<List<String>> _adminUserIds() async {
    final rows = await _client
        .from('profiles')
        .select('legacy_uid')
        .inFilter('role', ['adm', 'admin']);
    return ((rows as List?) ?? const [])
        .map((row) => _idFromRefOrPath(row['legacy_uid']))
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  Future<void> addRuralProperty({
    required String name,
    required List<List<double>> points,
    required String creatorUid,
    required String ownerUid,
    required bool isAdmin,
    List<String> userEmails = const [],
  }) async {
    final normalizedOwnerUid = _idFromRefOrPath(ownerUid);
    if (normalizedOwnerUid.isEmpty) {
      throw Exception('Dono da propriedade invalido.');
    }
    final normalizedCreatorUid = _idFromRefOrPath(creatorUid);
    final propertyId = const Uuid().v4();
    final linkedUsers = <String>{
      normalizedOwnerUid,
      if (normalizedCreatorUid.isNotEmpty) normalizedCreatorUid,
      if (isAdmin) ...await _resolveUserIdsByEmailsStrict(userEmails),
      if (isAdmin) ...await _adminUserIds(),
    }.toList()
      ..sort();
    await _client.from('rural_properties').insert({
      'id': propertyId,
      'name': name,
      'points': _encodeLatLonPoints(points),
      'user_uids': linkedUsers,
      'owner_uid': normalizedOwnerUid,
      'created_by_uid': normalizedCreatorUid.isNotEmpty
          ? normalizedCreatorUid
          : normalizedOwnerUid,
      'updated_by_uid': normalizedCreatorUid.isNotEmpty
          ? normalizedCreatorUid
          : normalizedOwnerUid,
      'property_scope_id': _computePropertyScopeId(propertyId),
    });
    try {
      await repairCloudState(apply: true, propertyId: propertyId);
    } catch (_) {}
  }

  Future<void> updateRuralProperty({
    required String id,
    required String name,
    required List<List<double>> points,
    required String editorUid,
    required String ownerUid,
    required bool isAdmin,
    List<String> userEmails = const [],
  }) async {
    final normalizedId = _idFromRefOrPath(id);
    final normalizedOwnerUid = _idFromRefOrPath(ownerUid);
    final normalizedEditorUid = _idFromRefOrPath(editorUid);
    final update = <String, dynamic>{
      'name': name,
      'points': _encodeLatLonPoints(points),
      'owner_uid': normalizedOwnerUid,
      'created_by_uid': normalizedOwnerUid,
      'updated_by_uid': normalizedEditorUid.isNotEmpty
          ? normalizedEditorUid
          : normalizedOwnerUid,
      'property_scope_id': _computePropertyScopeId(normalizedId),
    };
    if (isAdmin) {
      update['user_uids'] = <String>{
        normalizedOwnerUid,
        if (normalizedEditorUid.isNotEmpty) normalizedEditorUid,
        ...await _resolveUserIdsByEmailsStrict(userEmails),
        ...await _adminUserIds(),
      }.toList()
        ..sort();
    }
    await _client
        .from('rural_properties')
        .update(update)
        .eq('id', normalizedId);
    try {
      await repairCloudState(apply: true, propertyId: normalizedId);
    } catch (_) {}
  }

  Future<void> addArea({
    required String ownerUid,
    required String ruralPropertyId,
    required List<List<double>> perimeter,
    String? updatedByUid,
    List<String> linkedDeviceIds = const <String>[],
  }) async {
    final linkedUsers = await getLinkedUserIdsForProperty(ruralPropertyId);
    await _client.from('areas').insert({
      'owner_uid': _idFromRefOrPath(ownerUid),
      'property_id': _idFromRefOrPath(ruralPropertyId),
      'user_uids': linkedUsers,
      'perimeter': _encodeLatLonPoints(perimeter),
      'linked_device_ids': _normalizeLoraDeviceIds(linkedDeviceIds),
      'updated_by_uid': _idFromRefOrPath(updatedByUid ?? ownerUid),
    });
  }

  Future<String> createHerdingOperation({
    required String ownerUid,
    required String requestedByUid,
    required String requestedByRole,
    required String propertyId,
    required List<List<double>> targetPolygon,
    required List<String> selectedDeviceIds,
    required List<String> notifyUserIds,
    required String matrixGatewayId,
  }) async {
    final normalizedOwnerUid = _idFromRefOrPath(ownerUid);
    final normalizedRequestedByUid = _idFromRefOrPath(requestedByUid);
    final normalizedPropertyId = _idFromRefOrPath(propertyId);
    final normalizedMatrixGatewayId = _idFromRefOrPath(matrixGatewayId);
    final normalizedDeviceIds = selectedDeviceIds
        .map(_normalizeLoraDeviceId)
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();
    final normalizedNotifyUserIds = notifyUserIds
        .followedBy([normalizedRequestedByUid, normalizedOwnerUid])
        .map(_idFromRefOrPath)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    if (normalizedDeviceIds.isEmpty) {
      throw Exception('Selecione ao menos uma coleira para o arrebanhamento.');
    }
    if (targetPolygon.length < 3) {
      throw Exception('Informe um poligono destino com ao menos 3 pontos.');
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final operationId = const Uuid().v4();
    final deviceStatuses = <String, Map<String, dynamic>>{};
    for (final deviceId in normalizedDeviceIds) {
      deviceStatuses[deviceId] = <String, dynamic>{
        'status': 'pending',
        'retryCount': 0,
        'updatedAtMs': nowMs,
      };
    }
    await _client.from('herding_operations').insert({
      'id': operationId,
      'property_id': normalizedPropertyId,
      'owner_uid': normalizedOwnerUid,
      'requested_by_uid': normalizedRequestedByUid,
      'requested_by_role': _normalizeRoleValue(requestedByRole),
      'status': herdingOperationStatusValue(HerdingOperationStatus.submitted),
      'target_polygon': _encodeLatLonPoints(targetPolygon),
      'selected_device_ids': normalizedDeviceIds,
      'notify_user_ids': normalizedNotifyUserIds,
      'device_statuses': deviceStatuses,
      'matrix_gateway_id': normalizedMatrixGatewayId,
      'property_scope_id': _computePropertyScopeId(normalizedPropertyId),
    });
    return operationId;
  }

  Future<void> markHerdingOperationSubmissionFailed({
    required String operationId,
    required String reason,
  }) async {
    await _client.from('herding_operations').update({
      'status': herdingOperationStatusValue(HerdingOperationStatus.failed),
      'client_failure_reason': reason,
    }).eq('id', _idFromRefOrPath(operationId));
  }

  Future<void> addDevice({
    required String ownerUid,
    required String name,
    required String status,
    double? lat,
    double? lon,
    String? deviceId,
    String? propertyId,
    String? gatewayId,
  }) async {
    final normalizedDeviceId = _normalizeLoraDeviceId(deviceId);
    if (normalizedDeviceId == null) {
      throw Exception(
        'ID LoRa da coleira invalido. Informe um valor numerico maior que zero.',
      );
    }
    final position = (lat != null && lon != null) ? [lat, lon] : null;
    await _client.from('collars').upsert({
      'id': normalizedDeviceId,
      'device_id': normalizedDeviceId,
      'owner_uid': _idFromRefOrPath(ownerUid),
      'name': name,
      'status': status,
      'position': position,
      'gateway_id': _idFromRefOrPath(gatewayId),
      'property_id': _idFromRefOrPath(propertyId),
      'wifi_ota_enabled': true,
    });
  }

  Future<void> addGateway({
    required String name,
    required String status,
    bool isMatrix = false,
    String? gatewayId,
    String? host,
    String? propertyId,
    double? lat,
    double? lon,
  }) async {
    final normalizedGatewayId = _idFromRefOrPath(gatewayId);
    final normalizedPropertyId = _idFromRefOrPath(propertyId);
    final linkedUsers = normalizedPropertyId.isEmpty
        ? const <String>[]
        : await getLinkedUserIdsForProperty(normalizedPropertyId);
    final payload = {
      'id':
          normalizedGatewayId.isEmpty ? const Uuid().v4() : normalizedGatewayId,
      'gateway_id': normalizedGatewayId.isEmpty ? null : normalizedGatewayId,
      'name': name,
      'status': status,
      'host': host,
      'property_id': normalizedPropertyId.isEmpty ? null : normalizedPropertyId,
      'user_uids': linkedUsers,
      'wifi_ota_enabled': true,
      'position': (lat != null && lon != null) ? [lat, lon] : null,
      'is_matrix': isMatrix,
    };
    await _client.from('gateways').upsert(payload);
  }

  Future<void> updateDevice({
    required String id,
    required String deviceId,
    required String name,
    required String status,
    required double lat,
    required double lon,
    required String ownerUid,
    String? propertyId,
    String? gatewayId,
    bool? wifiOtaEnabled,
  }) async {
    final normalizedDeviceId = _normalizeLoraDeviceId(deviceId);
    if (normalizedDeviceId == null) {
      throw Exception(
        'ID LoRa da coleira invalido. Informe um valor numerico maior que zero.',
      );
    }
    final update = <String, dynamic>{
      'device_id': normalizedDeviceId,
      'name': name,
      'status': status,
      'owner_uid': _idFromRefOrPath(ownerUid),
      'position': [lat, lon],
      'gateway_id': _idFromRefOrPath(gatewayId),
      'property_id': _idFromRefOrPath(propertyId).isEmpty
          ? null
          : _idFromRefOrPath(propertyId),
      if (wifiOtaEnabled != null) 'wifi_ota_enabled': wifiOtaEnabled,
    };
    await _client.from('collars').update(update).eq('id', _idFromRefOrPath(id));
  }

  Future<void> updateGateway({
    required String id,
    required String name,
    required String status,
    required double lat,
    required double lon,
    bool? isMatrix,
    String? host,
    String? propertyId,
    bool? wifiOtaEnabled,
  }) async {
    final normalizedPropertyId = _idFromRefOrPath(propertyId);
    final linkedUsers = normalizedPropertyId.isEmpty
        ? const <String>[]
        : await getLinkedUserIdsForProperty(normalizedPropertyId);
    final update = <String, dynamic>{
      'name': name,
      'status': status,
      'gateway_id': _idFromRefOrPath(id),
      'host': host,
      'position': [lat, lon],
      'user_uids': linkedUsers,
      'property_id': normalizedPropertyId.isEmpty ? null : normalizedPropertyId,
      if (wifiOtaEnabled != null) 'wifi_ota_enabled': wifiOtaEnabled,
      if (isMatrix != null) 'is_matrix': isMatrix,
    };
    await _client
        .from('gateways')
        .update(update)
        .eq('id', _idFromRefOrPath(id));
  }

  Future<void> updateRuralPropertyPolygon({
    required String id,
    required List<List<double>> points,
    String? updatedByUid,
  }) async {
    await _client.from('rural_properties').update({
      'points': _encodeLatLonPoints(points),
      if (_idFromRefOrPath(updatedByUid).isNotEmpty)
        'updated_by_uid': _idFromRefOrPath(updatedByUid),
    }).eq('id', _idFromRefOrPath(id));
  }

  Future<void> updateAreaPerimeter({
    required String id,
    required List<List<double>> perimeter,
    String? updatedByUid,
    List<String> linkedDeviceIds = const <String>[],
  }) async {
    await _client.from('areas').update({
      'perimeter': _encodeLatLonPoints(perimeter),
      'linked_device_ids': _normalizeLoraDeviceIds(linkedDeviceIds),
      if (_idFromRefOrPath(updatedByUid).isNotEmpty)
        'updated_by_uid': _idFromRefOrPath(updatedByUid),
    }).eq('id', _idFromRefOrPath(id));
  }

  Future<void> setDeviceWifiOtaEnabled({
    required String id,
    required bool enabled,
  }) async {
    await _client
        .from('collars')
        .update({'wifi_ota_enabled': enabled}).eq('id', _idFromRefOrPath(id));
  }

  Future<void> setGatewayWifiOtaEnabled({
    required String id,
    required bool enabled,
  }) async {
    await _client
        .from('gateways')
        .update({'wifi_ota_enabled': enabled}).eq('id', _idFromRefOrPath(id));
  }

  Future<void> deleteDevice({required String id}) async {
    final normalizedId = _idFromRefOrPath(id);
    await _client.from('fences').delete().eq('device_id', normalizedId);
    await _client.from('herding_plans').delete().eq('device_id', normalizedId);
    await _client.from('collars').delete().eq('id', normalizedId);
  }

  Future<void> deleteGateway({required String id}) async {
    await _client.from('gateways').delete().eq('id', _idFromRefOrPath(id));
  }

  Future<void> deleteArea({required String id}) async {
    await _client.from('areas').delete().eq('id', _idFromRefOrPath(id));
  }

  Future<void> deleteRuralProperty({required String id}) async {
    final normalizedId = _idFromRefOrPath(id);
    await _client.from('areas').delete().eq('property_id', normalizedId);
    await _client
        .from('gateways')
        .update({'property_id': null, 'user_uids': const <String>[]}).eq(
            'property_id', normalizedId);
    await _client
        .from('collars')
        .update({'property_id': null}).eq('property_id', normalizedId);
    await _client.from('rural_properties').delete().eq('id', normalizedId);
  }

  Future<void> backfillLegacyAccessForAreasAndGateways() async {
    final properties = await getRuralProperties(uid: '', isAdmin: true);
    final propertyUsers = <String, List<String>>{
      for (final property in properties)
        _idFromRefOrPath(property['id']): <String>{
          _idFromRefOrPath(property['createdByUid']),
          ...((property['userUids'] as List?) ?? const <dynamic>[])
              .map(_idFromRefOrPath),
        }.where((id) => id.isNotEmpty).toList(),
    };
    final areas =
        await _client.from('areas').select('id,property_id,owner_uid');
    for (final raw in (areas as List?) ?? const []) {
      final row = Map<String, dynamic>.from(raw);
      final propertyId = _idFromRefOrPath(row['property_id']);
      if (propertyId.isEmpty) continue;
      final users = <String>{
        ...(propertyUsers[propertyId] ?? const <String>[]),
        _idFromRefOrPath(row['owner_uid']),
      }.where((id) => id.isNotEmpty).toList();
      await _client
          .from('areas')
          .update({'user_uids': users}).eq('id', _idFromRefOrPath(row['id']));
    }
    final gateways = await _client.from('gateways').select('id,property_id');
    for (final raw in (gateways as List?) ?? const []) {
      final row = Map<String, dynamic>.from(raw);
      final propertyId = _idFromRefOrPath(row['property_id']);
      if (propertyId.isEmpty) continue;
      await _client.from('gateways').update({
        'user_uids': propertyUsers[propertyId] ?? const <String>[]
      }).eq('id', _idFromRefOrPath(row['id']));
    }
  }

  Future<void> saveFence(
    String deviceId,
    String ownerUid,
    List<List<double>> points,
  ) async {
    await _client.from('fences').upsert({
      'device_id': _idFromRefOrPath(deviceId),
      'owner_uid': _idFromRefOrPath(ownerUid),
      'points': _encodeLatLonPoints(points),
    });
  }

  Future<List<List<double>>> getFence(String deviceId) async {
    final row = await _client
        .from('fences')
        .select('points')
        .eq('device_id', _idFromRefOrPath(deviceId))
        .maybeSingle();
    if (row == null) return const [];
    return _decodeLatLonPoints(row['points']);
  }

  Future<void> saveHerdingPlan(
    String deviceId,
    String ownerUid,
    List<List<List<double>>> phases,
  ) async {
    await _client.from('herding_plans').upsert({
      'device_id': _idFromRefOrPath(deviceId),
      'owner_uid': _idFromRefOrPath(ownerUid),
      'phases': _encodeHerdingPhases(phases),
    });
  }

  Future<List<List<List<double>>>> getHerdingPlan(String deviceId) async {
    final row = await _client
        .from('herding_plans')
        .select('phases')
        .eq('device_id', _idFromRefOrPath(deviceId))
        .maybeSingle();
    if (row == null) return const [];
    return _decodeHerdingPhases(row['phases']);
  }

  Future<void> saveCriticalEvent(Map<String, dynamic> event) async {
    final payload = Map<String, dynamic>.from(event);
    await _client.from('events').upsert({
      'id': _idFromRefOrPath(payload['id']).isEmpty
          ? const Uuid().v4()
          : _idFromRefOrPath(payload['id']),
      'owner_uid': _idFromRefOrPath(payload['ownerUid']),
      'property_id': _idFromRefOrPath(payload['propertyId']),
      'device_id': _idFromRefOrPath(payload['deviceId']),
      'gateway_id': _idFromRefOrPath(payload['gatewayId']),
      'type': _normalizeText(payload['type']),
      'event_type': _normalizeText(payload['eventType']),
      'polygon_kind': _normalizeText(payload['polygonKind']),
      'origin_doc_type': _normalizeText(payload['originDocType']),
      'origin_doc_id': _idFromRefOrPath(payload['originDocId']),
      'received_at_ms': _toInt(payload['receivedAtMs']),
      'payload': payload,
    });
  }
}

class Uuid {
  const Uuid();

  String v4() => const UuidValue().value();
}

class UuidValue {
  const UuidValue();

  String value() {
    final nowMicros = DateTime.now().microsecondsSinceEpoch;
    final bytes = List<int>.generate(16, (index) => nowMicros ^ index);
    final digest = sha256.convert(bytes).bytes;
    final b = digest.take(16).toList();
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    String hex(int value) => value.toRadixString(16).padLeft(2, '0');
    return '${hex(b[0])}${hex(b[1])}${hex(b[2])}${hex(b[3])}-'
        '${hex(b[4])}${hex(b[5])}-'
        '${hex(b[6])}${hex(b[7])}-'
        '${hex(b[8])}${hex(b[9])}-'
        '${hex(b[10])}${hex(b[11])}${hex(b[12])}${hex(b[13])}${hex(b[14])}${hex(b[15])}';
  }
}
