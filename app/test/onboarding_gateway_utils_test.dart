import 'package:flutter_test/flutter_test.dart';
import 'package:ruraltech_app/utils/onboarding_gateway_utils.dart';

void main() {
  String normalizeRefId(dynamic raw) {
    final value = (raw ?? '').toString().trim();
    if (value.isEmpty) return '';
    if (!value.contains('/')) return value;
    final parts = value.split('/').where((part) => part.isNotEmpty).toList();
    return parts.isEmpty ? value : parts.last;
  }

  group('Onboarding gateway utils', () {
    test('resolveSelectedGatewayWsHost normalizes gateway host fields', () {
      final wsHost = resolveSelectedGatewayWsHost(
        selectedGatewayId: 'gw-01',
        gateways: const [
          {
            'id': 'gw-01',
            'host': '192.168.4.1',
          },
        ],
        normalizeRefId: normalizeRefId,
      );

      expect(wsHost, 'ws://192.168.4.1:81');
    });

    test('resolveSelectedGatewayWsHost falls back to connected gateway host',
        () {
      final wsHost = resolveSelectedGatewayWsHost(
        selectedGatewayId: 'gateways/gw-02',
        gateways: const [],
        connectedGatewayCandidate: const {
          'gateway_id': 'gw-02',
          'host_ws': 'ws://10.0.0.44:81',
        },
        normalizeRefId: normalizeRefId,
      );

      expect(wsHost, 'ws://10.0.0.44:81');
    });

    test('matchesSelectedGatewayId accepts only the selected gateway id', () {
      expect(
        matchesSelectedGatewayId(
          selectedGatewayId: 'gateways/gw-03',
          candidateGatewayId: 'gw-03',
          normalizeRefId: normalizeRefId,
        ),
        isTrue,
      );

      expect(
        matchesSelectedGatewayId(
          selectedGatewayId: 'gateways/gw-03',
          candidateGatewayId: 'gw-99',
          normalizeRefId: normalizeRefId,
        ),
        isFalse,
      );
    });

    test('fallbackSelectedGatewayWsHost uses singleton discovery as fallback',
        () {
      final wsHost = fallbackSelectedGatewayWsHost(
        propertyGateways: const [
          {
            'id': 'gw-01',
            'host': '192.168.4.1',
          },
        ],
        discoveredGateways: const [
          {
            'gateway_id': 'RT-M-ABC123',
            'host_ws': 'ws://192.168.1.55:81',
          },
        ],
      );

      expect(wsHost, 'ws://192.168.1.55:81');
    });
  });
}
