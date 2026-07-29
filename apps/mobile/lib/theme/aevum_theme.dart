import 'package:flutter/material.dart';

import 'aevum_colors.dart';

class AevumTheme {
  AevumTheme._();

  static ThemeData light() {
    // Despite the method name, the Aevum brand is a dark theme.
    final colorScheme = ColorScheme.dark(
      primary: AevumColors.primary,
      secondary: AevumColors.secondary,
      error: AevumColors.error,
      surface: AevumColors.surface,
      onPrimary: AevumColors.background,
      onSecondary: AevumColors.background,
      onSurface: AevumColors.textPrimary,
      onError: Colors.white,
    );

    return ThemeData(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AevumColors.background,
      canvasColor: AevumColors.background,
      cardColor: AevumColors.surface,
      dividerColor: AevumColors.border,
      appBarTheme: const AppBarTheme(
        backgroundColor: AevumColors.surfaceDim,
        foregroundColor: AevumColors.textPrimary,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: AevumColors.surface,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AevumColors.border),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AevumColors.primary,
          foregroundColor: AevumColors.background,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AevumColors.primary,
          side: const BorderSide(color: AevumColors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AevumColors.muted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AevumColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AevumColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AevumColors.primary, width: 2),
        ),
        labelStyle: const TextStyle(color: AevumColors.textSecondary),
        hintStyle: const TextStyle(color: AevumColors.textSecondary),
        prefixIconColor: AevumColors.textSecondary,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? AevumColors.primary
                : AevumColors.muted;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? AevumColors.background
                : AevumColors.textSecondary;
          }),
          side: WidgetStateProperty.all(const BorderSide(color: AevumColors.border)),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(color: AevumColors.textPrimary, fontWeight: FontWeight.w600, letterSpacing: -0.5),
        headlineMedium: TextStyle(color: AevumColors.textPrimary, fontWeight: FontWeight.w600, letterSpacing: -0.5),
        titleLarge: TextStyle(color: AevumColors.textPrimary, fontWeight: FontWeight.w500),
        bodyLarge: TextStyle(color: AevumColors.textPrimary),
        bodyMedium: TextStyle(color: AevumColors.textPrimary),
        bodySmall: TextStyle(color: AevumColors.textSecondary),
        labelLarge: TextStyle(color: AevumColors.textPrimary, fontWeight: FontWeight.w600),
      ),
      useMaterial3: true,
      brightness: Brightness.dark,
    );
  }
}
