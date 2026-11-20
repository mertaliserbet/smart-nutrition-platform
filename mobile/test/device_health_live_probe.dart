// Explicit flutter run target for the real Android health screen; no fake reader.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/auth/login_api.dart';
import 'package:smart_nutrition_mobile/features/health/device_health_page.dart';
import 'package:smart_nutrition_mobile/features/health/device_health_reader.dart';
import 'water_test_support.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  final controller = LiveWidgetController(binding);
  const email = String.fromEnvironment('E2E_EMAIL');
  if (!RegExp(r'^synthetic-m3-device-\d+@example\.test$').hasMatch(email)) {
    throw StateError('Only an isolated synthetic account may run this probe.');
  }
  final session = AuthSession(api: LoginApi(), store: WaterMemoryStore());
  await session.initialize();
  final signedIn = await session.signIn(
    email: email,
    password: 'Synthetic M3 device password 2026!',
  );
  if (!signedIn) throw StateError('Isolated device login failed.');
  runApp(
    AuthSessionScope(
      session: session,
      child: const MaterialApp(home: DeviceHealthPage()),
    ),
  );
  await controller.pump(const Duration(seconds: 1));
  Future<void> tap(String text) async {
    final target = find.text(text);
    await controller.ensureVisible(target);
    await controller.pump(const Duration(milliseconds: 300));
    await controller.tap(target);
    for (var i = 0; i < 25; i++) {
      await controller.pump(const Duration(milliseconds: 200));
    }
  }

  await tap('Sunucu verilerini yenile');
  final emptySummary = find.text('Adım: Veri yok').evaluate().isNotEmpty;
  await tap('Bugünün verilerini oku');
  final now = DateTime.now();
  final readings = await DeviceHealthReader().read(
    from: DateTime(now.year, now.month, now.day),
    to: now,
    isCurrent: () => session.isAuthenticated,
  );
  int count(DeviceHealthReadState state) =>
      readings.values.where((r) => r.state == state).length;
  final unsupported = find
      .text('Bu cihazda sağlık verisi okuma desteklenmiyor.')
      .evaluate()
      .isNotEmpty;
  debugPrintSynchronously(
    'M3_DEVICE_RESULT ${jsonEncode({'realHealthScreen': true, 'realHttpsSummary': emptySummary, 'deniedMetrics': count(DeviceHealthReadState.denied), 'emptyMetrics': count(DeviceHealthReadState.empty), 'errorMetrics': count(DeviceHealthReadState.error), 'metricsWithNativeData': count(DeviceHealthReadState.data), 'unsupported': unsupported, 'deviceDataUploaded': false})}',
  );
  await controller.ensureVisible(find.text('Okuma izinlerini iste'));
  await controller.pump(const Duration(milliseconds: 300));
}
