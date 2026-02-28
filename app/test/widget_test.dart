import 'package:flutter_test/flutter_test.dart';
import 'package:ruraltech_app/services/gateway_service.dart';

void main() {
  group('GatewayService business rules', () {
    late GatewayService service;

    setUp(() {
      service = GatewayService();
    });

    test('rejects invalid device id before any network action', () {
      final ok = service.sendCommand(
        deviceId: 'abc',
        command: 'PING',
        payload: const {},
      );

      expect(ok, isFalse);
      expect(service.lastError, '[send_command] invalid_device_id');
      expect(service.messages, isNotEmpty);
      expect(service.messages.first['reason'], 'invalid_device_id');
      expect(service.messages.first['device_id'], 0);
    });

    test('validates SET_FENCE payload shape and bounds', () {
      final ok = service.sendCommand(
        deviceId: '42',
        command: 'SET_FENCE',
        payload: const {
          'points': [
            [10.0, 20.0],
            [11.0, 21.0],
            [120.0, 22.0],
          ],
        },
      );

      expect(ok, isFalse);
      expect(service.lastError, '[send_command] invalid_point_2');
      expect(service.messages.first['reason'], 'invalid_point_2');
      expect(service.messages.first['device_id'], 42);
    });

    test('validates SET_HERDING_PLAN phase points', () {
      final ok = service.sendCommand(
        deviceId: '7',
        command: 'SET_HERDING_PLAN',
        payload: const {
          'phases': [
            [
              [1.0, 1.0],
              [2.0, 2.0],
            ],
          ],
        },
      );

      expect(ok, isFalse);
      expect(service.lastError, '[send_command] phase_0_too_few_points');
      expect(service.messages.first['reason'], 'phase_0_too_few_points');
    });

    test('blocks LoRa-only SET_PARAMS without admin marker', () {
      final ok = service.sendCommand(
        deviceId: '9',
        command: 'SET_PARAMS',
        payload: const {'wifi_ota_enabled': false},
      );

      expect(ok, isFalse);
      expect(service.lastError, '[send_command] admin_required_for_lora_only');
      expect(service.messages.first['reason'], 'admin_required_for_lora_only');
    });

    test('accepts admin SET_PARAMS validation then fails disconnected gateway',
        () {
      final ok = service.sendCommand(
        deviceId: '9',
        command: 'SET_PARAMS',
        payload: const {
          'wifi_ota_enabled': false,
          'requested_by_role': 'adm',
        },
      );

      expect(ok, isFalse);
      expect(service.lastError, '[send_command] gateway_not_connected');
      expect(service.messages.first['reason'], 'gateway_not_connected');
    });

    test('valid command is rejected when websocket is disconnected', () {
      final ok = service.sendCommand(
        deviceId: '10',
        command: 'PING',
        payload: const {},
      );

      expect(ok, isFalse);
      expect(service.lastError, '[send_command] gateway_not_connected');
      expect(service.messages.first['reason'], 'gateway_not_connected');
      expect(service.messages.first['command'], 'PING');
    });

    test('discoveredCollars aggregates only supported message types', () {
      service.messages.addAll([
        {
          'type': 'telemetry',
          'device_id': 2,
          'payload': '{"lat": -10.0, "lon": 20.0}',
        },
        {
          'type': 'event',
          'device_id': '1',
          'payload': {
            'lat': 1.5,
            'lon': 2.5,
          },
        },
        {
          'type': 'foo',
          'device_id': 99,
          'payload': {
            'lat': 0.0,
            'lon': 0.0,
          },
        },
        {
          'type': 'ack',
          'device_id': 2,
          'payload': {
            'lat': 99.0,
            'lon': 99.0,
          },
        },
      ]);

      final collars = service.discoveredCollars;
      expect(collars.length, 2);
      expect(collars[0]['device_id_str'], '1');
      expect(collars[1]['device_id_str'], '2');
      expect(collars[1]['lat'], -10.0);
      expect(collars[1]['lon'], 20.0);
    });
  });
}
