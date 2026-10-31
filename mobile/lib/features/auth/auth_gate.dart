import 'package:flutter/material.dart';

import 'email_verification_page.dart';
import 'forgot_password_page.dart';
import 'login_page.dart';
import 'register_page.dart';
import 'auth_session.dart';
import '../navigation/main_shell.dart';

/// Route arguments, build mode and unverified login responses grant no access.
class AuthGate extends StatelessWidget {
  const AuthGate({this.initialIndex = 0, super.key});
  final int initialIndex;

  static Route<void> route(RouteSettings settings) {
    final page = switch (settings.name) {
      '/register' => const RegisterPage(),
      '/email-verification' => const EmailVerificationPage(),
      '/forgot-password' => const ForgotPasswordPage(),
      '/nutrition' => const AuthGate(initialIndex: 1),
      '/progress' => const AuthGate(initialIndex: 2),
      '/profile' => const AuthGate(initialIndex: 3),
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
    return session?.isAuthenticated == true
        ? MainShell(
            initialIndex: initialIndex,
            onLogout: () => session!.signOut(),
          )
        : const LoginPage();
  }
}
