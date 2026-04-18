import 'package:flutter/material.dart';

import '../../design/colors.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';

/// Scaffold de autenticação com hero topográfico + sheet curvo branco.
///
/// Usado em Login e Signup. O hero usa gradiente terra → floresta e um padrão
/// topográfico desenhado em CustomPainter (sem asset externo).
class RTAuthScaffold extends StatelessWidget {
  const RTAuthScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.heroHeight = 280,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final double heroHeight;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final topPadding = media.padding.top;
    final bottomPadding = media.viewInsets.bottom;

    return Scaffold(
      backgroundColor: RTColors.bg,
      resizeToAvoidBottomInset: true,
      body: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: Column(
          children: [
            SizedBox(
              height: heroHeight + topPadding,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [RTColors.heroStart, RTColors.heroEnd],
                        ),
                      ),
                      child: CustomPaint(
                        painter: _TopographicPainter(
                          color: RTColors.heroInk.withValues(alpha: 0.10),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      RTSpacing.x6,
                      topPadding + RTSpacing.x8,
                      RTSpacing.x6,
                      RTSpacing.x6,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _brand(),
                        const Spacer(),
                        Text(
                          title,
                          style: RTTypography.h2.copyWith(
                            color: RTColors.heroInk,
                            fontSize: 30,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: RTSpacing.x2),
                        Text(
                          subtitle,
                          style: RTTypography.body.copyWith(
                            color: RTColors.heroInk.withValues(alpha: 0.85),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Transform.translate(
              offset: const Offset(0, -28),
              child: Container(
                decoration: BoxDecoration(
                  color: RTColors.bg,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(RTRadius.r5),
                  ),
                  boxShadow: RTElevation.sh2,
                ),
                padding: const EdgeInsets.fromLTRB(
                  RTSpacing.x6,
                  RTSpacing.x6,
                  RTSpacing.x6,
                  RTSpacing.x6,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: child,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _brand() {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: RTColors.heroInk.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(RTRadius.r2),
            border: Border.all(
              color: RTColors.heroInk.withValues(alpha: 0.35),
            ),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.landscape_outlined,
            color: RTColors.heroInk,
            size: 20,
          ),
        ),
        const SizedBox(width: RTSpacing.x2),
        Text(
          'RuralTech',
          style: RTTypography.h3.copyWith(
            color: RTColors.heroInk,
            fontSize: 18,
          ),
        ),
      ],
    );
  }
}

class _TopographicPainter extends CustomPainter {
  _TopographicPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final w = size.width;
    final h = size.height;
    // Curvas concêntricas simulando isolinhas topográficas.
    for (var i = 0; i < 8; i++) {
      final t = i / 8;
      final path = Path();
      path.moveTo(-20, h * (0.25 + t * 0.6));
      path.cubicTo(
        w * 0.25, h * (0.15 + t * 0.55),
        w * 0.55, h * (0.45 + t * 0.35),
        w + 20, h * (0.2 + t * 0.5),
      );
      canvas.drawPath(path, paint);
    }

    // Círculos decorativos (pontos de referência).
    final dotPaint = Paint()
      ..color = color.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(w * 0.2, h * 0.35), 2.5, dotPaint);
    canvas.drawCircle(Offset(w * 0.75, h * 0.55), 2, dotPaint);
    canvas.drawCircle(Offset(w * 0.55, h * 0.75), 3, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _TopographicPainter oldDelegate) =>
      oldDelegate.color != color;
}
