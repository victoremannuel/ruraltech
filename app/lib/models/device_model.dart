class DeviceModel {
  final String id;
  final String name;
  final String status;
  final double? lat;
  final double? lon;

  DeviceModel({required this.id, required this.name, required this.status, this.lat, this.lon});

  factory DeviceModel.fromMap(String id, Map<String, dynamic> m) => DeviceModel(
        id: id,
        name: m['name'] ?? 'Coleira',
        status: m['status'] ?? 'unknown',
        lat: (m['lat'] as num?)?.toDouble(),
        lon: (m['lon'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toMap() => {'name': name, 'status': status, 'lat': lat, 'lon': lon};
}
