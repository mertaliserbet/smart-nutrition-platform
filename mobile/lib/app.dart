import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/auth_gate.dart';

class SmartNutritionApp extends StatelessWidget {
  const SmartNutritionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Nutrition',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      onGenerateRoute: AuthGate.route,
      // Resolve startup/deep links through the same public route allowlist.
      onGenerateInitialRoutes: (name) => [
        // Public entry pages must have a safe login route to return to.
        if (const [
          '/register',
          '/email-verification',
          '/forgot-password',
        ].contains(name))
          AuthGate.route(const RouteSettings(name: '/')),
        AuthGate.route(RouteSettings(name: name)),
      ],
    );
  }
}
