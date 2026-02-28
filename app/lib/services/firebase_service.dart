import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import '../config/manual_settings.dart';
import '../models/device_model.dart';

class FirebaseService {
  static const String _defaultRtdbUrl = ManualSettings.firebaseRtdbUrl;
  static const int _telemetryRetentionDays = 365;

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  late final FirebaseDatabase _rtdb;
  final Map<String, int> _telemetryDedupUntilMs = <String, int>{};

  FirebaseService() {
    final configuredUrl = Firebase.app().options.databaseURL?.trim() ?? '';
    _rtdb = FirebaseDatabase.instanceFor(
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

  DocumentReference<Map<String, dynamic>> _userRef(dynamic value) =>
      _db.collection('users').doc(_idFromRefOrPath(value));

  String _userPath(String uid) => '/users/$uid';

  DocumentReference<Map<String, dynamic>>? _propertyRefOrNull(dynamic value) {
    final id = _idFromRefOrPath(value);
    if (id.isEmpty) return null;
    return _db.collection('ruralProperties').doc(id);
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

  Map<String, Map<String, double>> _decodeTelemetryLatestSnapshot(dynamic raw) {
    if (raw is! Map) return const <String, Map<String, double>>{};
    final out = <String, Map<String, double>>{};
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
      out[key] = <String, double>{
        'lat': latD,
        'lon': lonD,
      };
    }
    return out;
  }

  List<DeviceModel> _mergeDevicesWithLiveTelemetry(
    List<DeviceModel> devices,
    Map<String, Map<String, double>> liveBySanitizedDeviceId,
  ) {
    return devices.map((device) {
      final key = _sanitizeRtdbKey(device.networkId);
      if (key.isEmpty) return device;
      final live = liveBySanitizedDeviceId[key];
      if (live == null) return device;
      final lat = live['lat'];
      final lon = live['lon'];
      if (lat == null || lon == null) return device;
      if (device.lat == lat && device.lon == lon) return device;
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
      );
    }).toList();
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

  Future<Map<String, double>?> getLatestTelemetryPositionForDevice(
      String rawDeviceId) async {
    final normalizedDeviceId = _normalizeLoraDeviceId(rawDeviceId);
    if (normalizedDeviceId == null) return null;
    final sanitizedDeviceId = _sanitizeRtdbKey(normalizedDeviceId);
    if (sanitizedDeviceId.isEmpty) return null;

    try {
      final snap = await _rtdb.ref('telemetryLatest/$sanitizedDeviceId').get();
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

  String _dayKeyFromMs(int msEpochUtc) {
    final dt = DateTime.fromMillisecondsSinceEpoch(msEpochUtc, isUtc: true);
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }

  bool _registerTelemetryDedupKey(String key, int nowMs) {
    _telemetryDedupUntilMs.removeWhere((_, until) => until <= nowMs);
    if (_telemetryDedupUntilMs.containsKey(key)) return false;
    _telemetryDedupUntilMs[key] = nowMs + 90 * 1000;
    return true;
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
    final sanitizedDeviceId = _sanitizeRtdbKey(deviceId);
    if (sanitizedDeviceId.isEmpty) return;

    final nowMs = receivedAtMs != null && receivedAtMs > 0
        ? receivedAtMs
        : DateTime.now().millisecondsSinceEpoch;
    final dedupKey = [
      sanitizedDeviceId,
      seq?.toString() ?? '-',
      sourceTimestampSec?.toString() ?? '-',
      lat.toStringAsFixed(6),
      lon.toStringAsFixed(6),
      gatewayId ?? '-',
    ].join('|');
    if (!_registerTelemetryDedupKey(dedupKey, nowMs)) return;

    final nowSec = nowMs ~/ 1000;
    final dayKey = _dayKeyFromMs(nowMs);
    final oldDayMs =
        nowMs - (_telemetryRetentionDays + 1) * 24 * 60 * 60 * 1000;
    final oldDayKey = _dayKeyFromMs(oldDayMs);

    final payload = <String, dynamic>{
      'deviceId': sanitizedDeviceId,
      'lat': lat,
      'lon': lon,
      'receivedAt': nowSec,
      'receivedAtMs': nowMs,
      'sourceType': sourceType,
      'writer': writer,
      'retentionDays': _telemetryRetentionDays,
      if (seq != null) 'seq': seq,
      if (sourceTimestampSec != null) 'sourceTimestampSec': sourceTimestampSec,
      if (gatewayId != null && gatewayId.trim().isNotEmpty)
        'gatewayId': gatewayId.trim(),
      if (gatewayRole != null && gatewayRole.trim().isNotEmpty)
        'gatewayRole': gatewayRole.trim(),
      if (gatewayWifiOtaEnabled != null)
        'gatewayWifiOtaEnabled': gatewayWifiOtaEnabled,
    };

    try {
      await _rtdb.ref('telemetryLatest/$sanitizedDeviceId').set(payload);
      await _rtdb
          .ref('telemetryHistory/$sanitizedDeviceId/$dayKey/$nowMs')
          .set(payload);
      unawaited(
        _rtdb.ref('telemetryHistory/$sanitizedDeviceId/$oldDayKey').remove(),
      );
    } catch (_) {
      // A falha de telemetria nao deve interromper o fluxo principal do app.
    }
  }

  Future<void> cleanupTelemetryRetentionForDevices(
    Iterable<String> rawDeviceIds, {
    int? nowMs,
  }) async {
    final baseNowMs = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final oldDayMs =
        baseNowMs - (_telemetryRetentionDays + 1) * 24 * 60 * 60 * 1000;
    final oldDayKey = _dayKeyFromMs(oldDayMs);
    final ids =
        rawDeviceIds.map(_sanitizeRtdbKey).where((id) => id.isNotEmpty).toSet();
    for (final id in ids) {
      try {
        await _rtdb.ref('telemetryHistory/$id/$oldDayKey').remove();
      } catch (_) {
        // cleanup best effort.
      }
    }
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
    return Stream.multi((controller) {
      List<DeviceModel> devices = const <DeviceModel>[];
      Map<String, Map<String, double>> liveBySanitizedDeviceId =
          const <String, Map<String, double>>{};

      void emit() {
        controller.add(
          _mergeDevicesWithLiveTelemetry(devices, liveBySanitizedDeviceId),
        );
      }

      final firestoreSub = firestoreStream.listen(
        (next) {
          devices = next;
          emit();
        },
        onError: controller.addError,
      );

      final telemetrySub = _rtdb.ref('telemetryLatest').onValue.listen(
        (event) {
          liveBySanitizedDeviceId =
              _decodeTelemetryLatestSnapshot(event.snapshot.value);
          emit();
        },
        onError: (_) {
          // Fallback para posicao do Firestore quando o feed ao vivo falhar.
          liveBySanitizedDeviceId = const <String, Map<String, double>>{};
          emit();
        },
      );

      controller.onCancel = () async {
        await firestoreSub.cancel();
        await telemetrySub.cancel();
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

    await _db.collection('ruralProperties').add({
      'name': name,
      'points': _encodeLatLonPoints(points),
      'userUids': linkedUsers.toList(),
      'ownerUid': _userRef(normalizedOwnerUid),
      'createdByUid': _userRef(normalizedOwnerUid),
      'updatedAt': FieldValue.serverTimestamp(),
    });
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
  }

  Future<void> addArea({
    required String ownerUid,
    required String ruralPropertyId,
    required List<List<double>> perimeter,
  }) async {
    final linkedUsers = await _linkedUsersForProperty(ruralPropertyId);
    await _db.collection('areas').add({
      'ownerUid': _userRef(ownerUid),
      'ruralPropertiesID': _propertyRefOrNull(ruralPropertyId),
      'userUids': linkedUsers,
      'perimeter': _encodeLatLonPoints(perimeter),
      'updatedAt': FieldValue.serverTimestamp(),
    });
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
  }) async {
    await _db.collection('ruralProperties').doc(id).set({
      'points': _encodeLatLonPoints(points),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateAreaPerimeter({
    required String id,
    required List<List<double>> perimeter,
  }) async {
    await _db.collection('areas').doc(id).set({
      'perimeter': _encodeLatLonPoints(perimeter),
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
