// Opt-in Android device check. Run with flutter run -t this file and a unique
// --dart-define=E2E_EMAIL=e2e-<random>@example.test. Never part of flutter test.
// Uses the existing SDK test controller and the real production HTTP client.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/app.dart';
import 'package:smart_nutrition_mobile/core/network/api_config.dart';
import 'package:smart_nutrition_mobile/features/auth/email_verification_page.dart';
import 'package:smart_nutrition_mobile/features/auth/login_page.dart';
import 'package:smart_nutrition_mobile/features/auth/register_page.dart';
import 'package:smart_nutrition_mobile/features/auth/registration_api.dart';
import 'package:smart_nutrition_mobile/features/navigation/main_shell.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  final controller = LiveWidgetController(binding);
  const email = String.fromEnvironment('E2E_EMAIL');
  var phase = 'configuration';
  final errors = <String>[];
  FlutterError.onError = (details) {
    // Report only error types, never widget contents, credentials or responses.
    errors.add(details.exception.runtimeType.toString());
  };
  final results = <String, Object>{};
  try {
    check(RegExp(r'^e2e-[a-z0-9-]+@example\.test$').hasMatch(email));
    final origin = ApiConfig.baseUri;
    check(origin.scheme == 'https' && origin.host == 'localhost');
    results['apiOrigin'] = origin.toString();
    final random = Random.secure();
    final password = base64UrlEncode(
      List<int>.generate(24, (_) => random.nextInt(256)),
    );

    phase = 'device_backend_connection';
    final client = HttpClient(context: ApiConfig.developmentSecurityContext);
    try {
      final request = await client.getUrl(origin.resolve('/health/ready'));
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      check(response.statusCode == 200);
      await response.drain<void>();
      results['deviceReadyStatus'] = response.statusCode;
    } finally {
      client.close(force: true);
    }

    phase = 'open_real_application';
    runApp(const SmartNutritionApp());
    await controller.pump(const Duration(milliseconds: 300));
    await waitFor(
      controller,
      () => find.byType(LoginPage).evaluate().isNotEmpty,
    );
    await tap(controller, 'Hesabınız yok mu? Kayıt ol');
    await waitFor(
      controller,
      () => find.byType(RegisterPage).evaluate().isNotEmpty,
    );

    phase = 'invalid_form';
    await tap(controller, 'Kayıt ol');
    check(find.text('Adınızı ve soyadınızı girin.').evaluate().length == 1);
    check(find.byType(EmailVerificationPage).evaluate().isEmpty);
    results['invalidFormStayedOnRegistration'] = true;

    phase = 'successful_registration';
    await fill(controller, email, password);
    await tap(controller, 'Kayıt ol');
    await waitFor(
      controller,
      () => find.byType(EmailVerificationPage).evaluate().isNotEmpty,
    );
    final page = controller.widget<EmailVerificationPage>(
      find.byType(EmailVerificationPage),
    );
    check(page.registrationCompleted && page.email == email);
    check(find.byType(RegisterPage, skipOffstage: false).evaluate().isEmpty);
    check(find.byType(MainShell, skipOffstage: false).evaluate().isEmpty);
    results['real201LedToVerification'] = true;
    results['emailTransferredWithoutLogin'] = true;
    await tap(controller, 'Giriş ekranına dön');
    await waitFor(
      controller,
      () => find.byType(LoginPage).evaluate().isNotEmpty,
    );

    phase = 'duplicate_registration';
    await tap(controller, 'Hesabınız yok mu? Kayıt ol');
    await waitFor(
      controller,
      () => find.byType(RegisterPage).evaluate().isNotEmpty,
    );
    await fill(controller, email, password);
    await tap(controller, 'Kayıt ol');
    await waitFor(
      controller,
      () => find
          .text(
            'Bu e-posta adresiyle bir hesap zaten var. Giriş yapmayı deneyebilirsiniz.',
          )
          .evaluate()
          .isNotEmpty,
    );
    check(
      find
          .byType(EmailVerificationPage, skipOffstage: false)
          .evaluate()
          .isEmpty,
    );
    results['real409StayedOnRegistration'] = true;
    await tap(controller, 'Zaten hesabınız var mı? Girişe dön');

    phase = 'real_connection_failure';
    await waitFor(
      controller,
      () => find.byType(LoginPage).evaluate().isNotEmpty,
    );
    // Use the real client against a closed local port; no mocked HTTP response.
    Navigator.of(controller.element(find.byType(LoginPage))).push(
      MaterialPageRoute<void>(
        builder: (context) => RegisterPage(
          registrationApi: RegistrationApi(
            baseUri: origin.replace(port: 1),
            timeout: const Duration(seconds: 5),
          ),
        ),
      ),
    );
    await waitFor(
      controller,
      () => find.byType(RegisterPage).evaluate().isNotEmpty,
    );
    await fill(controller, email, password);
    await tap(controller, 'Kayıt ol');
    await waitFor(
      controller,
      () => find
          .text(const RegistrationApiException.connection().message)
          .evaluate()
          .isNotEmpty,
    );
    check(
      find
          .byType(EmailVerificationPage, skipOffstage: false)
          .evaluate()
          .isEmpty,
    );
    check(find.byType(MainShell, skipOffstage: false).evaluate().isEmpty);
    results['realConnectionFailureStayedOnRegistration'] = true;
    check(
      controller.widget<FilledButton>(find.byType(FilledButton)).onPressed !=
          null,
    );
    check(errors.isEmpty);
    results['flutterErrors'] = errors.length;
    results['ok'] = true;
    debugPrintSynchronously('E2E_RESULT ${jsonEncode(results)}');
    exit(0);
  } catch (error) {
    debugPrintSynchronously(
      'E2E_RESULT ${jsonEncode({...results, 'ok': false, 'phase': phase, 'errorType': error.runtimeType.toString(), 'flutterErrorTypes': errors})}',
    );
    exit(1);
  }
}

void check(bool condition) {
  if (!condition) throw StateError('Device registration check failed.');
}

Future<void> waitFor(
  LiveWidgetController controller,
  bool Function() ready,
) async {
  final timer = Stopwatch()..start();
  while (!ready()) {
    if (timer.elapsed > const Duration(seconds: 30)) {
      throw StateError('Device registration check timed out.');
    }
    await controller.pump(const Duration(milliseconds: 100));
  }
  await controller.pump(const Duration(milliseconds: 300));
}

Future<void> tap(LiveWidgetController controller, String text) async {
  final finder = find.text(text);
  await controller.ensureVisible(finder);
  await controller.pump(const Duration(milliseconds: 300));
  await controller.tap(finder);
  await controller.pump(const Duration(milliseconds: 300));
}

Future<void> fill(
  LiveWidgetController controller,
  String email,
  String password,
) async {
  for (final (index, value) in [
    (0, 'Sentetik Mobil Danışanı'),
    (1, email),
    (2, password),
    (3, password),
  ]) {
    final field = find.byType(EditableText).at(index);
    await controller.ensureVisible(field);
    await controller.pump(const Duration(milliseconds: 150));
    await controller.tap(field);
    await controller.pump(const Duration(milliseconds: 150));
    controller
        .state<EditableTextState>(field)
        .updateEditingValue(
          TextEditingValue(
            text: value,
            selection: TextSelection.collapsed(offset: value.length),
          ),
        );
    await controller.pump(const Duration(milliseconds: 150));
  }
  FocusManager.instance.primaryFocus?.unfocus();
  await controller.pump(const Duration(milliseconds: 300));
}
