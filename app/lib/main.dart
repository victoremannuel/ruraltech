import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/manual_settings.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'services/bluetooth_discovery_service.dart';
import 'services/cloud_service.dart';
import 'services/gateway_service.dart';
import 'services/map_filter_service.dart';
import 'services/notification_service.dart';
import 'utils/top_feedback.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  String? bootstrapError;

  try {
    await Supabase.initialize(
      url: ManualSettings.supabaseUrl,
      anonKey: ManualSettings.supabaseAnonKey,
    );
  } catch (e) {
    bootstrapError = e.toString();
  }

  runApp(RuralTechApp(bootstrapError: bootstrapError));
}

class RuralTechApp extends StatelessWidget {
  const RuralTechApp({super.key, this.bootstrapError});

  final String? bootstrapError;

  @override
  Widget build(BuildContext context) {
    if (bootstrapError != null) {
      return MaterialApp(
        title: 'RuralTech',
        builder: (context, child) => AppFeedbackHost(
          child: child ?? const SizedBox.shrink(),
        ),
        home: Scaffold(
          appBar: AppBar(title: const Text('RuralTech')),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Falha ao iniciar o backend.',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Text(bootstrapError!),
                const SizedBox(height: 12),
                const Text(
                  'Configure o Supabase para esta plataforma suportada e rode novamente.',
                ),
              ],
            ),
          ),
        ),
      );
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        Provider(create: (_) => CloudService()),
        ChangeNotifierProvider(create: (_) => GatewayService()),
        ChangeNotifierProvider(create: (_) => BluetoothDiscoveryService()),
        ChangeNotifierProvider(create: (_) => MapFilterService()),
        ChangeNotifierProvider(create: (_) => NotificationService()),
      ],
      child: MaterialApp(
        title: 'RuralTech',
        builder: (context, child) => AppFeedbackHost(
          child: child ?? const SizedBox.shrink(),
        ),
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: Colors.white,
          colorScheme: const ColorScheme(
            brightness: Brightness.light,
            primary: Color(0xFF2F7D3D),
            onPrimary: Colors.white,
            secondary: Color(0xFFE7A300),
            onSecondary: Colors.white,
            error: Color(0xFFB3261E),
            onError: Colors.white,
            surface: Colors.white,
            onSurface: Color(0xFF173120),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFFF2F7F1),
            foregroundColor: Color(0xFF173120),
            surfaceTintColor: Colors.transparent,
            elevation: 0,
          ),
          cardTheme: const CardThemeData(
            color: Colors.white,
            surfaceTintColor: Colors.transparent,
            shadowColor: Color(0x22000000),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFFF6FAF5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFB8CFBD)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFB8CFBD)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: Color(0xFF2F7D3D), width: 1.4),
            ),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2F7D3D),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF2F7D3D),
              side: const BorderSide(color: Color(0xFF2F7D3D)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          textSelectionTheme: const TextSelectionThemeData(
            cursorColor: Color(0xFF2F7D3D),
            selectionColor: Color(0x552F7D3D),
            selectionHandleColor: Color(0xFF2F7D3D),
          ),
        ),
        home: Consumer<AuthService>(
          builder: (_, auth, __) => auth.user == null
              ? const LoginScreen()
              : const _AuthenticatedHome(),
        ),
      ),
    );
  }
}

class _AuthenticatedHome extends StatefulWidget {
  const _AuthenticatedHome();

  @override
  State<_AuthenticatedHome> createState() => _AuthenticatedHomeState();
}

class _AuthenticatedHomeState extends State<_AuthenticatedHome> {
  String? _initializedUid;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<AuthService>();
    final firebase = context.read<CloudService>();
    final notifications = context.read<NotificationService>();
    final uid = auth.user?.uid;
    if (uid == null || uid == _initializedUid) return;
    _initializedUid = uid;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      notifications.initialize(uid: uid, firebase: firebase);
    });
  }

  @override
  Widget build(BuildContext context) {
    return const HomeScreen();
  }
}
