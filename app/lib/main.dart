import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

import 'config/manual_settings.dart';
import 'design/theme.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'services/bluetooth_discovery_service.dart';
import 'services/cloud_service.dart';
import 'services/gateway_service.dart';
import 'services/map_filter_service.dart';
import 'services/notification_service.dart';
import 'utils/pending_notifications.dart';
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

      final rows = extractPendingNotifications(response.data);
      if (rows.isEmpty) return true;

      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );

      for (final raw in rows) {
        final row = raw;
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

  // WorkManager é exclusivo do Android. Guard de plataforma + try-catch evitam
  // que uma PlatformException impeça o runApp() de ser chamado. kIsWeb é
  // checado primeiro para não tocar em dart:io Platform na web.
  if (!kIsWeb && Platform.isAndroid) {
    try {
      await Workmanager().initialize(callbackDispatcher);
      await Workmanager().registerPeriodicTask(
        _kPollTaskName,
        _kPollTaskName,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingWorkPolicy.keep,
      );
    } catch (e) {
      debugPrint('WorkManager init failed: $e');
    }
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
        theme: buildRuralTechTheme(),
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
        theme: buildRuralTechTheme(),
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
    return const HomeShell();
  }
}
