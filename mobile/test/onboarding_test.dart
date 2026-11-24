import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/features/onboarding/limely_mascot.dart';
import 'package:smart_nutrition_mobile/features/onboarding/onboarding_page.dart';
import 'package:smart_nutrition_mobile/features/onboarding/onboarding_theme.dart';

void main() {
  setUpAll(() async {
    final loader = FontLoader('Figtree')
      ..addFont(rootBundle.load('assets/limely/fontlar/figtree/figtree.ttf'));
    await loader.load();
  });

  testWidgets(
    'answers survive back and edit; summary uses the entered values',
    (tester) async {
      await _open(tester);
      await _tap(tester, 'onboarding-start');
      await _tap(tester, 'onboarding-goal-gain');
      await _tap(tester, 'onboarding-goal-next');
      for (final name in ['age', 'height', 'weight']) {
        expect(
          tester.widget<TextField>(_key('onboarding-$name')).controller!.text,
          '',
        );
      }
      await _fill(tester, 'age', '28');
      await _fill(tester, 'height', '170');
      await _fill(tester, 'weight', '72,5');
      await _tap(tester, 'onboarding-activity-active');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Sana nasıl\neşlik edelim?'), findsOneWidget);
      expect(
        _semanticsFor(tester, 'onboarding-goal-gain').properties.checked,
        isTrue,
      );
      await _tap(tester, 'onboarding-goal-next');
      expect(
        tester.widget<TextField>(_key('onboarding-weight')).controller!.text,
        '72,5',
      );
      expect(
        _semanticsFor(tester, 'onboarding-activity-active').properties.checked,
        isTrue,
      );
      await _tap(tester, 'onboarding-review');
      expect(find.text('Güzel bir\nbaşlangıç!'), findsOneWidget);
      for (final answer in [
        'Kilo almak',
        '28 yaş',
        '170 cm',
        '72,5 kg',
        'Çok hareketli',
      ]) {
        expect(find.text(answer), findsOneWidget);
      }
      await _tap(tester, 'onboarding-edit');
      expect(
        tester.widget<TextField>(_key('onboarding-age')).controller!.text,
        '28',
      );
      await _fill(tester, 'weight', '73.1');
      await _tap(tester, 'onboarding-review');
      expect(find.text('73,1 kg'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('invalid or empty values cannot advance; comma decimals work', (
    tester,
  ) async {
    await _open(tester);
    await _tap(tester, 'onboarding-start');
    await _tap(tester, 'onboarding-goal-next');
    await _tap(tester, 'onboarding-review');
    expect(find.text('Yaş bilgisini gir.'), findsOneWidget);
    expect(find.text('Boy bilgisini gir.'), findsOneWidget);
    expect(find.text('Kilo bilgisini gir.'), findsOneWidget);
    expect(find.text('Güzel bir\nbaşlangıç!'), findsNothing);
    for (final values in [
      ('17', '99', '24.9'),
      ('121', '251', '400.1'),
      ('18.5', 'NaN', '1e2'),
      ('28', '170', '72,55'),
    ]) {
      await _fill(tester, 'age', values.$1);
      await _fill(tester, 'height', values.$2);
      await _fill(tester, 'weight', values.$3);
      await _tap(tester, 'onboarding-review');
      expect(find.text('Güzel bir\nbaşlangıç!'), findsNothing);
    }
    await _fill(tester, 'age', '28');
    await _fill(tester, 'height', '170');
    await _fill(tester, 'weight', '72,5');
    await _tap(tester, 'onboarding-review');
    expect(find.text('72,5 kg'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(320, 480),
    const Size(390, 844),
    const Size(568, 320),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('all steps are reachable at $size and text scale $scale', (
        tester,
      ) async {
        await _open(tester, size: size, textScale: scale);
        await _tap(tester, 'onboarding-start');
        await _tap(tester, 'onboarding-goal-lose');
        await _tap(tester, 'onboarding-goal-next');
        await _fill(tester, 'age', '28');
        await _fill(tester, 'height', '170');
        await _fill(tester, 'weight', '72');
        await _tap(tester, 'onboarding-review');
        expect(find.text('Güzel bir\nbaşlangıç!'), findsOneWidget);
        await _tap(tester, 'onboarding-edit');
        await _tap(tester, 'onboarding-back');
        await _tap(tester, 'onboarding-back');
        expect(find.text('Merhaba, ben\nLimely!'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('keyboard does not trap the form action or back navigation', (
    tester,
  ) async {
    await _open(tester, size: const Size(390, 700));
    await _tap(tester, 'onboarding-start');
    await _tap(tester, 'onboarding-goal-next');
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await _fill(tester, 'age', '28');
    await _fill(tester, 'height', '170');
    await _fill(tester, 'weight', '72');
    await _tap(tester, 'onboarding-review');
    expect(find.text('Güzel bir\nbaşlangıç!'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the introduction uses one local font and the reference palette',
    (tester) async {
      await _open(tester);
      final theme = Theme.of(
        tester.element(find.text('Merhaba, ben\nLimely!')),
      );
      expect(theme.textTheme.bodyMedium!.fontFamily, 'Figtree');
      expect(theme.scaffoldBackgroundColor, OnboardingTheme.background);
      expect(theme.brightness, Brightness.light);
      await _tap(tester, 'onboarding-start');
      expect(
        Theme.of(
          tester.element(find.text('Hedefini birlikte belirleyelim.')),
        ).textTheme.bodyMedium!.fontFamily,
        'Figtree',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('an initially empty viewport waits for Android screen metrics', (
    tester,
  ) async {
    await _open(tester, size: Size.zero);
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(find.text('Merhaba, ben\nLimely!'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion stays still, including after mascot replay', (
    tester,
  ) async {
    await _open(tester, reduceMotion: true);
    expect(tester.binding.transientCallbackCount, 0);
    final character = find
        .descendant(of: find.byType(LimelyMascot), matching: find.byType(Image))
        .last;
    final position = tester.getTopLeft(character);
    await tester.tap(find.byType(LimelyMascot));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.getTopLeft(character), position);
    expect(tester.takeException(), isNull);
  });

  testWidgets('login shortcut works without entering personal information', (
    tester,
  ) async {
    var requestedLogin = false;
    await _open(tester, onLogin: () => requestedLogin = true);
    await _tap(tester, 'onboarding-login');
    expect(requestedLogin, isTrue);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets(
    'a new introduction does not retain the previous personal draft',
    (tester) async {
      await _open(tester);
      await _tap(tester, 'onboarding-start');
      await _tap(tester, 'onboarding-goal-next');
      await _fill(tester, 'weight', '72,5');
      await tester.pumpWidget(const SizedBox.shrink());
      await _open(tester);
      await _tap(tester, 'onboarding-start');
      await _tap(tester, 'onboarding-goal-next');
      expect(
        tester.widget<TextField>(_key('onboarding-weight')).controller!.text,
        '',
      );
    },
  );

  if (const bool.fromEnvironment('CAPTURE_ONBOARDING')) {
    testWidgets('capture actual Flutter renders for visual review', (
      tester,
    ) async {
      final boundary = GlobalKey();
      await _open(tester, captureKey: boundary);
      await _capture(tester, boundary, '01-karsilama');
      await tester.tap(find.byType(LimelyMascot));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      await _capture(tester, boundary, '01b-el-sallama');
      await tester.pump(const Duration(milliseconds: 1180));
      await _capture(tester, boundary, '01c-goz-kirpma');
      await tester.pumpAndSettle();
      await _tap(tester, 'onboarding-start');
      await _capture(tester, boundary, '02-hedef');
      await _tap(tester, 'onboarding-goal-next');
      await _capture(tester, boundary, '03-seni-taniyalim');
      await _fill(tester, 'age', '28');
      await _fill(tester, 'height', '170');
      await _fill(tester, 'weight', '72,5');
      await _tap(tester, 'onboarding-review');
      await _capture(tester, boundary, '04-ozet');
    });
  }
}

Finder _key(String value) => find.byKey(ValueKey(value));

Semantics _semanticsFor(WidgetTester tester, String key) =>
    tester.widget<Semantics>(
      find.descendant(of: _key(key), matching: find.byType(Semantics)).first,
    );

Future<void> _open(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double textScale = 1,
  bool reduceMotion = false,
  VoidCallback? onLogin,
  GlobalKey? captureKey,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    RepaintBoundary(
      key: captureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reduceMotion,
          ),
          child: child!,
        ),
        home: OnboardingPage(onLogin: onLogin ?? () {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(_key(key));
  await tester.pumpAndSettle();
  await tester.tap(_key(key));
  await tester.pumpAndSettle();
}

Future<void> _fill(WidgetTester tester, String name, String text) async {
  await tester.ensureVisible(_key('onboarding-$name'));
  await tester.enterText(_key('onboarding-$name'), text);
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  await tester.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final folder = Directory('../output/limely-onboarding-qa');
    await folder.create(recursive: true);
    await File(
      '${folder.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
  });
}
