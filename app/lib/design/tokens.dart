import 'package:flutter/material.dart';

/// Spacing vertical/horizontal — escala base 4.
class RTSpacing {
  RTSpacing._();

  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;
  static const double x8 = 32;
  static const double x12 = 48;
  static const double x16 = 64;

  /// Padding padrão de telas.
  static const double screen = 16;

  /// Padding interno de cards.
  static const double card = 16;

  /// Espaço entre seções.
  static const double section = 24;
}

/// Raios de borda padronizados.
class RTRadius {
  RTRadius._();

  static const double r1 = 6; // chips, badges
  static const double r2 = 10; // buttons pequenos
  static const double r3 = 14; // cards, botões padrão
  static const double r4 = 18; // hero cards
  static const double r5 = 24; // bottom sheets, modais
  static const double rFull = 999;
}

/// Elevações (shadows) padronizadas.
class RTElevation {
  RTElevation._();

  static const List<BoxShadow> sh1 = [
    BoxShadow(
      color: Color(0x0F141E19),
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
    BoxShadow(
      color: Color(0x0A141E19),
      blurRadius: 0,
      offset: Offset(0, 1),
    ),
  ];

  static const List<BoxShadow> sh2 = [
    BoxShadow(
      color: Color(0x14141E19),
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
    BoxShadow(
      color: Color(0x0A141E19),
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
  ];

  static const List<BoxShadow> sh3 = [
    BoxShadow(
      color: Color(0x24141E19),
      blurRadius: 32,
      offset: Offset(0, 12),
    ),
    BoxShadow(
      color: Color(0x0F141E19),
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];

  static const List<BoxShadow> sh4 = [
    BoxShadow(
      color: Color(0x38141E19),
      blurRadius: 60,
      offset: Offset(0, 24),
    ),
    BoxShadow(
      color: Color(0x14141E19),
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];
}
