import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'services/firebase_service.dart';
import 'services/gateway_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const RuralTechApp());
}

class RuralTechApp extends StatelessWidget {
  const RuralTechApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        Provider(create: (_) => FirebaseService()),
        ChangeNotifierProvider(create: (_) => GatewayService()),
      ],
      child: MaterialApp(
        title: 'RuralTech',
        theme: ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true),
        home: Consumer<AuthService>(
          builder: (_, auth, __) => auth.user == null
              ? const LoginScreen()
              : const DashboardScreen(),
        ),
      ),
    );
  }
}
