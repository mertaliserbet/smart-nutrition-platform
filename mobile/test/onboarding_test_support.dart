import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Existing authentication tests explicitly choose login from the new welcome.
Future<void> openLoginFromWelcome(WidgetTester tester) async {
  final login = find.byKey(const ValueKey('onboarding-login'));
  if (login.evaluate().isNotEmpty) {
    await tester.ensureVisible(login);
    await tester.pumpAndSettle();
    await tester.tap(login);
    await tester.pumpAndSettle();
  }
}
