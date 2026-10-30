import 'package:flutter/material.dart';

import 'email_verification_page.dart';
import 'forgot_password_page.dart';
import 'login_page.dart';
import 'register_page.dart';

/// Keeps navigation signed out until a real mobile session can be verified.
///
/// There is no API-backed session source yet, so no authenticated route is
/// registered. Build mode, route arguments and form submissions cannot grant
/// access. Add the authenticated branch with real session verification only.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  static Route<void> route(RouteSettings settings) {
    final page = switch (settings.name) {
      '/register' => const RegisterPage(),
      '/email-verification' => const EmailVerificationPage(),
      '/forgot-password' => const ForgotPasswordPage(),
      _ => const AuthGate(),
    };

    return MaterialPageRoute<void>(
      settings: settings,
      builder: (context) => page,
    );
  }

  @override
  Widget build(BuildContext context) => const LoginPage();
}
