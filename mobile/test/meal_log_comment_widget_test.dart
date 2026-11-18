import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/core/theme/app_theme.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/nutrition/meal_log_comment_api.dart';
import 'package:smart_nutrition_mobile/features/nutrition/meal_log_comments_section.dart';
import 'package:smart_nutrition_mobile/features/nutrition/meal_log_detail_page.dart';
import 'meal_log_comment_test_support.dart';
import 'meal_log_test_support.dart';

void main() {
  late MealTestSession session;
  late CommentTestApi api;
  late MealTestApi meals;
  setUp(() {
    session = MealTestSession();
    api = CommentTestApi(session);
    meals = MealTestApi(session);
  });
  tearDown(() => session.dispose());
  Widget section({String id = mealId}) =>
      MealLogCommentsSection(mealLogId: id, api: api);
  Future<void> open(
    WidgetTester tester, {
    Widget? child,
    bool settle = true,
    bool dark = false,
    bool route = false,
  }) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async => tester.pumpWidget(const SizedBox()));
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      AuthSessionScope(
        session: session,
        child: MaterialApp(
          navigatorKey: navigator,
          theme: dark ? AppTheme.dark : AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: route
              ? const Scaffold(body: Text('Detay kapandı'))
              : child is MealLogDetailPage
              ? child
              : Scaffold(
                  body: SingleChildScrollView(child: child ?? section()),
                ),
        ),
      ),
    );
    if (route) {
      unawaited(
        navigator.currentState!.push<void>(
          MaterialPageRoute(builder: (_) => child!),
        ),
      );
    }
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> draft(
    WidgetTester tester, {
    String value = 'Sentetik yanıt 10',
  }) async {
    await tap(tester, find.byKey(const ValueKey('reply-$rootCommentId')));
    final field = find.byType(TextField);
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, value);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
  }

  for (final dark in [false, true]) {
    testWidgets(
      'small ${dark ? 'dark' : 'light'} view distinguishes roots/replies and refreshes after exactly one reply',
      (tester) async {
        api.rows = [rootComment(), clientReply(text: 'Önceki yanıt')];
        await open(tester, dark: dark);
        expect(find.text('Diyetisyen yorumu'), findsOneWidget);
        expect(find.text('Danışan yanıtı'), findsOneWidget);
        expect(find.text('Yanıtla'), findsOneWidget);
        await draft(tester);
        await tap(tester, find.text('Yanıt gönder'));
        expect(api.writes, 1);
        expect(api.lastParent, rootCommentId);
        expect(api.lastText, 'Sentetik yanıt 10');
        expect(api.pages, [1, 1]);
        expect(find.text('Yanıtınız kaydedildi.'), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'loading is not an empty list; empty and read errors have separate retry states',
    (tester) async {
      final pending = Completer<MealLogCommentPage>();
      api.pendingRead = pending.future;
      await open(tester, settle: false);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Henüz yorum veya yanıt yok.'), findsNothing);
      pending.complete((items: <MealLogComment>[], totalCount: 0));
      await tester.pumpAndSettle();
      expect(find.text('Henüz yorum veya yanıt yok.'), findsOneWidget);
      api.pendingRead = null;
      api.readFailure = const MealLogCommentApiException('Sentetik ağ hatası');
      await tap(tester, find.text('Yorumları yenile'));
      expect(find.text('Sentetik ağ hatası'), findsOneWidget);
      expect(find.text('Henüz yorum veya yanıt yok.'), findsNothing);
      api.readFailure = null;
      await tap(tester, find.text('Yorumları yenile'));
      expect(find.text('Diyetisyen yorumu'), findsOneWidget);
    },
  );
  testWidgets(
    'validates blank and Unicode length, then keeps pending POST nonrepeatable',
    (tester) async {
      await open(tester);
      await draft(tester, value: ' \n');
      await tap(tester, find.text('Yanıt gönder'));
      expect(api.writes, 0);
      expect(find.textContaining('Yanıt 1–2000 karakter'), findsOneWidget);
      final field = find.byType(TextField);
      await tester.enterText(field, '🥣' * 2001);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tap(tester, find.text('Yanıt gönder'));
      expect(api.writes, 0);
      final pending = Completer<MealLogComment>();
      api.pendingWrite = pending.future;
      await tester.enterText(field, 'Geçerli yanıt');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tap(tester, find.text('Yanıt gönder'));
      expect(api.writes, 1);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Yanıt gönder'),
            )
            .onPressed,
        isNull,
      );
      pending.complete(clientReply(text: 'Geçerli yanıt'));
      await tester.pumpAndSettle();
      expect(api.writes, 1);
    },
  );
  testWidgets(
    'uncertain reply locks writes until a fresh GET and clears its draft',
    (tester) async {
      await open(tester);
      await draft(tester);
      api.writeFailure = const MealLogCommentApiException(
        'Sonuç belirsiz',
        uncertain: true,
      );
      await tap(tester, find.text('Yanıt gönder'));
      expect(api.writes, 1);
      expect(find.textContaining('Yanıtı yeniden göndermeden'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Yanıt gönder'),
            )
            .onPressed,
        isNull,
      );
      api.writeFailure = null;
      await tap(tester, find.text('Yorumları yenile'));
      expect(api.writes, 1);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Yanıtla'), findsOneWidget);
    },
  );
  testWidgets(
    'server pages retain chronological roots and explain off-page parents',
    (tester) async {
      api.rows = [
        for (var i = 0; i < 10; i++)
          rootComment(
            id: '88888888-8888-4888-8888-${i.toString().padLeft(12, '0')}',
          ),
        clientReply(),
      ];
      await open(tester);
      await tap(tester, find.text('Sonraki yorum sayfası'));
      expect(api.pages, [1, 2]);
      expect(find.text('11 yorum/yanıt · Sayfa 2'), findsOneWidget);
      expect(find.text('İlgili yorum başka bir sayfada.'), findsOneWidget);
      expect(find.text('Yanıtla'), findsNothing);
      await tap(tester, find.text('Önceki yorum sayfası'));
      expect(api.pages, [1, 2, 1]);
    },
  );
  for (final status in [401, 403, 404]) {
    testWidgets(
      'comment GET $status removes the meal and drafts from the detail',
      (tester) async {
        await open(
          tester,
          child: MealLogDetailPage(id: mealId, api: meals, commentApi: api),
        );
        await draft(tester);
        api.readFailure = MealLogCommentApiException(
          'Erişim kapalı $status',
          statusCode: status,
        );
        await tap(tester, find.text('Yorumları yenile'));
        expect(find.text('Sentetik çorba'), findsNothing);
        expect(find.text('Erişim kapalı $status'), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
        expect(find.text('Diyetisyen yorumu'), findsNothing);
      },
    );
  }
  testWidgets('404 while posting removes old meal and reply text', (
    tester,
  ) async {
    await open(
      tester,
      child: MealLogDetailPage(id: mealId, api: meals, commentApi: api),
    );
    await draft(tester);
    api.writeFailure = const MealLogCommentApiException(
      'Öğün silinmiş',
      statusCode: 404,
    );
    await tap(tester, find.text('Yanıt gönder'));
    expect(find.text('Öğün silinmiş'), findsOneWidget);
    expect(find.text('Sentetik çorba'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });
  testWidgets(
    'confirmed meal deletion discards the entire comment section and draft',
    (tester) async {
      await open(
        tester,
        route: true,
        child: MealLogDetailPage(id: mealId, api: meals, commentApi: api),
      );
      await draft(tester);
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      await tap(tester, find.text('Öğünü sil'));
      await tester.tap(find.widgetWithText(FilledButton, 'Sil'));
      await tester.pumpAndSettle();
      expect(meals.deletes, 1);
      expect(find.text('Detay kapandı'), findsOneWidget);
      expect(find.byType(MealLogCommentsSection), findsNothing);
      expect(find.byType(TextField), findsNothing);
    },
  );
  testWidgets(
    'account change discards a previous read and any draft; logout hides comments',
    (tester) async {
      await open(tester);
      await draft(tester);
      final pending = Completer<MealLogCommentPage>();
      api.pendingRead = pending.future;
      await tap(tester, find.text('Yorumları yenile'));
      api.pendingRead = null;
      api.rows = [];
      session.changeOwner();
      await tester.pumpAndSettle();
      pending.complete((items: [rootComment()], totalCount: 1));
      await tester.pumpAndSettle();
      expect(find.text('Sentetik diyetisyen yorumu'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      session.end();
      await tester.pumpAndSettle();
      expect(find.text('Diyetisyen yorumları ve yanıtlar'), findsNothing);
    },
  );
  testWidgets('late POST cannot show success or old rows in a new account', (
    tester,
  ) async {
    await open(tester);
    await draft(tester);
    final pending = Completer<MealLogComment>();
    api.pendingWrite = pending.future;
    await tap(tester, find.text('Yanıt gönder'));
    api.rows = [];
    session.changeOwner();
    await tester.pump();
    pending.complete(clientReply());
    await tester.pumpAndSettle();
    expect(api.writes, 1);
    expect(find.text('Yanıtınız kaydedildi.'), findsNothing);
    expect(find.text('Sentetik danışan yanıtı'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });
  testWidgets('background and a changed meal clear private response state', (
    tester,
  ) async {
    await open(tester);
    await draft(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Diyetisyen yorumu'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    api.rows = [];
    await open(tester, child: section(id: commentAuthorId));
    expect(find.text('Henüz yorum veya yanıt yok.'), findsOneWidget);
  });
}
