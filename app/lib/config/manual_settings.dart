/// Configuracoes manuais do app para ambiente/rede.
/// Edite este arquivo ao mover o sistema para outro local.
class ManualSettings {
  const ManualSettings._();

  // Supabase como backend principal do app.
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://nhoewnfuyjbtpklrotbf.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_Esa4TxfvLs6Slc_WA5DFUw_RY8H7Uug',
  );

  static const String supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_Esa4TxfvLs6Slc_WA5DFUw_RY8H7Uug',
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
    '192.168.1',
    '192.168.0',
    '10.0.0',
  ];

  // Limite de hosts por sub-rede na descoberta ativa.
  static const int onboardingSubnetProbeLimit = 120;
}
