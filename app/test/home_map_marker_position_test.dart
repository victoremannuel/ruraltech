import 'package:flutter_test/flutter_test.dart';
import 'package:ruraltech_app/models/device_model.dart';
import 'package:ruraltech_app/utils/device_map_telemetry.dart';

void main() {
  group('Home marker position resolution', () {
    test('uses gateway sample immediately when it is newer than Firebase', () {
      final device = DeviceModel(
        id: 'doc-101',
        deviceId: '101',
        name: 'Coleira 101',
        status: 'active',
        lat: -16.6001,
        lon: -49.2001,
        propertyId: 'property-a',
        gatewayId: 'RT-GW-01',
        telemetryReceivedAtMs: 1000,
      );
      final localSamples = {
        '101': const DeviceMapTelemetrySample(
          deviceId: '101',
          lat: -16.6009,
          lon: -49.2009,
          receivedAtMs: 2000,
          gatewayId: 'RT-GW-01',
          source: 'gateway',
        ),
      };

      final resolved = resolvePreferredMapTelemetryForDevice(
        device: device,
        devices: [device],
        localSamplesByDeviceId: localSamples,
      );

      expect(resolved, isNotNull);
      expect(resolved!.lat, -16.6009);
      expect(resolved.lon, -49.2009);
      expect(resolved.receivedAtMs, 2000);
      expect(resolved.source, 'gateway');
    });

    test('uses event sample immediately when it is newer than Firebase', () {
      final device = DeviceModel(
        id: 'doc-101',
        deviceId: '101',
        name: 'Coleira 101',
        status: 'active',
        lat: -16.6001,
        lon: -49.2001,
        propertyId: 'property-a',
        gatewayId: 'RT-GW-01',
        telemetryReceivedAtMs: 1000,
      );
      final localSamples = {
        '101': const DeviceMapTelemetrySample(
          deviceId: '101',
          lat: -16.6012,
          lon: -49.2012,
          receivedAtMs: 2500,
          gatewayId: 'RT-GW-01',
          source: 'event',
        ),
      };

      final resolved = resolvePreferredMapTelemetryForDevice(
        device: device,
        devices: [device],
        localSamplesByDeviceId: localSamples,
      );

      expect(resolved, isNotNull);
      expect(resolved!.lat, -16.6012);
      expect(resolved.lon, -49.2012);
      expect(resolved.receivedAtMs, 2500);
      expect(resolved.source, 'event');
    });

    test('uses persisted event position timestamp when present on device', () {
      final device = DeviceModel(
        id: 'doc-101',
        deviceId: '101',
        name: 'Coleira 101',
        status: 'active',
        lat: -16.602,
        lon: -49.202,
        propertyId: 'property-a',
        gatewayId: 'RT-GW-01',
        telemetryReceivedAtMs: 1000,
        positionReceivedAtMs: 2600,
      );

      final resolved = resolvePreferredMapTelemetryForDevice(
        device: device,
        devices: [device],
        localSamplesByDeviceId: const {},
      );

      expect(resolved, isNotNull);
      expect(resolved!.lat, -16.602);
      expect(resolved.lon, -49.202);
      expect(resolved.receivedAtMs, 2600);
      expect(resolved.source, 'firebase');
    });

    test('keeps newer local sample when Firestore reemits an older point', () {
      final staleDevice = DeviceModel(
        id: 'doc-101',
        deviceId: '101',
        name: 'Coleira 101',
        status: 'active',
        lat: -16.6001,
        lon: -49.2001,
        propertyId: 'property-a',
        gatewayId: 'RT-GW-01',
        telemetryReceivedAtMs: 1000,
      );
      const localSample = DeviceMapTelemetrySample(
        deviceId: '101',
        lat: -16.6009,
        lon: -49.2009,
        receivedAtMs: 3000,
        gatewayId: 'RT-GW-01',
        source: 'gateway',
      );

      final persistedSample = deviceMapTelemetrySampleFromDevice(staleDevice);
      final resolved = resolvePreferredMapTelemetryForDevice(
        device: staleDevice,
        devices: [staleDevice],
        localSamplesByDeviceId: {'101': localSample},
      );

      expect(persistedSample, isNotNull);
      expect(
        shouldReplaceDeviceMapTelemetrySample(localSample, persistedSample!),
        isFalse,
      );
      expect(resolved, isNotNull);
      expect(resolved!.lat, localSample.lat);
      expect(resolved.lon, localSample.lon);
      expect(resolved.receivedAtMs, localSample.receivedAtMs);
    });

    test('switches back to Firebase when Firebase becomes newer', () {
      final device = DeviceModel(
        id: 'doc-101',
        deviceId: '101',
        name: 'Coleira 101',
        status: 'active',
        lat: -16.6015,
        lon: -49.2015,
        propertyId: 'property-a',
        gatewayId: 'RT-GW-01',
        telemetryReceivedAtMs: 4000,
      );
      final localSamples = {
        '101': const DeviceMapTelemetrySample(
          deviceId: '101',
          lat: -16.6009,
          lon: -49.2009,
          receivedAtMs: 3000,
          gatewayId: 'RT-GW-01',
          source: 'gateway',
        ),
      };

      final resolved = resolvePreferredMapTelemetryForDevice(
        device: device,
        devices: [device],
        localSamplesByDeviceId: localSamples,
      );

      expect(resolved, isNotNull);
      expect(resolved!.lat, -16.6015);
      expect(resolved.lon, -49.2015);
      expect(resolved.receivedAtMs, 4000);
      expect(resolved.source, 'firebase');
    });
  });
}
