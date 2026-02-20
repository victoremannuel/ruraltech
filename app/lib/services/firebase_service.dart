import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/device_model.dart';

class FirebaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<List<DeviceModel>> streamDevices(
      {required String uid, required bool isAdmin}) {
    Query<Map<String, dynamic>> query = _db.collection('devices');
    if (!isAdmin) {
      query = query.where('userUids', arrayContains: uid);
    }
    return query.snapshots().map(
          (s) =>
              s.docs.map((d) => DeviceModel.fromMap(d.id, d.data())).toList(),
        );
  }

  Stream<List<Map<String, dynamic>>> streamGateways(
      {required String uid, required bool isAdmin}) {
    Query<Map<String, dynamic>> query = _db.collection('gateways');
    if (!isAdmin) {
      query = query.where('userUids', arrayContains: uid);
    }
    return query.snapshots().map(
          (s) => s.docs
              .map(
                (d) => {
                  'id': d.id,
                  ...d.data(),
                },
              )
              .toList(),
        );
  }

  Stream<List<Map<String, dynamic>>> streamRuralProperties(
      {required String uid, required bool isAdmin}) {
    Query<Map<String, dynamic>> query = _db.collection('ruralProperties');
    if (!isAdmin) {
      query = query.where('userUids', arrayContains: uid);
    }
    return query.snapshots().map(
          (s) => s.docs
              .map(
                (d) => {
                  'id': d.id,
                  ...d.data(),
                },
              )
              .toList(),
        );
  }

  Future<List<String>> _resolveUserUidsByEmails(List<String> emails) async {
    final normalized = emails
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet();
    final List<String> uids = [];
    for (final email in normalized) {
      final snap = await _db
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        uids.add(snap.docs.first.id);
      }
    }
    return uids.toSet().toList();
  }

  Future<void> addRuralProperty({
    required String name,
    required List<List<double>> points,
    required String creatorUid,
    required bool isAdmin,
    List<String> userEmails = const [],
  }) async {
    final linkedUids = isAdmin
        ? await _resolveUserUidsByEmails(userEmails)
        : <String>[creatorUid];
    if (linkedUids.isEmpty) {
      throw Exception('Informe ao menos um email de usuario valido.');
    }

    await _db.collection('ruralProperties').add({
      'name': name,
      'points': points,
      'userUids': linkedUids,
      'createdByUid': creatorUid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<List<String>> _userUidsFromPropertyId(String? propertyId) async {
    if (propertyId == null || propertyId.trim().isEmpty) return const [];
    final snap =
        await _db.collection('ruralProperties').doc(propertyId.trim()).get();
    if (!snap.exists) return const [];
    final data = snap.data() ?? {};
    final raw = (data['userUids'] as List?) ?? const [];
    return raw.map((e) => e.toString()).toSet().toList();
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
    final propertyUsers = await _userUidsFromPropertyId(propertyId);
    final userUids = propertyUsers.isEmpty ? <String>[ownerUid] : propertyUsers;
    await _db.collection('devices').add({
      'ownerUid': ownerUid,
      'userUids': userUids,
      'name': name,
      'status': status,
      'lat': lat,
      'lon': lon,
      'gatewayId': gatewayId,
      'propertyId': propertyId,
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
    final propertyUsers = await _userUidsFromPropertyId(propertyId);
    final userUids = propertyUsers.isEmpty ? <String>[ownerUid] : propertyUsers;
    await _db.collection('gateways').add({
      'ownerUid': ownerUid,
      'userUids': userUids,
      'name': name,
      'status': status,
      'host': host,
      'propertyId': propertyId,
      'lat': lat,
      'lon': lon,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> saveFence(
      String deviceId, String ownerUid, List<List<double>> points) {
    return _db.collection('fences').doc(deviceId).set({
      'deviceId': deviceId,
      'ownerUid': ownerUid,
      'points': points,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> saveHerdingPlan(
      String deviceId, String ownerUid, List<List<List<double>>> phases) {
    return _db.collection('herdingPlans').doc(deviceId).set({
      'deviceId': deviceId,
      'ownerUid': ownerUid,
      'phases': phases,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> saveCriticalEvent(Map<String, dynamic> event) =>
      _db.collection('events').add(event);
}
