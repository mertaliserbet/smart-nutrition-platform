import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/app.dart';
import 'package:smart_nutrition_mobile/core/network/web_config.dart';
import 'package:smart_nutrition_mobile/core/theme/app_theme.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/auth/login_api.dart';
import 'package:smart_nutrition_mobile/features/auth/login_page.dart';
import 'package:smart_nutrition_mobile/features/auth/refresh_token_store.dart';
import 'package:smart_nutrition_mobile/features/profile/dietitian_application_info_page.dart';
import 'package:smart_nutrition_mobile/features/profile/profile_page.dart';

const website = 'https://nutrition.example.test:8443';
const application = '$website/uzman-basvurusu';
const launcher = MethodChannel('plugins.flutter.io/url_launcher');
final openButton = find.widgetWithText(FilledButton, 'Web Sitesine Git');
final copyButton = find.widgetWithText(OutlinedButton, 'Adresi Kopyala');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'website configuration keeps the application path and HTTPS in all modes',
    () {
      expect(
        WebConfig.dietitianApplicationUri(baseUrl: website).toString(),
        application,
      );
      expect(
        WebConfig.dietitianApplicationUri(
          baseUrl: '$website/',
          isDebug: false,
        ).toString(),
        application,
      );
      expect(
        WebConfig.dietitianApplicationUri(
          baseUrl: '',
          isDebug: true,
        ).toString(),
        'https://localhost:5173/uzman-basvurusu',
      );
      expect(
        () => WebConfig.dietitianApplicationUri(baseUrl: '', isDebug: false),
        throwsFormatException,
      );
    },
  );

  for (final invalid in [
    'http://localhost:5173',
    'http://10.0.2.2:5173',
    'http://nutrition.example.test',
    'javascript:alert(1)',
    'file:///private',
    '//nutrition.example.test',
    'https://user:password@nutrition.example.test',
    '$website/other',
    '$website?accessToken=secret',
    '$website#refreshToken=secret',
    '$website?',
    '$website#',
    ' $website',
    'https://localhost:0',
    'https://localhost:65536',
    'https://',
  ]) {
    test('rejects unsafe website configuration: $invalid', () {
      expect(
        () => WebConfig.dietitianApplicationUri(baseUrl: invalid),
        throwsFormatException,
      );
    });
  }

  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(launcher, (call) async {
          calls.add(call);
          return true;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(launcher, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'profile opens information and returns safely in ${brightness.name}',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: brightness == Brightness.light
                ? AppTheme.light
                : AppTheme.dark,
            home: const Scaffold(body: ProfilePage()),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Kişisel alanınız'), findsOneWidget);
        expect(calls, isEmpty);
        final apply = find.widgetWithText(
          FilledButton,
          'Diyetisyen Olarak Başvur',
        );
        await tester.ensureVisible(apply);
        await tester.tap(apply);
        await tester.pumpAndSettle();
        expect(find.byType(DietitianApplicationInfoPage), findsOneWidget);
        expect(find.text('Smart Nutrition Platform'), findsOneWidget);
        expect(find.byType(TextFormField), findsNothing);
        expect(find.textContaining('Admin incelemesi'), findsOneWidget);
        expect(
          Theme.of(
            tester.element(find.byType(DietitianApplicationInfoPage)),
          ).brightness,
          brightness,
        );
        expect(calls, isEmpty);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(DietitianApplicationInfoPage), findsNothing);
        expect(find.text('Kişisel alanınız'), findsOneWidget);
      },
    );

    testWidgets(
      'small screen with large text scrolls to both actions in ${brightness.name}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 480);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: brightness == Brightness.light
                ? AppTheme.light
                : AppTheme.dark,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.8)),
              child: child!,
            ),
            home: const DietitianApplicationInfoPage(webBaseUrl: website),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(copyButton);
        await tester.pumpAndSettle();
        expect(tester.widget<OutlinedButton>(copyButton).onPressed, isNotNull);
        expect(tester.widget<FilledButton>(openButton).onPressed, isNotNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('launches exact URL externally without headers or session data', (
    tester,
  ) async {
    await pumpInfo(tester);
    await tester.ensureVisible(openButton);
    await tester.tap(openButton);
    await tester.pumpAndSettle();
    final call = calls.single;
    expect(call.method, 'launch');
    final args = call.arguments as Map<Object?, Object?>;
    expect(args['url'], application);
    expect(args['useWebView'], false);
    expect(args['useSafariVC'], false);
    expect(args['headers'], isEmpty);
    expect(args['universalLinksOnly'], false);
    final uri = Uri.parse(args['url']! as String);
    expect(uri.hasQuery, isFalse);
    expect(uri.hasFragment, isFalse);
    expect(uri.userInfo, isEmpty);
  });

  testWidgets('copies the same address only after explicit action', (
    tester,
  ) async {
    final platformCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          platformCalls.add(call);
          return null;
        });
    await pumpInfo(tester);
    expect(
      platformCalls.where((call) => call.method == 'Clipboard.setData'),
      isEmpty,
    );
    await tester.ensureVisible(copyButton);
    await tester.tap(copyButton);
    await tester.pumpAndSettle();
    final copy = platformCalls.singleWhere(
      (call) => call.method == 'Clipboard.setData',
    );
    expect(copy.arguments, {'text': application});
    expect(find.text('Adres kopyalandı.'), findsOneWidget);
    expect(calls, isEmpty);
  });

  for (final throwsError in [false, true]) {
    testWidgets(
      'browser failure offers copying without raw platform errors ($throwsError)',
      (tester) async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(launcher, (call) async {
              calls.add(call);
              if (throwsError) {
                throw PlatformException(
                  code: 'synthetic',
                  message: 'private-platform-detail',
                );
              }
              return false;
            });
        await pumpInfo(tester);
        await tester.ensureVisible(openButton);
        await tester.tap(openButton);
        await tester.pumpAndSettle();
        expect(find.textContaining('Tarayıcı açılamadı.'), findsOneWidget);
        expect(find.textContaining('private-platform-detail'), findsNothing);
        expect(tester.widget<OutlinedButton>(copyButton).onPressed, isNotNull);
        expect(calls.length, 1);
      },
    );
  }

  testWidgets('clipboard failure never claims success', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            throw PlatformException(
              code: 'copy',
              message: 'private-platform-detail',
            );
          }
          return null;
        });
    await pumpInfo(tester);
    await tester.ensureVisible(copyButton);
    await tester.tap(copyButton);
    await tester.pumpAndSettle();
    expect(find.textContaining('Adres kopyalanamadı.'), findsOneWidget);
    expect(find.text('Adres kopyalandı.'), findsNothing);
    expect(find.textContaining('private-platform-detail'), findsNothing);
  });

  testWidgets(
    'pending launch blocks duplicates and safely completes after leaving',
    (tester) async {
      final pending = Completer<bool>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(launcher, (call) {
            calls.add(call);
            return pending.future;
          });
      await pumpInfo(tester);
      await tester.ensureVisible(openButton);
      final submit = tester.widget<FilledButton>(openButton).onPressed!;
      submit();
      submit();
      await tester.pump();
      expect(calls.length, 1);
      expect(tester.widget<FilledButton>(openButton).onPressed, isNull);
      expect(tester.widget<OutlinedButton>(copyButton).onPressed, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete(false);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('invalid URL fails closed with actions disabled', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DietitianApplicationInfoPage(
          webBaseUrl: 'https://web.example.test?token=secret',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(openButton).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(copyButton).onPressed, isNull);
    expect(find.textContaining('şu anda kullanılamıyor'), findsOneWidget);
    expect(find.textContaining('token=secret'), findsNothing);
    expect(calls, isEmpty);
  });

  testWidgets(
    'signed-in profile route is discarded on logout while information is open',
    (tester) async {
      final session = AuthSession(api: _LoginApi(), store: _MemoryStore());
      addTearDown(session.dispose);
      await session.initialize();
      expect(
        await session.signIn(
          email: 'synthetic@example.test',
          password: 'Synthetic password',
        ),
        isTrue,
      );
      await tester.pumpWidget(SmartNutritionApp(session: session));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profil'));
      await tester.pumpAndSettle();
      final apply = find.widgetWithText(
        FilledButton,
        'Diyetisyen Olarak Başvur',
      );
      await tester.ensureVisible(apply);
      await tester.tap(apply);
      await tester.pumpAndSettle();
      expect(find.byType(DietitianApplicationInfoPage), findsOneWidget);
      await session.signOut();
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byType(DietitianApplicationInfoPage), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      expect(calls, isEmpty);
    },
  );
}

Future<void> pumpInfo(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: const DietitianApplicationInfoPage(webBaseUrl: website),
    ),
  );
  await tester.pumpAndSettle();
}

class _MemoryStore implements RefreshTokenStore {
  StoredRefreshToken? _value;
  @override
  Future<StoredRefreshToken?> read() async => _value;
  @override
  Future<void> write(StoredRefreshToken token) async {
    _value = token;
  }

  @override
  Future<void> clear() async {
    _value = null;
  }
}

class _LoginApi extends LoginApi {
  @override
  Future<LoginUserResponse> login({
    required String email,
    required String password,
  }) async => LoginUserResponse(
    'synthetic.access.token',
    DateTime.now().add(const Duration(minutes: 15)),
    'synthetic-refresh',
    DateTime.now().add(const Duration(days: 30)),
  );
  @override
  Future<CurrentUserResponse> currentUser(
    String accessToken, {
    void Function()? onUnauthorized,
  }) async => const CurrentUserResponse(
    id: '139fb109-43b8-4b6d-9461-710596ca15ca',
    displayName: 'Synthetic',
    email: 'synthetic@example.test',
    role: 'client',
    isEmailVerified: true,
  );
  @override
  Future<void> logout(String refreshToken) async {}
}
