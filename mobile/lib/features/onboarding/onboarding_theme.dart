import 'package:flutter/material.dart';

/// Shared Limely presentation for the introduction and approved account screens.
abstract final class OnboardingTheme {
  static const background = Color(0xFFF8FAF2);
  static const ink = Color(0xFF203B2F);
  static const lime = Color(0xFFC9E879);
  static const soft = Color(0xFFEAF3DE);
  static const muted = Color(0xFF627365);
  static const border = Color(0xFFE1E7DB);
  static const selectedBorder = Color(0xFFBACF92);
  static const error = Color(0xFFA63131);

  // One complete Turkish font family for headings, controls and supporting text.
  static final data = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamily: 'Figtree',
    scaffoldBackgroundColor: background,
    colorScheme: const ColorScheme.light(
      primary: ink,
      onPrimary: background,
      secondary: lime,
      onSecondary: ink,
      surface: background,
      onSurface: ink,
      error: error,
      onError: Colors.white,
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: ink,
      selectionColor: lime,
      selectionHandleColor: ink,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        foregroundColor: ink,
        backgroundColor: lime,
        minimumSize: const Size(double.infinity, 56),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        textStyle: const TextStyle(
          fontFamily: 'Figtree',
          fontSize: 21,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
  );

  static TextStyle heading(double size) => TextStyle(
    fontSize: size,
    fontWeight: FontWeight.w800,
    height: 1.1,
    letterSpacing: -0.7,
    color: ink,
  );

  static const body = TextStyle(fontSize: 17, height: 1.45, color: muted);
  static const hint = TextStyle(fontSize: 14, height: 1.4, color: muted);
  static const shadow = [
    BoxShadow(color: Color(0x0C203B2F), blurRadius: 14, offset: Offset(0, 4)),
  ];
}

class OnboardingIcon extends StatelessWidget {
  const OnboardingIcon(this.name, {this.size = 24, super.key});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/limely/ikonlar/koyu/$name.png',
    width: size,
    height: size,
    excludeFromSemantics: true,
    filterQuality: FilterQuality.high,
  );
}
