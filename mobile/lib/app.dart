import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/login_page.dart';
import 'features/navigation/main_shell.dart';

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
      home: kDebugMode ? const MainShell() : const LoginPage(),
    );
  }
}
