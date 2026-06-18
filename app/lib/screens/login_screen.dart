import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: RTColors.bg,
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: screenHeight * 0.42,
            child: const _Hero(),
          ),
          Positioned(
            top: screenHeight * 0.36,
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                color: RTColors.bg,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(RTRadius.r5),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Entrar na operação',
                          style: RTTypography.h2.copyWith(fontSize: 24)),
                      const SizedBox(height: 6),
                      Text(
                        'Monitore propriedades, coleiras e gateways em campo.',
                        style: RTTypography.body
                            .copyWith(color: RTColors.inkSoft),
                      ),
                      const SizedBox(height: RTSpacing.x6),
                      RTField(
                        fieldKey: const Key('login_email_input'),
                        controller: _email,
                        label: 'E-mail',
                        hint: 'voce@fazenda.com',
                        leadingIcon: Icons.mail_outline,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        errorText: _emailError,
                        onChanged: (_) {
                          if (_emailError != null) {
                            setState(() => _emailError = null);
                          }
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
                          if (_passError != null) {
                            setState(() => _passError = null);
                          }
                        },
                        onSubmitted: _loading
                            ? null
                            : (_) => _runAuth(
                                () => auth.signIn(_email.text, _pass.text)),
                      ),
                      const SizedBox(height: RTSpacing.x6),
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
                                () => auth.signIn(_email.text, _pass.text)),
                      ),
                      const SizedBox(height: RTSpacing.x3),
                      RTButton(
                        key: const Key('login_signup_button'),
                        label: 'Criar conta',
                        variant: RTButtonVariant.ghost,
                        fullWidth: true,
                        onPressed: _loading
                            ? null
                            : () => _runAuth(
                                () => auth.signUp(_email.text, _pass.text)),
                      ),
                      const SizedBox(height: RTSpacing.x6),
                      _offlineHint(),
                    ],
                  ),
                ),
              ),
            ),
          ),
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

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [RTColors.heroStart, RTColors.heroEnd],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.08,
              child: CustomPaint(painter: _TopographyPainter()),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.terrain_outlined,
                      color: Colors.white, size: 22),
                ),
                const SizedBox(width: 10),
                Text(
                  'RuralTech',
                  style: RTTypography.h3.copyWith(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ]),
            ),
          ),
          Center(
            child: SizedBox(
              width: 220,
              height: 130,
              child: CustomPaint(painter: _PropertyPolygonPainter()),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopographyPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    for (double y = 20; y < size.height; y += 30) {
      final path = Path()..moveTo(0, y);
      for (double x = 0; x < size.width; x += 60) {
        path.quadraticBezierTo(x + 15, y - 15, x + 30, y);
        path.quadraticBezierTo(x + 45, y + 15, x + 60, y);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

class _PropertyPolygonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = const Color(0xFFE7A300).withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final poly = Path()
      ..moveTo(size.width * 0.15, size.height * 0.45)
      ..lineTo(size.width * 0.45, size.height * 0.10)
      ..lineTo(size.width * 0.85, size.height * 0.30)
      ..lineTo(size.width * 0.90, size.height * 0.70)
      ..lineTo(size.width * 0.55, size.height * 0.95)
      ..lineTo(size.width * 0.20, size.height * 0.85)
      ..close();

    canvas.drawPath(poly, fillPaint);
    _drawDashedPath(canvas, poly, strokePaint, dashWidth: 5, gap: 4);

    final dotPaint = Paint()..color = Colors.white;
    canvas.drawCircle(
        Offset(size.width * 0.35, size.height * 0.35), 4, dotPaint);
    canvas.drawCircle(
        Offset(size.width * 0.55, size.height * 0.55), 4, dotPaint);
    canvas.drawCircle(
      Offset(size.width * 0.50, size.height * 0.30),
      5,
      Paint()..color = const Color(0xFFE7A300),
    );
  }

  void _drawDashedPath(Canvas canvas, Path path, Paint paint,
      {double dashWidth = 5, double gap = 4}) {
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final end = (distance + dashWidth).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += dashWidth + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}
