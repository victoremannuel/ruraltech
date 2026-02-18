import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    return Scaffold(
      appBar: AppBar(title: const Text('RuralTech Login')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email')),
            TextField(controller: _pass, obscureText: true, decoration: const InputDecoration(labelText: 'Senha')),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: () => auth.signIn(_email.text, _pass.text), child: const Text('Entrar')),
            TextButton(onPressed: () => auth.signUp(_email.text, _pass.text), child: const Text('Criar conta')),
          ],
        ),
      ),
    );
  }
}
