import 'package:flutter_test/flutter_test.dart';
import 'package:ruraltech_app/models/device_model.dart';

void main() {
  group('DeviceModel lora id', () {
    test('accepts numeric deviceId from payload', () {
      final device = DeviceModel.fromMap('randomDoc', {
        'deviceId': '123',
        'name': 'Coleira A',
        'status': 'active',
      });

      expect(device.loraDeviceId, '123');
      expect(device.networkId, '123');
    });

    test('falls back to numeric firestore doc id when deviceId is absent', () {
      final device = DeviceModel.fromMap('456', {
        'name': 'Coleira B',
        'status': 'active',
      });

      expect(device.loraDeviceId, '456');
      expect(device.networkId, '456');
    });

    test('keeps non-numeric id visible but not valid for LoRa commands', () {
      final device = DeviceModel.fromMap('abc-doc', {
        'deviceId': 'abc-doc',
        'name': 'Coleira C',
        'status': 'active',
      });

      expect(device.loraDeviceId, isNull);
      expect(device.networkId, 'abc-doc');
    });

    test('parses daily health snapshot fields', () {
      const flags = DeviceModel.healthFlagGpsUartReady |
          DeviceModel.healthFlagGpsNmeaSeen |
          DeviceModel.healthFlagMpuReady |
          DeviceModel.healthFlagMlxReady |
          DeviceModel.healthFlagStorageReady |
          DeviceModel.healthFlagLoRaReady |
          DeviceModel.healthFlagLastLoRaTxOk;
      final device = DeviceModel.fromMap('123', {
        'deviceId': '123',
        'name': 'Coleira Saudavel',
        'status': 'active',
        'healthReceivedAtMs': 1760000000000,
        'healthGpsDayKey': 20260321,
        'healthFlags': flags,
        'healthUptimeSec': 86400,
        'healthTemperatureDeciC': 365,
        'healthSatellites': 8,
        'healthHdopCenti': 95,
        'healthI2cDevices': 2,
      });

      expect(device.hasDailyHealth, isTrue);
      expect(device.healthGpsUartReady, isTrue);
      expect(device.healthMpuReady, isTrue);
      expect(device.healthTemperatureC, 36.5);
      expect(device.healthHdop, 0.95);
      expect(device.healthSummary, 'OK');
    });

    test('marks fallback daily report as attention', () {
      const flags = DeviceModel.healthFlagGpsUartReady |
          DeviceModel.healthFlagGpsNmeaSeen |
          DeviceModel.healthFlagMpuReady |
          DeviceModel.healthFlagMlxReady |
          DeviceModel.healthFlagStorageReady |
          DeviceModel.healthFlagLoRaReady |
          DeviceModel.healthFlagLastLoRaTxOk |
          DeviceModel.healthFlagFallbackSchedule;
      final device = DeviceModel.fromMap('124', {
        'deviceId': '124',
        'name': 'Coleira Fallback',
        'status': 'active',
        'healthReceivedAtMs': 1760000000000,
        'healthFlags': flags,
      });

      expect(device.hasDailyHealth, isTrue);
      expect(device.healthFallbackSchedule, isTrue);
      expect(device.healthSummary, 'Atencao');
    });
  });
}
