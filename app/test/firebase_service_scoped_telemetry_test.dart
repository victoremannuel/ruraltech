import 'package:flutter_test/flutter_test.dart';
import 'package:ruraltech_app/models/device_model.dart';
import 'package:ruraltech_app/utils/device_map_telemetry.dart';

void main() {
  group('FirebaseService scoped live telemetry merge', () {
    test('keeps duplicate LoRa ids isolated by property', () {
      final devices = <DeviceModel>[
        DeviceModel(
          id: 'doc-a',
          deviceId: '7',
          name: 'Coleira A',
          status: 'active',
          lat: -10,
          lon: -10,
          propertyId: 'property-a',
          gatewayId: 'RT-GW-A',
          telemetryReceivedAtMs: 1000,
        ),
        DeviceModel(
          id: 'doc-b',
          deviceId: '7',
          name: 'Coleira B',
          status: 'active',
          lat: -20,
          lon: -20,
          propertyId: 'property-b',
          gatewayId: 'RT-GW-B',
          telemetryReceivedAtMs: 1000,
        ),
      ];

      final merged = mergeDevicesWithScopedLiveTelemetry(
        devices: devices,
        liveByPropertyId: {
          sanitizeMapRtdbKey('property-a'): {
            '7': {
              'lat': -16.6701,
              'lon': -49.2501,
              'telemetryReceivedAtMs': 2000,
            },
          },
          sanitizeMapRtdbKey('property-b'): {
            '7': {
              'lat': -16.8802,
              'lon': -49.5102,
              'telemetryReceivedAtMs': 3000,
            },
          },
        },
        healthByPropertyId: const {},
        eventByPropertyId: const {},
      );

      expect(merged, hasLength(2));
      expect(merged[0].lat, -16.6701);
      expect(merged[0].lon, -49.2501);
      expect(merged[0].telemetryReceivedAtMs, 2000);
      expect(merged[1].lat, -16.8802);
      expect(merged[1].lon, -49.5102);
      expect(merged[1].telemetryReceivedAtMs, 3000);
    });

    test('uses newer positional event when it is newer than telemetry', () {
      final devices = <DeviceModel>[
        DeviceModel(
          id: 'doc-a',
          deviceId: '7',
          name: 'Coleira A',
          status: 'active',
          lat: -10,
          lon: -10,
          propertyId: 'property-a',
          gatewayId: 'RT-GW-A',
          telemetryReceivedAtMs: 1000,
        ),
      ];

      final merged = mergeDevicesWithScopedLiveTelemetry(
        devices: devices,
        liveByPropertyId: {
          sanitizeMapRtdbKey('property-a'): {
            '7': {
              'lat': -16.6701,
              'lon': -49.2501,
              'telemetryReceivedAtMs': 2000,
            },
          },
        },
        healthByPropertyId: const {},
        eventByPropertyId: {
          sanitizeMapRtdbKey('property-a'): {
            '7': {
              'lat': -16.6715,
              'lon': -49.2515,
              'positionReceivedAtMs': 3000,
              'positionSourceType': 'event',
            },
          },
        },
      );

      expect(merged, hasLength(1));
      expect(merged.single.lat, -16.6715);
      expect(merged.single.lon, -49.2515);
      expect(merged.single.telemetryReceivedAtMs, 2000);
      expect(merged.single.positionReceivedAtMs, 3000);
    });
  });
}
