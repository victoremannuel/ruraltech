class DeviceModel {
  final String id;
  final String name;
  final String status;
  final double? lat;
  final double? lon;
  final String? propertyId;

  DeviceModel({
    required this.id,
    required this.name,
    required this.status,
    this.lat,
    this.lon,
    this.propertyId,
  });

  factory DeviceModel.fromMap(String id, Map<String, dynamic> m) => DeviceModel(
        id: id,
        name: m['name'] ?? 'Coleira',
        status: m['status'] ?? 'unknown',
        lat: (m['lat'] as num?)?.toDouble(),
        lon: (m['lon'] as num?)?.toDouble(),
        propertyId: m['propertyId'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'status': status,
        'lat': lat,
        'lon': lon,
        'propertyId': propertyId,
      };
}
