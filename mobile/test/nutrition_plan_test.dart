import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/app.dart';
import 'package:smart_nutrition_mobile/core/network/json_api.dart';
import 'package:smart_nutrition_mobile/core/theme/app_theme.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/auth/login_api.dart';
import 'package:smart_nutrition_mobile/features/auth/login_page.dart';
import 'package:smart_nutrition_mobile/features/navigation/main_shell.dart';
import 'package:smart_nutrition_mobile/features/nutrition/nutrition_page.dart';
import 'package:smart_nutrition_mobile/features/nutrition/manual_meal_log_page.dart';
import 'package:smart_nutrition_mobile/features/nutrition/nutrition_plan_api.dart';

NutritionPlanResponse plan({
  String title = 'Sentetik haftalık program',
  bool personal = false,
  int version = 1,
}) => NutritionPlanResponse(
  id: '11111111-1111-4111-8111-111111111111',
  clientId: '22222222-2222-4222-8222-222222222222',
  dietitianId: personal ? null : '33333333-3333-4333-8333-333333333333',
  title: title,
  startDate: '2026-11-03',
  endDate: null,
  dailyCaloriesTargetKcal: null,
  dailyWaterTargetMl: 2000,
  createdAt: DateTime.utc(2026, 11, 2),
  versionId: '55555555-5555-4555-8555-555555555555',
  versionNumber: version,
  items: [
    const NutritionPlanItem(
      id: 'item1',
      nutritionPlanId: 'plan',
      dayOfWeek: null,
      mealType: 'breakfast',
      description: 'Yulaf ve yoğurt 🥣',
      recommendedQuantity: '1 kâse',
      sortOrder: 0,
      alternativeGroupId: null,
    ),
    for (final (index, text) in [(1, 'Mercimek çorbası'), (2, 'Sebze çorbası')])
      NutritionPlanItem(
        id: 'item$index',
        nutritionPlanId: 'plan',
        dayOfWeek: 1,
        mealType: 'lunch',
        description: text,
        recommendedQuantity: null,
        sortOrder: index,
        alternativeGroupId: 'same-group',
      ),
  ],
);
void main() {
  late _Session session;
  late _Api api;
  setUp(() {
    session = _Session();
    api = _Api(session);
  });
  tearDown(() => session.dispose());
  Future<void> open(
    WidgetTester tester, {
    bool active = true,
    int revision = 0,
    Brightness brightness = Brightness.light,
    Size size = const Size(400, 1000),
    double scale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      AuthSessionScope(
        session: session,
        child: MaterialApp(
          theme: brightness == Brightness.light
              ? AppTheme.light
              : AppTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: NutritionPage(
              api: api,
              active: active,
              refreshRevision: revision,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> see(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  final refresh = find.widgetWithText(TextButton, 'Programı yenile');
  for (final brightness in Brightness.values) {
    testWidgets(
      'read-only program groups days/meals/alternatives in small ${brightness.name} screen',
      (tester) async {
        await open(
          tester,
          brightness: brightness,
          size: const Size(320, 640),
          scale: 1.5,
        );
        await tester.pumpAndSettle();
        for (final text in [
          'Beslenme Programım',
          'Sentetik haftalık program',
          'Her gün',
          'Kahvaltı',
          'Yulaf ve yoğurt 🥣',
          'Miktar önerisi: 1 kâse',
          'Pazartesi',
          'Öğle',
          'Mercimek çorbası',
          'Sebze çorbası',
        ]) {
          await see(tester, find.text(text));
          expect(find.text(text).hitTestable(), findsOneWidget);
        }
        expect(find.text('Alternatif 1'), findsNWidgets(2));
        expect(
          find.textContaining('Diyetisyeniniz tarafından atanmış'),
          findsOneWidget,
        );
        expect(find.byType(TextField), findsNothing);
        expect(find.textContaining('Düzenle'), findsNothing);
        expect(find.textContaining('0 kcal'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    '404-style null response is an empty state with retry, not an error',
    (tester) async {
      api.value = null;
      await open(tester);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Henüz aktif bir beslenme programınız bulunmuyor'),
        findsOneWidget,
      );
      expect(find.text('Yeniden dene'), findsNothing);
      expect(refresh, findsOneWidget);
    },
  );
  testWidgets(
    'initial loading shows no fabricated program before the response',
    (tester) async {
      final result = Completer<NutritionPlanResponse?>();
      api.result = result.future;
      await open(tester);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Sentetik haftalık program'), findsNothing);
      result.complete(plan());
      await tester.pumpAndSettle();
      expect(find.text('Sentetik haftalık program'), findsOneWidget);
      expect(api.reads, 1);
    },
  );
  for (final status in [401, 403, 500]) {
    testWidgets(
      '$status on refresh removes old program; retry replaces it with latest server state',
      (tester) async {
        await open(tester);
        await tester.pumpAndSettle();
        await see(tester, refresh);
        api.failure = NutritionPlanApiException(
          'Program erişimi doğrulanamadı ($status).',
          statusCode: status,
        );
        await tester.tap(refresh);
        await tester.pumpAndSettle();
        expect(find.text('Sentetik haftalık program'), findsNothing);
        expect(find.text('Yeniden dene'), findsOneWidget);
        api.failure = null;
        api.value = plan(title: 'Yeni sunucu programı', version: 2);
        await tester.tap(find.text('Yeniden dene'));
        await tester.pumpAndSettle();
        expect(find.text('Yeni sunucu programı'), findsOneWidget);
        expect(find.text('Aktif program · Sürüm 2'), findsOneWidget);
      },
    );
  }
  testWidgets(
    'transient connection failure hides stale content while preserving retry capability',
    (tester) async {
      await open(tester);
      await tester.pumpAndSettle();
      await see(tester, refresh);
      api.failure = const NutritionPlanApiException('Bağlantı kesildi.');
      await tester.tap(refresh);
      await tester.pumpAndSettle();
      expect(find.text('Sentetik haftalık program'), findsNothing);
      expect(find.text('Yeniden dene'), findsOneWidget);
      expect(session.isAuthenticated, isTrue);
    },
  );
  testWidgets(
    'relationship ending is reflected by empty refresh without retaining assigned program',
    (tester) async {
      await open(tester);
      await tester.pumpAndSettle();
      await see(tester, refresh);
      api.value = null;
      await tester.tap(refresh);
      await tester.pumpAndSettle();
      expect(find.text('Sentetik haftalık program'), findsNothing);
      expect(find.textContaining('Henüz aktif'), findsOneWidget);
    },
  );
  testWidgets(
    'hidden tab clears content, does not fetch, and re-entry reloads',
    (tester) async {
      await open(tester, active: false);
      expect(api.reads, 0);
      await open(tester);
      await tester.pumpAndSettle();
      expect(api.reads, 1);
      await open(tester, active: false);
      expect(find.text('Sentetik haftalık program'), findsNothing);
      api.value = null;
      await open(tester);
      await tester.pumpAndSettle();
      expect(api.reads, 2);
      expect(find.textContaining('Henüz aktif'), findsOneWidget);
    },
  );
  testWidgets(
    'background clears private content; resume rejects earlier response and reads latest program',
    (tester) async {
      final old = Completer<NutritionPlanResponse?>();
      api.result = old.future;
      await open(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      api.result = null;
      api.value = plan(title: 'Yeni sunucu programı');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      old.complete(plan());
      await tester.pumpAndSettle();
      expect(find.text('Yeni sunucu programı'), findsOneWidget);
      expect(find.text('Sentetik haftalık program'), findsNothing);
      expect(api.reads, 2);
    },
  );
  testWidgets(
    'account change, revision and disposal cannot display an older response',
    (tester) async {
      final old = Completer<NutritionPlanResponse?>();
      api.result = old.future;
      await open(tester);
      api.result = null;
      api.value = null;
      session.owner = '66666666-6666-4666-8666-666666666666';
      session.notifyListeners();
      await tester.pumpAndSettle();
      old.complete(plan());
      await tester.pumpAndSettle();
      expect(find.text('Sentetik haftalık program'), findsNothing);
      final late = Completer<NutritionPlanResponse?>();
      api.result = late.future;
      await open(tester, revision: 1);
      await tester.pumpWidget(const SizedBox());
      late.complete(plan());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'personal program is labelled separately without editing controls',
    (tester) async {
      api.value = plan(personal: true);
      await open(tester);
      await tester.pumpAndSettle();
      expect(
        find.text('Kişisel programınız · Salt okunur görünüm'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
    },
  );
  testWidgets(
    'manual meal form stays available and return refreshes the program',
    (tester) async {
      await open(tester);
      await tester.pumpAndSettle();
      await see(tester, find.text('Öğün ekle'));
      await tester.tap(find.text('Öğün ekle'));
      await tester.pumpAndSettle();
      expect(find.byType(ManualMealLogPage), findsOneWidget);
      api.value = null;
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(api.reads, 2);
      expect(find.textContaining('Henüz aktif'), findsOneWidget);
    },
  );
  testWidgets(
    'navigation loads only selected nutrition tab; logout discards it',
    (tester) async {
      await tester.pumpWidget(SmartNutritionApp(session: session));
      await tester.pumpAndSettle();
      expect(session.requests, isEmpty);
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Beslenme'),
        ),
      );
      await tester.pumpAndSettle();
      expect(session.requests.length, 1);
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Beslenme'),
        ),
      );
      await tester.pumpAndSettle();
      expect(session.requests.length, 2);
      await tester.tap(find.text('Profil'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Beslenme'),
        ),
      );
      await tester.pumpAndSettle();
      expect(session.requests.length, 3);
      await tester.tap(find.byTooltip('Diyetisyen Bul'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        session.requests
            .where((path) => path == '/api/v1/nutrition-plans/active')
            .length,
        4,
      );
      await session.signOut();
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byType(NutritionPage, skipOffstage: false), findsNothing);
      expect(find.byType(MainShell, skipOffstage: false), findsNothing);
    },
  );
}

class _Api extends NutritionPlanApi {
  _Api(super.session);
  NutritionPlanResponse? value = plan();
  Future<NutritionPlanResponse?>? result;
  NutritionPlanApiException? failure;
  int reads = 0;
  @override
  Future<NutritionPlanResponse?> active() async {
    reads++;
    if (failure != null) throw failure!;
    return result ?? value;
  }
}

class _Session extends AuthSession {
  bool authenticated = true;
  String owner = '77777777-7777-4777-8777-777777777777';
  List<String> requests = [];
  @override
  bool get isAuthenticated => authenticated;
  @override
  bool get isBlocking => false;
  @override
  CurrentUserResponse? get user => authenticated
      ? CurrentUserResponse(
          id: owner,
          displayName: 'Sentetik',
          email: 'synthetic@example.test',
          role: 'client',
          isEmailVerified: true,
        )
      : null;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> signOut({String? message}) async {
    authenticated = false;
    notifyListeners();
  }

  @override
  Future<JsonApiResponse> authorizedRequest({
    required String path,
    Map<String, Object?>? payload,
    String? profileContext,
    String? method,
    int maxResponseBytes = 65536,
  }) async {
    requests.add(path);
    return (statusCode: 404, body: null, hasBody: false, retryAfter: null);
  }
}
