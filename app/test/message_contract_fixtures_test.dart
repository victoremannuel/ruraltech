import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Directory _resolveFixturesDir() {
  final direct = Directory('${Directory.current.path}/contracts/messages');
  if (direct.existsSync()) return direct;

  final parent = Directory('${Directory.current.path}/../contracts/messages');
  if (parent.existsSync()) return parent;

  throw StateError(
    'Diretorio de fixtures nao encontrado em ${Directory.current.path}',
  );
}

Map<String, dynamic> _readFixture(Directory base, String fileName) {
  final file = File('${base.path}/$fileName');
  expect(file.existsSync(), isTrue, reason: 'Fixture ausente: $fileName');
  final raw = file.readAsStringSync();
  final decoded = jsonDecode(raw);
  expect(decoded, isA<Map<String, dynamic>>());
  return decoded as Map<String, dynamic>;
}

Map<String, dynamic> _decodePayloadMap(Map<String, dynamic> message) {
  final payload = message['payload'];
  expect(payload, isA<String>());
  final decoded = jsonDecode(payload as String);
  expect(decoded, isA<Map<String, dynamic>>());
  return decoded as Map<String, dynamic>;
}

void main() {
  group('Message contract fixtures', () {
    late Directory fixturesDir;

    setUpAll(() {
      fixturesDir = _resolveFixturesDir();
    });

    test('hello fixture', () {
      final hello = _readFixture(fixturesDir, 'hello.json');
      expect(hello['type'], 'hello');
      expect(hello['status'], 'connected');
    });

    test('telemetry fixture', () {
      final telemetry = _readFixture(fixturesDir, 'telemetry.json');
      expect(telemetry['type'], 'telemetry');
      expect(telemetry['device_id'], isA<int>());
      expect(telemetry['scope_id'], isA<String>());
      expect(telemetry['seq'], isA<int>());
      expect(telemetry['timestamp'], isA<int>());
      expect(telemetry['gateway_id'], isA<String>());
      expect(telemetry['gateway_role'], anyOf('gateway', 'matrix'));
      expect(telemetry['gateway_wifi_ota_enabled'], isA<bool>());

      final payload = _decodePayloadMap(telemetry);
      expect(payload['scope_id'], isA<String>());
      expect(payload['lat'], isA<num>());
      expect(payload['lon'], isA<num>());
    });

    test('event fixture', () {
      final event = _readFixture(fixturesDir, 'event.json');
      expect(event['type'], 'event');
      expect(event['device_id'], isA<int>());
      expect(event['scope_id'], isA<String>());
      expect(event['seq'], isA<int>());
      final payload = _decodePayloadMap(event);
      expect(payload['scope_id'], isA<String>());
      expect(payload['event_type'], isA<String>());
      expect(payload['severity'], isA<String>());
    });

    test('health daily event fixture', () {
      final event = _readFixture(fixturesDir, 'health_daily_event.json');
      expect(event['type'], 'event');
      expect(event['device_id'], isA<int>());
      expect(event['scope_id'], isA<String>());
      expect(event['seq'], isA<int>());

      final payload = _decodePayloadMap(event);
      expect(payload['scope_id'], isA<String>());
      expect(payload['type'], 'health_daily');
      expect(payload['up'], isA<int>());
      expect(payload['tp'], isA<int>());
      expect(payload['sa'], isA<int>());
      expect(payload['hd'], isA<int>());
      expect(payload['i2'], isA<int>());
      expect(payload['hf'], isA<int>());
    });

    test('ack and nack fixtures', () {
      final ack = _readFixture(fixturesDir, 'ack.json');
      final nack = _readFixture(fixturesDir, 'nack.json');

      expect(ack['type'], 'ack');
      expect(nack['type'], 'nack');

      final ackPayload = _decodePayloadMap(ack);
      final nackPayload = _decodePayloadMap(nack);
      expect(ack['scope_id'], isA<String>());
      expect(nack['scope_id'], isA<String>());
      expect(ackPayload['scope_id'], isA<String>());
      expect(nackPayload['scope_id'], isA<String>());
      expect(ackPayload['cmd'], isA<String>());
      expect(ackPayload['cmd_id'], isA<String>());
      expect(ackPayload['cmd_seq'], isA<int>());
      expect(nackPayload['cmd'], isA<String>());
      expect(nackPayload['cmd_id'], isA<String>());
      expect(nackPayload['cmd_seq'], isA<int>());
      expect(nackPayload['reason'], isA<String>());
    });

    test('command_result fixtures', () {
      final ok = _readFixture(fixturesDir, 'command_result_ok.json');
      final error = _readFixture(fixturesDir, 'command_result_error.json');

      expect(ok['type'], 'command_result');
      expect(ok['ok'], isTrue);
      expect(ok['reason'], isNull);
      expect(ok['command_id'], isA<String>());
      expect(ok['command'], isA<String>());
      expect(ok['device_id'], isA<int>());

      expect(error['type'], 'command_result');
      expect(error['ok'], isFalse);
      expect(error['command_id'], isA<String>());
      expect(error['reason'], isA<String>());
      expect(error['command'], isA<String>());
      expect(error['device_id'], isA<int>());
    });
  });
}
