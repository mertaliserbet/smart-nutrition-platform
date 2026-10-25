import 'package:flutter/material.dart';

/// Initial mobile values, pending the shared design approval in docs/09 and 12.
/// Typography and surface/text colors use Material 3 TextTheme/ColorScheme roles.
abstract final class AppTokens {
  // Mobile counterpart of color.brand.primary; not a final brand palette.
  static const brandPrimary = Color(0xFF386A5E);

  static const spacingSmall = 8.0;
  static const spacingMedium = 16.0;
  static const spacingLarge = 24.0;
  static const spacingExtraLarge = 32.0;

  static const radiusMedium = 16.0;
  static const contentMaxWidth = 480.0;
  static const brandIconSize = 40.0;
}
