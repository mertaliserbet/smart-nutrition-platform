// Opt-in local HTTPS integration check; all accounts and records are synthetic.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/core/network/json_api.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/auth/login_api.dart';
import 'package:smart_nutrition_mobile/features/auth/refresh_token_store.dart';
import 'package:smart_nutrition_mobile/features/home/dashboard_data.dart';
import 'package:smart_nutrition_mobile/features/home/dashboard_live_cards.dart';
import 'package:smart_nutrition_mobile/features/nutrition/meal_log_api.dart';
import 'package:smart_nutrition_mobile/features/nutrition/nutrition_plan_api.dart';
import 'package:smart_nutrition_mobile/features/personal_nutrition_targets/personal_nutrition_target_api.dart';
import 'package:smart_nutrition_mobile/features/personal_nutrition_targets/target_progress.dart';
import 'package:smart_nutrition_mobile/features/water/water_log_api.dart';

class _RealHttp extends HttpOverrides {}

class _Store implements RefreshTokenStore {
  StoredRefreshToken? value;
  @override
  Future<StoredRefreshToken?> read() async => value;
  @override
  Future<void> write(StoredRefreshToken token) async {
    value = token;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

void main() {
  testWidgets(
    'real HTTPS: target creation, partial update, clearing and Dashboard progress',
    (tester) async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final origin = Uri.parse('https://localhost:7099');
        final email =
            'synthetic-targets-live-${DateTime.now().microsecondsSinceEpoch}@example.test';
        final password = base64UrlEncode(
          List.generate(32, (_) => Random.secure().nextInt(256)),
        );
        final file = File(Platform.environment['SNP_TARGETS_RESULT']!);
        final result = <String, Object?>{
          'email': email,
          'messageIds': <String>[],
        };
        late AuthSession session;
        final mail = HttpClient();
        Future<void> save() => file.writeAsString(jsonEncode(result));
        Future<Map<String, dynamic>> mailbox(String path) async {
          final request = await mail.getUrl(
            Uri.parse('http://127.0.0.1:8025$path'),
          );
          final response = await request.close();
          expect(response.statusCode, 200);
          return jsonDecode(await utf8.decoder.bind(response).join())
              as Map<String, dynamic>;
        }

        late PersonalNutritionTargetResponse personal;
        NutritionPlanResponse? plan;
        late DashboardMeals meals;
        num water = 0;
        late PersonalNutritionTargetApi targetApi;
        Future<void> read() async {
          personal = await targetApi.get();
          plan = await NutritionPlanApi(session).active();
          final day = WaterDayRange.forDate(DateTime.now());
          meals = DashboardMeals(
            await MealLogApi(session).forRange(from: day.from, to: day.to),
          );
          water = await WaterLogApi(session).dailyTotal(day);
        }

        Future<void> render() async {
          final targets = AsyncSnapshot.withData(
            ConnectionState.done,
            personal,
          );
          final program = AsyncSnapshot<NutritionPlanResponse?>.withData(
            ConnectionState.done,
            plan,
          );
          final consumed = AsyncSnapshot.withData(ConnectionState.done, meals);
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: Column(
                    children: [
                      DashboardLiveCards.energy(
                        tester.element(find.byType(MaterialApp)),
                        consumed,
                        program,
                        () {},
                        targets,
                        () {},
                        () {},
                      ),
                      DashboardLiveCards.macros(consumed, targets),
                      NutritionTargetProgress(
                        target: EffectiveNutritionTarget.resolve(
                          'dailyWaterTargetMl',
                          targets,
                          plan: program,
                        ),
                        unit: 'mL',
                        consumed: water,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        try {
          await tester.runAsync(() async {
            session = AuthSession(
              api: LoginApi(baseUri: origin),
              store: _Store(),
            );
            targetApi = PersonalNutritionTargetApi(session);
            await save();
            final registered = await requestJson(
              method: 'POST',
              path: '/api/v1/auth/register',
              baseUri: origin,
              payload: {
                'email': email,
                'password': password,
                'displayName': 'Synthetic targets probe',
                'role': 'client',
              },
              timeout: const Duration(seconds: 20),
            );
            expect(registered.statusCode, 201);
            result['userId'] = (registered.body as Map)['id'];
            await save();
            String? token;
            for (var attempt = 0; attempt < 100 && token == null; attempt++) {
              final messages = await mailbox(
                '/api/v1/search?query=${Uri.encodeQueryComponent('to:$email')}',
              );
              for (final message in messages['messages'] as List) {
                final id = (message as Map)['ID'] as String;
                final detail = await mailbox(
                  '/api/v1/message/${Uri.encodeComponent(id)}',
                );
                final tokens = (detail['Text'] as String)
                    .split('\n')
                    .map((x) => x.trim())
                    .where((x) => RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(x));
                if (tokens.isNotEmpty) {
                  token = tokens.single;
                  (result['messageIds'] as List<String>).add(id);
                  break;
                }
              }
              if (token == null) {
                await Future<void>.delayed(const Duration(milliseconds: 100));
              }
            }
            await save();
            expect(token, isNotNull);
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
            expect((await targetApi.get()).values.values, everyElement(isNull));
            await targetApi.patch({
              'dailyCaloriesTargetKcal': 1800,
              'dailyProteinTargetGrams': 90,
              'dailyCarbsTargetGrams': 225,
              'dailyFatTargetGrams': 60,
              'dailyWaterTargetMl': 1800,
            });
            await targetApi.patch({
              'dailyCaloriesTargetKcal': 2000,
              'dailyProteinTargetGrams': 100,
              'dailyWaterTargetMl': 2000,
            });
            expect((await targetApi.get()).dailyCarbsTargetGrams, 225);
            final consumedAt = DateTime.now();
            final meal = await MealLogApi(session).create({
              'mealType': 'lunch',
              'consumedAt': consumedAt.toUtc().toIso8601String(),
              'source': 'manual',
              'items': [
                {
                  'displayName': 'Synthetic dashboard item',
                  'isEstimated': false,
                  'caloriesKcal': 500,
                  'proteinGrams': 25,
                  'carbsGrams': 56.25,
                  'fatGrams': 15,
                },
              ],
            });
            result['clientId'] = meal.clientId;
            result['mealId'] = meal.id;
            await save();
            final row = await WaterLogApi(
              session,
            ).create(amountMl: 500, consumedAt: consumedAt);
            result['waterId'] = row.id;
            await save();
            await read();
          });
          // A first empty widget provides a BuildContext for the pure Dashboard cards.
          await tester.pumpWidget(const MaterialApp(home: SizedBox()));
          await render();
          final bars = tester.widgetList<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          );
          expect(bars, hasLength(5));
          for (final bar in bars) {
            expect(bar.value, closeTo(.25, .0001));
          }
          expect(find.text('500 / 2000 kcal · %25'), findsOneWidget);
          expect(find.text('500 / 2000 mL · %25'), findsOneWidget);
          await tester.runAsync(() async {
            await targetApi.patch({'dailyProteinTargetGrams': null});
            expect((await targetApi.get()).dailyCaloriesTargetKcal, 2000);
            await targetApi.patch({
              'dailyCaloriesTargetKcal': null,
              'dailyCarbsTargetGrams': null,
              'dailyFatTargetGrams': null,
              'dailyWaterTargetMl': null,
            });
            await read();
            expect(personal.values.values, everyElement(isNull));
          });
          await render();
          expect(find.byType(LinearProgressIndicator), findsNothing);
          expect(find.text('500 kcal'), findsOneWidget);
          expect(find.text('Henüz hedef belirlenmedi'), findsWidgets);
          result['passed'] = true;
          result['dashboardProgress'] = '25% then no target after clearing';
          await tester.runAsync(save);
        } finally {
          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(() async {
            if (session.isAuthenticated) await session.signOut();
            session.dispose();
            mail.close(force: true);
            await save();
          });
        }
      }, _RealHttp());
    },
    skip: Platform.environment['SNP_TARGETS_PROBE'] != '1',
  );
}
