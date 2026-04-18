import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../components/domain/rt_auth_scaffold.dart';
import '../components/primitives/rt_button.dart';
import '../components/primitives/rt_field.dart';
import '../design/colors.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../services/auth_service.dart';
import '../utils/cloud_compat.dart';
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
  String? _emailError;
  String? _passError;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  String _authErrorMessage(Object e) {
    if (e is CloudAuthException) {
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

  bool _validateInputs() {
    final email = _email.text.trim();
    final pass = _pass.text;
    String? emailErr;
    String? passErr;
    final emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (email.isEmpty) {
      emailErr = 'Informe o email.';
    } else if (!emailRe.hasMatch(email)) {
      emailErr = 'Email invalido.';
    }
    if (pass.isEmpty) {
      passErr = 'Informe a senha.';
    } else if (pass.length < 6) {
      passErr = 'Use ao menos 6 caracteres.';
    }
    setState(() {
      _emailError = emailErr;
      _passError = passErr;
    });
    return emailErr == null && passErr == null;
  }

  Future<void> _runAuth(Future<void> Function() action) async {
    if (!_validateInputs()) {
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

    return RTAuthScaffold(
      title: 'Bem-vindo de volta',
      subtitle: 'Entre para monitorar sua operação em campo.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RTField(
            fieldKey: const Key('login_email_input'),
            controller: _email,
            label: 'Email',
            hint: 'voce@fazenda.com',
            leadingIcon: Icons.mail_outline,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            errorText: _emailError,
            onChanged: (_) {
              if (_emailError != null) setState(() => _emailError = null);
            },
          ),
          const SizedBox(height: RTSpacing.x4),
          RTField(
            fieldKey: const Key('login_password_input'),
            controller: _pass,
            label: 'Senha',
            hint: 'Pelo menos 6 caracteres',
            leadingIcon: Icons.lock_outline,
            obscure: true,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            errorText: _passError,
            onChanged: (_) {
              if (_passError != null) setState(() => _passError = null);
            },
            onSubmitted: _loading
                ? null
                : (_) =>
                    _runAuth(() => auth.signIn(_email.text, _pass.text)),
          ),
          const SizedBox(height: RTSpacing.x5),
          RTButton(
            key: const Key('login_signin_button'),
            label: 'Entrar',
            trailing: Icons.arrow_forward,
            fullWidth: true,
            size: RTButtonSize.lg,
            loading: _loading,
            onPressed: _loading
                ? null
                : () => _runAuth(
                      () => auth.signIn(_email.text, _pass.text),
                    ),
          ),
          const SizedBox(height: RTSpacing.x3),
          RTButton(
            key: const Key('login_signup_button'),
            label: 'Criar conta',
            variant: RTButtonVariant.ghost,
            fullWidth: true,
            onPressed: _loading
                ? null
                : () =>
                    _runAuth(() => auth.signUp(_email.text, _pass.text)),
          ),
          const SizedBox(height: RTSpacing.x5),
          _offlineHint(),
        ],
      ),
    );
  }

  Widget _offlineHint() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RTSpacing.x3,
        vertical: RTSpacing.x3,
      ),
      decoration: BoxDecoration(
        color: RTColors.accentSoft,
        borderRadius: BorderRadius.circular(RTRadius.r3),
        border: Border.all(color: RTColors.accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi_off_outlined, color: RTColors.accent, size: 20),
          const SizedBox(width: RTSpacing.x2),
          Expanded(
            child: Text(
              'Sem sinal? Você ainda pode operar em modo offline — os dados sincronizam assim que o gateway voltar.',
              style: RTTypography.bodySmall.copyWith(color: RTColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}
