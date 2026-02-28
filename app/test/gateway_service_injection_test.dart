import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ruraltech_app/services/gateway_service.dart';

void main() {
  group('GatewayService dependency injection', () {
    test('uses injected websocket connector and host override', () {
      Uri? receivedUri;
      final service = GatewayService(
        initialGatewayHost: 'ws://10.10.10.5:81',
        webSocketConnector: (uri) {
          receivedUri = uri;
          throw Exception('forced_connector_error');
        },
      );

      service.connect();

      expect(receivedUri?.toString(), 'ws://10.10.10.5:81');
      expect(service.isConnected, isFalse);
      expect(service.lastError, contains('forced_connector_error'));
    });

    test('uses injected http client to discover local gateways', () async {
      final probedUris = <Uri>[];
      final service = GatewayService(
        initialGatewayHost: 'ws://10.0.0.1:81',
        httpGet: (uri, {headers}) async {
          probedUris.add(uri);
          if (uri.host == '10.0.0.1') {
            return http.Response(
              '{"service":"gateway","gatewayId":"RT-GW-01","ap_ssid":"RT-GW-01"}',
              200,
            );
          }
          return http.Response('not-found', 404);
        },
      );

      final gateways =
          await service.discoverGatewaysOnLocalNetwork(maxHosts: 1);
      final found =
          gateways.where((g) => g['source'] == 'network_probe').toList();

      expect(probedUris, isNotEmpty);
      expect(found, isNotEmpty);
      expect(found.first['gateway_id_raw'], 'RT-GW-01');
      expect(found.first['host_ws'], 'ws://10.0.0.1:81');
    });

    test('clock injection controls ensureConnected timeout checks', () async {
      var ticks = 0;
      final service = GatewayService(
        clock: () {
          ticks += 1;
          return DateTime(2026, 1, 1).add(Duration(seconds: ticks * 10));
        },
        webSocketConnector: (_) => throw Exception('offline'),
      );

      final ok = await service.ensureConnected(
        timeout: const Duration(milliseconds: 1),
      );

      expect(ok, isFalse);
      expect(service.lastError, 'gateway_not_connected');
      expect(ticks, greaterThanOrEqualTo(2));
    });
  });
}
