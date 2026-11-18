// Opt-in local HTTPS probe. No stored credentials or TLS bypass.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:smart_nutrition_mobile/features/body_measurements/measurement_chart.dart';
import 'package:smart_nutrition_mobile/features/progress/progress_page.dart';
import 'package:smart_nutrition_mobile/core/network/json_api.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/auth/login_api.dart';
import 'package:smart_nutrition_mobile/features/auth/refresh_token_store.dart';
import 'package:smart_nutrition_mobile/features/body_measurements/body_measurement_api.dart';

void main() {
  testWidgets(
    'real HTTPS: body record/chart/update/delete',
    (tester) async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final origin = Uri.parse('https://localhost:7099');
        final email =
            'synthetic-body-live-${DateTime.now().microsecondsSinceEpoch}@example.test';
        final password = base64UrlEncode(
          List.generate(32, (_) => Random.secure().nextInt(256)),
        );
        final result = <String, Object?>{
          'email': email,
          'messageIds': <String>[],
        };
        final resultFile = File(Platform.environment['SNP_BODY_RESULT']!);
        final mail = HttpClient();
        late AuthSession session;
        Future<void> saveResult() =>
            resultFile.writeAsString(jsonEncode(result));
        Future<Map<String, dynamic>> mailbox(String path) async {
          final response = await (await mail.getUrl(
            Uri.parse('http://127.0.0.1:8025$path'),
          )).close();
          expect(response.statusCode, 200);
          return jsonDecode(await utf8.decoder.bind(response).join())
              as Map<String, dynamic>;
        }

        try {
          await tester.runAsync(() async {
            session = AuthSession(
              api: LoginApi(baseUri: origin),
              store: _Store(),
            );
            final registered = await requestJson(
              method: 'POST',
              path: '/api/v1/auth/register',
              baseUri: origin,
              payload: {
                'email': email,
                'password': password,
                'displayName': 'Sentetik ölçüm HTTPS testi',
              },
              timeout: const Duration(seconds: 20),
            );
            expect(registered.statusCode, 201);
            result['userId'] = (registered.body as Map)['id'];
            await saveResult();
            String? token;
            for (var attempt = 0; attempt < 100 && token == null; attempt++) {
              final found = await mailbox(
                '/api/v1/search?query=${Uri.encodeQueryComponent('to:$email')}',
              );
              for (final message in found['messages'] as List) {
                final id = (message as Map)['ID'] as String;
                final detail = await mailbox(
                  '/api/v1/message/${Uri.encodeComponent(id)}',
                );
                final candidates = (detail['Text'] as String)
                    .split('\n')
                    .map((s) => s.trim())
                    .where((s) => RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(s));
                if (candidates.isNotEmpty) {
                  token = candidates.single;
                  (result['messageIds'] as List<String>).add(id);
                  break;
                }
              }
              if (token == null) {
                await Future<void>.delayed(const Duration(milliseconds: 100));
              }
            }
            await saveResult();
            expect(
              token != null,
              isTrue,
              reason: 'Synthetic verification mail not received.',
            );
            final verified = await requestJson(
              method: 'POST',
              path: '/api/v1/auth/verify-email',
              baseUri: origin,
              payload: {'token': token!},
              timeout: const Duration(seconds: 20),
            );
            expect(verified.statusCode, 204);
            await session.initialize();
            expect(
              await session.signIn(email: email, password: password),
              isTrue,
            );
          });
          final api = BodyMeasurementApi(session);
          final ids = <String>[];
          await tester.runAsync(() async {
            expect(await api.history(), isEmpty);
            final at = DateTime.now().subtract(const Duration(days: 3));
            for (final input in [
              ({'weightKg': 73.5, 'waistCm': 84}, at),
              ({'waistCm': 85}, at.add(const Duration(days: 1))),
              ({'weightKg': 72.25}, at.add(const Duration(days: 2))),
            ]) {
              final row = await api.create(
                values: input.$1,
                measuredAt: input.$2,
                note: 'Synthetic HTTPS measurement',
              );
              ids.add(row.id);
            }
            result['measurementIds'] = ids;
            await saveResult();
            final rows = await api.history();
            expect(measurementPoints(rows, 'weightKg').map((p) => p.value), [
              73.5,
              72.25,
            ]);
            expect(measurementPoints(rows, 'waistCm').map((p) => p.value), [
              84,
              85,
            ]);
            expect(measurementPoints(rows, 'chestCm'), isEmpty);
          });
          await tester.runAsync(() async {
            await tester.pumpWidget(
              AuthSessionScope(
                session: session,
                child: MaterialApp(
                  home: Scaffold(body: ProgressPage(api: api)),
                ),
              ),
            );
            await api.history();
          });
          Future<void> waitFor(Finder finder) async {
            for (
              var attempt = 0;
              attempt < 50 && finder.evaluate().isEmpty;
              attempt++
            ) {
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 100)),
              );
              await tester.pump();
            }
            expect(
              finder,
              findsOneWidget,
              reason: tester
                  .widgetList<Text>(find.byType(Text))
                  .map((text) => text.data)
                  .join(' | '),
            );
          }

          Future<void> refresh() async {
            final target = find.text('Ölçümleri yenile');
            await tester.scrollUntilVisible(
              target,
              200,
              scrollable: find.byType(Scrollable).last,
            );
            await tester.ensureVisible(target);
            await tester.pump();
            await tester.runAsync(() async {
              await tester.tap(target);
              await api.history();
            });
            await tester.pump();
            tester
                .state<ScrollableState>(find.byType(Scrollable).last)
                .position
                .jumpTo(0);
            await tester.pump();
          }

          await waitFor(
            find.byKey(const ValueKey('measurement-chart-weightKg')),
          );
          final chart = tester.widget<MeasurementChart>(
            find.byWidgetPredicate(
              (w) => w is MeasurementChart && w.field == 'weightKg',
            ),
          );
          expect(
            measurementPoints(chart.rows, 'weightKg').map((p) => p.value),
            [73.5, 72.25],
          );
          await tester.runAsync(() async {
            await api.update(ids.first, {'weightKg': 74.25, 'note': null});
            expect((await api.get(ids.first)).note, isNull);
          });
          await refresh();
          await waitFor(
            find.byKey(const ValueKey('measurement-chart-weightKg')),
          );
          final updated = tester.widget<MeasurementChart>(
            find.byWidgetPredicate(
              (w) => w is MeasurementChart && w.field == 'weightKg',
            ),
          );
          expect(
            measurementPoints(updated.rows, 'weightKg').first.value,
            74.25,
          );
          await tester.runAsync(() async {
            for (final id in ids) {
              await api.delete(id);
            }
            expect(await api.history(), isEmpty);
          });
          await refresh();
          await waitFor(
            find.text('Henüz ölçüm yok. İlk ölçümünüzü ekleyebilirsiniz.'),
          );
          expect(
            find.byKey(const ValueKey('measurement-chart-weightKg')),
            findsNothing,
          );
          result['passed'] = true;
        } finally {
          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(() async {
            if (session.isAuthenticated) await session.signOut();
            await saveResult();
          });
          session.dispose();
          mail.close(force: true);
        }
      }, _RealHttp());
    },
    skip: Platform.environment['SNP_BODY_PROBE'] != '1',
  );
}

class _RealHttp extends HttpOverrides {}

class _Store implements RefreshTokenStore {
  StoredRefreshToken? value;
  @override
  Future<StoredRefreshToken?> read() async => value;
  @override
  Future<void> write(StoredRefreshToken value) async {
    this.value = value;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}
