import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/core/network/json_api.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/auth/login_api.dart';
import 'package:smart_nutrition_mobile/features/chat/chat_page.dart';
import 'package:smart_nutrition_mobile/features/chat/chat_view.dart';
import 'package:smart_nutrition_mobile/features/dietitians/dietitian_api.dart';
import 'package:smart_nutrition_mobile/features/onboarding/onboarding_theme.dart';

const _expertId = '33333333-3333-4333-8333-333333333333';
const _relationship = RelationshipResponse(
  id: '11111111-1111-4111-8111-111111111111',
  clientId: '22222222-2222-4222-8222-222222222222',
  dietitianId: _expertId,
  status: 'active',
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
    Size size = const Size(390, 920),
    double scale = 1,
    bool settle = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      AuthSessionScope(
        session: session,
        child: MaterialApp(
          theme: OnboardingTheme.data,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: child!,
          ),
          routes: {
            '/dietitians': (_) =>
                Scaffold(appBar: AppBar(title: const Text('Uzman araması'))),
          },
          home: Scaffold(
            body: ChatPage(active: active, refreshRevision: revision, api: api),
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> tap(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets('Unicode draft is editable and send cannot create a message', (
    tester,
  ) async {
    await open(tester);
    expect(
      find.text('Mert Ali, aklındakileri Deniz ile paylaş.'),
      findsOneWidget,
    );
    await tap(tester, find.text('Merhaba diyelim'));
    const value = 'i ı İ I ş Ş ö Ö ü Ü ğ Ğ ç Ç\n你好 مرحبا';
    await tester.enterText(find.byType(TextField), value);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, value);
    expect(field.inputFormatters, isNull);
    expect(field.textCapitalization, TextCapitalization.none);
    expect(field.textInputAction, TextInputAction.newline);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == 'Mesajı gönder',
            ),
          )
          .onPressed,
      isNull,
    );
    expect(find.byType(ChatBubble), findsNothing);
    expect(find.text('Uğur Çetin'), findsNothing);
    expect(find.textContaining('Şerbet'), findsNothing);
    expect(session.requests, isEmpty);
    expect(api.reads, 1);
    expect(tester.takeException(), isNull);
  });
  for (final (size, scale) in [
    (const Size(320, 480), 2.0),
    (const Size(568, 320), 2.0),
    (const Size(430, 900), 1.3),
  ]) {
    testWidgets('layout and attachment sheet fit $size at scale $scale', (
      tester,
    ) async {
      await open(tester, size: size, scale: scale);
      await tap(tester, find.byTooltip('Dosya ekle'));
      expect(find.text('Sohbetine ekle'), findsOneWidget);
      expect(find.text('Dosya seç'), findsOneWidget);
      expect(find.text('Planımdan paylaş'), findsOneWidget);
      expect(
        find.text('Dosya paylaşımı henüz kullanıma açık değil.'),
        findsOneWidget,
      );
      await tap(tester, find.text('Sohbete dön'));
      await tap(tester, find.byTooltip('Sohbet bilgisini aç'));
      expect(find.text('Deniz ile sohbetin'), findsOneWidget);
      await tap(tester, find.text('Sohbete dön'));
      expect(tester.takeException(), isNull);
      expect(session.requests, isEmpty);
    });
  }
  testWidgets('keyboard leaves composer visible and does not enable sending', (
    tester,
  ) async {
    await open(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tap(tester, find.text('Merhaba diyelim'));
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.byType(TextField));
    expect(rect.bottom, lessThanOrEqualTo(600));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'no relationship is a truthful empty state and uses existing expert search',
    (tester) async {
      api.rows = [];
      await open(tester);
      expect(find.text('Deniz Yılmaz'), findsNothing);
      expect(
        find.textContaining('Diyetisyen bağlantın henüz yok'),
        findsOneWidget,
      );
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      await tap(tester, find.text('Diyetisyen bul'));
      expect(find.text('Uzman araması'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(api.reads, 2);
    },
  );
  testWidgets('loading and retry never retain stale expert identity', (
    tester,
  ) async {
    await open(tester);
    api.failure = const DietitianApiException('Sentetik bağlantı hatası');
    await open(tester, revision: 1);
    expect(find.text('Deniz Yılmaz'), findsNothing);
    expect(find.text('Sentetik bağlantı hatası'), findsOneWidget);
    api.failure = null;
    api.experts = [const DietitianListItem(_expertId, 'Yeni Uzman')];
    await tap(tester, find.text('Yeniden dene'));
    expect(find.text('Yeni Uzman'), findsOneWidget);
  });
  testWidgets(
    'unavailable directory never substitutes an unrelated dietitian',
    (tester) async {
      api.experts = [const DietitianListItem('another-id', 'Başka Uzman')];
      await open(tester);
      expect(find.text('Başka Uzman'), findsNothing);
      expect(find.text('Diyetisyenin'), findsOneWidget);
      expect(api.searches, 1);
    },
  );
  testWidgets(
    'hidden tab does not read, clears draft and ignores pending name',
    (tester) async {
      await open(tester, active: false);
      expect(api.reads, 0);
      await open(tester);
      await tester.enterText(find.byType(TextField), 'Özel taslak');
      api.pendingNames = Completer<DietitianPage<DietitianListItem>>();
      await open(tester, revision: 1);
      await open(tester, active: false, revision: 1);
      api.pendingNames!.complete((
        items: [const DietitianListItem(_expertId, 'Geç Gelen Uzman')],
        totalCount: 1,
      ));
      await tester.pumpAndSettle();
      expect(find.text('Geç Gelen Uzman'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(api.reads, 2);
    },
  );
  testWidgets(
    'account switch discards old relationship result and clears draft',
    (tester) async {
      api.pending = Completer<DietitianPage<RelationshipResponse>>();
      final pending = api.pending!;
      await open(tester, settle: false);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      api.pending = null;
      api.rows = [];
      session.changeOwner();
      await tester.pumpAndSettle();
      pending.complete((items: [_relationship], totalCount: 1));
      await tester.pumpAndSettle();
      expect(find.text('Deniz Yılmaz'), findsNothing);
      expect(
        find.textContaining('Diyetisyen bağlantın henüz yok'),
        findsOneWidget,
      );
      expect(api.searches, 0);
    },
  );
  testWidgets(
    'background hides private sheet snapshot and draft; resume refetches',
    (tester) async {
      await open(tester);
      await tester.enterText(find.byType(TextField), 'Özel taslak');
      await tap(tester, find.byTooltip('Sohbet bilgisini aç'));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text('Deniz ile sohbetin'), findsNothing);
      expect(find.text('Deniz Yılmaz'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(
        find.text('Bilgileri görüntülemek için Sohbet ekranını yeniden aç.'),
        findsOneWidget,
      );
      await tap(tester, find.text('Sohbete dön'));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(api.reads, 2);
    },
  );
  testWidgets(
    'read-only bubble and file layouts fit enlarged text without fabricated persistence',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 700);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          theme: OnboardingTheme.data,
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: SingleChildScrollView(
                child: Column(
                  children: const [
                    ChatBubble(
                      own: false,
                      author: 'Sentetik Uzman',
                      text: 'Örnek konuşma',
                      time: '09:30',
                      attachment: ChatFileCard(
                        name: 'ornek-ŞİÖ-belge.pdf',
                        description: 'Örnek dosya',
                      ),
                    ),
                    ChatBubble(
                      own: true,
                      author: 'Sentetik Danışan',
                      text: 'Türkçe metin: ş ğ ı ö ü ç',
                      time: '09:34',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ChatBubble), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );
}

class _Session extends AuthSession {
  String owner = '77777777-7777-4777-8777-777777777777';
  bool authenticated = true;
  final requests = <String>[];
  @override
  bool get isAuthenticated => authenticated;
  @override
  bool get isBlocking => false;
  @override
  CurrentUserResponse? get user => authenticated
      ? CurrentUserResponse(
          id: owner,
          displayName: 'Mert Ali Şerbet',
          email: 'synthetic-chat@example.test',
          role: 'client',
          isEmailVerified: true,
        )
      : null;
  void changeOwner() {
    owner = '88888888-8888-4888-8888-888888888888';
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
    requests.add('${method ?? 'GET'} $path');
    throw StateError('No transport is permitted in this fixture');
  }
}

class _Api extends DietitianApi {
  _Api(super.session);
  List<RelationshipResponse> rows = [_relationship];
  List<DietitianListItem> experts = [
    const DietitianListItem(_expertId, 'Deniz Yılmaz'),
  ];
  int reads = 0, searches = 0;
  DietitianApiException? failure;
  Completer<DietitianPage<RelationshipResponse>>? pending;
  Completer<DietitianPage<DietitianListItem>>? pendingNames;
  @override
  Future<DietitianPage<RelationshipResponse>> relationships({
    required String status,
    int page = 1,
  }) async {
    reads++;
    if (failure != null) throw failure!;
    return pending?.future ?? (items: rows, totalCount: rows.length);
  }

  @override
  Future<DietitianPage<DietitianListItem>> search({
    required int page,
    String query = '',
  }) async {
    searches++;
    return pendingNames?.future ?? (items: experts, totalCount: experts.length);
  }
}
