import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Tokens de cor do RuralTech v2.
///
/// As cores do handoff são definidas em OKLCH. Convertemos para sRGB em tempo
/// de carga para preservar a intenção perceptual sem depender de ferramentas
/// externas.
class RTColors {
  RTColors._();

  // Neutros (quentes, cromas sutis)
  static final Color bg = _oklch(0.985, 0.004, 95);
  static final Color bgAlt = _oklch(0.965, 0.008, 95);
  static final Color bgSubtle = _oklch(0.945, 0.012, 95);
  static final Color hairSoft = _oklch(0.92, 0.006, 150);
  static final Color hair = _oklch(0.90, 0.008, 150);
  static final Color inkMute = _oklch(0.58, 0.010, 150);
  static final Color inkSoft = _oklch(0.38, 0.015, 150);
  static final Color ink = _oklch(0.18, 0.015, 150);

  // Primário (floresta)
  static final Color primarySoft = _oklch(0.94, 0.04, 150);
  static final Color primary = _oklch(0.42, 0.11, 150);
  static final Color primaryDeep = _oklch(0.30, 0.10, 150);
  static final Color onPrimary = _oklch(0.99, 0.003, 95);

  // Accent (terra)
  static final Color accentSoft = _oklch(0.93, 0.05, 70);
  static final Color accent = _oklch(0.62, 0.14, 55);
  static final Color onAccent = _oklch(0.99, 0.003, 95);

  // Feedback
  static final Color ok = _oklch(0.55, 0.14, 150);
  static final Color okSoft = _oklch(0.93, 0.06, 150);
  static final Color warn = _oklch(0.72, 0.15, 75);
  static final Color warnSoft = _oklch(0.94, 0.07, 85);
  static final Color danger = _oklch(0.55, 0.19, 25);
  static final Color dangerSoft = _oklch(0.94, 0.05, 25);
  static final Color info = _oklch(0.55, 0.12, 230);
  static final Color infoSoft = _oklch(0.94, 0.04, 230);

  // Hero (login)
  static final Color heroStart = _oklch(0.62, 0.14, 55);
  static final Color heroEnd = _oklch(0.42, 0.11, 150);
  static final Color heroInk = _oklch(0.98, 0.01, 95);
}

/// Converte OKLCH → [Color] sRGB (8 bits por canal).
///
/// Algoritmo: OKLCH → OKLab → LMS linear → RGB linear → sRGB (gamma).
Color _oklch(double l, double c, double hDeg) {
  final hRad = hDeg * math.pi / 180.0;
  final a = c * math.cos(hRad);
  final b = c * math.sin(hRad);

  final lPrime = l + 0.3963377774 * a + 0.2158037573 * b;
  final mPrime = l - 0.1055613458 * a - 0.0638541728 * b;
  final sPrime = l - 0.0894841775 * a - 1.2914855480 * b;

  final lLin = lPrime * lPrime * lPrime;
  final mLin = mPrime * mPrime * mPrime;
  final sLin = sPrime * sPrime * sPrime;

  final rLin = 4.0767416621 * lLin - 3.3077115913 * mLin + 0.2309699292 * sLin;
  final gLin = -1.2684380046 * lLin + 2.6097574011 * mLin - 0.3413193965 * sLin;
  final bLin = -0.0041960863 * lLin - 0.7034186147 * mLin + 1.7076147010 * sLin;

  int toByte(double v) {
    final clamped = v.isNaN ? 0.0 : v.clamp(0.0, 1.0).toDouble();
    final gamma = clamped <= 0.0031308
        ? 12.92 * clamped
        : 1.055 * math.pow(clamped, 1.0 / 2.4) - 0.055;
    return (gamma * 255.0).round().clamp(0, 255);
  }

  return Color.fromARGB(255, toByte(rLin), toByte(gLin), toByte(bLin));
}
