import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/core/theme/app_theme.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/client_tasks/client_task_api.dart';
import 'package:smart_nutrition_mobile/features/client_tasks/client_task_page.dart';
import 'package:smart_nutrition_mobile/features/client_tasks/client_task_detail_page.dart';
import 'client_task_test_support.dart';
import 'water_test_support.dart';

void main() {
  late WaterTestSession session;
  late TaskTestApi api;
  setUp(() {
    session = WaterTestSession();
    api = TaskTestApi(session);
  });
  tearDown(() => session.dispose());
  Future<void> open(
    WidgetTester tester, {
    bool detail = false,
    bool settle = true,
    ThemeData? theme,
  }) async {
    addTearDown(() async => tester.pumpWidget(const SizedBox()));
    await tester.pumpWidget(
      AuthSessionScope(
        session: session,
        child: MaterialApp(
          theme: theme,
          home: detail
              ? ClientTaskDetailPage(api: api, taskId: taskId)
              : ClientTaskPage(api: api),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> tap(
    WidgetTester tester,
    String text, {
    bool settle = true,
  }) async {
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pump();
    await tester.scrollUntilVisible(find.text(text), 200, maxScrolls: 30);
    await tester.tap(find.text(text));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  testWidgets('new user sees empty tasks with no demo records', (tester) async {
    api.rows = [];
    api.total = 0;
    await open(tester);
    expect(find.text('Henüz atanmış göreviniz yok.'), findsOneWidget);
    expect(find.text('Sentetik danışan görevi'), findsNothing);
  });
  testWidgets(
    'loading is distinct from empty and network failure is retryable',
    (tester) async {
      final pending = Completer<ClientTaskPageResult<ClientTask>>();
      api.pendingList = pending.future;
      await open(tester, settle: false);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Henüz atanmış göreviniz yok.'), findsNothing);
      pending.completeError(const ClientTaskApiException('Sentetik ağ hatası'));
      await tester.pumpAndSettle();
      expect(find.text('Sentetik ağ hatası'), findsOneWidget);
      api.pendingList = null;
      await tester.tap(find.text('Yeniden dene'));
      await tester.pumpAndSettle();
      expect(find.text('Sentetik danışan görevi'), findsOneWidget);
    },
  );
  testWidgets('list pagination and detail read refresh after returning', (
    tester,
  ) async {
    api.total = 11;
    await open(tester);
    await tap(tester, 'Sonraki');
    expect(api.pages.last, 2);
    await tap(tester, 'Önceki');
    expect(api.pages.last, 1);
    await tap(tester, 'Sentetik danışan görevi');
    expect(find.text('Görev detayı'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(api.pages.length, 4);
  });
  testWidgets(
    'pending starts or completes; completion disables all further mutations',
    (tester) async {
      await open(tester, detail: true);
      await tap(tester, 'Göreve başla');
      expect(api.statuses.single, ClientTaskStatus.inProgress);
      expect(find.text('Göreve başla'), findsNothing);
      await tap(tester, 'Görevi tamamla');
      expect(api.statuses.last, ClientTaskStatus.completed);
      expect(find.text('Görevi tamamla'), findsNothing);
      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.text('Durum: Tamamlandı'), findsOneWidget);
    },
  );
  testWidgets('cancelled task is read-only and immutable history is paged', (
    tester,
  ) async {
    api.task = taskSample(status: ClientTaskStatus.cancelled);
    api.historyTotal = 11;
    await open(tester, detail: true);
    expect(find.text('Göreve başla'), findsNothing);
    expect(find.text('Görevi tamamla'), findsNothing);
    await tap(tester, 'Sonraki geçmiş');
    expect(api.historyPages.last, 2);
    expect(api.writes, 0);
  });
  testWidgets('409 reloads current version without repeating completion', (
    tester,
  ) async {
    await open(tester, detail: true);
    api.writeFailure = const ClientTaskApiException(
      'Görev değişmiş.',
      statusCode: 409,
    );
    api.task = taskSample(status: ClientTaskStatus.cancelled, version: 2);
    await tap(tester, 'Görevi tamamla');
    expect(api.writes, 1);
    expect(api.gets, 2);
    expect(find.text('Görev değişmiş.'), findsOneWidget);
    expect(find.text('Durum: İptal edildi'), findsOneWidget);
    expect(find.text('Görevi tamamla'), findsNothing);
  });
  testWidgets(
    'uncertain mutation blocks another write until explicit refresh',
    (tester) async {
      await open(tester, detail: true);
      api.writeFailure = const ClientTaskApiException(
        'network',
        uncertain: true,
      );
      await tap(tester, 'Görevi tamamla');
      expect(api.writes, 1);
      expect(find.text('Görevi tamamla'), findsNothing);
      expect(
        find.textContaining('İşlemin sonucu doğrulanamadı'),
        findsOneWidget,
      );
      api.writeFailure = null;
      await tester.tap(find.text('Güncel kaydı yenile'));
      await tester.pumpAndSettle();
      expect(api.writes, 1);
      expect(find.text('Görevi tamamla'), findsOneWidget);
    },
  );
  testWidgets('403 on refresh removes old detail and history', (tester) async {
    await open(tester, detail: true);
    api.failure = const ClientTaskApiException(
      'Erişim kapandı.',
      statusCode: 403,
    );
    await tester.tap(find.byTooltip('Yenile'));
    await tester.pumpAndSettle();
    expect(find.text('Erişim kapandı.'), findsOneWidget);
    expect(find.text('Sentetik danışan görevi'), findsNothing);
    expect(find.text('Görev geçmişi'), findsNothing);
  });
  testWidgets(
    'account change discards list completion and does not fetch as new owner',
    (tester) async {
      final pending = Completer<ClientTaskPageResult<ClientTask>>();
      api.pendingList = pending.future;
      await open(tester, settle: false);
      session.changeOwner();
      await tester.pump();
      pending.complete((items: [taskSample()], totalCount: 1));
      await tester.pumpAndSettle();
      expect(find.text('Sentetik danışan görevi'), findsNothing);
      expect(
        find.text('Bu ekranı mevcut hesabınızla yeniden açın.'),
        findsOneWidget,
      );
      expect(api.pages.length, 1);
    },
  );
  testWidgets(
    'logout while saving discards old result and does not repeat write',
    (tester) async {
      final pending = Completer<ClientTask>();
      api.pendingWrite = pending.future;
      await open(tester, detail: true);
      await tap(tester, 'Görevi tamamla', settle: false);
      session.end();
      await tester.pump();
      pending.complete(taskSample(status: ClientTaskStatus.completed));
      await tester.pumpAndSettle();
      expect(find.textContaining('Sentetik danışan görevi'), findsNothing);
      expect(api.writes, 1);
      expect(api.gets, 1);
    },
  );
  for (final theme in [AppTheme.light, AppTheme.dark]) {
    testWidgets('narrow detail with large text fits ${theme.brightness}', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await open(tester, detail: true, theme: theme);
      await tester.scrollUntilVisible(find.text('Görev geçmişi'), 200);
      expect(tester.takeException(), null);
    });
  }
}
