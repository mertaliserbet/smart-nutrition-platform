import 'package:flutter/material.dart';

import 'email_verification_page.dart';
import 'forgot_password_page.dart';
import 'login_page.dart';
import 'register_page.dart';
import 'auth_session.dart';
import '../navigation/main_shell.dart';
import '../dietitians/dietitian_finder_page.dart';
import '../dietitians/client_connections_page.dart';
import 'web_panel_link.dart';
import '../personal_nutrition_targets/personal_nutrition_target_page.dart';
import '../health/device_health_page.dart';
import '../client_tasks/client_task_page.dart';

/// Route arguments, build mode and unverified login responses grant no access.
class AuthGate extends StatelessWidget {
  const AuthGate({this.initialIndex = 0, this.child, super.key});
  final int initialIndex;
  final Widget? child;

  static Route<void> route(RouteSettings settings) {
    final page = switch (settings.name) {
      '/register' => const RegisterPage(),
      '/email-verification' => const EmailVerificationPage(),
      '/forgot-password' => const ForgotPasswordPage(),
      '/nutrition' => const AuthGate(initialIndex: 1),
      '/progress' => const AuthGate(initialIndex: 2),
      '/profile' => const AuthGate(initialIndex: 3),
      '/personal-nutrition-targets' => const AuthGate(
        child: PersonalNutritionTargetPage(),
      ),
      '/dietitians' => const AuthGate(child: DietitianFinderPage()),
      '/client-connections' => const AuthGate(child: ClientConnectionsPage()),
      '/dietitian-account' => const AuthGate(child: WebPanelPage()),
      '/device-health' => const AuthGate(child: DeviceHealthPage()),
      '/client-tasks' => const AuthGate(child: ClientTaskPage()),
      _ => const AuthGate(),
    };

    return MaterialPageRoute<void>(
      settings: settings,
      builder: (context) => page,
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = AuthSessionScope.maybeOf(context);
    final account = session?.user;
    if (account == null) return const LoginPage();
    if (account.role != 'client') {
      return WebPanelPage(key: ValueKey(account.id), showSignOut: true);
    }
    return child ??
        MainShell(
          initialIndex: initialIndex,
          onLogout: () => session!.signOut(),
        );
  }
}
