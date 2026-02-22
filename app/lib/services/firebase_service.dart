import 'dart:async';

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

  Stream<List<DeviceModel>> streamDevices(
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
      final sub4 = linkedQueryRef.snapshots().listen(
        (snap) {
          linkedDocsRef = snap.docs;
          emit();
        },
        onError: controller.addError,
      );
      final sub5 = linkedQueryPath.snapshots().listen(
        (snap) {
          linkedDocsPath = snap.docs;
          emit();
        },
        onError: controller.addError,
      );
      final sub6 = linkedQueryUid.snapshots().listen(
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
    required bool isAdmin,
    List<String> userEmails = const [],
  }) async {
    final linkedUsers = <DocumentReference<Map<String, dynamic>>>{
      _userRef(creatorUid)
    };

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
      'createdByUid': _userRef(creatorUid),
      'updatedAt': FieldValue.serverTimestamp(),
    });
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
    String? gatewayId,
    String? propertyId,
  }) async {
    final normalizedDeviceId = deviceId == null || deviceId.trim().isEmpty
        ? null
        : _idFromRefOrPath(deviceId);
    final payload = {
      'ownerUid': _userRef(ownerUid),
      'name': name,
      'status': status,
      'deviceId': normalizedDeviceId,
      'position': [lat ?? 0, lon ?? 0],
      'gatewayId': gatewayId == null || gatewayId.trim().isEmpty
          ? null
          : _db.collection('gateways').doc(_idFromRefOrPath(gatewayId)),
      'propertyId': _propertyRefOrNull(propertyId),
      'wifi_ota_enabled': true,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (normalizedDeviceId == null) {
      await _db.collection('collars').add(payload);
    } else {
      await _db
          .collection('collars')
          .doc(normalizedDeviceId)
          .set(payload, SetOptions(merge: true));
    }
  }

  Future<void> addGateway({
    required String ownerUid,
    required String name,
    required String status,
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
    final payload = {
      'ownerUid': _userRef(ownerUid),
      'name': name,
      'status': status,
      'gatewayId': normalizedGatewayId,
      'host': host,
      'propertyId': _propertyRefOrNull(propertyId),
      'userUids': linkedUsers,
      'wifi_ota_enabled': true,
      'position': [lat ?? 0, lon ?? 0],
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
    required String name,
    required String status,
    required double lat,
    required double lon,
    required String ownerUid,
    String? gatewayId,
    String? propertyId,
    bool? wifiOtaEnabled,
  }) async {
    final update = <String, dynamic>{
      'name': name,
      'status': status,
      'deviceId': _idFromRefOrPath(id),
      'ownerUid': _userRef(ownerUid),
      'position': [lat, lon],
      'gatewayId': gatewayId == null || gatewayId.trim().isEmpty
          ? null
          : _db.collection('gateways').doc(_idFromRefOrPath(gatewayId)),
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
    String? host,
    String? propertyId,
    bool? wifiOtaEnabled,
  }) async {
    List<DocumentReference<Map<String, dynamic>>> linkedUsers = const [];
    if (propertyId != null && propertyId.trim().isNotEmpty) {
      linkedUsers = await _linkedUsersForProperty(propertyId);
    }
    final update = <String, dynamic>{
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
    await patchCollection('gateways', 'propertyId', true);
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
