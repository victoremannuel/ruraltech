import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart' as rtdb;
import 'package:http/http.dart' as http;
import '../config/manual_settings.dart';
import '../models/device_model.dart';
import '../models/herding_operation_model.dart';
import '../utils/device_map_telemetry.dart';

class FirebaseService {
  static const String _defaultRtdbUrl = ManualSettings.firebaseRtdbUrl;
  static const String _supabaseUrl = ManualSettings.supabaseUrl;
  static const String _supabasePublishableKey =
      ManualSettings.supabasePublishableKey;

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  late final rtdb.FirebaseDatabase _rtdb;

  FirebaseService() {
    final configuredUrl = Firebase.app().options.databaseURL?.trim() ?? '';
    _rtdb = rtdb.FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: configuredUrl.isNotEmpty ? configuredUrl : _defaultRtdbUrl,
    );
  }

  List<Map<String, double>> _encodeLatLonPoints(List<List<double>> points) {
    return points
        .where((p) => p.length >= 2)
        .map((p) => {'lat': p[0], 'lon': p[1]})
        .toList();
  }

  List<Map<String, dynamic>> _encodeHerdingPhases(
      List<List<List<double>>> phases) {
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
    return '';
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

  Future<String?> _resolveGatewayWsHostByGatewayId(String? gatewayId) async {
    final normalizedGatewayId = _idFromRefOrPath(gatewayId);
    if (normalizedGatewayId.isEmpty) return null;

    final gatewayDoc =
        await _db.collection('gateways').doc(normalizedGatewayId).get();
    if (!gatewayDoc.exists) return null;
    final data = gatewayDoc.data() ?? const <String, dynamic>{};
    final candidates = <dynamic>[
      data['host_ws'],
      data['hostWs'],
      data['host'],
      data['ip'],
    ];
    for (final candidate in candidates) {
      final wsHost = _normalizeWsHost(candidate?.toString());
      if (wsHost != null) return wsHost;
    }
    return null;
  }

  Future<String?> resolveGatewayWsHostForDevice({
    required String deviceId,
    String? fallbackGatewayId,
  }) async {
    try {
      final fromFallback = await _resolveGatewayWsHostByGatewayId(
        fallbackGatewayId,
      );
      if (fromFallback != null) return fromFallback;

      final normalizedDeviceId = _normalizeLoraDeviceId(deviceId);
      final candidateDocIds = <String>{
        _idFromRefOrPath(deviceId),
        if (normalizedDeviceId != null) normalizedDeviceId,
      }.where((id) => id.isNotEmpty);

      for (final docId in candidateDocIds) {
        final collarDoc = await _db.collection('collars').doc(docId).get();
        if (!collarDoc.exists) continue;
        final data = collarDoc.data() ?? const <String, dynamic>{};
        final wsHost =
            await _resolveGatewayWsHostByGatewayId(data['gatewayId']);
        if (wsHost != null) return wsHost;
      }

      if (normalizedDeviceId != null) {
        final byDeviceId = await _db
            .collection('collars')
            .where('deviceId', isEqualTo: normalizedDeviceId)
            .limit(1)
            .get();
        if (byDeviceId.docs.isNotEmpty) {
          final data = byDeviceId.docs.first.data();
          final wsHost =
              await _resolveGatewayWsHostByGatewayId(data['gatewayId']);
          if (wsHost != null) return wsHost;
        }
      }
    } catch (_) {
      // Resolve is best-effort; caller can fallback to currently connected host.
    }
    return null;
  }

  Future<String?> resolveMatrixGatewayIdForProperty({
    required String propertyId,
  }) async {
    final normalizedPropertyId = _idFromRefOrPath(propertyId);
    if (normalizedPropertyId.isEmpty) return null;
    final doc = await _findMatrixGatewayDocForProperty(normalizedPropertyId);
    return doc?.id;
  }

  Future<String?> resolveMatrixGatewayWsHost({
    required String propertyId,
  }) async {
    final matrixGatewayId =
        await resolveMatrixGatewayIdForProperty(propertyId: propertyId);
    if (matrixGatewayId == null || matrixGatewayId.isEmpty) return null;
    return _resolveGatewayWsHostByGatewayId(matrixGatewayId);
  }

  Future<Map<String, dynamic>> getScopedCommandReadiness({
    required String propertyId,
    required List<String> targetDeviceIds,
    List<String> targetGatewayIds = const [],
    String? matrixGatewayId,
  }) async {
    final normalizedPropertyId = _idFromRefOrPath(propertyId);
    if (normalizedPropertyId.isEmpty) {
      return {
        'ok': false,
        'reason': 'invalid_property_id',
      };
    }

    final propertySnap = await _getPropertyDoc(normalizedPropertyId);
    if (!propertySnap.exists) {
      return {
        'ok': false,
        'reason': 'property_not_found',
      };
    }
    final propertyData = propertySnap.data() ?? const <String, dynamic>{};
    final propertyScopeId =
        (propertyData['propertyScopeId'] ?? '').toString().trim().toUpperCase();
    if (propertyScopeId.isEmpty) {
      return {
        'ok': false,
        'reason': 'property_scope_not_ready',
      };
    }

    final resolvedMatrixGatewayId = _idFromRefOrPath(matrixGatewayId).isNotEmpty
        ? _idFromRefOrPath(matrixGatewayId)
        : await resolveMatrixGatewayIdForProperty(
            propertyId: normalizedPropertyId);
    if (resolvedMatrixGatewayId == null || resolvedMatrixGatewayId.isEmpty) {
      return {
        'ok': false,
        'reason': 'no_matrix_for_property',
      };
    }

    final matrixSnap =
        await _db.collection('gateways').doc(resolvedMatrixGatewayId).get();
    if (!matrixSnap.exists) {
      return {
        'ok': false,
        'reason': 'matrix_not_found',
      };
    }
    final matrixData = matrixSnap.data() ?? const <String, dynamic>{};
    if (matrixData['is_matrix'] != true ||
        !_matchesPropertyForData(
          matrixData,
          expectedPropertyId: normalizedPropertyId,
          expectedScopeId: propertyScopeId,
        )) {
      return {
        'ok': false,
        'reason': 'matrix_property_mismatch',
      };
    }
    if (!_bindingReadyForData(matrixData, expectedScopeId: propertyScopeId)) {
      return {
        'ok': false,
        'reason': 'matrix_not_ready',
        'matrixGatewayId': resolvedMatrixGatewayId,
      };
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
      return {
        'ok': false,
        'reason': 'no_targets',
      };
    }

    for (final deviceId in normalizedDeviceIds) {
      final snap = await _db.collection('collars').doc(deviceId).get();
      if (!snap.exists) {
        return {
          'ok': false,
          'reason': 'unknown_target_device:$deviceId',
        };
      }
      final data = snap.data() ?? const <String, dynamic>{};
      if (!_matchesPropertyForData(
        data,
        expectedPropertyId: normalizedPropertyId,
        expectedScopeId: propertyScopeId,
      )) {
        return {
          'ok': false,
          'reason': 'target_device_property_mismatch:$deviceId',
        };
      }
      if (!_bindingReadyForData(data, expectedScopeId: propertyScopeId)) {
        return {
          'ok': false,
          'reason': 'target_device_not_ready:$deviceId',
        };
      }
    }

    for (final gatewayId in normalizedGatewayIds) {
      final snap = await _db.collection('gateways').doc(gatewayId).get();
      if (!snap.exists) {
        return {
          'ok': false,
          'reason': 'unknown_target_gateway:$gatewayId',
        };
      }
      final data = snap.data() ?? const <String, dynamic>{};
      if (!_matchesPropertyForData(
        data,
        expectedPropertyId: normalizedPropertyId,
        expectedScopeId: propertyScopeId,
      )) {
        return {
          'ok': false,
          'reason': 'target_gateway_property_mismatch:$gatewayId',
        };
      }
      if (!_bindingReadyForData(data, expectedScopeId: propertyScopeId)) {
        return {
          'ok': false,
          'reason': 'target_gateway_not_ready:$gatewayId',
        };
      }
    }

    return {
      'ok': true,
      'reason': null,
      'propertyId': normalizedPropertyId,
      'propertyScopeId': propertyScopeId,
      'matrixGatewayId': resolvedMatrixGatewayId,
      'matrixRuntimeId':
          _matrixRuntimeIdFromGatewayData(resolvedMatrixGatewayId, matrixData),
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

    final normalizedPropertyId = readiness['propertyId'] as String;
    final normalizedRequestedByUid = _idFromRefOrPath(requestedByUid);
    if (normalizedRequestedByUid.isEmpty) {
      throw Exception('invalid_requested_by_uid');
    }

    final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (idToken == null || idToken.trim().isEmpty) {
      throw Exception('missing_firebase_id_token');
    }

    final expiresAtMs = DateTime.now()
        .add(ttl ?? const Duration(minutes: 15))
        .millisecondsSinceEpoch;
    final response = await _postSupabaseFunction(
      'queue-lora-command',
      idToken: idToken,
      body: <String, dynamic>{
        'command': normalizedCommand,
        'propertyId': normalizedPropertyId,
        'propertyScopeId': readiness['propertyScopeId'],
        'matrixGatewayId': readiness['matrixGatewayId'],
        'targetDeviceIds': readiness['targetDeviceIds'],
        'targetGatewayIds': readiness['targetGatewayIds'],
        'payload': payload,
        'requestedByRole': _normalizeRoleValue(requestedByRole),
        'requestedByUid': normalizedRequestedByUid,
        'ttlMs': expiresAtMs - DateTime.now().millisecondsSinceEpoch,
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
    final normalizedOperationId = _idFromRefOrPath(operationId);
    final normalizedCommandId = _idFromRefOrPath(loraCommandId);
    if (normalizedOperationId.isEmpty || normalizedCommandId.isEmpty) return;
    await _db.collection('herdingOperations').doc(normalizedOperationId).set({
      'loraCommandId': normalizedCommandId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<Map<String, dynamic>?> streamCommandStatus({
    required String propertyId,
    required String commandId,
  }) {
    final propertyKey = _sanitizeRtdbKey(propertyId);
    final normalizedCommandId = _idFromRefOrPath(commandId);
    if (propertyKey.isEmpty || normalizedCommandId.isEmpty) {
      return Stream.value(null);
    }
    return _rtdb
        .ref('propertyCommands/$propertyKey/$normalizedCommandId')
        .onValue
        .map((event) {
      final value = event.snapshot.value;
      if (value is! Map) return null;
      return {
        'id': normalizedCommandId,
        ...Map<String, dynamic>.from(value.cast<String, dynamic>()),
      };
    });
  }

  Future<void> registerPushToken({
    required String uid,
    required String token,
  }) async {
    final normalizedUid = _idFromRefOrPath(uid);
    final normalizedToken = token.trim();
    if (normalizedUid.isEmpty || normalizedToken.isEmpty) return;

    await _db.collection('users').doc(normalizedUid).set({
      'fcmTokens': FieldValue.arrayUnion(<String>[normalizedToken]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  DocumentReference<Map<String, dynamic>> _userRef(dynamic value) =>
      _db.collection('users').doc(_idFromRefOrPath(value));

  String _userPath(String uid) => '/users/$uid';

  DocumentReference<Map<String, dynamic>>? _propertyRefOrNull(dynamic value) {
    final id = _idFromRefOrPath(value);
    if (id.isEmpty) return null;
    return _db.collection('ruralProperties').doc(id);
  }

  String _propertyPath(String propertyId) => '/ruralProperties/$propertyId';

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

  Future<Map<String, dynamic>> _postSupabaseFunction(
    String functionName, {
    required String idToken,
    Map<String, dynamic>? body,
  }) async {
    final response = await http.post(
      _supabaseFunctionUri(functionName),
      headers: <String, String>{
        'content-type': 'application/json',
        'apikey': _supabasePublishableKey,
        'authorization': 'Bearer $idToken',
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

  Future<Map<String, dynamic>> repairFirebaseMirrors({
    bool apply = true,
    String? propertyId,
    String? gatewayId,
  }) async {
    final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (idToken == null || idToken.trim().isEmpty) {
      throw Exception('missing_firebase_id_token');
    }
    return _postSupabaseFunction(
      'repair-firebase-mirrors',
      idToken: idToken,
      body: <String, dynamic>{
        'apply': apply,
        if (propertyId != null && propertyId.trim().isNotEmpty)
          'propertyId': _idFromRefOrPath(propertyId),
        if (gatewayId != null && gatewayId.trim().isNotEmpty)
          'gatewayId': _idFromRefOrPath(gatewayId),
      },
    );
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _getPropertyDoc(
    String propertyId,
  ) {
    final normalizedPropertyId = _idFromRefOrPath(propertyId);
    return _db.collection('ruralProperties').doc(normalizedPropertyId).get();
  }

  Future<DocumentSnapshot<Map<String, dynamic>>?>
      _findMatrixGatewayDocForProperty(
    String propertyId,
  ) async {
    final normalizedPropertyId = _idFromRefOrPath(propertyId);
    if (normalizedPropertyId.isEmpty) return null;
    final propertySnap = await _getPropertyDoc(normalizedPropertyId);
    final propertyData = propertySnap.data() ?? const <String, dynamic>{};
    final expectedScopeId =
        (propertyData['propertyScopeId'] ?? '').toString().trim().toUpperCase();

    final propertyRef = _propertyRefOrNull(normalizedPropertyId);
    final candidates = <dynamic>[
      propertyRef,
      normalizedPropertyId,
      _propertyPath(normalizedPropertyId),
    ];

    final byId = <String, DocumentSnapshot<Map<String, dynamic>>>{};
    for (final candidate in candidates) {
      final snap = await _db
          .collection('gateways')
          .where('propertyId', isEqualTo: candidate)
          .where('is_matrix', isEqualTo: true)
          .limit(5)
          .get();
      for (final doc in snap.docs) {
        byId[doc.id] = doc;
      }
    }

    if (byId.isEmpty && expectedScopeId.isNotEmpty) {
      final snap = await _db
          .collection('gateways')
          .where('is_matrix', isEqualTo: true)
          .limit(25)
          .get();
      for (final doc in snap.docs) {
        final data = doc.data();
        if (_matchesPropertyForData(
          data,
          expectedPropertyId: normalizedPropertyId,
          expectedScopeId: expectedScopeId,
        )) {
          byId[doc.id] = doc;
        }
      }
    }

    if (byId.isEmpty) return null;
    final docs = byId.values.toList()..sort((a, b) => a.id.compareTo(b.id));
    return docs.first;
  }

  String? _matrixRuntimeIdFromGatewayData(
    String gatewayId,
    Map<String, dynamic> data,
  ) {
    final runtimeStatus = data['runtimeStatus'];
    final runtimeMatrixId = runtimeStatus is Map
        ? _idFromRefOrPath(
            runtimeStatus['matrixId'] ?? runtimeStatus['rtdbMatrixId'])
        : '';
    final explicit = _idFromRefOrPath(
      data['rtdbMatrixId'] ?? data['matrixId'] ?? runtimeMatrixId,
    );
    final candidate = explicit.isNotEmpty ? explicit : gatewayId;
    final sanitized = _sanitizeRtdbKey(candidate);
    return sanitized.isEmpty ? null : sanitized;
  }

  String _resolvedScopeIdForData(Map<String, dynamic> data) {
    final runtimeStatus = data['runtimeStatus'];
    final runtimeMap = runtimeStatus is Map<String, dynamic>
        ? runtimeStatus
        : const <String, dynamic>{};
    return (runtimeMap['propertyScopeId'] ?? data['propertyScopeId'] ?? '')
        .toString()
        .trim()
        .toUpperCase();
  }

  bool _matchesPropertyForData(
    Map<String, dynamic> data, {
    required String expectedPropertyId,
    required String expectedScopeId,
  }) {
    final runtimeStatus = data['runtimeStatus'];
    final runtimeMap = runtimeStatus is Map<String, dynamic>
        ? runtimeStatus
        : const <String, dynamic>{};
    final directPropertyId =
        _idFromRefOrPath(data['propertyId'] ?? runtimeMap['propertyId']);
    if (directPropertyId.isNotEmpty) {
      return directPropertyId == expectedPropertyId;
    }
    final runtimeScopeId = _resolvedScopeIdForData(data);
    return runtimeScopeId.isNotEmpty && runtimeScopeId == expectedScopeId;
  }

  bool _bindingReadyForData(
    Map<String, dynamic> data, {
    required String expectedScopeId,
  }) {
    final runtimeStatus = data['runtimeStatus'];
    final runtimeMap = runtimeStatus is Map<String, dynamic>
        ? runtimeStatus
        : const <String, dynamic>{};
    final supportsScopedLora = data['supportsScopedLora'] == true ||
        runtimeMap['supportsScopedLora'] == true;
    final runtimeScopeId = _resolvedScopeIdForData(data);
    final bindingReady = data['bindingReady'] == true ||
        runtimeMap['bindingReady'] == true ||
        (supportsScopedLora &&
            runtimeScopeId.isNotEmpty &&
            runtimeScopeId == expectedScopeId);
    return supportsScopedLora &&
        bindingReady &&
        runtimeScopeId.isNotEmpty &&
        runtimeScopeId == expectedScopeId;
  }

  Future<List<DocumentReference<Map<String, dynamic>>>> _linkedUsersForProperty(
      String propertyId) async {
    final id = _idFromRefOrPath(propertyId);
    if (id.isEmpty) return const [];
    final snap = await _db.collection('ruralProperties').doc(id).get();
    if (!snap.exists) return const [];
    final data = snap.data() ?? {};
    final out = <DocumentReference<Map<String, dynamic>>>{};

    final createdById = _idFromRefOrPath(data['createdByUid']);
    if (createdById.isNotEmpty) out.add(_userRef(createdById));
    final ownerId = _idFromRefOrPath(data['ownerUid']);
    if (ownerId.isNotEmpty) out.add(_userRef(ownerId));

    final rawUsers = data['userUids'];
    if (rawUsers is List) {
      for (final u in rawUsers) {
        final userId = _idFromRefOrPath(u);
        if (userId.isNotEmpty) out.add(_userRef(userId));
      }
    }
    return out.toList();
  }

  Future<List<String>> getLinkedUserIdsForProperty(String propertyId) async {
    final refs = await _linkedUsersForProperty(propertyId);
    final ids = refs.map((ref) => ref.id).where((id) => id.isNotEmpty).toSet();
    return ids.toList()..sort();
  }

  double? _latFromPosition(Map<String, dynamic> m) {
    final pos = m['position'];
    if (pos is GeoPoint) return pos.latitude;
    if (pos is List && pos.length >= 2 && pos[0] is num) {
      return (pos[0] as num).toDouble();
    }
    if (pos is List && pos.isNotEmpty && pos[0] is GeoPoint) {
      return (pos[0] as GeoPoint).latitude;
    }
    if (m['lat'] is num) return (m['lat'] as num).toDouble();
    return null;
  }

  double? _lonFromPosition(Map<String, dynamic> m) {
    final pos = m['position'];
    if (pos is GeoPoint) return pos.longitude;
    if (pos is List && pos.length >= 2 && pos[1] is num) {
      return (pos[1] as num).toDouble();
    }
    if (pos is List && pos.isNotEmpty && pos[0] is GeoPoint) {
      return (pos[0] as GeoPoint).longitude;
    }
    if (m['lon'] is num) return (m['lon'] as num).toDouble();
    return null;
  }

  Map<String, Map<String, dynamic>> _decodeTelemetryLatestDetailsSnapshot(
    dynamic raw,
  ) {
    if (raw is! Map) return const <String, Map<String, dynamic>>{};
    final out = <String, Map<String, dynamic>>{};
    for (final entry in raw.entries) {
      final key = entry.key?.toString().trim() ?? '';
      if (key.isEmpty) continue;
      final value = entry.value;
      if (value is! Map) continue;
      final lat = value['lat'];
      final lon = value['lon'];
      if (lat is! num || lon is! num) continue;
      final latD = lat.toDouble();
      final lonD = lon.toDouble();
      if (!latD.isFinite || !lonD.isFinite) continue;
      if (latD < -90 || latD > 90 || lonD < -180 || lonD > 180) continue;
      final telemetry = <String, dynamic>{
        'lat': latD,
        'lon': lonD,
      };
      final receivedAtMs =
          _coerceTimestampMs(value['receivedAtMs'] ?? value['receivedAt']);
      if (receivedAtMs > 0) {
        telemetry['telemetryReceivedAtMs'] = receivedAtMs;
      }
      out[key] = telemetry;
    }
    return out;
  }

  Map<String, Map<String, double>> _decodeTelemetryLatestSnapshot(dynamic raw) {
    final detailed = _decodeTelemetryLatestDetailsSnapshot(raw);
    return detailed.map(
      (key, value) => MapEntry(
        key,
        <String, double>{
          'lat': (value['lat'] as num).toDouble(),
          'lon': (value['lon'] as num).toDouble(),
        },
      ),
    );
  }

  Map<String, Map<String, dynamic>> _decodeHealthLatestSnapshot(dynamic raw) {
    if (raw is! Map) return const <String, Map<String, dynamic>>{};
    final out = <String, Map<String, dynamic>>{};
    for (final entry in raw.entries) {
      final key = entry.key?.toString().trim() ?? '';
      if (key.isEmpty) continue;
      final value = entry.value;
      if (value is! Map) continue;

      final health = <String, dynamic>{
        if (_toIntValue(value['receivedAtMs']) != null)
          'healthReceivedAtMs': _toIntValue(value['receivedAtMs']),
        if (_toIntValue(value['gpsDayKey']) != null)
          'healthGpsDayKey': _toIntValue(value['gpsDayKey']),
        if (_toIntValue(value['healthFlags']) != null)
          'healthFlags': _toIntValue(value['healthFlags']),
        if (_toIntValue(value['uptimeSec']) != null)
          'healthUptimeSec': _toIntValue(value['uptimeSec']),
        if (_toIntValue(value['temperatureDeciC']) != null)
          'healthTemperatureDeciC': _toIntValue(value['temperatureDeciC']),
        if (_toIntValue(value['sat']) != null)
          'healthSatellites': _toIntValue(value['sat']),
        if (_toIntValue(value['hdopCenti']) != null)
          'healthHdopCenti': _toIntValue(value['hdopCenti']),
        if (_toIntValue(value['i2cDevices']) != null)
          'healthI2cDevices': _toIntValue(value['i2cDevices']),
      };
      if (health.isNotEmpty) out[key] = health;
    }
    return out;
  }

  int _eventSortKeyMs(Map<String, dynamic> event) {
    final createdAt = event['createdAt'];
    if (createdAt is Timestamp) return createdAt.millisecondsSinceEpoch;
    if (createdAt is DateTime) return createdAt.millisecondsSinceEpoch;
    if (createdAt is num) {
      final raw = createdAt.toInt();
      return raw > 1000000000000 ? raw : raw * 1000;
    }

    final receivedAtMs = event['receivedAtMs'];
    if (receivedAtMs is num) return receivedAtMs.toInt();

    final sourceTimestampSec =
        event['sourceTimestampSec'] ?? event['timestamp'];
    if (sourceTimestampSec is num) return sourceTimestampSec.toInt() * 1000;
    return 0;
  }

  List<Map<String, dynamic>> _decodeTelemetryHistorySnapshot(
    dynamic raw, {
    required String propertyId,
    required String normalizedDeviceId,
  }) {
    if (raw is! Map) return const <Map<String, dynamic>>[];
    final items = <Map<String, dynamic>>[];
    for (final dayEntry in raw.entries) {
      final dayKey = dayEntry.key?.toString().trim() ?? '';
      final dayMap = dayEntry.value;
      if (dayKey.isEmpty || dayMap is! Map) continue;
      for (final entry in dayMap.entries) {
        final entryId = entry.key?.toString().trim() ?? '';
        final value = entry.value;
        if (entryId.isEmpty || value is! Map) continue;
        final lat = _toFiniteCoord(value['lat']);
        final lon = _toFiniteCoord(value['lon']);
        if (lat == null || lon == null) continue;
        final rawMap = _normalizeJsonLike(value);
        if (rawMap is! Map<String, dynamic>) continue;
        items.add({
          'id': 'telemetry:$dayKey:$entryId',
          'entryId': entryId,
          'dayKey': dayKey,
          'deviceId': normalizedDeviceId,
          'propertyId': propertyId,
          'kind': 'telemetry',
          'type': 'telemetry',
          'receivedAtMs': _coerceTimestampMs(
            value['receivedAtMs'] ?? value['receivedAt'],
            fallbackId: entryId,
          ),
          'gatewayId': value['gatewayId'],
          'gatewayRole': value['gatewayRole'],
          'lat': lat,
          'lon': lon,
          'raw': rawMap,
        });
      }
    }
    return items;
  }

  Map<String, dynamic>? _decodeLatestTelemetryLogEntry(
    dynamic raw, {
    required String propertyId,
    required String normalizedDeviceId,
  }) {
    if (raw is! Map) return null;
    final lat = _toFiniteCoord(raw['lat']);
    final lon = _toFiniteCoord(raw['lon']);
    if (lat == null || lon == null) return null;
    final rawMap = _normalizeJsonLike(raw);
    if (rawMap is! Map<String, dynamic>) return null;
    final receivedAtMs = _coerceTimestampMs(
      raw['receivedAtMs'] ?? raw['receivedAt'],
    );
    return {
      'id': 'telemetry:latest:$normalizedDeviceId',
      'entryId': 'latest',
      'dayKey': '',
      'deviceId': normalizedDeviceId,
      'propertyId': propertyId,
      'kind': 'telemetry',
      'type': 'telemetry',
      'receivedAtMs': receivedAtMs > 0 ? receivedAtMs : null,
      'gatewayId': raw['gatewayId'],
      'gatewayRole': raw['gatewayRole'],
      'lat': lat,
      'lon': lon,
      'raw': rawMap,
    };
  }

  List<Map<String, dynamic>> _decodeHealthHistorySnapshot(
    dynamic raw, {
    required String propertyId,
    required String normalizedDeviceId,
  }) {
    if (raw is! Map) return const <Map<String, dynamic>>[];
    final items = <Map<String, dynamic>>[];
    for (final dayEntry in raw.entries) {
      final dayKey = dayEntry.key?.toString().trim() ?? '';
      final dayMap = dayEntry.value;
      if (dayKey.isEmpty || dayMap is! Map) continue;
      for (final entry in dayMap.entries) {
        final entryId = entry.key?.toString().trim() ?? '';
        final value = entry.value;
        if (entryId.isEmpty || value is! Map) continue;
        final rawMap = _normalizeJsonLike(value);
        if (rawMap is! Map<String, dynamic>) continue;
        items.add({
          'id': 'health:$dayKey:$entryId',
          'entryId': entryId,
          'dayKey': dayKey,
          'deviceId': normalizedDeviceId,
          'propertyId': propertyId,
          'kind': 'health_daily',
          'type': 'health_daily',
          'receivedAtMs': _coerceTimestampMs(
            value['receivedAtMs'] ?? value['receivedAt'],
            fallbackId: entryId,
          ),
          'gatewayId': value['gatewayId'],
          'gatewayRole': value['gatewayRole'],
          'healthFlags': _toIntValue(value['healthFlags']),
          'sat': _toIntValue(value['sat']),
          'temperatureDeciC': _toIntValue(value['temperatureDeciC']),
          'raw': rawMap,
        });
      }
    }
    return items;
  }

  List<Map<String, dynamic>> _decodePropertyEventsForDevice(
    dynamic raw, {
    required String propertyId,
    required String normalizedDeviceId,
  }) {
    if (raw is! Map) return const <Map<String, dynamic>>[];
    final items = <Map<String, dynamic>>[];
    for (final dayEntry in raw.entries) {
      final dayKey = dayEntry.key?.toString().trim() ?? '';
      final dayMap = dayEntry.value;
      if (dayKey.isEmpty || dayMap is! Map) continue;
      for (final entry in dayMap.entries) {
        final entryId = entry.key?.toString().trim() ?? '';
        final value = entry.value;
        if (entryId.isEmpty || value is! Map) continue;
        final candidateDeviceId = _normalizeLoraDeviceId(
              value['deviceId'] ?? value['device_id'],
            ) ??
            _normalizeLoraDeviceId(
              value['payload'] is Map
                  ? (value['payload'] as Map)['deviceId']
                  : null,
            );
        if (candidateDeviceId != normalizedDeviceId) continue;

        final eventType = (value['eventType'] ?? value['type'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        if (eventType == 'health_daily') continue;

        final rawMap = _normalizeJsonLike(value);
        if (rawMap is! Map<String, dynamic>) continue;
        items.add({
          'id': 'event:$dayKey:$entryId',
          'entryId': entryId,
          'dayKey': dayKey,
          'deviceId': normalizedDeviceId,
          'propertyId': propertyId,
          'kind': eventType.isEmpty ? 'event' : eventType,
          'type': 'event',
          'eventType': eventType,
          'receivedAtMs': _coerceTimestampMs(
            value['receivedAtMs'] ??
                value['receivedAt'] ??
                value['sourceTimestampSec'],
            fallbackId: entryId,
          ),
          'gatewayId': value['gatewayId'],
          'gatewayRole': value['gatewayRole'],
          'raw': rawMap,
        });
      }
    }
    return items;
  }

  List<Map<String, dynamic>> _mergeCollarFirebaseLogItems({
    required String propertyId,
    required String normalizedDeviceId,
    dynamic latestTelemetryRaw,
    dynamic telemetryHistoryRaw,
    dynamic healthHistoryRaw,
    dynamic eventsRaw,
  }) {
    final items = <Map<String, dynamic>>[
      ..._decodeTelemetryHistorySnapshot(
        telemetryHistoryRaw,
        propertyId: propertyId,
        normalizedDeviceId: normalizedDeviceId,
      ),
      ..._decodeHealthHistorySnapshot(
        healthHistoryRaw,
        propertyId: propertyId,
        normalizedDeviceId: normalizedDeviceId,
      ),
      ..._decodePropertyEventsForDevice(
        eventsRaw,
        propertyId: propertyId,
        normalizedDeviceId: normalizedDeviceId,
      ),
    ];
    final latestTelemetry = _decodeLatestTelemetryLogEntry(
      latestTelemetryRaw,
      propertyId: propertyId,
      normalizedDeviceId: normalizedDeviceId,
    );
    if (latestTelemetry != null) {
      final alreadyPresent = items.any(
        (item) =>
            item['type'] == 'telemetry' &&
            item['receivedAtMs'] == latestTelemetry['receivedAtMs'] &&
            item['lat'] == latestTelemetry['lat'] &&
            item['lon'] == latestTelemetry['lon'],
      );
      if (!alreadyPresent) {
        items.add(latestTelemetry);
      }
    }
    items.sort((a, b) => _eventSortKeyMs(b).compareTo(_eventSortKeyMs(a)));
    return items;
  }

  Map<String, dynamic> _eventFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return {
      'id': doc.id,
      ...data,
      'ownerUid': _idFromRefOrPath(data['ownerUid']),
    };
  }

  int _herdingOperationSortKeyMs(HerdingOperationModel operation) {
    final updatedAt = operation.updatedAt;
    if (updatedAt != null) return updatedAt.millisecondsSinceEpoch;
    final createdAt = operation.createdAt;
    if (createdAt != null) return createdAt.millisecondsSinceEpoch;
    return 0;
  }

  String _sanitizeRtdbKey(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.replaceAll(RegExp(r'[.#$\[\]/]'), '_');
  }

  double? _toFiniteCoord(dynamic value) {
    if (value is num) {
      final out = value.toDouble();
      return out.isFinite ? out : null;
    }
    if (value is String) {
      final out = double.tryParse(value.trim());
      if (out == null || !out.isFinite) return null;
      return out;
    }
    return null;
  }

  int? _toIntValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  dynamic _normalizeJsonLike(dynamic value) {
    if (value is Map) {
      final out = <String, dynamic>{};
      for (final entry in value.entries) {
        final key = entry.key?.toString().trim() ?? '';
        if (key.isEmpty) continue;
        out[key] = _normalizeJsonLike(entry.value);
      }
      return out;
    }
    if (value is List) {
      return value.map(_normalizeJsonLike).toList(growable: false);
    }
    return value;
  }

  Map<String, dynamic>? _decodeJsonMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      final normalized = _normalizeJsonLike(raw);
      return normalized is Map<String, dynamic> ? normalized : null;
    }
    if (raw is! String || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        final normalized = _normalizeJsonLike(decoded);
        return normalized is Map<String, dynamic> ? normalized : null;
      }
    } catch (_) {}
    return null;
  }

  int _coerceTimestampMs(dynamic raw, {dynamic fallbackId}) {
    final direct = _toIntValue(raw);
    if (direct != null && direct > 0) {
      return direct > 1000000000000 ? direct : direct * 1000;
    }
    final fallback = _toIntValue(fallbackId);
    if (fallback != null && fallback > 0) {
      return fallback > 1000000000000 ? fallback : fallback * 1000;
    }
    return 0;
  }

  Map<String, Map<String, dynamic>> _decodeLatestEventPositionSnapshot(
    dynamic raw,
  ) {
    if (raw is! Map) return const <String, Map<String, dynamic>>{};
    final out = <String, Map<String, dynamic>>{};

    for (final dayEntry in raw.entries) {
      final dayMap = dayEntry.value;
      if (dayMap is! Map) continue;
      for (final eventEntry in dayMap.entries) {
        final entryId = eventEntry.key?.toString().trim() ?? '';
        final value = eventEntry.value;
        if (entryId.isEmpty || value is! Map) continue;

        final payload = _decodeJsonMap(value['payload']);
        final normalizedDeviceId = _normalizeLoraDeviceId(
              value['deviceId'] ?? value['device_id'],
            ) ??
            _normalizeLoraDeviceId(
              payload?['deviceId'] ?? payload?['device_id'],
            );
        if (normalizedDeviceId == null) continue;

        final lat = _toFiniteCoord(
          value['lat'] ?? payload?['lat'] ?? payload?['gps']?['lat'],
        );
        final lon = _toFiniteCoord(
          value['lon'] ??
              value['lng'] ??
              payload?['lon'] ??
              payload?['lng'] ??
              payload?['gps']?['lon'],
        );
        if (lat == null ||
            lon == null ||
            lat < -90 ||
            lat > 90 ||
            lon < -180 ||
            lon > 180) {
          continue;
        }

        final receivedAtMs = _coerceTimestampMs(
          value['receivedAtMs'] ??
              value['receivedAt'] ??
              value['sourceTimestampSec'] ??
              value['timestamp'] ??
              payload?['receivedAtMs'] ??
              payload?['receivedAt'],
          fallbackId: entryId,
        );
        final current = out[normalizedDeviceId];
        final currentMs = current?['positionReceivedAtMs'] as int? ?? 0;
        if (current != null && receivedAtMs <= currentMs) continue;

        out[normalizedDeviceId] = <String, dynamic>{
          'lat': lat,
          'lon': lon,
          'positionReceivedAtMs': receivedAtMs,
          'positionSourceType': 'event',
          'eventType': (value['eventType'] ??
                  value['type'] ??
                  payload?['event_type'] ??
                  payload?['type'])
              ?.toString(),
        };
      }
    }
    return out;
  }

  String _normalizeRoleValue(String value) {
    final raw = value.trim().toLowerCase();
    return raw.isEmpty ? 'user' : raw;
  }

  Future<Map<String, double>?> getLatestTelemetryPositionForDevice(
      String rawDeviceId) async {
    final normalizedDeviceId = _normalizeLoraDeviceId(rawDeviceId);
    if (normalizedDeviceId == null) return null;
    final sanitizedDeviceId = _sanitizeRtdbKey(normalizedDeviceId);
    if (sanitizedDeviceId.isEmpty) return null;

    try {
      final collarDoc =
          await _db.collection('collars').doc(normalizedDeviceId).get();
      final propertyId = _idFromRefOrPath(
        (collarDoc.data() ?? const <String, dynamic>{})['propertyId'],
      );
      if (propertyId.isEmpty) return null;
      final propertyKey = _sanitizeRtdbKey(propertyId);
      final snap = await _rtdb
          .ref('propertyTelemetryLatest/$propertyKey/$sanitizedDeviceId')
          .get();
      final value = snap.value;
      if (value is! Map) return null;
      final lat = _toFiniteCoord(value['lat']);
      final lon = _toFiniteCoord(value['lon']);
      if (lat == null ||
          lon == null ||
          lat < -90 ||
          lat > 90 ||
          lon < -180 ||
          lon > 180) {
        return null;
      }
      return <String, double>{
        'lat': lat,
        'lon': lon,
      };
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _decodeLatestTelemetryEntry(dynamic raw) {
    if (raw is! Map) return null;
    final lat = _toFiniteCoord(raw['lat']);
    final lon = _toFiniteCoord(raw['lon']);
    if (lat == null ||
        lon == null ||
        lat < -90 ||
        lat > 90 ||
        lon < -180 ||
        lon > 180) {
      return null;
    }
    final out = <String, dynamic>{
      'lat': lat,
      'lon': lon,
    };
    final receivedAtMs =
        _coerceTimestampMs(raw['receivedAtMs'] ?? raw['receivedAt']);
    if (receivedAtMs > 0) out['telemetryReceivedAtMs'] = receivedAtMs;
    return out;
  }

  Stream<Map<String, dynamic>?> streamLatestTelemetryEntryForDevice({
    required String propertyId,
    required String deviceId,
  }) {
    final propertyKey = _sanitizeRtdbKey(propertyId);
    final normalizedDeviceId = _normalizeLoraDeviceId(deviceId);
    if (propertyKey.isEmpty || normalizedDeviceId == null) {
      return Stream.value(null);
    }
    final deviceKey = _sanitizeRtdbKey(normalizedDeviceId);
    if (deviceKey.isEmpty) return Stream.value(null);

    return _rtdb
        .ref('propertyTelemetryLatest/$propertyKey/$deviceKey')
        .onValue
        .map((event) => _decodeLatestTelemetryEntry(event.snapshot.value));
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
  }) async {
    // Fluxo legado desativado: uplink LoRa autoritativo e persistido apenas pela matriz.
    return;
  }

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
  }) async {
    // Fluxo legado desativado: health uplink autoritativo e persistido apenas pela matriz.
    return;
  }

  Future<void> cleanupTelemetryRetentionForDevices(
    Iterable<String> rawDeviceIds, {
    int? nowMs,
  }) async {
    // O retention do RTDB property-scoped e feito pela matriz/backend.
    return;
  }

  Stream<List<DeviceModel>> _streamFirestoreDevices(
      {required String uid, required bool isAdmin}) {
    if (isAdmin) {
      return _db.collection('collars').snapshots().map(
            (s) =>
                s.docs.map((d) => DeviceModel.fromMap(d.id, d.data())).toList(),
          );
    }

    final userRef = _userRef(uid);
    final userPath = _userPath(uid);
    final q1 = _db.collection('collars').where('ownerUid', isEqualTo: userRef);
    final q2 = _db.collection('collars').where('ownerUid', isEqualTo: userPath);
    final q3 = _db.collection('collars').where('ownerUid', isEqualTo: uid);

    return Stream.multi((controller) {
      List<QueryDocumentSnapshot<Map<String, dynamic>>> d1 = const [];
      List<QueryDocumentSnapshot<Map<String, dynamic>>> d2 = const [];
      List<QueryDocumentSnapshot<Map<String, dynamic>>> d3 = const [];
      void emit() {
        final byId = <String, DeviceModel>{};
        for (final d in [...d1, ...d2, ...d3]) {
          byId[d.id] = DeviceModel.fromMap(d.id, d.data());
        }
        controller.add(byId.values.toList());
      }

      final s1 = q1.snapshots().listen((snap) {
        d1 = snap.docs;
        emit();
      }, onError: controller.addError);
      final s2 = q2.snapshots().listen((snap) {
        d2 = snap.docs;
        emit();
      }, onError: controller.addError);
      final s3 = q3.snapshots().listen((snap) {
        d3 = snap.docs;
        emit();
      }, onError: controller.addError);

      controller.onCancel = () async {
        await s1.cancel();
        await s2.cancel();
        await s3.cancel();
      };
    });
  }

  Stream<List<DeviceModel>> streamDevices(
      {required String uid, required bool isAdmin}) {
    final firestoreStream = _streamFirestoreDevices(uid: uid, isAdmin: isAdmin);
    final propertiesStream = streamRuralProperties(uid: uid, isAdmin: isAdmin);
    return Stream.multi((controller) {
      List<DeviceModel> devices = const <DeviceModel>[];
      Map<String, Map<String, Map<String, dynamic>>> liveByPropertyId =
          const <String, Map<String, Map<String, dynamic>>>{};
      Map<String, Map<String, Map<String, dynamic>>> healthByPropertyId =
          const <String, Map<String, Map<String, dynamic>>>{};
      Map<String, Map<String, Map<String, dynamic>>> eventByPropertyId =
          const <String, Map<String, Map<String, dynamic>>>{};
      final telemetrySubsByPropertyKey =
          <String, StreamSubscription<rtdb.DatabaseEvent>>{};
      final healthSubsByPropertyKey =
          <String, StreamSubscription<rtdb.DatabaseEvent>>{};
      final eventSubsByPropertyKey =
          <String, StreamSubscription<rtdb.DatabaseEvent>>{};
      final activePropertyKeys = <String>{};

      void emit() {
        controller.add(
          mergeDevicesWithScopedLiveTelemetry(
            devices: devices,
            liveByPropertyId: liveByPropertyId,
            healthByPropertyId: healthByPropertyId,
            eventByPropertyId: eventByPropertyId,
          ),
        );
      }

      Future<void> reconcilePropertyFeeds(List<String> propertyIds) async {
        final desiredPropertyKeys = propertyIds
            .map(_sanitizeRtdbKey)
            .where((key) => key.isNotEmpty)
            .toSet();
        if (activePropertyKeys.length == desiredPropertyKeys.length &&
            activePropertyKeys.containsAll(desiredPropertyKeys)) {
          return;
        }

        final removedPropertyKeys =
            activePropertyKeys.difference(desiredPropertyKeys).toList()..sort();
        for (final propertyKey in removedPropertyKeys) {
          final telemetrySub = telemetrySubsByPropertyKey.remove(propertyKey);
          if (telemetrySub != null) {
            await telemetrySub.cancel();
          }
          final healthSub = healthSubsByPropertyKey.remove(propertyKey);
          if (healthSub != null) {
            await healthSub.cancel();
          }
          final eventSub = eventSubsByPropertyKey.remove(propertyKey);
          if (eventSub != null) {
            await eventSub.cancel();
          }

          if (liveByPropertyId.containsKey(propertyKey)) {
            final next = Map<String, Map<String, Map<String, dynamic>>>.from(
              liveByPropertyId,
            );
            next.remove(propertyKey);
            liveByPropertyId = next;
          }
          if (healthByPropertyId.containsKey(propertyKey)) {
            final next = Map<String, Map<String, Map<String, dynamic>>>.from(
              healthByPropertyId,
            );
            next.remove(propertyKey);
            healthByPropertyId = next;
          }
          if (eventByPropertyId.containsKey(propertyKey)) {
            final next = Map<String, Map<String, Map<String, dynamic>>>.from(
              eventByPropertyId,
            );
            next.remove(propertyKey);
            eventByPropertyId = next;
          }
        }

        final addedPropertyKeys =
            desiredPropertyKeys.difference(activePropertyKeys).toList()..sort();
        for (final propertyKey in addedPropertyKeys) {
          telemetrySubsByPropertyKey[propertyKey] =
              _rtdb.ref('propertyTelemetryLatest/$propertyKey').onValue.listen(
            (event) {
              liveByPropertyId = {
                ...liveByPropertyId,
                propertyKey: _decodeTelemetryLatestDetailsSnapshot(
                  event.snapshot.value,
                ),
              };
              emit();
            },
            onError: (_) {
              liveByPropertyId = {
                ...liveByPropertyId,
                propertyKey: const <String, Map<String, dynamic>>{},
              };
              emit();
            },
          );

          healthSubsByPropertyKey[propertyKey] =
              _rtdb.ref('propertyHealthLatest/$propertyKey').onValue.listen(
            (event) {
              healthByPropertyId = {
                ...healthByPropertyId,
                propertyKey: _decodeHealthLatestSnapshot(
                  event.snapshot.value,
                ),
              };
              emit();
            },
            onError: (_) {
              healthByPropertyId = {
                ...healthByPropertyId,
                propertyKey: const <String, Map<String, dynamic>>{},
              };
              emit();
            },
          );

          eventSubsByPropertyKey[propertyKey] =
              _rtdb.ref('propertyEvents/$propertyKey').onValue.listen(
            (event) {
              eventByPropertyId = {
                ...eventByPropertyId,
                propertyKey: _decodeLatestEventPositionSnapshot(
                  event.snapshot.value,
                ),
              };
              emit();
            },
            onError: (_) {
              eventByPropertyId = {
                ...eventByPropertyId,
                propertyKey: const <String, Map<String, dynamic>>{},
              };
              emit();
            },
          );
        }

        activePropertyKeys
          ..clear()
          ..addAll(desiredPropertyKeys);
        emit();
      }

      final firestoreSub = firestoreStream.listen(
        (next) {
          devices = next;
          emit();
        },
        onError: controller.addError,
      );
      final propertySub = propertiesStream.listen(
        (properties) {
          final propertyIds = properties
              .map((property) => _idFromRefOrPath(property['id']))
              .where((id) => id.isNotEmpty)
              .toList()
            ..sort();
          unawaited(reconcilePropertyFeeds(propertyIds));
        },
        onError: controller.addError,
      );

      controller.onCancel = () async {
        await firestoreSub.cancel();
        await propertySub.cancel();
        for (final sub in telemetrySubsByPropertyKey.values) {
          await sub.cancel();
        }
        for (final sub in healthSubsByPropertyKey.values) {
          await sub.cancel();
        }
        for (final sub in eventSubsByPropertyKey.values) {
          await sub.cancel();
        }
      };
    });
  }

  Stream<List<Map<String, dynamic>>> streamGateways(
      {required String uid, required bool isAdmin}) {
    if (isAdmin) {
      return _db.collection('gateways').snapshots().map((s) {
        return s.docs.map((d) {
          final data = d.data();
          return {
            'id': d.id,
            ...data,
            'lat': _latFromPosition(data),
            'lon': _lonFromPosition(data),
            'propertyId': _idFromRefOrPath(data['propertyId']),
            'wifi_ota_enabled': data['wifi_ota_enabled'] is bool
                ? data['wifi_ota_enabled']
                : true,
            'is_matrix': data['is_matrix'] is bool ? data['is_matrix'] : false,
          };
        }).toList();
      });
    }

    final userRef = _userRef(uid);
    final userPath = '/users/$uid';
    final q1 =
        _db.collection('gateways').where('userUids', arrayContains: userRef);
    final q2 =
        _db.collection('gateways').where('userUids', arrayContains: userPath);
    final q3 = _db.collection('gateways').where('userUids', arrayContains: uid);

    return Stream.multi((controller) {
      List<QueryDocumentSnapshot<Map<String, dynamic>>> d1 = const [];
      List<QueryDocumentSnapshot<Map<String, dynamic>>> d2 = const [];
      List<QueryDocumentSnapshot<Map<String, dynamic>>> d3 = const [];

      void emit() {
        final byId = <String, Map<String, dynamic>>{};
        for (final d in [...d1, ...d2, ...d3]) {
          final data = d.data();
          byId[d.id] = {
            'id': d.id,
            ...data,
            'lat': _latFromPosition(data),
            'lon': _lonFromPosition(data),
            'propertyId': _idFromRefOrPath(data['propertyId']),
            'wifi_ota_enabled': data['wifi_ota_enabled'] is bool
                ? data['wifi_ota_enabled']
                : true,
            'is_matrix': data['is_matrix'] is bool ? data['is_matrix'] : false,
          };
        }
        controller.add(byId.values.toList());
      }

      void onQueryError(Object error, StackTrace stackTrace) {
        if (error is FirebaseException && error.code == 'permission-denied') {
          return;
        }
        controller.addError(error, stackTrace);
      }

      final s1 = q1.snapshots().listen((snap) {
        d1 = snap.docs;
        emit();
      }, onError: onQueryError);
      final s2 = q2.snapshots().listen((snap) {
        d2 = snap.docs;
        emit();
      }, onError: onQueryError);
      final s3 = q3.snapshots().listen((snap) {
        d3 = snap.docs;
        emit();
      }, onError: onQueryError);

      controller.onCancel = () async {
        await s1.cancel();
        await s2.cancel();
        await s3.cancel();
      };
    });
  }

  Stream<Map<String, Map<String, double>>> streamPropertyTelemetry(
    String propertyId,
  ) {
    final propertyKey = _sanitizeRtdbKey(propertyId);
    if (propertyKey.isEmpty) {
      return Stream.value(const <String, Map<String, double>>{});
    }
    return _rtdb.ref('propertyTelemetryLatest/$propertyKey').onValue.map(
          (event) => _decodeTelemetryLatestSnapshot(event.snapshot.value),
        );
  }

  Stream<Map<String, Map<String, dynamic>>> streamPropertyHealth(
    String propertyId,
  ) {
    final propertyKey = _sanitizeRtdbKey(propertyId);
    if (propertyKey.isEmpty) {
      return Stream.value(const <String, Map<String, dynamic>>{});
    }
    return _rtdb.ref('propertyHealthLatest/$propertyKey').onValue.map(
          (event) => _decodeHealthLatestSnapshot(event.snapshot.value),
        );
  }

  Stream<List<Map<String, dynamic>>> streamPropertyEvents(
    String propertyId, {
    int limit = 200,
  }) {
    final propertyKey = _sanitizeRtdbKey(propertyId);
    if (propertyKey.isEmpty) {
      return Stream.value(const <Map<String, dynamic>>[]);
    }

    return _rtdb.ref('propertyEvents/$propertyKey').onValue.map((event) {
      final root = event.snapshot.value;
      if (root is! Map) return const <Map<String, dynamic>>[];
      final items = <Map<String, dynamic>>[];
      for (final dayEntry in root.entries) {
        final dayKey = dayEntry.key?.toString().trim() ?? '';
        final dayMap = dayEntry.value;
        if (dayKey.isEmpty || dayMap is! Map) continue;
        for (final eventEntry in dayMap.entries) {
          final eventId = eventEntry.key?.toString().trim() ?? '';
          final value = eventEntry.value;
          if (eventId.isEmpty || value is! Map) continue;
          items.add({
            'id': eventId,
            'dayKey': dayKey,
            ...Map<String, dynamic>.from(value),
          });
        }
      }
      items.sort((a, b) => _eventSortKeyMs(b).compareTo(_eventSortKeyMs(a)));
      if (items.length <= limit) return items;
      return items.take(limit).toList();
    });
  }

  Future<List<Map<String, dynamic>>> getCollarFirebaseLog({
    required String propertyId,
    required String deviceId,
  }) async {
    final propertyKey = _sanitizeRtdbKey(propertyId);
    final normalizedDeviceId = _normalizeLoraDeviceId(deviceId);
    if (propertyKey.isEmpty || normalizedDeviceId == null) {
      return const <Map<String, dynamic>>[];
    }
    final deviceKey = _sanitizeRtdbKey(normalizedDeviceId);
    if (deviceKey.isEmpty) return const <Map<String, dynamic>>[];

    final latestTelemetrySnap = await _rtdb
        .ref('propertyTelemetryLatest/$propertyKey/$deviceKey')
        .get();
    final telemetrySnap = await _rtdb
        .ref('propertyTelemetryHistory/$propertyKey/$deviceKey')
        .get();
    final healthSnap =
        await _rtdb.ref('propertyHealthHistory/$propertyKey/$deviceKey').get();
    final eventsSnap = await _rtdb.ref('propertyEvents/$propertyKey').get();

    return _mergeCollarFirebaseLogItems(
      propertyId: propertyId,
      normalizedDeviceId: normalizedDeviceId,
      latestTelemetryRaw: latestTelemetrySnap.value,
      telemetryHistoryRaw: telemetrySnap.value,
      healthHistoryRaw: healthSnap.value,
      eventsRaw: eventsSnap.value,
    );
  }

  Stream<List<Map<String, dynamic>>> streamCollarFirebaseLog({
    required String propertyId,
    required String deviceId,
  }) {
    final propertyKey = _sanitizeRtdbKey(propertyId);
    final normalizedDeviceId = _normalizeLoraDeviceId(deviceId);
    if (propertyKey.isEmpty || normalizedDeviceId == null) {
      return Stream.value(const <Map<String, dynamic>>[]);
    }
    final deviceKey = _sanitizeRtdbKey(normalizedDeviceId);
    if (deviceKey.isEmpty) return Stream.value(const <Map<String, dynamic>>[]);

    return Stream.multi((controller) {
      dynamic latestTelemetryRaw;
      dynamic telemetryHistoryRaw;
      dynamic healthHistoryRaw;
      dynamic eventsRaw;

      void emit() {
        controller.add(
          _mergeCollarFirebaseLogItems(
            propertyId: propertyId,
            normalizedDeviceId: normalizedDeviceId,
            latestTelemetryRaw: latestTelemetryRaw,
            telemetryHistoryRaw: telemetryHistoryRaw,
            healthHistoryRaw: healthHistoryRaw,
            eventsRaw: eventsRaw,
          ),
        );
      }

      final latestTelemetrySub = _rtdb
          .ref('propertyTelemetryLatest/$propertyKey/$deviceKey')
          .onValue
          .listen(
        (event) {
          latestTelemetryRaw = event.snapshot.value;
          emit();
        },
        onError: controller.addError,
      );
      final telemetrySub = _rtdb
          .ref('propertyTelemetryHistory/$propertyKey/$deviceKey')
          .onValue
          .listen(
        (event) {
          telemetryHistoryRaw = event.snapshot.value;
          emit();
        },
        onError: controller.addError,
      );
      final healthSub = _rtdb
          .ref('propertyHealthHistory/$propertyKey/$deviceKey')
          .onValue
          .listen(
        (event) {
          healthHistoryRaw = event.snapshot.value;
          emit();
        },
        onError: controller.addError,
      );
      final eventsSub = _rtdb.ref('propertyEvents/$propertyKey').onValue.listen(
        (event) {
          eventsRaw = event.snapshot.value;
          emit();
        },
        onError: controller.addError,
      );

      controller.onCancel = () async {
        await latestTelemetrySub.cancel();
        await telemetrySub.cancel();
        await healthSub.cancel();
        await eventsSub.cancel();
      };
    });
  }

  Stream<List<Map<String, dynamic>>> streamRuralProperties(
      {required String uid, required bool isAdmin}) {
    if (isAdmin) {
      return _db.collection('ruralProperties').snapshots().map(
            (s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList(),
          );
    }

    final userRef = _userRef(uid);
    final userPath = _userPath(uid);
    final ownerQueryRef = _db
        .collection('ruralProperties')
        .where('createdByUid', isEqualTo: userRef);
    final ownerQueryPath = _db
        .collection('ruralProperties')
        .where('createdByUid', isEqualTo: userPath);
    final ownerQueryUid =
        _db.collection('ruralProperties').where('createdByUid', isEqualTo: uid);
    final ownerUidQueryRef =
        _db.collection('ruralProperties').where('ownerUid', isEqualTo: userRef);
    final ownerUidQueryPath = _db
        .collection('ruralProperties')
        .where('ownerUid', isEqualTo: userPath);
    final ownerUidQueryUid =
        _db.collection('ruralProperties').where('ownerUid', isEqualTo: uid);
    final linkedQueryRef = _db
        .collection('ruralProperties')
        .where('userUids', arrayContains: userRef);
    final linkedQueryPath = _db
        .collection('ruralProperties')
        .where('userUids', arrayContains: userPath);
    final linkedQueryUid =
        _db.collection('ruralProperties').where('userUids', arrayContains: uid);

    return Stream.multi((controller) {
      List<QueryDocumentSnapshot<Map<String, dynamic>>> ownerDocsRef = const [];
      List<QueryDocumentSnapshot<Map<String, dynamic>>> ownerDocsPath =
          const [];
      List<QueryDocumentSnapshot<Map<String, dynamic>>> ownerDocsUid = const [];
      List<QueryDocumentSnapshot<Map<String, dynamic>>> ownerUidDocsRef =
          const [];
      List<QueryDocumentSnapshot<Map<String, dynamic>>> ownerUidDocsPath =
          const [];
      List<QueryDocumentSnapshot<Map<String, dynamic>>> ownerUidDocsUid =
          const [];
      List<QueryDocumentSnapshot<Map<String, dynamic>>> linkedDocsRef =
          const [];
      List<QueryDocumentSnapshot<Map<String, dynamic>>> linkedDocsPath =
          const [];
      List<QueryDocumentSnapshot<Map<String, dynamic>>> linkedDocsUid =
          const [];

      void emit() {
        final byId = <String, Map<String, dynamic>>{};
        for (final d in [
          ...ownerDocsRef,
          ...ownerDocsPath,
          ...ownerDocsUid,
          ...ownerUidDocsRef,
          ...ownerUidDocsPath,
          ...ownerUidDocsUid,
          ...linkedDocsRef,
          ...linkedDocsPath,
          ...linkedDocsUid,
        ]) {
          byId[d.id] = {'id': d.id, ...d.data()};
        }
        controller.add(byId.values.toList());
      }

      final sub1 = ownerQueryRef.snapshots().listen(
        (snap) {
          ownerDocsRef = snap.docs;
          emit();
        },
        onError: controller.addError,
      );
      final sub2 = ownerQueryPath.snapshots().listen(
        (snap) {
          ownerDocsPath = snap.docs;
          emit();
        },
        onError: controller.addError,
      );
      final sub3 = ownerQueryUid.snapshots().listen(
        (snap) {
          ownerDocsUid = snap.docs;
          emit();
        },
        onError: controller.addError,
      );
      final sub4 = ownerUidQueryRef.snapshots().listen(
        (snap) {
          ownerUidDocsRef = snap.docs;
          emit();
        },
        onError: controller.addError,
      );
      final sub5 = ownerUidQueryPath.snapshots().listen(
        (snap) {
          ownerUidDocsPath = snap.docs;
          emit();
        },
        onError: controller.addError,
      );
      final sub6 = ownerUidQueryUid.snapshots().listen(
        (snap) {
          ownerUidDocsUid = snap.docs;
          emit();
        },
        onError: controller.addError,
      );
      final sub7 = linkedQueryRef.snapshots().listen(
        (snap) {
          linkedDocsRef = snap.docs;
          emit();
        },
        onError: controller.addError,
      );
      final sub8 = linkedQueryPath.snapshots().listen(
        (snap) {
          linkedDocsPath = snap.docs;
          emit();
        },
        onError: controller.addError,
      );
      final sub9 = linkedQueryUid.snapshots().listen(
        (snap) {
          linkedDocsUid = snap.docs;
          emit();
        },
        onError: controller.addError,
      );

      controller.onCancel = () async {
        await sub1.cancel();
        await sub2.cancel();
        await sub3.cancel();
        await sub4.cancel();
        await sub5.cancel();
        await sub6.cancel();
        await sub7.cancel();
        await sub8.cancel();
        await sub9.cancel();
      };
    });
  }

  Stream<List<Map<String, dynamic>>> streamAreas(
      {required String uid, required bool isAdmin}) {
    if (isAdmin) {
      return _db.collection('areas').snapshots().map((s) {
        return s.docs
            .map((d) => {
                  'id': d.id,
                  ...d.data(),
                  'propertyId': _idFromRefOrPath(d.data()['ruralPropertiesID']),
                })
            .toList();
      });
    }

    final userRef = _userRef(uid);
    final userPath = '/users/$uid';
    final q1 =
        _db.collection('areas').where('userUids', arrayContains: userRef);
    final q2 =
        _db.collection('areas').where('userUids', arrayContains: userPath);
    final q3 = _db.collection('areas').where('userUids', arrayContains: uid);

    return Stream.multi((controller) {
      List<QueryDocumentSnapshot<Map<String, dynamic>>> d1 = const [];
      List<QueryDocumentSnapshot<Map<String, dynamic>>> d2 = const [];
      List<QueryDocumentSnapshot<Map<String, dynamic>>> d3 = const [];

      void emit() {
        final byId = <String, Map<String, dynamic>>{};
        for (final d in [...d1, ...d2, ...d3]) {
          final data = d.data();
          byId[d.id] = {
            'id': d.id,
            ...data,
            'propertyId': _idFromRefOrPath(data['ruralPropertiesID']),
          };
        }
        controller.add(byId.values.toList());
      }

      void onQueryError(Object error, StackTrace stackTrace) {
        if (error is FirebaseException && error.code == 'permission-denied') {
          return;
        }
        controller.addError(error, stackTrace);
      }

      final s1 = q1.snapshots().listen((snap) {
        d1 = snap.docs;
        emit();
      }, onError: onQueryError);
      final s2 = q2.snapshots().listen((snap) {
        d2 = snap.docs;
        emit();
      }, onError: onQueryError);
      final s3 = q3.snapshots().listen((snap) {
        d3 = snap.docs;
        emit();
      }, onError: onQueryError);

      controller.onCancel = () async {
        await s1.cancel();
        await s2.cancel();
        await s3.cancel();
      };
    });
  }

  Stream<List<Map<String, dynamic>>> streamCriticalEvents({
    required String uid,
    required bool isAdmin,
  }) {
    if (isAdmin) {
      return _db
          .collection('events')
          .orderBy('createdAt', descending: true)
          .limit(300)
          .snapshots()
          .map((s) => s.docs.map(_eventFromDoc).toList());
    }

    final userRef = _userRef(uid);
    final userPath = _userPath(uid);
    final q1 = _db.collection('events').where('ownerUid', isEqualTo: userRef);
    final q2 = _db.collection('events').where('ownerUid', isEqualTo: userPath);
    final q3 = _db.collection('events').where('ownerUid', isEqualTo: uid);

    return Stream.multi((controller) {
      List<QueryDocumentSnapshot<Map<String, dynamic>>> d1 = const [];
      List<QueryDocumentSnapshot<Map<String, dynamic>>> d2 = const [];
      List<QueryDocumentSnapshot<Map<String, dynamic>>> d3 = const [];

      void emit() {
        final byId = <String, Map<String, dynamic>>{};
        for (final d in [...d1, ...d2, ...d3]) {
          byId[d.id] = _eventFromDoc(d);
        }
        final merged = byId.values.toList();
        merged.sort(
          (a, b) => _eventSortKeyMs(b).compareTo(_eventSortKeyMs(a)),
        );
        controller.add(merged);
      }

      final s1 = q1.snapshots().listen(
        (snap) {
          d1 = snap.docs;
          emit();
        },
        onError: controller.addError,
      );
      final s2 = q2.snapshots().listen(
        (snap) {
          d2 = snap.docs;
          emit();
        },
        onError: controller.addError,
      );
      final s3 = q3.snapshots().listen(
        (snap) {
          d3 = snap.docs;
          emit();
        },
        onError: controller.addError,
      );

      controller.onCancel = () async {
        await s1.cancel();
        await s2.cancel();
        await s3.cancel();
      };
    });
  }

  Stream<List<HerdingOperationModel>> streamHerdingOperations({
    required String uid,
    required bool isAdmin,
  }) {
    Query<Map<String, dynamic>> query = _db.collection('herdingOperations');
    if (!isAdmin) {
      query = query.where('notifyUserIds', arrayContains: uid);
    }

    return query.snapshots().map((snapshot) {
      final operations =
          snapshot.docs.map(HerdingOperationModel.fromDoc).toList()
            ..sort(
              (a, b) => _herdingOperationSortKeyMs(b)
                  .compareTo(_herdingOperationSortKeyMs(a)),
            );
      return operations;
    });
  }

  Stream<HerdingOperationModel?> streamHerdingOperation(String operationId) {
    final normalizedId = _idFromRefOrPath(operationId);
    if (normalizedId.isEmpty) return Stream.value(null);
    return _db
        .collection('herdingOperations')
        .doc(normalizedId)
        .snapshots()
        .map(
      (snapshot) {
        if (!snapshot.exists) return null;
        return HerdingOperationModel.fromDoc(snapshot);
      },
    );
  }

  Future<List<Map<String, dynamic>>> getRuralProperties(
      {required String uid, required bool isAdmin}) async {
    if (isAdmin) {
      final s = await _db.collection('ruralProperties').get();
      return s.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    }

    final userRef = _userRef(uid);
    final userPath = _userPath(uid);
    final ownerRef = await _db
        .collection('ruralProperties')
        .where('createdByUid', isEqualTo: userRef)
        .get();
    final ownerPath = await _db
        .collection('ruralProperties')
        .where('createdByUid', isEqualTo: userPath)
        .get();
    final ownerUid = await _db
        .collection('ruralProperties')
        .where('createdByUid', isEqualTo: uid)
        .get();
    final byOwnerRef = await _db
        .collection('ruralProperties')
        .where('ownerUid', isEqualTo: userRef)
        .get();
    final byOwnerPath = await _db
        .collection('ruralProperties')
        .where('ownerUid', isEqualTo: userPath)
        .get();
    final byOwnerUid = await _db
        .collection('ruralProperties')
        .where('ownerUid', isEqualTo: uid)
        .get();
    final linkedRef = await _db
        .collection('ruralProperties')
        .where('userUids', arrayContains: userRef)
        .get();
    final linkedPath = await _db
        .collection('ruralProperties')
        .where('userUids', arrayContains: userPath)
        .get();
    final linkedUid = await _db
        .collection('ruralProperties')
        .where('userUids', arrayContains: uid)
        .get();

    final byId = <String, Map<String, dynamic>>{};
    for (final d in [
      ...ownerRef.docs,
      ...ownerPath.docs,
      ...ownerUid.docs,
      ...byOwnerRef.docs,
      ...byOwnerPath.docs,
      ...byOwnerUid.docs,
      ...linkedRef.docs,
      ...linkedPath.docs,
      ...linkedUid.docs,
    ]) {
      byId[d.id] = {'id': d.id, ...d.data()};
    }
    return byId.values.toList();
  }

  Future<List<DocumentReference<Map<String, dynamic>>>>
      _resolveAdminRefs() async {
    final snap =
        await _db.collection('users').where('role', isEqualTo: 'adm').get();
    return snap.docs.map((d) => d.reference).toList();
  }

  Future<Map<String, DocumentReference<Map<String, dynamic>>>>
      _resolveUserRefsByEmailsStrict(List<String> emails) async {
    final normalized = emails
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet();
    if (normalized.isEmpty) return {};

    final found = <String, DocumentReference<Map<String, dynamic>>>{};

    // Fast path: exact indexed lookup by email.
    final snapshots = await Future.wait(
      normalized.map(
        (email) => _db
            .collection('users')
            .where('email', isEqualTo: email)
            .limit(1)
            .get(),
      ),
    );
    for (final snap in snapshots) {
      if (snap.docs.isEmpty) continue;
      final doc = snap.docs.first;
      final docEmail = (doc.data()['email'] as String?)?.trim().toLowerCase();
      if (docEmail != null && docEmail.isNotEmpty) {
        found[docEmail] = doc.reference;
      }
    }

    // Fallback for legacy docs that may have non-normalized email values.
    final missing = normalized.where((e) => !found.containsKey(e)).toSet();
    if (missing.isNotEmpty) {
      final allUsers = await _db.collection('users').get();
      for (final doc in allUsers.docs) {
        final rawEmail = (doc.data()['email'] as String?)?.trim().toLowerCase();
        if (rawEmail == null || rawEmail.isEmpty) continue;
        if (missing.contains(rawEmail)) {
          found[rawEmail] = doc.reference;
        }
      }
    }

    return found;
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
    final linkedUsers = <DocumentReference<Map<String, dynamic>>>{
      _userRef(normalizedOwnerUid)
    };
    if (normalizedCreatorUid.isNotEmpty) {
      linkedUsers.add(_userRef(normalizedCreatorUid));
    }

    if (isAdmin) {
      final resolvedByEmail = await _resolveUserRefsByEmailsStrict(userEmails);
      final requestedEmails = userEmails
          .map((e) => e.trim().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toSet();
      final missingEmails = requestedEmails
          .where((e) => !resolvedByEmail.containsKey(e))
          .toList();

      if (missingEmails.isNotEmpty) {
        throw Exception(
          'Usuarios nao encontrados para os emails: ${missingEmails.join(', ')}',
        );
      }

      linkedUsers.addAll(resolvedByEmail.values);
      linkedUsers.addAll(await _resolveAdminRefs());
    }

    if (linkedUsers.isEmpty) {
      throw Exception('Informe ao menos um email de usuario valido.');
    }

    final docRef = _db.collection('ruralProperties').doc();
    final propertyScopeId = _computePropertyScopeId(docRef.id);
    await docRef.set({
      'name': name,
      'points': _encodeLatLonPoints(points),
      'userUids': linkedUsers.toList(),
      'ownerUid': _userRef(normalizedOwnerUid),
      'createdByUid': _userRef(normalizedOwnerUid),
      'updatedByUid': _userRef(
        normalizedCreatorUid.isNotEmpty
            ? normalizedCreatorUid
            : normalizedOwnerUid,
      ),
      'propertyScopeId': propertyScopeId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    try {
      await repairFirebaseMirrors(apply: true, propertyId: docRef.id);
    } catch (_) {
      // Cadastro da propriedade nao pode falhar se o backend de mirror estiver indisponivel.
    }
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
    final normalizedOwnerUid = _idFromRefOrPath(ownerUid);
    if (normalizedOwnerUid.isEmpty) {
      throw Exception('Dono da propriedade invalido.');
    }
    final update = <String, dynamic>{
      'name': name,
      'points': _encodeLatLonPoints(points),
      'ownerUid': _userRef(normalizedOwnerUid),
      'createdByUid': _userRef(normalizedOwnerUid),
      'updatedByUid': _userRef(
        _idFromRefOrPath(editorUid).isNotEmpty
            ? _idFromRefOrPath(editorUid)
            : normalizedOwnerUid,
      ),
      'propertyScopeId': _computePropertyScopeId(id),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (isAdmin) {
      final linkedUsers = <DocumentReference<Map<String, dynamic>>>{};
      linkedUsers.add(_userRef(normalizedOwnerUid));
      final editorId = _idFromRefOrPath(editorUid);
      if (editorId.isNotEmpty) {
        linkedUsers.add(_userRef(editorId));
      }

      final resolvedByEmail = await _resolveUserRefsByEmailsStrict(userEmails);
      final requestedEmails = userEmails
          .map((e) => e.trim().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toSet();
      final missingEmails = requestedEmails
          .where((e) => !resolvedByEmail.containsKey(e))
          .toList();

      if (missingEmails.isNotEmpty) {
        throw Exception(
          'Usuarios nao encontrados para os emails: ${missingEmails.join(', ')}',
        );
      }

      linkedUsers.addAll(resolvedByEmail.values);
      linkedUsers.addAll(await _resolveAdminRefs());

      if (linkedUsers.isEmpty) {
        throw Exception('Informe ao menos um email de usuario valido.');
      }

      update['userUids'] = linkedUsers.toList();
    }

    await _db
        .collection('ruralProperties')
        .doc(id)
        .set(update, SetOptions(merge: true));
    try {
      await repairFirebaseMirrors(apply: true, propertyId: id);
    } catch (_) {
      // Mantem o update do cadastro mesmo quando o backend de mirror estiver fora.
    }
  }

  Future<void> addArea({
    required String ownerUid,
    required String ruralPropertyId,
    required List<List<double>> perimeter,
    String? updatedByUid,
    List<String> linkedDeviceIds = const <String>[],
  }) async {
    final linkedUsers = await _linkedUsersForProperty(ruralPropertyId);
    final normalizedOwnerUid = _idFromRefOrPath(ownerUid);
    final normalizedUpdatedByUid = _idFromRefOrPath(updatedByUid);
    await _db.collection('areas').add({
      'ownerUid': _userRef(normalizedOwnerUid),
      'ruralPropertiesID': _propertyRefOrNull(ruralPropertyId),
      'userUids': linkedUsers,
      'perimeter': _encodeLatLonPoints(perimeter),
      'linkedDeviceIds': _normalizeLoraDeviceIds(linkedDeviceIds),
      'updatedByUid': _userRef(
        normalizedUpdatedByUid.isNotEmpty
            ? normalizedUpdatedByUid
            : normalizedOwnerUid,
      ),
      'updatedAt': FieldValue.serverTimestamp(),
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
        .map((id) => _normalizeLoraDeviceId(id))
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

    if (normalizedOwnerUid.isEmpty ||
        normalizedRequestedByUid.isEmpty ||
        normalizedPropertyId.isEmpty ||
        normalizedMatrixGatewayId.isEmpty) {
      throw Exception(
          'Dados obrigatorios do arrebanhamento estao incompletos.');
    }
    if (normalizedDeviceIds.isEmpty) {
      throw Exception('Selecione ao menos uma coleira para o arrebanhamento.');
    }
    if (targetPolygon.length < 3) {
      throw Exception('Informe um poligono destino com ao menos 3 pontos.');
    }

    final docRef = _db.collection('herdingOperations').doc();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final deviceStatuses = <String, Map<String, dynamic>>{};
    for (final deviceId in normalizedDeviceIds) {
      deviceStatuses[deviceId] = <String, dynamic>{
        'status': 'pending',
        'retryCount': 0,
        'updatedAtMs': nowMs,
      };
    }

    await docRef.set({
      'operationId': docRef.id,
      'ownerUid': _userRef(normalizedOwnerUid),
      'requestedByUid': _userRef(normalizedRequestedByUid),
      'requestedByRole': requestedByRole.trim().isEmpty
          ? 'user'
          : requestedByRole.trim().toLowerCase(),
      'propertyId': normalizedPropertyId,
      'matrixGatewayId': normalizedMatrixGatewayId,
      'status': herdingOperationStatusValue(HerdingOperationStatus.submitted),
      'targetPolygon': _encodeLatLonPoints(targetPolygon),
      'selectedDeviceIds': normalizedDeviceIds,
      'notifyUserIds': normalizedNotifyUserIds,
      'deviceStatuses': deviceStatuses,
      'areaPromotionRequested': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return docRef.id;
  }

  Future<void> markHerdingOperationSubmissionFailed({
    required String operationId,
    required String reason,
  }) async {
    final normalizedId = _idFromRefOrPath(operationId);
    if (normalizedId.isEmpty) return;
    await _db.collection('herdingOperations').doc(normalizedId).set({
      'status': herdingOperationStatusValue(HerdingOperationStatus.failed),
      'clientFailureReason': reason,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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
    final normalizedGatewayId = gatewayId == null || gatewayId.trim().isEmpty
        ? null
        : _idFromRefOrPath(gatewayId);
    final position = (lat != null && lon != null) ? [lat, lon] : null;

    final collection = _db.collection('collars');
    final docRef = collection.doc(normalizedDeviceId);
    final payload = {
      'ownerUid': _userRef(ownerUid),
      'name': name,
      'status': status,
      'deviceId': normalizedDeviceId,
      'position': position,
      'gatewayId': normalizedGatewayId,
      'propertyId': _propertyRefOrNull(propertyId),
      'wifi_ota_enabled': true,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await docRef.set(payload, SetOptions(merge: true));
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
    final linkedUsers = propertyId == null
        ? const <DocumentReference<Map<String, dynamic>>>[]
        : await _linkedUsersForProperty(propertyId);
    final normalizedGatewayId = gatewayId == null || gatewayId.trim().isEmpty
        ? null
        : _idFromRefOrPath(gatewayId);
    final position = (lat != null && lon != null) ? [lat, lon] : null;
    final payload = {
      'ownerUid': null,
      'name': name,
      'status': status,
      'gatewayId': normalizedGatewayId,
      'host': host,
      'propertyId': _propertyRefOrNull(propertyId),
      'userUids': linkedUsers,
      'wifi_ota_enabled': true,
      'position': position,
      'is_matrix': isMatrix,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (normalizedGatewayId == null) {
      await _db.collection('gateways').add(payload);
    } else {
      await _db
          .collection('gateways')
          .doc(normalizedGatewayId)
          .set(payload, SetOptions(merge: true));
    }
  }

  Future<List<Map<String, String>>> getUserOptions() async {
    final snap = await _db.collection('users').get();
    final users = snap.docs.map((d) {
      final data = d.data();
      final email = (data['email'] as String?)?.trim().toLowerCase();
      return <String, String>{
        'uid': d.id,
        'email': (email == null || email.isEmpty) ? d.id : email,
      };
    }).toList();
    users.sort((a, b) => a['email']!.compareTo(b['email']!));
    return users;
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
    final normalizedGatewayId = gatewayId == null || gatewayId.trim().isEmpty
        ? null
        : _idFromRefOrPath(gatewayId);
    final update = <String, dynamic>{
      'deviceId': normalizedDeviceId,
      'name': name,
      'status': status,
      'ownerUid': _userRef(ownerUid),
      'position': [lat, lon],
      'gatewayId': normalizedGatewayId,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (wifiOtaEnabled != null) {
      update['wifi_ota_enabled'] = wifiOtaEnabled;
    }

    if (propertyId != null && propertyId.trim().isNotEmpty) {
      update['propertyId'] = _propertyRefOrNull(propertyId);
    } else {
      update['propertyId'] = null;
    }

    await _db
        .collection('collars')
        .doc(id)
        .set(update, SetOptions(merge: true));
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
    List<DocumentReference<Map<String, dynamic>>> linkedUsers = const [];
    if (propertyId != null && propertyId.trim().isNotEmpty) {
      linkedUsers = await _linkedUsersForProperty(propertyId);
    }
    final update = <String, dynamic>{
      'ownerUid': null,
      'name': name,
      'status': status,
      'gatewayId': _idFromRefOrPath(id),
      'host': host,
      'position': [lat, lon],
      'userUids': linkedUsers,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (wifiOtaEnabled != null) {
      update['wifi_ota_enabled'] = wifiOtaEnabled;
    }
    if (isMatrix != null) {
      update['is_matrix'] = isMatrix;
    }

    if (propertyId != null && propertyId.trim().isNotEmpty) {
      update['propertyId'] = _propertyRefOrNull(propertyId);
    } else {
      update['propertyId'] = null;
    }

    await _db
        .collection('gateways')
        .doc(id)
        .set(update, SetOptions(merge: true));
  }

  Future<void> updateRuralPropertyPolygon({
    required String id,
    required List<List<double>> points,
    String? updatedByUid,
  }) async {
    final normalizedUpdatedByUid = _idFromRefOrPath(updatedByUid);
    await _db.collection('ruralProperties').doc(id).set({
      'points': _encodeLatLonPoints(points),
      if (normalizedUpdatedByUid.isNotEmpty)
        'updatedByUid': _userRef(normalizedUpdatedByUid),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateAreaPerimeter({
    required String id,
    required List<List<double>> perimeter,
    String? updatedByUid,
    List<String> linkedDeviceIds = const <String>[],
  }) async {
    final normalizedUpdatedByUid = _idFromRefOrPath(updatedByUid);
    await _db.collection('areas').doc(id).set({
      'perimeter': _encodeLatLonPoints(perimeter),
      'linkedDeviceIds': _normalizeLoraDeviceIds(linkedDeviceIds),
      if (normalizedUpdatedByUid.isNotEmpty)
        'updatedByUid': _userRef(normalizedUpdatedByUid),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setDeviceWifiOtaEnabled({
    required String id,
    required bool enabled,
  }) async {
    await _db.collection('collars').doc(id).set({
      'wifi_ota_enabled': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setGatewayWifiOtaEnabled({
    required String id,
    required bool enabled,
  }) async {
    await _db.collection('gateways').doc(id).set({
      'wifi_ota_enabled': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteDevice({required String id}) async {
    final batch = _db.batch();
    batch.delete(_db.collection('collars').doc(id));
    batch.delete(_db.collection('fences').doc(id));
    batch.delete(_db.collection('herdingPlans').doc(id));
    await batch.commit();
  }

  Future<void> deleteGateway({required String id}) async {
    await _db.collection('gateways').doc(id).delete();
  }

  Future<void> deleteArea({required String id}) async {
    await _db.collection('areas').doc(id).delete();
  }

  Future<void> deleteRuralProperty({required String id}) async {
    final propertyRef = _db.collection('ruralProperties').doc(id);
    final propertyPath = '/ruralProperties/$id';

    final areaSnaps = await Future.wait([
      _db
          .collection('areas')
          .where('ruralPropertiesID', isEqualTo: propertyRef)
          .get(),
      _db.collection('areas').where('ruralPropertiesID', isEqualTo: id).get(),
      _db
          .collection('areas')
          .where('ruralPropertiesID', isEqualTo: propertyPath)
          .get(),
    ]);
    final gatewaySnaps = await Future.wait([
      _db
          .collection('gateways')
          .where('propertyId', isEqualTo: propertyRef)
          .get(),
      _db.collection('gateways').where('propertyId', isEqualTo: id).get(),
      _db
          .collection('gateways')
          .where('propertyId', isEqualTo: propertyPath)
          .get(),
    ]);
    final collarSnaps = await Future.wait([
      _db
          .collection('collars')
          .where('propertyId', isEqualTo: propertyRef)
          .get(),
      _db.collection('collars').where('propertyId', isEqualTo: id).get(),
      _db
          .collection('collars')
          .where('propertyId', isEqualTo: propertyPath)
          .get(),
    ]);

    final areaDocs = <String, DocumentReference<Map<String, dynamic>>>{};
    for (final s in areaSnaps) {
      for (final d in s.docs) {
        areaDocs[d.reference.path] = d.reference;
      }
    }

    final gatewayDocs = <String, DocumentReference<Map<String, dynamic>>>{};
    for (final s in gatewaySnaps) {
      for (final d in s.docs) {
        gatewayDocs[d.reference.path] = d.reference;
      }
    }

    final collarDocs = <String, DocumentReference<Map<String, dynamic>>>{};
    for (final s in collarSnaps) {
      for (final d in s.docs) {
        collarDocs[d.reference.path] = d.reference;
      }
    }

    WriteBatch batch = _db.batch();
    var opCount = 0;

    Future<void> flush() async {
      if (opCount == 0) return;
      await batch.commit();
      batch = _db.batch();
      opCount = 0;
    }

    for (final docRef in areaDocs.values) {
      batch.delete(docRef);
      opCount++;
      if (opCount >= 400) await flush();
    }

    for (final docRef in gatewayDocs.values) {
      batch.set(
        docRef,
        {
          'propertyId': null,
          'userUids': const [],
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      opCount++;
      if (opCount >= 400) await flush();
    }

    for (final docRef in collarDocs.values) {
      batch.set(
        docRef,
        {
          'propertyId': null,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      opCount++;
      if (opCount >= 400) await flush();
    }

    batch.delete(propertyRef);
    opCount++;
    await flush();
  }

  Future<void> backfillLegacyAccessForAreasAndGateways() async {
    final props = await _db.collection('ruralProperties').get();
    final propUsers = <String, List<DocumentReference<Map<String, dynamic>>>>{};
    for (final p in props.docs) {
      final data = p.data();
      final set = <DocumentReference<Map<String, dynamic>>>{};
      final createdById = _idFromRefOrPath(data['createdByUid']);
      if (createdById.isNotEmpty) set.add(_userRef(createdById));
      final users = data['userUids'];
      if (users is List) {
        for (final u in users) {
          final uid = _idFromRefOrPath(u);
          if (uid.isNotEmpty) set.add(_userRef(uid));
        }
      }
      propUsers[p.id] = set.toList();
    }

    Future<void> patchCollection(
      String collection,
      String propertyField,
      bool includeOwner,
    ) async {
      final snap = await _db.collection(collection).get();
      if (snap.docs.isEmpty) return;
      WriteBatch batch = _db.batch();
      var opCount = 0;

      Future<void> flush() async {
        if (opCount == 0) return;
        await batch.commit();
        batch = _db.batch();
        opCount = 0;
      }

      for (final d in snap.docs) {
        final data = d.data();
        final propertyId = _idFromRefOrPath(data[propertyField]);
        if (propertyId.isEmpty) continue;
        final linked = [
          ...(propUsers[propertyId] ??
              const <DocumentReference<Map<String, dynamic>>>[])
        ];
        if (includeOwner) {
          final ownerId = _idFromRefOrPath(data['ownerUid']);
          if (ownerId.isNotEmpty) linked.add(_userRef(ownerId));
        }
        final unique = <String, DocumentReference<Map<String, dynamic>>>{};
        for (final r in linked) {
          unique[r.id] = r;
        }
        batch.set(
            d.reference,
            {
              'userUids': unique.values.toList(),
              propertyField: _propertyRefOrNull(propertyId),
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true));
        opCount++;
        if (opCount >= 400) {
          await flush();
        }
      }
      await flush();
    }

    await patchCollection('areas', 'ruralPropertiesID', true);
    await patchCollection('gateways', 'propertyId', false);
  }

  Future<void> saveFence(
      String deviceId, String ownerUid, List<List<double>> points) {
    return _db.collection('fences').doc(deviceId).set({
      'deviceId': deviceId,
      'ownerUid': _userRef(ownerUid),
      'points': _encodeLatLonPoints(points),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<List<List<double>>> getFence(String deviceId) async {
    final snap = await _db.collection('fences').doc(deviceId).get();
    if (!snap.exists) return const [];
    final data = snap.data() ?? const <String, dynamic>{};
    return _decodeLatLonPoints(data['points']);
  }

  Future<void> saveHerdingPlan(
      String deviceId, String ownerUid, List<List<List<double>>> phases) {
    return _db.collection('herdingPlans').doc(deviceId).set({
      'deviceId': deviceId,
      'ownerUid': _userRef(ownerUid),
      'phases': _encodeHerdingPhases(phases),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<List<List<List<double>>>> getHerdingPlan(String deviceId) async {
    final snap = await _db.collection('herdingPlans').doc(deviceId).get();
    if (!snap.exists) return const [];
    final data = snap.data() ?? const <String, dynamic>{};
    return _decodeHerdingPhases(data['phases']);
  }

  Future<void> saveCriticalEvent(Map<String, dynamic> event) {
    final payload = Map<String, dynamic>.from(event);
    payload['createdAt'] ??= FieldValue.serverTimestamp();
    return _db.collection('events').add(payload);
  }
}
