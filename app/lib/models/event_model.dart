class EventModel {
  final String type;
  final String deviceId;
  final DateTime createdAt;
  final Map<String, dynamic> payload;

  EventModel({required this.type, required this.deviceId, required this.createdAt, required this.payload});
}
