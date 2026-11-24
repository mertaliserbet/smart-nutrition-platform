// Opt-in ADB/emulator target. Real app, API and native health reader; synthetic accounts only.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/app.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/auth/login_api.dart';
import 'package:smart_nutrition_mobile/features/auth/login_page.dart';
import 'package:smart_nutrition_mobile/features/navigation/main_shell.dart';
import 'package:smart_nutrition_mobile/features/nutrition/manual_meal_log_page.dart';
import 'package:smart_nutrition_mobile/features/body_measurements/body_measurement_api.dart';
import 'package:smart_nutrition_mobile/features/body_measurements/measurement_chart.dart';
import 'package:smart_nutrition_mobile/features/progress/progress_page.dart';
import 'package:smart_nutrition_mobile/features/client_tasks/client_task_page.dart';
import 'package:smart_nutrition_mobile/features/health/device_health_page.dart';
import 'package:smart_nutrition_mobile/features/health/device_health_reader.dart';
import 'water_test_support.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  final controller = LiveWidgetController(binding);
  const owner = String.fromEnvironment('E2E_EMAIL');
  const other = String.fromEnvironment('E2E_OTHER_EMAIL');
  for (final email in [owner, other]) {
    if (!RegExp(
      r'^synthetic-m6-device-[ab]-\d+@example\.test$',
    ).hasMatch(email)) {
      throw StateError('Only isolated M6 accounts are allowed.');
    }
  }
  final session = AuthSession(api: LoginApi(), store: WaterMemoryStore());
  final results = <String, Object>{};
  var phase = 'initial_login';
  void check(bool value) {
    if (!value) throw StateError('Device assertion failed during $phase');
  }

  Future<void> pump([int count = 4]) async {
    for (var i = 0; i < count; i++) {
      await controller.pump(const Duration(milliseconds: 150));
    }
  }

  Future<void> wait(bool Function() condition) async {
    final watch = Stopwatch()..start();
    while (!condition()) {
      if (watch.elapsed > const Duration(seconds: 30)) {
        throw StateError('Device stage timed out: $phase');
      }
      await pump(1);
    }
    await pump(3);
  }

  Future<void> tap(Finder target) async {
    await controller.ensureVisible(target);
    await pump(2);
    await controller.tap(target);
    await pump(6);
  }

  Future<void> text(String label) => tap(find.text(label).last);
  Future<void> fill(Finder editable, String value) async {
    await controller.ensureVisible(editable);
    await pump(1);
    controller
        .state<EditableTextState>(editable)
        .updateEditingValue(
          TextEditingValue(
            text: value,
            selection: TextSelection.collapsed(offset: value.length),
          ),
        );
    await pump(1);
  }

  Future<void> tab(String label) => tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  Future<void> back() async {
    controller.state<NavigatorState>(find.byType(Navigator).first).pop();
    await pump(5);
  }

  Future<void> login(String email) async {
    await wait(
      () =>
          find.byType(LoginPage).evaluate().isNotEmpty ||
          find.byKey(const ValueKey('onboarding-login')).evaluate().isNotEmpty,
    );
    if (find.byKey(const ValueKey('onboarding-login')).evaluate().isNotEmpty) {
      await tap(find.byKey(const ValueKey('onboarding-login')));
      await wait(() => find.byType(LoginPage).evaluate().isNotEmpty);
    }
    await fill(find.byType(EditableText).at(0), email);
    await fill(
      find.byType(EditableText).at(1),
      'Synthetic M6 device password 2026!',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await pump(2);
    await text('Giriş yap');
    await wait(() => find.byType(MainShell).evaluate().isNotEmpty);
    await pump(12);
  }

  FlutterError.onError = (details) => debugPrintSynchronously(
    'M6_DEVICE_FRAMEWORK_ERROR ${details.exception.runtimeType}',
  );
  try {
    runApp(SmartNutritionApp(session: session));
    await pump(5);
    await login(owner);
    results['realLogin'] = true;
    phase = 'empty_nutrition';
    await tab('Beslenme');
    await pump(10);
    await text('Öğün geçmişi');
    await wait(
      () => find
          .text('Henüz öğün yok. İlk öğününüzü ekleyebilirsiniz.')
          .evaluate()
          .isNotEmpty,
    );
    results['emptyMeals'] = true;
    await back();
    phase = 'create_meal';
    await text('Öğün ekle');
    await wait(() => find.byType(ManualMealLogPage).evaluate().isNotEmpty);
    await text('Kahvaltı');
    for (final entry in {
      'displayName': 'Synthetic M6 device meal',
      'quantityGrams': '100',
      'caloriesKcal': '150',
      'proteinGrams': '10',
      'carbsGrams': '20',
      'fatGrams': '3',
    }.entries) {
      await fill(
        find.descendant(
          of: find.byKey(ValueKey('item-0-${entry.key}')),
          matching: find.byType(EditableText),
        ),
        entry.value,
      );
    }
    FocusManager.instance.primaryFocus?.unfocus();
    await pump(2);
    await text('Kaydet');
    await wait(() => find.byType(ManualMealLogPage).evaluate().isEmpty);
    await text('Öğün geçmişi');
    await wait(
      () =>
          find.textContaining('Synthetic M6 device meal').evaluate().isNotEmpty,
    );
    results['realMealCreateAndHistory'] = true;
    await back();
    phase = 'measurements';
    await tab('İlerleme');
    await wait(
      () => find
          .text('Henüz ölçüm yok. İlk ölçümünüzü ekleyebilirsiniz.')
          .evaluate()
          .isNotEmpty,
    );
    results['emptyMeasurements'] = true;
    final measurements = BodyMeasurementApi(session);
    await measurements.create(
      values: {'weightKg': 70},
      measuredAt: DateTime.now().subtract(const Duration(days: 2)),
    );
    await measurements.create(
      values: {'weightKg': 69, 'waistCm': 80},
      measuredAt: DateTime.now().subtract(const Duration(days: 1)),
    );
    await text('Ölçümleri yenile');
    await wait(() => find.byType(MeasurementChart).evaluate().isNotEmpty);
    results['realMeasurementCharts'] = true;
    phase = 'profile_and_tasks';
    await tab('Profil');
    await text('Günlük hedeflerim');
    await pump(10);
    check(find.byType(EditableText).evaluate().isNotEmpty);
    await back();
    results['personalTargetsScreen'] = true;
    await text('Görevlerim');
    await wait(() => find.byType(ClientTaskPage).evaluate().isNotEmpty);
    await wait(
      () => find.text('Henüz atanmış göreviniz yok.').evaluate().isNotEmpty,
    );
    results['emptyTasks'] = true;
    await back();
    phase = 'native_health';
    await text('Cihaz sağlık verileri');
    await wait(() => find.byType(DeviceHealthPage).evaluate().isNotEmpty);
    await text('Sunucu verilerini yenile');
    await pump(10);
    results['realHealthHttpsSummary'] = find
        .text('Adım: Veri yok')
        .evaluate()
        .isNotEmpty;
    final reader = DeviceHealthReader();
    final now = DateTime.now();
    final initial = await reader.read(
      from: DateTime(now.year, now.month, now.day),
      to: now,
      isCurrent: () => true,
    );
    results['initialDeniedHealthTypes'] = initial.values
        .where((r) => r.state == DeviceHealthReadState.denied)
        .length;
    await text('Okuma izinlerini iste');
    debugPrintSynchronously('M6_NATIVE_PERMISSION_WAIT');
    final watch = Stopwatch()..start();
    while (watch.elapsed < const Duration(minutes: 2)) {
      var allowed = true;
      for (final metric in DeviceHealthMetric.values) {
        for (final type in reader.source.types(metric)) {
          if (await reader.source.hasReadPermission(type) != true) {
            allowed = false;
          }
        }
      }
      if (allowed) break;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    await pump(10);
    await text('Bugünün verilerini oku');
    await pump(10);
    final readings = await reader.read(
      from: DateTime(now.year, now.month, now.day),
      to: DateTime.now(),
      isCurrent: () => true,
    );
    results['emptyHealthTypes'] = readings.values
        .where((r) => r.state == DeviceHealthReadState.empty)
        .length;
    results['healthTypesWithData'] = readings.values
        .where((r) => r.state == DeviceHealthReadState.data)
        .length;
    results['healthReadErrors'] = readings.values
        .where((r) => r.state == DeviceHealthReadState.error)
        .length;
    results['deviceHealthUploaded'] = false;
    await back();
    phase = 'logout_account_change';
    await tap(find.byTooltip('Çıkış yap'));
    await wait(() => find.byType(LoginPage).evaluate().isNotEmpty);
    results['logoutGate'] = find
        .byType(MainShell, skipOffstage: false)
        .evaluate()
        .isEmpty;
    await login(other);
    await tab('Beslenme');
    await text('Öğün geçmişi');
    await wait(
      () => find
          .text('Henüz öğün yok. İlk öğününüzü ekleyebilirsiniz.')
          .evaluate()
          .isNotEmpty,
    );
    check(find.textContaining('Synthetic M6 device meal').evaluate().isEmpty);
    results['accountIsolationMeals'] = true;
    await back();
    await tab('İlerleme');
    await wait(
      () => find
          .text('Henüz ölçüm yok. İlk ölçümünüzü ekleyebilirsiniz.')
          .evaluate()
          .isNotEmpty,
    );
    results['accountIsolationCharts'] = find
        .byType(MeasurementChart)
        .evaluate()
        .isEmpty;
    check(find.byType(ProgressPage).evaluate().isNotEmpty);
    debugPrintSynchronously('M6_DEVICE_RESULT ${jsonEncode(results)}');
    debugPrintSynchronously('M6_ADB_NETWORK_READY');
  } catch (error, stack) {
    debugPrintSynchronously(
      'M6_DEVICE_FAILED ${jsonEncode({'phase': phase, 'type': error.runtimeType.toString()})}',
    );
    debugPrintSynchronously(stack.toString());
  }
}
