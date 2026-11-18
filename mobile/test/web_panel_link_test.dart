import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/core/network/web_config.dart';
import 'package:smart_nutrition_mobile/features/auth/web_panel_link.dart';

const _launcher = MethodChannel('plugins.flutter.io/url_launcher');
const _origin = 'https://nutrition.example.test:8443';
final _open = find.textContaining('Diyetisyen misiniz? Web paneline gidin');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_launcher, (call) async {
          calls.add(call);
          return true;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_launcher, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });
  Future<void> pump(
    WidgetTester tester, {
    bool enabled = true,
    String base = _origin,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WebPanelLink(enabled: enabled, webBaseUrl: base),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test(
    'web login uses configured origin with no mobile credentials or fallback in release',
    () {
      expect(
        WebConfig.loginUri(baseUrl: '$_origin/', isDebug: false).toString(),
        '$_origin/giris',
      );
      expect(
        () => WebConfig.loginUri(baseUrl: '', isDebug: false),
        throwsFormatException,
      );
    },
  );
  testWidgets(
    'visible web address opens exact login in external browser with no headers',
    (tester) async {
      await pump(tester);
      expect(find.textContaining('$_origin/giris'), findsOneWidget);
      await tester.tap(_open);
      await tester.pumpAndSettle();
      expect(calls.single.method, 'launch');
      final args = calls.single.arguments as Map;
      expect(args['url'], '$_origin/giris');
      expect(args['headers'], isEmpty);
      expect(args['useWebView'], false);
      expect(args['useSafariVC'], false);
    },
  );
  testWidgets(
    'disabled login state and unsafe configuration cannot open the browser',
    (tester) async {
      await pump(tester, enabled: false);
      expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed,
        isNull,
      );
      await pump(tester, base: 'https://nutrition.example.test?token=secret');
      expect(
        find.text('Diyetisyen web adresi şu anda kullanılamıyor.'),
        findsOneWidget,
      );
      expect(find.byType(TextButton), findsNothing);
      expect(calls, isEmpty);
    },
  );
  testWidgets(
    'browser failure offers copy and explicit retry without automatic reopening',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_launcher, (call) async {
            calls.add(call);
            return false;
          });
      String? clipboard;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              clipboard = (call.arguments as Map)['text'] as String;
            }
            return null;
          });
      await pump(tester);
      await tester.tap(_open);
      await tester.pumpAndSettle();
      expect(find.textContaining('Tarayıcı açılamadı.'), findsOneWidget);
      await tester.tap(find.text('Web adresini kopyala'));
      await tester.pumpAndSettle();
      expect(clipboard, '$_origin/giris');
      expect(calls, hasLength(1));
      await tester.tap(_open);
      await tester.pumpAndSettle();
      expect(calls, hasLength(2));
    },
  );
  testWidgets(
    'pending opening blocks duplicate taps and safely completes after leaving',
    (tester) async {
      final response = Completer<bool>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_launcher, (call) {
            calls.add(call);
            return response.future;
          });
      await pump(tester);
      await tester.tap(_open);
      await tester.pump();
      expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed,
        isNull,
      );
      expect(calls, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      response.complete(false);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
