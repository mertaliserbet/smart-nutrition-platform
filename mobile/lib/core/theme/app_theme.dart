import 'package:flutter/material.dart';

import 'app_tokens.dart';

abstract final class AppTheme {
  static final light = _build(Brightness.light);
  static final dark = _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppTokens.brandPrimary,
        brightness: brightness,
      ),
    );

    return theme.copyWith(
      textTheme: theme.textTheme.copyWith(
        headlineMedium: theme.textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
      ),
    );
  }
}
