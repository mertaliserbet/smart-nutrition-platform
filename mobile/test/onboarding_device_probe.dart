// Opt-in: flutter run -d <device> -t test/onboarding_device_probe.dart --no-pub
// Exercises the real Android renderer with synthetic, in-memory answers only.
// It does not initialize a session, call an API or read existing account data.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/features/onboarding/onboarding_page.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  final controller = LiveWidgetController(binding);
  final boundary = GlobalKey();
  final errors = <String>[];
  final screenshots = <String, String>{};
  FlutterError.onError = (details) {
    errors.add(details.exception.runtimeType.toString());
    debugPrintSynchronously(
      'ONBOARDING_RENDER_ERROR ${details.exceptionAsString()}',
    );
  };
  var phase = 'welcome';
  try {
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: boundary,
          child: OnboardingPage(onLogin: () {}),
        ),
      ),
    );
    await controller.pump(const Duration(milliseconds: 300));
    await controller.pumpAndSettle();

    Future<void> capture(String name) async {
      await controller.pump(const Duration(milliseconds: 100));
      final image =
          await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final file = File(
        '${Directory.systemTemp.path}/limely-onboarding-$name.png',
      );
      await file.writeAsBytes(data!.buffer.asUint8List());
      screenshots[name] = file.path;
    }

    await capture('01-karsilama');
    phase = 'goal';
    await tap(controller, 'onboarding-start');
    await capture('02-hedef');
    phase = 'details';
    await tap(controller, 'onboarding-goal-next');
    await capture('03-seni-taniyalim');

    phase = 'validation';
    await tap(controller, 'onboarding-review');
    check(find.text('Yaş bilgisini gir.').evaluate().isNotEmpty);
    for (final (name, value) in [
      ('age', '28'),
      ('height', '170'),
      ('weight', '72,5'),
    ]) {
      final input = find.descendant(
        of: find.byKey(ValueKey('onboarding-$name')),
        matching: find.byType(EditableText),
      );
      await controller.ensureVisible(input);
      await controller.tap(input);
      await controller.pump(const Duration(milliseconds: 150));
      controller
          .state<EditableTextState>(input)
          .updateEditingValue(
            TextEditingValue(
              text: value,
              selection: TextSelection.collapsed(offset: value.length),
            ),
          );
      await controller.pump(const Duration(milliseconds: 150));
    }
    phase = 'summary';
    await tap(controller, 'onboarding-review');
    check(find.text('Güzel bir\nbaşlangıç!').evaluate().isNotEmpty);
    check(find.text('72,5 kg').evaluate().isNotEmpty);
    await capture('04-ozet');

    phase = 'edit';
    await tap(controller, 'onboarding-edit');
    final weight = controller.widget<TextField>(
      find.byKey(const ValueKey('onboarding-weight')),
    );
    check(weight.controller!.text == '72,5');
    await tap(controller, 'onboarding-back');
    await tap(controller, 'onboarding-back');
    check(find.text('Merhaba, ben\nLimely!').evaluate().isNotEmpty);
    check(errors.isEmpty);
    debugPrintSynchronously(
      'ONBOARDING_DEVICE_RESULT ${jsonEncode({'ok': true, 'steps': 4, 'validation': true, 'commaDecimal': true, 'editPreservedAnswers': true, 'flutterErrors': errors.length, 'screenshots': screenshots})}',
    );
  } catch (error) {
    debugPrintSynchronously(
      'ONBOARDING_DEVICE_RESULT ${jsonEncode({'ok': false, 'phase': phase, 'errorType': error.runtimeType.toString(), 'flutterErrors': errors, 'screenshots': screenshots})}',
    );
  }
}

Future<void> tap(LiveWidgetController controller, String key) async {
  final finder = find.byKey(ValueKey(key));
  await controller.ensureVisible(finder);
  await controller.pump(const Duration(milliseconds: 100));
  await controller.tap(finder);
  await controller.pumpAndSettle();
}

void check(bool condition) {
  if (!condition) throw StateError('Onboarding device check failed');
}
