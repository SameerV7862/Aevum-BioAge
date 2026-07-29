import 'package:flutter/material.dart';

import 'aevum_colors.dart';

class AevumTheme {
  AevumTheme._();

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AevumColors.primary,
      primary: AevumColors.primary,
      secondary: AevumColors.secondary,
      error: AevumColors.error,
      brightness: Brightness.light,
    );

    return ThemeData(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AevumColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: AevumColors.surface,
        foregroundColor: AevumColors.textPrimary,
        elevation: 0,
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: AevumColors.textPrimary),
        bodySmall: TextStyle(color: AevumColors.textSecondary),
      ),
      useMaterial3: true,
    );
  }
}
