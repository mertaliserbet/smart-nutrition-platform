import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/core/network/json_api.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/auth/login_api.dart';
import 'package:smart_nutrition_mobile/features/auth/web_panel_link.dart';
import 'package:smart_nutrition_mobile/features/dietitians/dietitian_account_page.dart';
import 'package:smart_nutrition_mobile/features/dietitians/dietitian_api.dart';
import 'package:smart_nutrition_mobile/features/onboarding/onboarding_theme.dart';
import 'package:smart_nutrition_mobile/features/profile/profile_page.dart';
import 'package:smart_nutrition_mobile/features/profile/profile_sharing_sheet.dart';

const _relation = RelationshipResponse(
  id: '11111111-1111-4111-8111-111111111111',
  clientId: '22222222-2222-4222-8222-222222222222',
  dietitianId: '33333333-3333-4333-8333-333333333333',
  status: 'active',
);
DataSharingPermission _permission(
  String category,
  bool value,
) => DataSharingPermission(
  id: '44444444-4444-4444-8444-${(DietitianApi.sharingCategories.indexOf(category) + 1).toString().padLeft(12, '0')}',
  relationshipId: _relation.id,
  isGranted: value,
  category: category,
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
              disableAnimations: true,
              textScaler: TextScaler.linear(scale),
            ),
            child: child!,
          ),
          routes: {
            for (final path in [
              '/personal-nutrition-targets',
              '/client-tasks',
              '/device-health',
              '/dietitians',
              '/client-connections',
              '/forgot-password',
            ])
              path: (_) => Scaffold(appBar: AppBar(title: Text(path))),
          },
          home: Scaffold(
            body: ProfilePage(
              active: active,
              refreshRevision: revision,
              api: api,
            ),
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

  Future<void> tap(
    WidgetTester tester,
    Finder finder, {
    bool settle = true,
  }) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Finder toggle(String key) => find.byKey(ValueKey('sharing-$key'));
  Future<void> share(WidgetTester tester, {bool settle = true}) async {
    await tap(tester, find.text('Veri paylaşımım'), settle: settle);
  }

  bool value(WidgetTester tester, String key) =>
      tester.widget<Switch>(toggle(key)).value;

  testWidgets(
    'identity uses session, details are readonly and unrelated names are never substituted',
    (tester) async {
      await open(tester);
      expect(find.text('Şule İpek Çetin'), findsOneWidget);
      expect(find.text('Şule İpek, yolculuğun burada.'), findsOneWidget);
      expect(find.text('Deniz Yılmaz'), findsOneWidget);
      expect(find.text('Mert Ali Şerbet'), findsNothing);
      expect(find.text('Uğur Çetin'), findsNothing);
      await tap(tester, find.text('Bilgilerimi gör'));
      expect(find.text('synthetic-profile@example.test'), findsWidgets);
      expect(find.text('Doğrulandı'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await tap(tester, find.text('Hesabıma dön'));
      api.experts = [const DietitianListItem('other-id', 'Yanlış Uzman')];
      await open(tester, revision: 1);
      expect(find.text('Yanlış Uzman'), findsNothing);
      expect(find.text('Diyetisyenin'), findsOneWidget);
    },
  );
  for (final (size, scale) in [
    (const Size(320, 480), 2.0),
    (const Size(568, 320), 2.0),
    (const Size(430, 900), 1.3),
  ]) {
    testWidgets('profile and private sheets fit $size at scale $scale', (
      tester,
    ) async {
      await open(tester, size: size, scale: scale);
      for (final label in [
        'Bilgilerimi gör',
        'Hesap güvenliği',
        'Limely hakkında',
      ]) {
        await tap(tester, find.text(label));
        await tap(tester, find.text('Hesabıma dön'));
      }
      await share(tester);
      expect(find.byType(Switch), findsNWidgets(5));
      await tap(tester, find.byTooltip('Paylaşım tercihlerini kapat'));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('existing menu and password-reset routes are preserved', (
    tester,
  ) async {
    await open(tester);
    for (final (label, path) in [
      ('Günlük hedeflerim', '/personal-nutrition-targets'),
      ('Görevlerim', '/client-tasks'),
      ('Cihaz sağlık verileri', '/device-health'),
    ]) {
      await tap(tester, find.text(label));
      expect(find.text(path), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
    await tap(tester, find.text('Hesap güvenliği'));
    await tap(tester, find.text('Şifremi yenile'));
    expect(find.text('/forgot-password'), findsOneWidget);
  });
  testWidgets(
    'connection errors and no active expert never hide personal navigation',
    (tester) async {
      api.connectionFailure = const DietitianApiException(
        'Sentetik bağlantı hatası',
      );
      await open(tester);
      expect(find.text('Şule İpek Çetin'), findsOneWidget);
      expect(find.text('Günlük hedeflerim'), findsOneWidget);
      expect(find.text('Sentetik bağlantı hatası'), findsOneWidget);
      api.connectionFailure = null;
      api.relations = [];
      await tap(tester, find.text('Bağlantıyı yeniden yükle'));
      expect(find.text('Diyetisyeninle bağlantı kur'), findsOneWidget);
      await tap(tester, find.text('Diyetisyen Bul'));
      expect(find.text('/dietitians'), findsOneWidget);
    },
  );
  testWidgets(
    'expert entry follows actual pending and verified states, without changing client role',
    (tester) async {
      api.professional = (
        id: _relation.dietitianId,
        displayName: 'Sentetik Uzman',
        isVerified: false,
      );
      await open(tester);
      expect(find.text('Başvurun değerlendirmede'), findsOneWidget);
      await tap(tester, find.text('Başvuru durumunu gör'));
      expect(find.textContaining('yönetici onayı bekliyor'), findsOneWidget);
      await tap(tester, find.text('Hesabıma dön'));
      api.professional = (
        id: _relation.dietitianId,
        displayName: 'Sentetik Uzman',
        isVerified: true,
      );
      await open(tester, revision: 1);
      await tap(tester, find.text('Diyetisyen Paneline Git'));
      await tap(
        tester,
        find.widgetWithText(FilledButton, 'Diyetisyen Paneline Git'),
      );
      expect(find.byType(WebPanelPage), findsOneWidget);
      expect(session.user!.role, 'client');
      expect(api.writes, isEmpty);
    },
  );
  testWidgets(
    'unknown professional status cannot pretend that an application is eligible',
    (tester) async {
      api.professionalFailure = const DietitianApiException(
        'Başvuru bilgisi okunamadı',
      );
      await open(tester);
      expect(find.text('Başvuru bilgisi okunamadı'), findsOneWidget);
      expect(find.text('Diyetisyen başvurusu hakkında'), findsNothing);
      expect(find.text('Deniz Yılmaz'), findsOneWidget);
    },
  );
  testWidgets(
    'same-account application reuses existing form and cannot survive background',
    (tester) async {
      await open(tester);
      await tap(tester, find.text('Diyetisyen başvurusu hakkında'));
      await tap(tester, find.text('Başvuruya geç'));
      expect(find.byType(DietitianAccountPage), findsOneWidget);
      expect(find.text('Mesleki kayıt açıklaması'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.byType(DietitianAccountPage), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(
        find.text('Bilgileri görüntülemek için Hesabım ekranını yeniden aç.'),
        findsOneWidget,
      );
      expect(session.user!.role, 'client');
    },
  );
  testWidgets('logout needs explicit confirmation and is invoked once', (
    tester,
  ) async {
    await open(tester);
    await tap(tester, find.text('Çıkış yap'));
    await tap(tester, find.text('Vazgeç'));
    expect(session.signOuts, 0);
    await tap(tester, find.text('Çıkış yap'));
    await tap(tester, find.widgetWithText(FilledButton, 'Çıkış yap'));
    expect(session.signOuts, 1);
    expect(session.isAuthenticated, isFalse);
    expect(find.text('Şule İpek Çetin'), findsNothing);
  });
  testWidgets(
    'hidden profile makes no calls and stale owner responses never surface',
    (tester) async {
      await open(tester, active: false);
      expect(api.relationshipReads, 0);
      expect(api.profileReads, 0);
      api.pendingRelationship =
          Completer<DietitianPage<RelationshipResponse>>();
      final pending = api.pendingRelationship!;
      await open(tester, settle: false);
      api.pendingRelationship = null;
      api.relations = [];
      session.changeOwner();
      await tester.pumpAndSettle();
      pending.complete((items: [_relation], totalCount: 1));
      await tester.pumpAndSettle();
      expect(find.text('Deniz Yılmaz'), findsNothing);
      expect(find.text('Şule İpek Çetin'), findsNothing);
      expect(find.text('Yeni Kullanıcı'), findsOneWidget);
    },
  );
  testWidgets(
    'private details expire on owner switch and cannot restore old personal data',
    (tester) async {
      await open(tester);
      await tap(tester, find.text('Bilgilerimi gör'));
      api.relations = [];
      session.changeOwner();
      await tester.pumpAndSettle();
      expect(find.text('Şule İpek Çetin'), findsNothing);
      expect(
        find.text('Bilgileri görüntülemek için Hesabım ekranını yeniden aç.'),
        findsOneWidget,
      );
      await tap(tester, find.text('Hesabıma dön'));
      expect(find.text('Yeni Kullanıcı'), findsOneWidget);
    },
  );
  testWidgets('permission read failure has unknown values and writes nothing', (
    tester,
  ) async {
    api.permissionFailure = const DietitianApiException('İzinler okunamadı');
    await open(tester);
    await share(tester);
    expect(find.byType(Switch), findsNothing);
    expect(find.text('İzinler okunamadı'), findsOneWidget);
    expect(api.writes, isEmpty);
    api.permissionFailure = null;
    await tap(tester, find.text('İzinleri yeniden yükle'));
    expect(value(tester, 'meal_logs'), isTrue);
  });
  testWidgets(
    'permission switches start from API data; closing discards draft',
    (tester) async {
      await open(tester);
      await share(tester);
      expect(value(tester, 'nutrition_plans'), isTrue);
      expect(value(tester, 'body_measurements'), isFalse);
      expect(tester.widget<Switch>(toggle('water_logs')).onChanged, isNull);
      await tap(tester, toggle('meal_logs'));
      expect(value(tester, 'meal_logs'), isFalse);
      expect(api.writes, isEmpty);
      await tap(tester, find.byTooltip('Paylaşım tercihlerini kapat'));
      await share(tester);
      expect(value(tester, 'meal_logs'), isTrue);
      expect(api.writes, isEmpty);
    },
  );
  testWidgets(
    'save writes only changed categories and verifies the server state',
    (tester) async {
      await open(tester);
      await share(tester);
      await tap(tester, toggle('meal_logs'));
      await tap(tester, find.text('Tercihlerimi kaydet'));
      expect(find.byType(ProfileSharingSheet), findsNothing);
      expect(api.writes, [(category: 'meal_logs', granted: false)]);
      expect(api.permissionReads, 3);
      expect(find.text('Paylaşım tercihlerin kaydedildi.'), findsOneWidget);
      expect(
        api.permissionsRows
            .firstWhere((p) => p.category == 'nutrition_plans')
            .isGranted,
        isTrue,
      );
    },
  );
  testWidgets(
    'concurrent permission change is reviewed without overwriting it',
    (tester) async {
      await open(tester);
      await share(tester);
      await tap(tester, toggle('nutrition_plans'));
      api.permissionsRows = [
        _permission('nutrition_plans', true),
        _permission('meal_logs', false),
        _permission('client_tasks', true),
      ];
      await tap(tester, find.text('Tercihlerimi kaydet'));
      expect(api.writes, isEmpty);
      expect(value(tester, 'nutrition_plans'), isTrue);
      expect(value(tester, 'meal_logs'), isFalse);
      expect(find.textContaining('başka bir işlemde değişti'), findsOneWidget);
    },
  );
  testWidgets(
    'partial failure clears uncertain values and requires reconciliation before retry',
    (tester) async {
      await open(tester);
      await share(tester);
      await tap(tester, toggle('nutrition_plans'));
      await tap(tester, toggle('body_measurements'));
      api.failCategory = 'body_measurements';
      await tap(tester, find.text('Tercihlerimi kaydet'));
      expect(api.writes, [
        (category: 'nutrition_plans', granted: false),
        (category: 'body_measurements', granted: true),
      ]);
      expect(find.byType(Switch), findsNothing);
      expect(find.textContaining('Tekrar işlem yapmadan'), findsOneWidget);
      api.failCategory = null;
      await tap(tester, find.text('İzinleri yeniden yükle'));
      expect(value(tester, 'nutrition_plans'), isFalse);
      expect(value(tester, 'body_measurements'), isFalse);
      expect(api.writes, hasLength(2));
    },
  );
  testWidgets('ended relationship is rejected before any write', (
    tester,
  ) async {
    await open(tester);
    await share(tester);
    await tap(tester, toggle('meal_logs'));
    api.relations = [];
    await tap(tester, find.text('Tercihlerimi kaydet'));
    expect(api.writes, isEmpty);
    expect(find.byType(Switch), findsNothing);
    expect(find.textContaining('bağlantın değişti'), findsOneWidget);
  });
  testWidgets('existing water grant can only be revoked; it is never enabled', (
    tester,
  ) async {
    api.permissionsRows.add(_permission('water_logs', true));
    await open(tester);
    await share(tester);
    expect(find.text('Paylaşım açık'), findsOneWidget);
    await tap(tester, toggle('water_logs'));
    await tap(tester, find.text('Tercihlerimi kaydet'));
    expect(api.writes, [(category: 'water_logs', granted: false)]);
    await share(tester);
    expect(tester.widget<Switch>(toggle('water_logs')).onChanged, isNull);
    expect(value(tester, 'water_logs'), isFalse);
  });
  testWidgets('in-flight save blocks duplicate submission and dismissal', (
    tester,
  ) async {
    await open(tester);
    await share(tester);
    await tap(tester, toggle('meal_logs'));
    api.pendingWrite = Completer<DataSharingPermission>();
    await tap(tester, find.text('Tercihlerimi kaydet'), settle: false);
    expect(api.writes, hasLength(1));
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(ProfileSharingSheet), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (w) =>
                  w is IconButton && w.tooltip == 'Paylaşım tercihlerini kapat',
            ),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Kaydediliyor…'),
          )
          .onPressed,
      isNull,
    );
    api.pendingWrite!.complete(_permission('meal_logs', false));
    await tester.pumpAndSettle();
    expect(api.writes, hasLength(1));
    expect(find.byType(ProfileSharingSheet), findsNothing);
  });
  testWidgets(
    'account change while saving prevents subsequent category writes',
    (tester) async {
      await open(tester);
      await share(tester);
      await tap(tester, toggle('meal_logs'));
      await tap(tester, toggle('body_measurements'));
      api.pendingWrite = Completer<DataSharingPermission>();
      await tap(tester, find.text('Tercihlerimi kaydet'), settle: false);
      api.relations = [];
      session.changeOwner();
      await tester.pump();
      expect(find.text('Deniz Yılmaz'), findsNothing);
      expect(find.byType(Switch), findsNothing);
      api.pendingWrite!.complete(_permission('meal_logs', false));
      await tester.pumpAndSettle();
      expect(api.writes, hasLength(1));
      expect(
        find.text('Bilgileri görüntülemek için Hesabım ekranını yeniden aç.'),
        findsOneWidget,
      );
    },
  );
}

class _Session extends AuthSession {
  String owner = '77777777-7777-4777-8777-777777777777',
      name = 'Şule İpek Çetin';
  bool authenticated = true;
  int signOuts = 0;
  @override
  bool get isAuthenticated => authenticated;
  @override
  bool get isBlocking => false;
  @override
  CurrentUserResponse? get user => authenticated
      ? CurrentUserResponse(
          id: owner,
          displayName: name,
          email: 'synthetic-profile@example.test',
          role: 'client',
          isEmailVerified: true,
        )
      : null;
  void changeOwner() {
    owner = '88888888-8888-4888-8888-888888888888';
    name = 'Yeni Kullanıcı';
    notifyListeners();
  }

  @override
  Future<void> signOut({String? message}) async {
    signOuts++;
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
  }) async =>
      const (statusCode: 404, body: null, hasBody: false, retryAfter: null);
}

class _Api extends DietitianApi {
  _Api(super.session);
  List<RelationshipResponse> relations = [_relation];
  List<DietitianListItem> experts = [
    const DietitianListItem(
      '33333333-3333-4333-8333-333333333333',
      'Deniz Yılmaz',
    ),
  ];
  List<DataSharingPermission> permissionsRows = [
    _permission('nutrition_plans', true),
    _permission('meal_logs', true),
    _permission('client_tasks', true),
  ];
  DietitianStatusResponse? professional;
  DietitianApiException? connectionFailure,
      professionalFailure,
      permissionFailure;
  String? failCategory;
  int relationshipReads = 0, profileReads = 0, permissionReads = 0;
  Completer<DietitianPage<RelationshipResponse>>? pendingRelationship;
  Completer<DataSharingPermission>? pendingWrite;
  final writes = <({String category, bool granted})>[];
  @override
  Future<DietitianPage<RelationshipResponse>> relationships({
    required String status,
    int page = 1,
  }) async {
    relationshipReads++;
    if (connectionFailure != null) throw connectionFailure!;
    return pendingRelationship?.future ??
        (items: relations, totalCount: relations.length);
  }

  @override
  Future<DietitianStatusResponse?> profile() async {
    profileReads++;
    if (professionalFailure != null) throw professionalFailure!;
    return professional;
  }

  @override
  Future<DietitianPage<DietitianListItem>> search({
    required int page,
    String query = '',
  }) async => (items: experts, totalCount: experts.length);
  @override
  Future<List<DataSharingPermission>> permissions(String relationshipId) async {
    permissionReads++;
    if (permissionFailure != null) throw permissionFailure!;
    return List.of(permissionsRows);
  }

  @override
  Future<DataSharingPermission> setPermission({
    required String relationshipId,
    required bool isGranted,
    DataSharingPermission? current,
    String category = 'nutrition_plans',
  }) async {
    writes.add((category: category, granted: isGranted));
    if (category == failCategory) {
      throw const DietitianApiException('Sentetik yazma hatası');
    }
    final result = pendingWrite == null
        ? _permission(category, isGranted)
        : await pendingWrite!.future;
    permissionsRows = [
      ...permissionsRows.where((p) => p.category != category),
      result,
    ];
    return result;
  }
}
