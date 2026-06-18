import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'colors.dart';

/// Tipografia do RuralTech v2.
///
/// Três famílias:
/// - **Inter Tight** → displays, títulos
/// - **Inter** → corpo, UI geral
/// - **JetBrains Mono** → dados técnicos (IDs LoRa, coords, HDOP, RSSI)
class RTTypography {
  RTTypography._();

  static TextStyle get h1 => GoogleFonts.interTight(
        fontSize: 56,
        fontWeight: FontWeight.w700,
        height: 1.05,
        letterSpacing: -0.04 * 56,
        color: RTColors.ink,
      );

  static TextStyle get h2 => GoogleFonts.interTight(
        fontSize: 36,
        fontWeight: FontWeight.w700,
        height: 1.1,
        letterSpacing: -0.03 * 36,
        color: RTColors.ink,
      );

  static TextStyle get h3 => GoogleFonts.interTight(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        height: 1.2,
        letterSpacing: -0.02 * 22,
        color: RTColors.ink,
      );

  /// Eyebrow / seções (uppercase no conteúdo).
  static TextStyle get eyebrow => GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 1.3,
        letterSpacing: 0.08 * 12,
        color: RTColors.inkSoft,
      );

  static TextStyle get body => GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.55,
        color: RTColors.ink,
      );

  static TextStyle get bodyStrong => GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        height: 1.55,
        color: RTColors.ink,
      );

  static TextStyle get bodySmall => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        height: 1.45,
        color: RTColors.inkSoft,
      );

  static TextStyle get label => GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: RTColors.ink,
      );

  /// Dados técnicos (coords, HDOP, RSSI, IDs).
  static TextStyle get mono => GoogleFonts.jetBrainsMono(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        height: 1.4,
        letterSpacing: -0.01 * 13,
        color: RTColors.ink,
      );

  static TextStyle get monoSmall => GoogleFonts.jetBrainsMono(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: RTColors.inkSoft,
      );

  static TextStyle get monoLarge => GoogleFonts.jetBrainsMono(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.3,
        letterSpacing: -0.01 * 16,
        color: RTColors.ink,
      );

  /// TextTheme compatível com Material 3.
  static TextTheme textTheme() => TextTheme(
        displayLarge: h1,
        displayMedium: h2,
        displaySmall: h3,
        headlineLarge: h2,
        headlineMedium: h3,
        headlineSmall: h3.copyWith(fontSize: 18),
        titleLarge: GoogleFonts.interTight(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: RTColors.ink,
          letterSpacing: -0.01 * 20,
        ),
        titleMedium: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: RTColors.ink,
        ),
        titleSmall: label,
        bodyLarge: body,
        bodyMedium: body.copyWith(fontSize: 14),
        bodySmall: bodySmall,
        labelLarge: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: RTColors.ink,
        ),
        labelMedium: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: RTColors.inkSoft,
        ),
        labelSmall: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: RTColors.inkSoft,
          letterSpacing: 0.04 * 11,
        ),
      );
}
