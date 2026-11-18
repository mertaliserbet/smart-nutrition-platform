import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/health/device_health_page.dart';
import 'package:smart_nutrition_mobile/features/health/device_health_reader.dart';
import 'package:smart_nutrition_mobile/features/health/health_data_api.dart';
import 'device_health_test_support.dart';
import 'health_sync_test_support.dart';
import 'water_test_support.dart';

void main() {
  late WaterTestSession session;
  late FakeDeviceHealthSource source;
  late SyncTestApi api;
  setUp(() {
    session = WaterTestSession();
    source = FakeDeviceHealthSource();
    api = SyncTestApi(session);
  });
  tearDown(() => session.dispose());
  Future<void> open(WidgetTester tester) async {
    addTearDown(() async => tester.pumpWidget(const SizedBox()));
    await tester.pumpWidget(
      AuthSessionScope(
        session: session,
        child: MaterialApp(
          home: DeviceHealthPage(
            reader: DeviceHealthReader(source: source),
            api: api,
            now: () => DateTime(2026, 11, 19, 12),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> visible(WidgetTester tester, Finder target) async {
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pump();
    await tester.scrollUntilVisible(target, 200, maxScrolls: 40);
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
  }

  Future<void> tap(
    WidgetTester tester,
    String text, {
    bool settle = true,
  }) async {
    final finder = find.text(text);
    await visible(tester, finder);
    await tester.tap(finder);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> consent(WidgetTester tester) async {
    final finder = find.byKey(const ValueKey('health-transfer-consent'));
    await visible(tester, finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('opening screen or native reading never connects or uploads', (
    tester,
  ) async {
    await open(tester);
    expect(api.reads, 0);
    expect(api.payloads, isEmpty);
    await tap(tester, 'Bugünün verilerini oku');
    expect(source.reads, 5);
    expect(api.creates, 0);
    await visible(tester, find.text('Bugünü oku ve senkronize et'));
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Bugünü oku ve senkronize et'),
          )
          .onPressed,
      null,
    );
  });
  testWidgets(
    'explicit approval and manual sync update server summary and success time',
    (tester) async {
      source.rows[HealthDataType.STEPS] = [syncSample()];
      await open(tester);
      await consent(tester);
      await tap(tester, 'Bugünü oku ve senkronize et');
      expect(api.payloads.length, 1);
      expect(api.creates, 1);
      await visible(
        tester,
        find.textContaining('Son başarılı senkronizasyon:'),
      );
      expect(
        find.textContaining('Son başarılı senkronizasyon:'),
        findsOneWidget,
      );
      await visible(tester, find.text('Adım: 1250'));
      expect(find.text('Adım: 1250'), findsOneWidget);
      expect(find.text('Mesafe (km): Veri yok'), findsOneWidget);
    },
  );
  testWidgets('empty or denied native reads do not send a fake zero batch', (
    tester,
  ) async {
    source.permissions[HealthDataType.STEPS] = false;
    await open(tester);
    await consent(tester);
    await tap(tester, 'Bugünü oku ve senkronize et');
    expect(api.payloads, isEmpty);
    expect(api.creates, 0);
    await visible(tester, find.textContaining('Yeni aktarılabilir kayıt yok'));
    expect(find.textContaining('Yeni aktarılabilir kayıt yok'), findsOneWidget);
    expect(find.text('Adım: 0'), findsNothing);
  });
  testWidgets(
    'retry requires user action and uses identical batch after fresh read',
    (tester) async {
      source.rows[HealthDataType.STEPS] = [syncSample()];
      api.syncFailure = const HealthDataException('network', uncertain: true);
      await open(tester);
      await consent(tester);
      await tap(tester, 'Bugünü oku ve senkronize et');
      expect(api.payloads.length, 1);
      final original = api.lastJson;
      api.syncFailure = null;
      await tap(tester, 'Aynı aktarımı yeniden dene');
      expect(api.payloads.length, 2);
      expect(api.lastJson, original);
    },
  );
  testWidgets(
    'stopping transfer revokes connection; reactivation needs explicit consent',
    (tester) async {
      api.connection = syncConnection(lastSyncedAt: syncFrom);
      await open(tester);
      await tap(tester, 'Sunucu verilerini yenile');
      await tap(tester, 'Sunucuya aktarımı durdur');
      expect(api.connection!.status, 'revoked');
      expect(api.payloads, isEmpty);
      await visible(tester, find.text('Sunucuya aktarımı yeniden aç'));
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(
                OutlinedButton,
                'Sunucuya aktarımı yeniden aç',
              ),
            )
            .onPressed,
        null,
      );
      await consent(tester);
      await tap(tester, 'Sunucuya aktarımı yeniden aç');
      expect(api.connection!.status, 'active');
      expect(api.payloads, isEmpty);
      expect(source.reads, 0);
    },
  );
  testWidgets('account change during sync clears late results and approval', (
    tester,
  ) async {
    source.rows[HealthDataType.STEPS] = [syncSample()];
    final pending = Completer<WearableSyncReceipt>();
    api.pendingSync = pending.future;
    await open(tester);
    await consent(tester);
    await tap(tester, 'Bugünü oku ve senkronize et', settle: false);
    session.changeOwner();
    await tester.pump();
    pending.complete(WearableSyncReceipt('synthetic', DateTime.now(), 1));
    await tester.pumpAndSettle();
    expect(
      find.text('Bu ekranı mevcut hesabınızla yeniden açın.'),
      findsOneWidget,
    );
    expect(find.textContaining('Son başarılı senkronizasyon:'), findsNothing);
    expect(api.payloads.length, 1);
  });
  testWidgets(
    'server errors do not appear as no observations or a successful zero',
    (tester) async {
      api.readFailure = const HealthDataException(
        'Sağlık servisi bulunamadı.',
        statusCode: 404,
      );
      await open(tester);
      await tap(tester, 'Sunucu verilerini yenile');
      await visible(tester, find.text('Sağlık servisi bulunamadı.'));
      expect(find.text('Sağlık servisi bulunamadı.'), findsOneWidget);
      expect(find.text('Adım: 0'), findsNothing);
      expect(api.payloads, isEmpty);
    },
  );
}
