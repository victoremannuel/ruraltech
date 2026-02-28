/// Configuracoes manuais do app para ambiente/rede.
/// Edite este arquivo ao mover o sistema para outro local.
class ManualSettings {
  const ManualSettings._();

  // RTDB fallback caso o databaseURL nao esteja definido no FirebaseOptions.
  static const String firebaseRtdbUrl = String.fromEnvironment(
    'FIREBASE_RTDB_URL',
    defaultValue: 'https://ruraltech10-default-rtdb.firebaseio.com',
  );

  // Host padrao de conexao WebSocket com gateway.
  static const String defaultGatewayWsHost = String.fromEnvironment(
    'RT_GATEWAY_WS_HOST',
    defaultValue: 'ws://192.168.4.1:81',
  );

  // Identificador usado no user-agent de tiles de mapa (OSM).
  static const String mapUserAgentPackageName = 'com.victor.ruraltechapp';

  // Sub-redes usadas na descoberta local de gateway/coleira via Wi-Fi.
  static const List<String> onboardingSubnets = <String>[
    '192.168.4',
  ];

  // Limite de hosts por sub-rede na descoberta ativa.
  static const int onboardingSubnetProbeLimit = 120;
}
