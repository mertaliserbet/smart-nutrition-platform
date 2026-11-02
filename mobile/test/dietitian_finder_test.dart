import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/app.dart';
import 'package:smart_nutrition_mobile/core/network/json_api.dart';
import 'package:smart_nutrition_mobile/core/theme/app_theme.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/auth/login_page.dart';
import 'package:smart_nutrition_mobile/features/dietitians/dietitian_api.dart';
import 'package:smart_nutrition_mobile/features/dietitians/dietitian_finder_page.dart';

const expert = DietitianListItem(
  '11111111-1111-4111-8111-111111111111',
  'Sentetik Ece',
);
const relation = RelationshipResponse(
  id: '33333333-3333-4333-8333-333333333333',
  clientId: '22222222-2222-4222-8222-222222222222',
  dietitianId: '11111111-1111-4111-8111-111111111111',
  status: 'pending',
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
    Brightness brightness = Brightness.light,
    Size size = const Size(400, 1200),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
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
          home: DietitianFinderPage(api: api),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> visible(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  Future<void> select(WidgetTester tester) async {
    final tile = find.byKey(ValueKey(expert.id));
    await visible(tester, tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
  }

  final send = find.widgetWithText(FilledButton, 'Bağlantı İsteği Gönder');
  final codeSend = find.widgetWithText(
    OutlinedButton,
    'Davet Koduyla İstek Gönder',
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'small ${brightness.name} screen shows real profile fields and waits for confirmed pending response',
      (tester) async {
        await open(
          tester,
          brightness: brightness,
          size: const Size(320, 640),
          scale: 1.3,
        );
        await select(tester);
        expect(find.text('Admin onaylı diyetisyen'), findsOneWidget);
        expect(find.textContaining('Veri paylaşımı ayrıca'), findsOneWidget);
        final result = Completer<RelationshipResponse>();
        api.post = result.future;
        await tester.ensureVisible(send);
        await tester.tap(send);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(api.writes, 1);
        expect(api.lastId, expert.id);
        expect(api.lastCode, isNull);
        expect(find.textContaining('isteğiniz gönderildi'), findsNothing);
        expect(tester.widget<OutlinedButton>(codeSend).onPressed, isNull);
        result.complete(relation);
        await tester.pumpAndSettle();
        expect(api.writes, 1);
        expect(api.pending, [relation]);
        await tester.scrollUntilVisible(
          find.textContaining('Bağlantı isteğiniz gönderildi'),
          -250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          find.textContaining('Bağlantı isteğiniz gönderildi'),
          findsOneWidget,
        );
        await select(tester);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(
                  FilledButton,
                  'Onay bekleyen isteğiniz var',
                ),
              )
              .onPressed,
          isNull,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'invitation validates locally and normalizes exactly one request',
    (tester) async {
      await open(tester);
      final field = find.widgetWithText(TextField, 'Davet kodu');
      await tester.enterText(field, 'invalid');
      await tester.tap(codeSend);
      await tester.pumpAndSettle();
      expect(find.textContaining('16 karakterli davet kodunu'), findsOneWidget);
      expect(api.writes, 0);
      await tester.enterText(field, ' abcdefgh234567ab ');
      await tester.tap(codeSend);
      await tester.pumpAndSettle();
      expect(api.writes, 1);
      expect(api.lastCode, 'ABCDEFGH234567AB');
      expect(api.lastId, isNull);
      expect(
        find.textContaining('Bağlantı isteğiniz gönderildi'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'active relationship disables both direct and invitation requests',
    (tester) async {
      api.active = RelationshipResponse(
        id: relation.id,
        clientId: relation.clientId,
        dietitianId: relation.dietitianId,
        status: 'active',
      );
      await open(tester);
      expect(find.text('Aktif diyetisyeniniz'), findsWidgets);
      expect(tester.widget<OutlinedButton>(codeSend).onPressed, isNull);
      await select(tester);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Aktif diyetisyeniniz var'),
            )
            .onPressed,
        isNull,
      );
      expect(api.writes, 0);
    },
  );
  for (final status in [409, 422, 429, 500]) {
    testWidgets(
      'HTTP $status gives no success or automatic retry; refresh required',
      (tester) async {
        api.failure = DietitianApiException(
          'Sentetik işlem hatası $status',
          statusCode: status,
          retryAfter: const Duration(seconds: 60),
        );
        await open(tester);
        await select(tester);
        await tester.tap(send);
        await tester.pumpAndSettle();
        expect(api.writes, 1);
        expect(find.textContaining('isteğiniz gönderildi'), findsNothing);
        expect(find.textContaining('Tekrar göndermeden'), findsOneWidget);
        expect(tester.widget<OutlinedButton>(codeSend).onPressed, isNull);
        await tester.tap(
          find.widgetWithText(TextButton, 'Bağlantıları yenile'),
        );
        await tester.pumpAndSettle();
        expect(api.writes, 1);
        expect(
          tester.widget<OutlinedButton>(codeSend).onPressed != null,
          status != 429,
        );
      },
    );
  }
  testWidgets(
    'unknown write result is checked via reads before any further send',
    (tester) async {
      api.failure = const DietitianApiException('Bağlantı kesildi.');
      await open(tester);
      await select(tester);
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(api.writes, 1);
      expect(find.textContaining('isteğiniz gönderildi'), findsNothing);
      api.pending = [relation];
      api.failure = null;
      await tester.tap(find.widgetWithText(TextButton, 'Bağlantıları yenile'));
      await tester.pumpAndSettle();
      expect(find.text('Bekleyen istekler (1)'), findsOneWidget);
      expect(api.writes, 1);
      await select(tester);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Onay bekleyen isteğiniz var'),
            )
            .onPressed,
        isNull,
      );
    },
  );
  testWidgets(
    'failed relationship read blocks writes even when search succeeds',
    (tester) async {
      api.readFailure = true;
      await open(tester);
      expect(find.textContaining('İstek göndermeden'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(codeSend).onPressed, isNull);
      await select(tester);
      expect(tester.widget<FilledButton>(send).onPressed, isNull);
      expect(api.writes, 0);
    },
  );
  testWidgets(
    'search pagination, pending pagination and empty state use API results',
    (tester) async {
      api.searchTotal = 11;
      api.pendingTotal = 11;
      api.pending = [relation];
      await open(tester);
      await tester.tap(find.text('İstekler sonraki'));
      await tester.pumpAndSettle();
      expect(api.lastPendingPage, 2);
      final next = find.text('Uzmanlar sonraki');
      await visible(tester, next);
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(api.lastPage, 2);
      final field = find.widgetWithText(TextField, 'Diyetisyen adı');
      await visible(tester, field);
      await tester.enterText(field, ' İpek ');
      api.experts = [];
      api.searchTotal = 0;
      await tester.tap(find.widgetWithText(FilledButton, 'Ara'));
      await tester.pumpAndSettle();
      expect(api.lastPage, 1);
      expect(api.lastQuery, 'İpek');
      expect(
        find.textContaining('eşleşen onaylı diyetisyen bulunamadı'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'late search cannot replace the newer query or update a disposed page',
    (tester) async {
      await open(tester);
      final field = find.widgetWithText(TextField, 'Diyetisyen adı');
      await visible(tester, field);
      final old = Completer<DietitianPage<DietitianListItem>>();
      api.searchResult = old.future;
      await tester.enterText(field, 'Eski');
      await tester.tap(find.widgetWithText(FilledButton, 'Ara'));
      await tester.pump();
      api.searchResult = null;
      api.experts = [];
      await tester.enterText(field, 'Yeni');
      await tester.tap(find.widgetWithText(FilledButton, 'Ara'));
      await tester.pumpAndSettle();
      old.complete((items: [expert], totalCount: 1));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey(expert.id)), findsNothing);
      final late = Completer<DietitianPage<DietitianListItem>>();
      api.searchResult = late.future;
      await tester.tap(find.widgetWithText(FilledButton, 'Ara'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      late.complete((items: [expert], totalCount: 1));
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'late mutation result cannot update a page that has been closed',
    (tester) async {
      await open(tester);
      await select(tester);
      final result = Completer<RelationshipResponse>();
      api.post = result.future;
      await tester.tap(send);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(api.writes, 1);
      await tester.pumpWidget(const SizedBox());
      result.complete(relation);
      await tester.pumpAndSettle();
      expect(find.textContaining('isteğiniz gönderildi'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'profile and app bar open guarded route; logout removes it and back cannot restore it',
    (tester) async {
      await tester.pumpWidget(SmartNutritionApp(session: session));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Diyetisyen Bul'));
      await tester.pumpAndSettle();
      expect(find.byType(DietitianFinderPage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profil'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Diyetisyen Bul'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Diyetisyen Bul'));
      await tester.pumpAndSettle();
      expect(find.byType(DietitianFinderPage), findsOneWidget);
      await session.signOut();
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      expect(
        find.byType(DietitianFinderPage, skipOffstage: false),
        findsNothing,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
    },
  );
}

class _Session extends AuthSession {
  bool authenticated = true;
  @override
  bool get isAuthenticated => authenticated;
  @override
  bool get isBlocking => false;
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
    Map<String, String>? payload,
    String? profileContext,
  }) async => (
    statusCode: 200,
    body: {'items': [], 'totalCount': 0},
    hasBody: true,
    retryAfter: null,
  );
}

class _Api extends DietitianApi {
  _Api(super.session);
  List<DietitianListItem> experts = [expert];
  List<RelationshipResponse> pending = [];
  RelationshipResponse? active;
  int writes = 0, lastPage = 0, lastPendingPage = 0;
  int? searchTotal, pendingTotal;
  String? lastId, lastCode, lastQuery;
  bool readFailure = false;
  DietitianApiException? failure;
  Future<RelationshipResponse>? post;
  Future<DietitianPage<DietitianListItem>>? searchResult;
  @override
  Future<DietitianPage<DietitianListItem>> search({
    required int page,
    String query = '',
  }) async {
    lastPage = page;
    lastQuery = query;
    return searchResult ??
        (items: experts, totalCount: searchTotal ?? experts.length);
  }

  @override
  Future<DietitianPage<RelationshipResponse>> relationships({
    required String status,
    int page = 1,
  }) async {
    if (readFailure) {
      throw const DietitianApiException('Bağlantılar okunamadı.');
    }
    if (status == 'active') {
      return (items: [?active], totalCount: active == null ? 0 : 1);
    }
    lastPendingPage = page;
    return (items: pending, totalCount: pendingTotal ?? pending.length);
  }

  @override
  Future<RelationshipResponse> request({
    String? dietitianId,
    String? invitationCode,
  }) async {
    writes++;
    lastId = dietitianId;
    lastCode = invitationCode;
    if (failure != null) throw failure!;
    final result = await (post ?? Future.value(relation));
    pending = [result];
    return result;
  }
}
