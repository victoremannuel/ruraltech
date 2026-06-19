import 'package:flutter/material.dart';

import 'colors.dart';
import 'tokens.dart';
import 'typography.dart';

/// Constrói o [ThemeData] oficial do RuralTech v2.
///
/// Mantém Material 3 e usa tokens OKLCH + fontes Inter Tight/Inter/JetBrains
/// Mono. Componentes primitivos (`RT*`) assumem estas tokens.
ThemeData buildRuralTechTheme() {
  final colorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: RTColors.primary,
    onPrimary: RTColors.onPrimary,
    primaryContainer: RTColors.primarySoft,
    onPrimaryContainer: RTColors.primaryDeep,
    secondary: RTColors.accent,
    onSecondary: RTColors.onAccent,
    secondaryContainer: RTColors.accentSoft,
    onSecondaryContainer: RTColors.ink,
    tertiary: RTColors.info,
    onTertiary: RTColors.onPrimary,
    tertiaryContainer: RTColors.infoSoft,
    onTertiaryContainer: RTColors.ink,
    error: RTColors.danger,
    onError: RTColors.onPrimary,
    errorContainer: RTColors.dangerSoft,
    onErrorContainer: RTColors.ink,
    surface: RTColors.bg,
    onSurface: RTColors.ink,
    surfaceContainerHighest: RTColors.bgSubtle,
    surfaceContainerHigh: RTColors.bgAlt,
    surfaceContainer: RTColors.bgAlt,
    surfaceContainerLow: RTColors.bg,
    surfaceContainerLowest: RTColors.bg,
    onSurfaceVariant: RTColors.inkSoft,
    outline: RTColors.hair,
    outlineVariant: RTColors.hairSoft,
    shadow: const Color(0xFF000000),
    scrim: const Color(0xFF000000),
    inverseSurface: RTColors.ink,
    onInverseSurface: RTColors.bg,
    inversePrimary: RTColors.primarySoft,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: RTColors.bg,
    canvasColor: RTColors.bg,
    textTheme: RTTypography.textTheme(),
    appBarTheme: AppBarTheme(
      backgroundColor: RTColors.bg,
      foregroundColor: RTColors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: RTTypography.h3.copyWith(fontSize: 18),
      iconTheme: IconThemeData(color: RTColors.ink, size: 24),
    ),
    cardTheme: CardThemeData(
      color: RTColors.bg,
      surfaceTintColor: Colors.transparent,
      shadowColor: const Color(0x14141E19),
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RTRadius.r3),
        side: BorderSide(color: RTColors.hairSoft),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: RTColors.hairSoft,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: RTColors.bgAlt,
      hintStyle: RTTypography.body.copyWith(color: RTColors.inkMute),
      labelStyle: RTTypography.bodySmall.copyWith(color: RTColors.inkSoft),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: RTSpacing.x4,
        vertical: RTSpacing.x3,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(RTRadius.r3),
        borderSide: BorderSide(color: RTColors.hair),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(RTRadius.r3),
        borderSide: BorderSide(color: RTColors.hair),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(RTRadius.r3),
        borderSide: BorderSide(color: RTColors.primary, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(RTRadius.r3),
        borderSide: BorderSide(color: RTColors.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(RTRadius.r3),
        borderSide: BorderSide(color: RTColors.danger, width: 1.6),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: RTColors.primary,
        foregroundColor: RTColors.onPrimary,
        textStyle: RTTypography.label,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: RTSpacing.x5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RTRadius.r3),
        ),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: RTColors.primary,
        side: BorderSide(color: RTColors.primary),
        textStyle: RTTypography.label,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: RTSpacing.x5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RTRadius.r3),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: RTColors.primary,
        textStyle: RTTypography.label,
        padding: const EdgeInsets.symmetric(
          horizontal: RTSpacing.x4,
          vertical: RTSpacing.x2,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: RTColors.bgAlt,
      selectedColor: RTColors.primarySoft,
      labelStyle: RTTypography.label.copyWith(fontSize: 12),
      side: BorderSide(color: RTColors.hair),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RTRadius.rFull),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: RTSpacing.x3,
        vertical: RTSpacing.x1,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: RTColors.bg,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(RTRadius.r5),
        ),
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: RTColors.primary,
      selectionColor: RTColors.primary.withValues(alpha: 0.3),
      selectionHandleColor: RTColors.primary,
    ),
    iconTheme: IconThemeData(color: RTColors.inkSoft, size: 22),
  );
}
