import 'package:flutter_test/flutter_test.dart';
import 'package:ruraltech_app/services/bluetooth_discovery_service.dart';

void main() {
  group('BluetoothDiscoveryService retry classification', () {
    test('treats discoverServices disconnected error as retryable', () {
      const error =
          'FlutterBluePlusException | discoverServices | fbp-code: 6 | Device is disconnected';

      expect(
        BluetoothDiscoveryService.isRetryableBleDiscoverError(error),
        isTrue,
      );
    });

    test('treats discoverServices timeout error as retryable', () {
      const error =
          'FlutterBluePlusException | discoverServices | timed out waiting for services';

      expect(
        BluetoothDiscoveryService.isRetryableBleDiscoverError(error),
        isTrue,
      );
    });

    test('does not treat unrelated discoverServices error as retryable', () {
      const error =
          'FlutterBluePlusException | discoverServices | native-code: 42 | attribute table invalid';

      expect(
        BluetoothDiscoveryService.isRetryableBleDiscoverError(error),
        isFalse,
      );
    });
  });
}
