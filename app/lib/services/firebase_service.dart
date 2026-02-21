import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/device_model.dart';

class FirebaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

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

  DocumentReference<Map<String, dynamic>> _userRef(dynamic value) =>
      _db.collection('users').doc(_idFromRefOrPath(value));

  DocumentReference<Map<String, dynamic>>? _propertyRefOrNull(dynamic value) {
    final id = _idFromRefOrPath(value);
    if (id.isEmpty) return null;
    return _db.collection('ruralProperties').doc(id);
  }

  bool _hasUserAccess(dynamic rawUserRefs, String uid) {
    if (rawUserRefs is! List) return false;
    return rawUserRefs.any((e) => _idFromRefOrPath(e) == uid);
  }

  bool _isOwner(Map<String, dynamic> data, String uid) =>
      _idFromRefOrPath(data['ownerUid']) == uid;

  bool _canAccessPropertyData(Map<String, dynamic> data, String uid) {
    final owner = _idFromRefOrPath(data['createdByUid']) == uid;
    final linked = _hasUserAccess(data['userUids'], uid);
    return owner || linked;
  }

  Future<bool> _canAccessPropertyById(
      String propertyId, String uid, bool isAdmin) async {
    if (isAdmin) return true;
    if (propertyId.isEmpty) return false;
    final propSnap = await _db.collection('ruralProperties').doc(propertyId).get();
    if (!propSnap.exists) return false;
    final data = propSnap.data() ?? {};
    return _canAccessPropertyData(data, uid);
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

  Stream<List<DeviceModel>> streamDevices(
      {required String uid, required bool isAdmin}) {
    return _db.collection('collars').snapshots().map((s) {
      final docs = isAdmin ? s.docs : s.docs.where((d) => _isOwner(d.data(), uid));
      return docs.map((d) => DeviceModel.fromMap(d.id, d.data())).toList();
    });
  }

  Stream<List<Map<String, dynamic>>> streamGateways(
      {required String uid, required bool isAdmin}) {
    return _db.collection('gateways').snapshots().asyncMap((s) async {
      final out = <Map<String, dynamic>>[];
      for (final d in s.docs) {
        final data = d.data();
        final propertyId = _idFromRefOrPath(data['propertyId']);
        final allowed = isAdmin || await _canAccessPropertyById(propertyId, uid, isAdmin);
        if (allowed) {
          out.add({
            'id': d.id,
            ...data,
            'lat': _latFromPosition(data),
            'lon': _lonFromPosition(data),
            'propertyId': propertyId,
          });
        }
      }
      return out;
    });
  }

  Stream<List<Map<String, dynamic>>> streamRuralProperties(
      {required String uid, required bool isAdmin}) {
    return _db.collection('ruralProperties').snapshots().map((s) {
      final docs = isAdmin
          ? s.docs
          : s.docs.where((d) => _canAccessPropertyData(d.data(), uid));
      return docs
          .map(
            (d) => {
              'id': d.id,
              ...d.data(),
            },
          )
          .toList();
    });
  }

  Stream<List<Map<String, dynamic>>> streamAreas(
      {required String uid, required bool isAdmin}) {
    return _db.collection('areas').snapshots().asyncMap((s) async {
      final out = <Map<String, dynamic>>[];
      for (final d in s.docs) {
        final data = d.data();
        final propertyId = _idFromRefOrPath(data['ruralPropertiesID']);
        final allowed = isAdmin || await _canAccessPropertyById(propertyId, uid, isAdmin);
        if (allowed) {
          out.add({
            'id': d.id,
            ...data,
            'propertyId': propertyId,
          });
        }
      }
      return out;
    });
  }

  Future<List<Map<String, dynamic>>> getRuralProperties(
      {required String uid, required bool isAdmin}) async {
    final s = await _db.collection('ruralProperties').get();
    final docs = isAdmin
        ? s.docs
        : s.docs.where((d) => _canAccessPropertyData(d.data(), uid));
    return docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<List<DocumentReference<Map<String, dynamic>>>>
      _resolveUserRefsByEmails(List<String> emails) async {
    final normalized = emails
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet();
    final snapshots = await Future.wait(
      normalized.map(
        (email) => _db
            .collection('users')
            .where('email', isEqualTo: email)
            .limit(1)
            .get(),
      ),
    );
    final refs = snapshots
        .where((snap) => snap.docs.isNotEmpty)
        .map((snap) => snap.docs.first.reference)
        .toList();
    return refs;
  }

  Future<void> addRuralProperty({
    required String name,
    required List<List<double>> points,
    required String creatorUid,
    required bool isAdmin,
    List<String> userEmails = const [],
  }) async {
    final linkedUsers = <DocumentReference<Map<String, dynamic>>>{
      _userRef(creatorUid),
      if (isAdmin) ...(await _resolveUserRefsByEmails(userEmails)),
    }.toList();
    if (linkedUsers.isEmpty) {
      throw Exception('Informe ao menos um email de usuario valido.');
    }

    await _db.collection('ruralProperties').add({
      'name': name,
      'points': _encodeLatLonPoints(points),
      'userUids': linkedUsers,
      'createdByUid': _userRef(creatorUid),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> addArea({
    required String ownerUid,
    required String ruralPropertyId,
    required List<List<double>> perimeter,
  }) async {
    await _db.collection('areas').add({
      'ownerUid': _userRef(ownerUid),
      'ruralPropertiesID': _propertyRefOrNull(ruralPropertyId),
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
    String? gatewayId,
    String? propertyId,
  }) async {
    await _db.collection('collars').add({
      'ownerUid': _userRef(ownerUid),
      'name': name,
      'status': status,
      'position': [lat ?? 0, lon ?? 0],
      'gatewayId': gatewayId == null || gatewayId.trim().isEmpty
          ? null
          : _db.collection('gateways').doc(_idFromRefOrPath(gatewayId)),
      'propertyId': _propertyRefOrNull(propertyId),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> addGateway({
    required String ownerUid,
    required String name,
    required String status,
    String? host,
    String? propertyId,
    double? lat,
    double? lon,
  }) async {
    await _db.collection('gateways').add({
      'name': name,
      'status': status,
      'host': host,
      'propertyId': _propertyRefOrNull(propertyId),
      'position': [lat ?? 0, lon ?? 0],
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateDevice({
    required String id,
    required String name,
    required String status,
    required double lat,
    required double lon,
    String? gatewayId,
    String? propertyId,
  }) async {
    final update = <String, dynamic>{
      'name': name,
      'status': status,
      'position': [lat, lon],
      'gatewayId': gatewayId == null || gatewayId.trim().isEmpty
          ? null
          : _db.collection('gateways').doc(_idFromRefOrPath(gatewayId)),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (propertyId != null && propertyId.trim().isNotEmpty) {
      update['propertyId'] = _propertyRefOrNull(propertyId);
    } else {
      update['propertyId'] = null;
    }

    await _db.collection('collars').doc(id).set(update, SetOptions(merge: true));
  }

  Future<void> updateGateway({
    required String id,
    required String name,
    required String status,
    required double lat,
    required double lon,
    String? host,
    String? propertyId,
  }) async {
    final update = <String, dynamic>{
      'name': name,
      'status': status,
      'host': host,
      'position': [lat, lon],
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (propertyId != null && propertyId.trim().isNotEmpty) {
      update['propertyId'] = _propertyRefOrNull(propertyId);
    } else {
      update['propertyId'] = null;
    }

    await _db.collection('gateways').doc(id).set(update, SetOptions(merge: true));
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

  Future<void> saveFence(
      String deviceId, String ownerUid, List<List<double>> points) {
    return _db.collection('fences').doc(deviceId).set({
      'deviceId': deviceId,
      'ownerUid': _userRef(ownerUid),
      'points': _encodeLatLonPoints(points),
      'updatedAt': FieldValue.serverTimestamp(),
    });
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

  Future<void> saveCriticalEvent(Map<String, dynamic> event) =>
      _db.collection('events').add(event);
}
