import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/app.dart';
import 'package:smart_nutrition_mobile/features/auth/login_page.dart';
import 'package:smart_nutrition_mobile/features/auth/register_page.dart';
import 'package:smart_nutrition_mobile/features/onboarding/onboarding_page.dart';

void main() {
  setUpAll(() async {
    await (FontLoader('Figtree')..addFont(
          rootBundle.load('assets/limely/fontlar/figtree/figtree.ttf'),
        ))
        .load();
  });

  testWidgets(
    'account back returns to the actual summary without losing answers',
    (tester) async {
      await _open(tester);
      await _summary(tester);
      expect(find.text('72,5 kg'), findsOneWidget);
      expect(find.byTooltip('Önceki ekrana dön').hitTestable(), findsOneWidget);
      expect(find.text('Bilgilerimi düzenle'), findsNothing);
      await _tap(tester, 'onboarding-account');
      expect(find.byType(RegisterPage), findsOneWidget);
      expect(find.byTooltip('Önceki ekrana dön').hitTestable(), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(3));
      await tester.enterText(find.byType(TextFormField).at(0), 'İpek Şen');
      await tester.enterText(
        find.byType(TextFormField).at(2),
        '  Sentetik şifre  ',
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('72,5 kg'), findsOneWidget);
      expect(find.byType(RegisterPage), findsNothing);
      await _tap(tester, 'onboarding-account');
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        isEmpty,
      );
      await _tap(tester, 'register-back');
      await _tap(tester, 'onboarding-back');
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('onboarding-weight')))
            .controller!
            .text,
        '72,5',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('account login shortcut discards the anonymous draft', (
    tester,
  ) async {
    await _open(tester);
    await _summary(tester);
    await _tap(tester, 'onboarding-account');
    final login = find.widgetWithText(TextButton, 'Giriş yap');
    await tester.ensureVisible(login);
    await tester.tap(login);
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(OnboardingPage, skipOffstage: false), findsNothing);
    expect(find.text('E-posta doğrulama hakkında'), findsNothing);
    await _tap(tester, 'login-register');
    await _tap(tester, 'onboarding-start');
    await _tap(tester, 'onboarding-goal-next');
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('onboarding-weight')))
          .controller!
          .text,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  if (const bool.fromEnvironment('CAPTURE_LIMELY_AUTH')) {
    testWidgets('capture the implemented login summary and account screens', (
      tester,
    ) async {
      final boundary = GlobalKey();
      await _open(tester, boundary: boundary);
      await _tap(tester, 'onboarding-login');
      await _capture(tester, boundary, '01-giris-yap');
      await _tap(tester, 'login-register');
      await _summary(tester);
      await _capture(tester, boundary, '02-baslangic-ozeti');
      await _tap(tester, 'onboarding-account');
      await _capture(tester, boundary, '03-hesap-olustur');
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _open(WidgetTester tester, {GlobalKey? boundary}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetPadding);
  await tester.pumpWidget(
    RepaintBoundary(key: boundary, child: const SmartNutritionApp()),
  );
  await tester.pumpAndSettle();
}

Future<void> _summary(WidgetTester tester) async {
  await _tap(tester, 'onboarding-start');
  await _tap(tester, 'onboarding-goal-next');
  for (final (field, value) in [
    ('age', '28'),
    ('height', '170'),
    ('weight', '72,5'),
  ]) {
    final input = find.byKey(ValueKey('onboarding-$field'));
    await tester.ensureVisible(input);
    await tester.enterText(input, value);
  }
  await _tap(tester, 'onboarding-review');
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  // Widget tests can settle before asynchronous PNG decoding has completed.
  await tester.runAsync(() async {
    await Future.wait(
      tester
          .widgetList<Image>(find.byType(Image))
          .map((image) => precacheImage(image.image, key.currentContext!)),
    );
  });
  await tester.pumpAndSettle();
  final back = find.byTooltip('Önceki ekrana dön');
  expect(back.hitTestable(), findsOneWidget);
  await tester.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final folder = Directory('../output/limely-auth-uygulama-qa');
    await folder.create(recursive: true);
    await File(
      '${folder.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
  });
}
