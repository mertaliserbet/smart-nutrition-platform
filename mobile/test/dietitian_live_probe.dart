// Explicit opt-in: flutter test test/dietitian_live_probe.dart.
// Supply only disposable synthetic accounts using SNP_LIVE_* environment variables.
// The provisioning caller must clean their exact database rows and Mailpit messages.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_nutrition_mobile/core/network/api_config.dart';
import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/auth/login_api.dart';
import 'package:smart_nutrition_mobile/features/auth/refresh_token_store.dart';
import 'package:smart_nutrition_mobile/features/dietitians/dietitian_api.dart';

void main() {
  test(
    'real HTTPS: mutual approval, cancellation, sharing grant/revoke and ended access',
    () async {
      final env = Platform.environment;
      String input(String key) {
        final value = env['SNP_LIVE_$key'];
        if (value == null || value.isEmpty) {
          throw StateError('Missing disposable test input: $key');
        }
        return value;
      }

      final origin = ApiConfig.validate(input('ORIGIN'), allowLocalHttp: false);
      expect(origin.host, 'localhost');
      final password = input('PASSWORD');
      final a = AuthSession(
        api: LoginApi(baseUri: origin),
        store: _MemoryStore(),
      );
      final b = AuthSession(
        api: LoginApi(baseUri: origin),
        store: _MemoryStore(),
      );
      try {
        for (final (session, email) in [
          (a, input('CLIENT_A')),
          (b, input('CLIENT_B')),
        ]) {
          expect(email.startsWith('synthetic-finder-'), isTrue);
          await session.initialize();
          expect(
            await session.signIn(email: email, password: password),
            isTrue,
          );
        }
        final api = DietitianApi(a), codeApi = DietitianApi(b);
        final directory = await api.search(page: 1, query: input('QUERY'));
        expect(directory.totalCount, 1);
        expect(directory.items.single.id, input('EXPERT_ID'));
        expect((await api.relationships(status: 'active')).items, isEmpty);
        final pending = await api.request(
          dietitianId: directory.items.single.id,
        );
        expect(pending.status, 'pending');
        expect(
          (await api.relationships(status: 'pending')).items.single.id,
          pending.id,
        );
        await expectLater(
          api.request(dietitianId: directory.items.single.id),
          throwsA(
            isA<DietitianApiException>().having(
              (e) => e.statusCode,
              'duplicate',
              409,
            ),
          ),
        );
        final invited = await codeApi.request(
          invitationCode: input('INVITATION').toLowerCase(),
        );
        expect(invited.status, 'pending');
        final expert = await LoginApi(
          baseUri: origin,
        ).login(email: input('EXPERT_EMAIL'), password: password);
        final http = HttpClient(context: ApiConfig.developmentSecurityContext);
        try {
          Future<void> expertRequest(
            String path,
            int status, {
            String method = 'GET',
          }) async {
            final request = await http.openUrl(
              method,
              origin.resolve('/api/v1/$path'),
            );
            request.followRedirects = false;
            request.headers.set(
              HttpHeaders.authorizationHeader,
              'Bearer ${expert.accessToken}',
            );
            request.headers.set('X-Profile-Context', 'dietitian');
            final response = await request.close();
            expect(response.statusCode, status);
            await response.drain<void>();
          }

          final forbiddenApproval = await a.authorizedRequest(
            path: '/api/v1/dietitian-relationships/${pending.id}/accept',
            method: 'POST',
            profileContext: 'client',
          );
          expect(forbiddenApproval.statusCode, 403);
          expect(await api.permission(pending.id), isNull);
          await expectLater(
            api.setPermission(relationshipId: pending.id, isGranted: true),
            throwsA(
              isA<DietitianApiException>().having(
                (e) => e.statusCode,
                'pending permission',
                409,
              ),
            ),
          );
          await expertRequest(
            'dietitian-relationships/${pending.id}/accept',
            200,
            method: 'POST',
          );
          expect(
            await api.permission(pending.id),
            isNull,
          ); // Acceptance creates no permission.
          final planPath =
              'nutrition-plans?clientId=${pending.clientId}&page=1&pageSize=10';
          await expertRequest(planPath, 403);
          final granted = await api.setPermission(
            relationshipId: pending.id,
            isGranted: true,
          );
          expect((await api.permission(pending.id))!.isGranted, isTrue);
          await expertRequest(planPath, 200);
          final revoked = await api.setPermission(
            relationshipId: pending.id,
            isGranted: false,
            current: granted,
          );
          expect(revoked.isGranted, isFalse);
          expect((await api.permission(pending.id))!.isGranted, isFalse);
          await expertRequest(planPath, 403);
          expect(
            (await api.relationships(status: 'active')).items.single.id,
            pending.id,
          );
          expect((await api.relationships(status: 'pending')).items, isEmpty);
          await expectLater(
            api.request(dietitianId: directory.items.single.id),
            throwsA(
              isA<DietitianApiException>().having(
                (e) => e.statusCode,
                'active conflict',
                409,
              ),
            ),
          );
          final canceled = await codeApi.endRelationship(invited);
          expect(canceled.status, 'ended');
          final retry = await codeApi.request(
            dietitianId: directory.items.single.id,
          );
          await expertRequest(
            'dietitian-relationships/${retry.id}/reject',
            200,
            method: 'POST',
          );
          expect(
            (await codeApi.relationships(status: 'rejected')).items.single.id,
            retry.id,
          );
          final active = (await api.relationships(
            status: 'active',
          )).items.single;
          expect((await api.endRelationship(active)).status, 'ended');
          expect((await api.relationships(status: 'active')).items, isEmpty);
          expect(
            (await api.relationships(status: 'ended')).items.single.id,
            pending.id,
          );
          await expertRequest(planPath, 404);
          await expectLater(
            api.setPermission(
              relationshipId: pending.id,
              isGranted: true,
              current: revoked,
            ),
            throwsA(
              isA<DietitianApiException>().having(
                (e) => e.statusCode,
                'ended permission',
                409,
              ),
            ),
          );
        } finally {
          http.close(force: true);
          await LoginApi(baseUri: origin).logout(expert.refreshToken);
        }
        expect(a.isAuthenticated, isTrue);
        expect(b.isAuthenticated, isTrue);
      } finally {
        await a.signOut();
        await b.signOut();
        a.dispose();
        b.dispose();
      }
    },
  );
}

class _MemoryStore implements RefreshTokenStore {
  StoredRefreshToken? value;
  @override
  Future<StoredRefreshToken?> read() async => value;
  @override
  Future<void> write(StoredRefreshToken record) async {
    value = record;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}
