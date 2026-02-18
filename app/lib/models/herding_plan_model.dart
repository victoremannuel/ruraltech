class HerdingPlanModel {
  final String id;
  final String deviceId;
  final List<List<List<double>>> phases;

  HerdingPlanModel({required this.id, required this.deviceId, required this.phases});

  Map<String, dynamic> toMap() => {'deviceId': deviceId, 'phases': phases};
}
