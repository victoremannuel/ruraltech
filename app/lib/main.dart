import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

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

const _kPollTaskName = 'poll_notifications';

/// Callback dispatcher executado em isolate separado pelo WorkManager (Android).
/// Re-inicializa Supabase, busca pending_notifications não entregues e exibe
/// via flutter_local_notifications. Ignora silenciosamente se não houver sessão.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, _) async {
    if (task != _kPollTaskName) return true;
    try {
      WidgetsFlutterBinding.ensureInitialized();
      DartPluginRegistrant.ensureInitialized();

      await Supabase.initialize(
        url: ManualSettings.supabaseUrl,
        anonKey: ManualSettings.supabaseAnonKey,
      );

      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) return true;

      final response = await Supabase.instance.client.functions
          .invoke('poll-notifications', body: <String, dynamic>{});

      final rows = response.data as List?;
      if (rows == null || rows.isEmpty) return true;

      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );

      for (final raw in rows) {
        final row = raw as Map<String, dynamic>;
        await plugin.show(
          DateTime.now().millisecondsSinceEpoch.remainder(100000),
          (row['title'] as String?)?.isNotEmpty == true
              ? row['title'] as String
              : 'RuralTech',
          row['body'] as String?,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'ruraltech_push',
              'RuralTech',
              channelDescription: 'Notificações do RuralTech',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
        );
      }
      return true;
    } catch (_) {
      return false;
    }
  });
}

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

  // Registra tarefa periódica WorkManager para polling de notificações em background
  // (Android). A tarefa verifica a sessão internamente e é no-op se não autenticado.
  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerPeriodicTask(
    _kPollTaskName,
    _kPollTaskName,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingWorkPolicy.keep,
  );

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
    final cloud = context.read<CloudService>();
    final notifications = context.read<NotificationService>();
    final uid = auth.user?.uid;
    if (uid == null || uid == _initializedUid) return;
    _initializedUid = uid;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      notifications.initialize(uid: uid, cloud: cloud);
    });
  }

  @override
  Widget build(BuildContext context) {
    return const HomeScreen();
  }
}
