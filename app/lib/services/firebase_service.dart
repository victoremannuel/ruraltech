import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/device_model.dart';

class FirebaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<List<DeviceModel>> streamDevices() {
    return _db.collection('devices').snapshots().map((s) => s.docs.map((d) => DeviceModel.fromMap(d.id, d.data())).toList());
  }

  Future<void> saveFence(String deviceId, List<List<double>> points) {
    return _db.collection('fences').doc(deviceId).set({'deviceId': deviceId, 'points': points, 'updatedAt': FieldValue.serverTimestamp()});
  }

  Future<void> saveHerdingPlan(String deviceId, List<List<List<double>>> phases) {
    return _db.collection('herdingPlans').doc(deviceId).set({'deviceId': deviceId, 'phases': phases, 'updatedAt': FieldValue.serverTimestamp()});
  }

  Future<void> saveCriticalEvent(Map<String, dynamic> event) => _db.collection('events').add(event);
}
