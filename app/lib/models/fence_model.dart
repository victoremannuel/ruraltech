class FenceModel {
  final String id;
  final String deviceId;
  final List<List<double>> points;

  FenceModel({required this.id, required this.deviceId, required this.points});

  Map<String, dynamic> toMap() => {'deviceId': deviceId, 'points': points};
}
