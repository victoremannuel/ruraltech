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
  });
}
