import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../utils/top_feedback.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _loading = false;

  String _authErrorMessage(Object e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'invalid-email':
          return 'Email invalido.';
        case 'invalid-credential':
          return 'Email ou senha invalidos.';
        case 'user-not-found':
          return 'Usuario nao encontrado.';
        case 'wrong-password':
          return 'Senha incorreta.';
        case 'email-already-in-use':
          return 'Este email ja esta em uso.';
        case 'weak-password':
          return 'Senha fraca. Use ao menos 6 caracteres.';
        case 'too-many-requests':
          return 'Muitas tentativas. Tente novamente em alguns minutos.';
        default:
          return e.message ?? 'Falha na autenticacao.';
      }
    }
    return e.toString();
  }

  Future<void> _runAuth(Future<void> Function() action) async {
    final email = _email.text.trim();
    final pass = _pass.text;
    if (email.isEmpty || pass.isEmpty) {
      AppFeedback.error('Preencha email e senha.');
      return;
    }
    setState(() => _loading = true);
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      AppFeedback.error(_authErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    return Scaffold(
      appBar: AppBar(title: const Text('RuralTech Login')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/branding/logotipo.png',
                  width: 260,
                ),
                const SizedBox(height: 18),
                TextField(
                  key: const Key('login_email_input'),
                  controller: _email,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('login_password_input'),
                  controller: _pass,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Senha'),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    key: const Key('login_signin_button'),
                    onPressed: _loading
                        ? null
                        : () => _runAuth(
                              () => auth.signIn(_email.text, _pass.text),
                            ),
                    child: _loading
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Entrar'),
                  ),
                ),
                TextButton(
                  key: const Key('login_signup_button'),
                  onPressed: _loading
                      ? null
                      : () =>
                          _runAuth(() => auth.signUp(_email.text, _pass.text)),
                  child: const Text('Criar conta'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
