import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/auth/login_api.dart';
import 'package:smart_nutrition_mobile/features/water/water_log_api.dart';
import 'water_test_support.dart';

void main() {
  late HttpServer server;
  late AuthSession session;
  late WaterLogApi api;
  late Future<void> Function(HttpRequest) resource;
  var renewals = 0;
  setUp(() async {
    renewals = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    resource = (r) => reply(r, 200, waterJson());
    final expiry = DateTime.now().toUtc().add(const Duration(days: 30));
    Map<String, Object?> pair(int revision) => {
      'accessToken': 'synthetic.water$revision.signature',
      'tokenType': 'Bearer',
      'expiresAt': DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 15))
          .toIso8601String(),
      'refreshToken': (revision == 0 ? 'A' : 'B') * 43,
      'refreshTokenExpiresAt': expiry.toIso8601String(),
    };
    server.listen((r) async {
      switch (r.uri.path) {
        case '/api/v1/auth/login':
          await r.drain<void>();
          await reply(r, 200, pair(0));
        case '/api/v1/auth/me':
          await reply(r, 200, {
            'id': '44444444-4444-4444-8444-444444444444',
            'displayName': 'Sentetik',
            'email': 'synthetic@example.test',
            'role': 'client',
            'isEmailVerified': true,
          });
        case '/api/v1/auth/refresh':
          renewals++;
          await r.drain<void>();
          await reply(r, 200, pair(1));
        default:
          await resource(r);
      }
    });
    session = AuthSession(
      api: LoginApi(baseUri: Uri.parse('http://127.0.0.1:${server.port}')),
      store: WaterMemoryStore(),
    );
    await session.initialize();
    expect(
      await session.signIn(
        email: 'synthetic@example.test',
        password: 'Synthetic password',
      ),
      isTrue,
    );
    api = WaterLogApi(session);
  });
  tearDown(() async {
    session.dispose();
    await server.close(force: true);
  });
  test(
    'day query has explicit offsets and next calendar midnight, preserving 23/25 hours',
    () async {
      for (final spring in [true, false]) {
        final date = spring ? DateTime(2026, 3, 8) : DateTime(2026, 11, 1);
        final calls = <int>[];
        final day = WaterDayRange.forDate(
          date,
          localDate: (year, month, number) {
            calls.add(number);
            final offset = spring
                ? (number == 8 ? -5 : -4)
                : (number == 1 ? -4 : -5);
            return _OffsetDate(
              DateTime.utc(year, month, number),
              Duration(hours: offset),
            );
          },
        );
        expect(calls, spring ? [8, 9] : [1, 2]);
        expect(
          day.to.toUtc().difference(day.from.toUtc()).inHours,
          spring ? 23 : 25,
        );
        resource = (r) async {
          expect(r.uri.path, '/api/v1/water-logs/daily-total');
          expect(r.uri.queryParameters, day.query);
          expect(
            r.uri.queryParameters['from'],
            endsWith(spring ? '-05:00' : '-04:00'),
          );
          await reply(r, 200, {
            'from': day.from.toUtc().toIso8601String(),
            'to': day.to.toUtc().toIso8601String(),
            'totalAmountMl': 0,
          });
        };
        expect(await api.dailyTotal(day), 0);
      }
    },
  );
  test(
    'local day serialization includes offset and query escapes plus signs',
    () async {
      final day = WaterDayRange(
        _OffsetDate(DateTime.utc(2026, 11, 17), const Duration(hours: 3)),
        _OffsetDate(DateTime.utc(2026, 11, 18), const Duration(hours: 3)),
      );
      resource = (r) async {
        expect(r.uri.query, contains('%2B03%3A00'));
        expect(r.headers.value('x-profile-context'), 'client');
        expect(
          r.headers.value('authorization'),
          'Bearer synthetic.water0.signature',
        );
        expect(r.headers.value('cookie'), isNull);
        expect(await utf8.decoder.bind(r).join(), isEmpty);
        await reply(r, 200, {
          'from': '2026-11-16T21:00:00Z',
          'to': '2026-11-17T21:00:00Z',
          'totalAmountMl': 125.5,
        });
      };
      expect(await api.dailyTotal(day), 125.5);
    },
  );
  test(
    'CRUD uses numeric amounts, no clientId, immutable source and bodyless delete',
    () async {
      final methods = <String>[];
      resource = (r) async {
        methods.add(r.method);
        expect(r.headers.value('x-profile-context'), 'client');
        if (r.method == 'POST' || r.method == 'PATCH') {
          final body = jsonDecode(await utf8.decoder.bind(r).join()) as Map;
          expect(body['amountMl'], 125.5);
          expect(body.containsKey('clientId'), isFalse);
          expect(body.containsKey('id'), isFalse);
          expect(body.containsKey('source'), r.method == 'POST');
        } else {
          expect(await utf8.decoder.bind(r).join(), isEmpty);
        }
        await reply(
          r,
          r.method == 'POST'
              ? 201
              : r.method == 'DELETE'
              ? 204
              : 200,
          r.method == 'DELETE' ? null : waterJson(amount: 125.5),
        );
      };
      await api.create(amountMl: 125.5, consumedAt: DateTime.now());
      await api.get(waterId);
      await api.update(waterId, amountMl: 125.5, consumedAt: DateTime.now());
      await api.delete(waterId);
      expect(methods, ['POST', 'GET', 'PATCH', 'DELETE']);
    },
  );
  test(
    'history sends canonical pagination and distinguishes empty from malformed data',
    () async {
      resource = (r) async {
        expect(r.uri.queryParameters, {'page': '2', 'pageSize': '10'});
        await reply(r, 200, {
          'items': [waterJson()],
          'totalCount': 11,
        });
      };
      expect((await api.list(page: 2)).totalCount, 11);
      resource = (r) => reply(r, 200, {'items': [], 'totalCount': 0});
      expect((await api.list()).items, isEmpty);
      resource = (r) => reply(r, 200, {
        'items': [waterJson()],
        'totalCount': 0,
      });
      await expectLater(api.list(), throwsA(isA<WaterLogApiException>()));
    },
  );
  test('GET refreshes once on 401', () async {
    var reads = 0;
    resource = (r) async {
      reads++;
      await reply(r, reads == 1 ? 401 : 200, reads == 1 ? null : waterJson());
    };
    await api.get(waterId);
    expect(reads, 2);
    expect(renewals, 1);
  });
  for (final method in ['POST', 'PATCH', 'DELETE']) {
    test('$method never replays after 401 even if refresh succeeds', () async {
      var writes = 0;
      resource = (r) async {
        writes++;
        await r.drain<void>();
        await reply(r, 401, null);
      };
      final future = method == 'POST'
          ? api.create(amountMl: 250, consumedAt: DateTime.now())
          : method == 'PATCH'
          ? api.update(waterId, amountMl: 250, consumedAt: DateTime.now())
          : api.delete(waterId);
      await expectLater(
        future,
        throwsA(
          isA<WaterLogApiException>().having(
            (e) => e.statusCode,
            'status',
            401,
          ),
        ),
      );
      expect(writes, 1);
      expect(renewals, 1);
      expect(session.isAuthenticated, isTrue);
    });
  }
  test(
    'bad totals and row fields fail closed, and malformed mutation result is uncertain',
    () async {
      final day = WaterDayRange.forDate(DateTime.now());
      for (final invalid in [null, -1, '250']) {
        resource = (r) => reply(r, 200, {
          'from': day.from.toUtc().toIso8601String(),
          'to': day.to.toUtc().toIso8601String(),
          'totalAmountMl': invalid,
        });
        await expectLater(
          api.dailyTotal(day),
          throwsA(isA<WaterLogApiException>()),
        );
      }
      resource = (r) => reply(r, 200, {
        'from': day.from.toUtc().toIso8601String(),
        'to': day.from.toUtc().toIso8601String(),
        'totalAmountMl': 1,
      });
      await expectLater(
        api.dailyTotal(day),
        throwsA(isA<WaterLogApiException>()),
      );
      final invalidRow = waterJson()..['amountMl'] = 0;
      resource = (r) => reply(r, 200, invalidRow);
      await expectLater(api.get(waterId), throwsA(isA<WaterLogApiException>()));
      resource = (r) async {
        await r.drain<void>();
        await reply(r, 201, {'private': 'Synthetic server data'});
      };
      await expectLater(
        api.create(amountMl: 1, consumedAt: DateTime.now()),
        throwsA(
          isA<WaterLogApiException>().having(
            (e) => e.uncertain,
            'uncertain',
            isTrue,
          ),
        ),
      );
    },
  );
  test(
    'network failure preserves login and makes write result uncertain',
    () async {
      await server.close(force: true);
      await expectLater(
        api.create(amountMl: 250, consumedAt: DateTime.now()),
        throwsA(
          isA<WaterLogApiException>().having(
            (e) => e.uncertain,
            'uncertain',
            isTrue,
          ),
        ),
      );
      expect(session.isAuthenticated, isTrue);
    },
  );
}

Future<void> reply(HttpRequest request, int status, Object? body) async {
  request.response.statusCode = status;
  request.response.headers.contentType = ContentType.json;
  if (body != null) request.response.write(jsonEncode(body));
  await request.response.close();
}

class _OffsetDate extends Fake implements DateTime {
  _OffsetDate(this.wall, this.offset);
  final DateTime wall;
  final Duration offset;
  @override
  bool get isUtc => false;
  @override
  Duration get timeZoneOffset => offset;
  @override
  String toIso8601String() =>
      wall.toIso8601String().replaceFirst(RegExp(r'Z$'), '');
  @override
  DateTime toUtc() => wall.subtract(offset);
}
