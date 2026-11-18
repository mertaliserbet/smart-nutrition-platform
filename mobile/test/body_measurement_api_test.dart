import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/auth/login_api.dart';
import 'package:smart_nutrition_mobile/features/body_measurements/body_measurement_api.dart';
import 'water_test_support.dart';
import 'body_measurement_test_support.dart';

void main() {
  late HttpServer server;
  late AuthSession session;
  late BodyMeasurementApi api;
  late Future<void> Function(HttpRequest) resource;
  var renewals = 0;
  setUp(() async {
    renewals = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    resource = (r) => reply(r, 200, bodyJson());
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
    api = BodyMeasurementApi(session);
  });
  tearDown(() async {
    session.dispose();
    await server.close(force: true);
  });

  test(
    'CRUD uses client context and partial nulls without clientId or mutation replay',
    () async {
      final calls = <String>[];
      final bodies = <Map<String, dynamic>>[];
      resource = (r) async {
        expect(r.headers.value('X-Profile-Context'), 'client');
        expect(r.headers.value('Authorization'), startsWith('Bearer '));
        calls.add(r.method);
        if (r.method == 'POST' || r.method == 'PATCH') {
          bodies.add(
            jsonDecode(await utf8.decoder.bind(r).join())
                as Map<String, dynamic>,
          );
        }
        await reply(
          r,
          r.method == 'POST'
              ? 201
              : r.method == 'DELETE'
              ? 204
              : 200,
          r.method == 'DELETE' ? null : bodyJson(),
        );
      };
      await api.create(
        values: {'weightKg': 73.125, 'waistCm': null},
        measuredAt: DateTime(2026, 11, 18, 12),
      );
      expect(bodies.single['measuredAt'], endsWith('Z'));
      expect(bodies.single['source'], 'manual');
      expect(bodies.single.containsKey('clientId'), false);
      await api.get(bodyId);
      await api.update(bodyId, {'waistCm': null});
      await api.delete(bodyId);
      expect(bodies.last, {'waistCm': null});
      expect(calls, ['POST', 'GET', 'PATCH', 'DELETE']);
    },
  );
  test(
    'history consumes every ascending page and preserves absent metrics',
    () async {
      final pages = <int>[];
      resource = (r) async {
        final page = int.parse(r.uri.queryParameters['page']!);
        pages.add(page);
        expect(r.uri.queryParameters['pageSize'], '100');
        expect(r.uri.queryParameters['sortOrder'], 'asc');
        final rows = [
          for (var i = (page - 1) * 100; i < (page == 1 ? 100 : 101); i++)
            bodyJson(
              id: '${(i + 1).toString().padLeft(8, '0')}-1111-4111-8111-111111111111',
            ),
        ];
        await reply(r, 200, {'items': rows, 'totalCount': 101});
      };
      final rows = await api.history();
      expect(rows.length, 101);
      expect(pages, [1, 2]);
      expect(rows.every((r) => r.hipCm == null), true);
    },
  );
  test(
    'changed total and duplicate records during paged history fail without partial charts',
    () async {
      var reads = 0;
      resource = (r) async {
        reads++;
        await reply(r, 200, {
          'items': [bodyJson()],
          'totalCount': reads == 1 ? 2 : 1,
        });
      };
      await expectLater(
        api.history(),
        throwsA(isA<BodyMeasurementApiException>()),
      );
      expect(reads, 2);
    },
  );
  test(
    'date filters send UTC instants and public list stays paginated',
    () async {
      resource = (r) async {
        expect(r.uri.queryParameters['from'], '2026-11-01T00:00:00.000Z');
        expect(r.uri.queryParameters['to'], '2026-12-01T00:00:00.000Z');
        expect(r.uri.queryParameters['page'], '2');
        await reply(r, 200, {'items': [], 'totalCount': 1});
      };
      expect(
        (await api.list(
          page: 2,
          from: DateTime.utc(2026, 11, 1),
          to: DateTime.utc(2026, 12, 1),
        )).items,
        isEmpty,
      );
    },
  );
  for (final scenario in [
    'negative',
    'empty',
    'missing',
    'foreignId',
    'badDate',
    'badFat',
    'mixedOwners',
  ]) {
    test('rejects malformed response: $scenario', () async {
      final row = bodyJson();
      if (scenario == 'negative') row['weightKg'] = -1;
      if (scenario == 'empty') row['weightKg'] = null;
      if (scenario == 'missing') row.remove('note');
      if (scenario == 'foreignId') row['id'] = bodyClientId;
      if (scenario == 'badDate') row['measuredAt'] = '2026-11-18T09:00:00';
      if (scenario == 'badFat') row['bodyFatPercent'] = 101;
      resource = (r) async => reply(
        r,
        200,
        scenario == 'mixedOwners'
            ? {
                'items': [
                  row,
                  {...bodyJson(id: bodyClientId), 'clientId': bodyId},
                ],
                'totalCount': 2,
              }
            : row,
      );
      await expectLater(
        scenario == 'mixedOwners' ? api.list() : api.get(bodyId),
        throwsA(isA<BodyMeasurementApiException>()),
      );
    });
  }
  test('GET refreshes once after 401', () async {
    var reads = 0;
    resource = (r) async {
      reads++;
      await reply(r, reads == 1 ? 401 : 200, reads == 1 ? null : bodyJson());
    };
    await api.get(bodyId);
    expect(reads, 2);
    expect(renewals, 1);
  });
  for (final method in ['POST', 'PATCH', 'DELETE']) {
    test('$method is sent once when unauthorized', () async {
      var writes = 0;
      resource = (r) async {
        writes++;
        await r.drain<void>();
        await reply(r, 401, null);
      };
      final operation = method == 'POST'
          ? api.create(values: {'weightKg': 73}, measuredAt: DateTime.now())
          : method == 'PATCH'
          ? api.update(bodyId, {'weightKg': 73})
          : api.delete(bodyId);
      await expectLater(operation, throwsA(isA<BodyMeasurementApiException>()));
      expect(writes, 1);
    });
  }
  test('server failure on mutation is uncertain and never retried', () async {
    var writes = 0;
    resource = (r) async {
      writes++;
      await r.drain<void>();
      await reply(r, 500, null);
    };
    await expectLater(
      api.update(bodyId, {'weightKg': 73}),
      throwsA(
        isA<BodyMeasurementApiException>().having(
          (e) => e.uncertain,
          'uncertain',
          true,
        ),
      ),
    );
    expect(writes, 1);
  });
}

Future<void> reply(HttpRequest request, int status, Object? body) async {
  request.response.statusCode = status;
  request.response.headers.contentType = ContentType.json;
  if (body != null) request.response.write(jsonEncode(body));
  await request.response.close();
}
