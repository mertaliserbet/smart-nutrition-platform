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
import 'package:smart_nutrition_mobile/features/dietitians/client_connections_page.dart';

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

  Future<void> manage(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    Size size = const Size(400, 1200),
    double scale = 1,
  }) async {
    await open(tester, brightness: brightness, size: size, scale: scale);
    final button = find.widgetWithText(
      OutlinedButton,
      'Bağlantıları ve paylaşımı yönet',
    );
    await visible(tester, button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(ClientConnectionsPage), findsOneWidget);
  }

  Future<void> filter(WidgetTester tester, String label) async {
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  RelationshipResponse status(String value) => RelationshipResponse(
    id: relation.id,
    clientId: relation.clientId,
    dietitianId: relation.dietitianId,
    status: value,
  );
  const permission = DataSharingPermission(
    id: '44444444-4444-4444-8444-444444444444',
    relationshipId: '33333333-3333-4333-8333-333333333333',
    isGranted: true,
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      'sharing is closed by default; explicit dialog grants and revokes in ${brightness.name}',
      (tester) async {
        api.active = status('active');
        await manage(
          tester,
          brightness: brightness,
          size: const Size(320, 640),
          scale: 1.3,
        );
        expect(
          find.text('İsteğiniz kabul edildi; bağlantınız aktif.'),
          findsOneWidget,
        );
        expect(api.permissionWrites, 0);
        expect(find.textContaining('Paylaşım izni kapalı'), findsOneWidget);
        final grant = find.widgetWithText(FilledButton, 'Paylaşıma İzin Ver');
        await visible(tester, grant);
        await tester.tap(grant);
        await tester.pumpAndSettle();
        expect(find.textContaining('izin veriyor musunuz'), findsOneWidget);
        await tester.tap(find.text('Vazgeç'));
        await tester.pumpAndSettle();
        expect(api.permissionWrites, 0);
        await tester.tap(grant);
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(of: find.byType(AlertDialog), matching: grant),
        );
        await tester.pumpAndSettle();
        expect(api.permissionWrites, 1);
        expect(api.lastGranted, isTrue);
        expect(api.lastPermission, isNull);
        expect(find.text('Paylaşım izni açık.'), findsOneWidget);
        final revoke = find.widgetWithText(FilledButton, 'İzni Geri Al');
        await visible(tester, revoke);
        await tester.tap(revoke);
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(of: find.byType(AlertDialog), matching: revoke),
        );
        await tester.pumpAndSettle();
        expect(api.permissionWrites, 2);
        expect(api.lastGranted, isFalse);
        expect(api.lastPermission, isNotNull);
        expect(api.active, isNotNull);
        expect(find.textContaining('Paylaşım izni kapalı'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'client cancels own pending request; no accept/reject/share controls exist',
    (tester) async {
      api.pending = [relation];
      await manage(tester);
      await filter(tester, 'Onay bekleyen');
      expect(
        find.textContaining('Diyetisyenin kabul veya ret'),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Kabul et'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Reddet'), findsNothing);
      expect(
        find.widgetWithText(FilledButton, 'Paylaşıma İzin Ver'),
        findsNothing,
      );
      final cancel = find.widgetWithText(OutlinedButton, 'İsteği İptal Et');
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'İsteği İptal Et'));
      await tester.pumpAndSettle();
      expect(api.ends, 1);
      expect(api.pending, isEmpty);
      expect(api.permissionWrites, 0);
      expect(find.text('Bağlantı isteğiniz iptal edildi.'), findsOneWidget);
      await filter(tester, 'Sonlandırılan');
      expect(find.textContaining('Bu bağlantı sona erdi'), findsOneWidget);
    },
  );
  testWidgets(
    'ending active connection requires confirmation and refreshes finder on return',
    (tester) async {
      api.active = status('active');
      api.grant = permission;
      await manage(tester);
      final end = find.widgetWithText(OutlinedButton, 'Bağlantıyı Sonlandır');
      await tester.tap(end);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('aktif atanmış programı arşivlenir'),
        findsOneWidget,
      );
      await tester.tap(
        find.widgetWithText(FilledButton, 'Bağlantıyı Sonlandır'),
      );
      await tester.pumpAndSettle();
      expect(api.active, isNull);
      expect(api.ends, 1);
      expect(api.permissionWrites, 0);
      expect(find.text('Aktif diyetisyen bağlantınız yok.'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Aktif diyetisyeniniz yok.'), findsOneWidget);
    },
  );
  testWidgets('rejected and ended history is read only and paginated', (
    tester,
  ) async {
    api.history = [status('rejected')];
    api.historyTotal = 11;
    await manage(tester);
    await filter(tester, 'Reddedilen');
    expect(
      find.text('Diyetisyen bağlantı isteğinizi reddetti.'),
      findsOneWidget,
    );
    expect(find.text('İsteği İptal Et'), findsNothing);
    expect(find.text('Bağlantıyı Sonlandır'), findsNothing);
    await tester.tap(find.text('Sonraki bağlantılar'));
    await tester.pumpAndSettle();
    expect(api.historyPage, 2);
    expect(api.ends, 0);
    expect(api.permissionWrites, 0);
  });
  for (final failureStatus in [403, 409, 500]) {
    testWidgets(
      'permission failure $failureStatus hides stale state and requires explicit reload',
      (tester) async {
        api.active = status('active');
        api.grant = permission;
        api.permissionFailure = DietitianApiException(
          'İzin işlemi hatası $failureStatus',
          statusCode: failureStatus,
        );
        await manage(tester);
        final revoke = find.widgetWithText(FilledButton, 'İzni Geri Al');
        await tester.tap(revoke);
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(of: find.byType(AlertDialog), matching: revoke),
        );
        await tester.pumpAndSettle();
        expect(api.permissionWrites, 1);
        expect(find.text('Paylaşım izni açık.'), findsNothing);
        expect(find.text('Paylaşım izniniz geri alındı.'), findsNothing);
        expect(find.textContaining('Tekrar işlem yapmadan'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'İzni Geri Al'), findsNothing);
        await tester.tap(find.text('Durumu yenile'));
        await tester.pumpAndSettle();
        expect(api.permissionWrites, 1);
        expect(find.text('Paylaşım izni açık.'), findsOneWidget);
      },
    );
  }
  testWidgets(
    'unknown network result does not claim permission or cancellation success',
    (tester) async {
      api.pending = [relation];
      api.endFailure = const DietitianApiException('Bağlantı kesildi.');
      await manage(tester);
      await filter(tester, 'Onay bekleyen');
      await tester.tap(find.widgetWithText(OutlinedButton, 'İsteği İptal Et'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'İsteği İptal Et'));
      await tester.pumpAndSettle();
      expect(api.ends, 1);
      expect(find.text('Bağlantı isteğiniz iptal edildi.'), findsNothing);
      expect(find.textContaining('Tekrar işlem yapmadan'), findsOneWidget);
    },
  );
  testWidgets(
    'permission read failure is unknown, not closed permission; no mutation control appears',
    (tester) async {
      api.active = status('active');
      api.permissionReadFailure = true;
      await manage(tester);
      expect(api.permissionWrites, 0);
      expect(find.textContaining('Paylaşım izni kapalı'), findsNothing);
      expect(find.text('Paylaşıma İzin Ver'), findsNothing);
      expect(find.textContaining('Güncel durum doğrulanmadan'), findsOneWidget);
    },
  );
  testWidgets(
    'loading grant prevents duplicate writes and ignores completion after exit',
    (tester) async {
      api.active = status('active');
      await manage(tester);
      final grant = find.widgetWithText(FilledButton, 'Paylaşıma İzin Ver');
      final result = Completer<DataSharingPermission>();
      api.permissionResult = result.future;
      await tester.tap(grant);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: find.byType(AlertDialog), matching: grant),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(api.permissionWrites, 1);
      expect(tester.widget<FilledButton>(grant).onPressed, isNull);
      expect(
        find.text('Beslenme programları için paylaşım izni verildi.'),
        findsNothing,
      );
      await tester.pageBack();
      await tester.pump();
      result.complete(permission);
      await tester.pumpAndSettle();
      expect(api.permissionWrites, 1);
      expect(find.byType(ClientConnectionsPage), findsNothing);
      expect(tester.takeException(), isNull);
    },
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
    'Turkish IME composing text is preserved and submitted without transliteration',
    (tester) async {
      await open(tester);
      final field = find.widgetWithText(TextField, 'Diyetisyen adı');
      await visible(tester, field);
      await tester.showKeyboard(field);
      const query = 'Çağrı İpek Şen ıİğĞşŞçÇöÖüÜ';
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: query,
          selection: TextSelection.collapsed(offset: query.length),
          composing: TextRange(start: 0, end: 5),
        ),
      );
      await tester.pump();
      expect(tester.widget<TextField>(field).controller!.text, query);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: query,
          selection: TextSelection.collapsed(offset: query.length),
        ),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Ara'));
      await tester.pumpAndSettle();
      expect(api.lastQuery, query);
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
      final manageButton = find.widgetWithText(
        OutlinedButton,
        'Bağlantıları ve paylaşımı yönet',
      );
      await tester.ensureVisible(manageButton);
      await tester.tap(manageButton);
      await tester.pumpAndSettle();
      expect(find.byType(ClientConnectionsPage), findsOneWidget);
      await session.signOut();
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      expect(
        find.byType(DietitianFinderPage, skipOffstage: false),
        findsNothing,
      );
      expect(
        find.byType(ClientConnectionsPage, skipOffstage: false),
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
    Map<String, Object?>? payload,
    String? profileContext,
    String? method,
    int maxResponseBytes = 65536,
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
  List<RelationshipResponse> history = [];
  int historyPage = 0, ends = 0, permissionWrites = 0;
  int? historyTotal;
  DataSharingPermission? grant, lastPermission;
  bool? lastGranted;
  bool permissionReadFailure = false;
  DietitianApiException? permissionFailure, endFailure;
  Future<DataSharingPermission>? permissionResult;
  @override
  Future<DataSharingPermission?> permission(String relationshipId) async {
    if (permissionReadFailure) {
      throw const DietitianApiException('Paylaşım durumu okunamadı.');
    }
    return grant;
  }

  @override
  Future<DataSharingPermission> setPermission({
    required String relationshipId,
    required bool isGranted,
    DataSharingPermission? current,
  }) async {
    permissionWrites++;
    lastGranted = isGranted;
    lastPermission = current;
    if (permissionFailure != null) throw permissionFailure!;
    grant =
        await (permissionResult ??
            Future.value(
              DataSharingPermission(
                id: '44444444-4444-4444-8444-444444444444',
                relationshipId: relationshipId,
                isGranted: isGranted,
              ),
            ));
    return grant!;
  }

  @override
  Future<RelationshipResponse> endRelationship(RelationshipResponse row) async {
    ends++;
    if (endFailure != null) throw endFailure!;
    final ended = RelationshipResponse(
      id: row.id,
      clientId: row.clientId,
      dietitianId: row.dietitianId,
      status: 'ended',
    );
    pending.removeWhere((candidate) => candidate.id == row.id);
    if (active?.id == row.id) active = null;
    history.add(ended);
    return ended;
  }

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
    if (status == 'rejected' || status == 'ended') {
      historyPage = page;
      final rows = history.where((row) => row.status == status).toList();
      return (items: rows, totalCount: historyTotal ?? rows.length);
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
