import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'services/firebase_service.dart';
import 'services/gateway_service.dart';
import 'services/map_filter_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  String? bootstrapError;

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
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
        home: Scaffold(
          appBar: AppBar(title: const Text('RuralTech')),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Falha ao iniciar Firebase.',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Text(bootstrapError!),
                const SizedBox(height: 12),
                const Text(
                  'Configure o Firebase para esta plataforma (iOS) e rode novamente.',
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
        Provider(create: (_) => FirebaseService()),
        ChangeNotifierProvider(create: (_) => GatewayService()),
        ChangeNotifierProvider(create: (_) => MapFilterService()),
      ],
      child: MaterialApp(
        title: 'RuralTech',
        theme: ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true),
        home: Consumer<AuthService>(
          builder: (_, auth, __) =>
              auth.user == null ? const LoginScreen() : const HomeScreen(),
        ),
      ),
    );
  }
}
