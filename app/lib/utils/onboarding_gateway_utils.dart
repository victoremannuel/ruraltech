String? normalizeGatewayWsHost(String? raw) {
  final value = (raw ?? '').trim();
  if (value.isEmpty) return null;
  if (value.startsWith('ws://') || value.startsWith('wss://')) return value;
  if (value.startsWith('http://') || value.startsWith('https://')) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) return null;
    return 'ws://${uri.host}:81';
  }
  if (value.contains('://')) return null;
  if (value.contains(':')) return 'ws://$value';
  return 'ws://$value:81';
}

String? resolveSelectedGatewayWsHost({
  required String? selectedGatewayId,
  required Iterable<Map<String, dynamic>> gateways,
  Map<String, dynamic>? connectedGatewayCandidate,
  required String Function(dynamic raw) normalizeRefId,
}) {
  final normalizedGatewayId = normalizeRefId(selectedGatewayId);
  if (normalizedGatewayId.isEmpty) return null;

  Map<String, dynamic>? selectedGateway;
  for (final gateway in gateways) {
    if (normalizeRefId(gateway['id']) == normalizedGatewayId) {
      selectedGateway = gateway;
      break;
    }
  }

  final candidates = <dynamic>[
    selectedGateway?['host_ws'],
    selectedGateway?['hostWs'],
    selectedGateway?['host'],
    selectedGateway?['ip'],
    if (connectedGatewayCandidate != null &&
        normalizeRefId(
              connectedGatewayCandidate['gateway_id'] ??
                  connectedGatewayCandidate['gateway_id_raw'],
            ) ==
            normalizedGatewayId)
      connectedGatewayCandidate['host_ws'],
  ];

  for (final candidate in candidates) {
    final wsHost = normalizeGatewayWsHost(candidate?.toString());
    if (wsHost != null) return wsHost;
  }
  return null;
}

bool matchesSelectedGatewayId({
  required String? selectedGatewayId,
  required dynamic candidateGatewayId,
  required String Function(dynamic raw) normalizeRefId,
  bool allowMissingGatewayId = true,
}) {
  final normalizedSelectedGatewayId = normalizeRefId(selectedGatewayId);
  if (normalizedSelectedGatewayId.isEmpty) return true;

  final normalizedCandidateGatewayId = normalizeRefId(candidateGatewayId);
  if (normalizedCandidateGatewayId.isEmpty) return allowMissingGatewayId;
  return normalizedCandidateGatewayId == normalizedSelectedGatewayId;
}
