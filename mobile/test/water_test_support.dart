import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/auth/login_api.dart';
import 'package:smart_nutrition_mobile/features/auth/refresh_token_store.dart';
import 'package:smart_nutrition_mobile/features/water/water_log_api.dart';

const waterId = '11111111-1111-4111-8111-111111111111';
const waterClientId = '22222222-2222-4222-8222-222222222222';
Map<String, Object?> waterJson({num amount = 250}) => {
  'id': waterId,
  'clientId': waterClientId,
  'amountMl': amount,
  'consumedAt': '2026-11-17T10:00:00Z',
  'source': 'manual',
};
WaterLog waterSample({num amount = 250}) => WaterLog(
  id: waterId,
  clientId: waterClientId,
  amountMl: amount,
  consumedAt: DateTime.utc(2026, 11, 17, 10),
  source: 'manual',
);

class WaterTestSession extends AuthSession {
  bool authenticated = true;
  String owner = '44444444-4444-4444-8444-444444444444';
  @override
  bool get isAuthenticated => authenticated;
  @override
  bool get isBlocking => false;
  @override
  CurrentUserResponse? get user => authenticated
      ? CurrentUserResponse(
          id: owner,
          displayName: 'Sentetik',
          email: 'synthetic@example.test',
          role: 'client',
          isEmailVerified: true,
        )
      : null;
  void end() {
    authenticated = false;
    notifyListeners();
  }

  void changeOwner() {
    owner = '55555555-5555-4555-8555-555555555555';
    notifyListeners();
  }
}

class WaterTestApi extends WaterLogApi {
  WaterTestApi(super.session);
  num total = 0;
  List<WaterLog> rows = [];
  int? count;
  WaterLogApiException? failure;
  Future<num>? pendingTotal;
  Future<WaterLog>? pendingWrite;
  final days = <WaterDayRange>[];
  final pages = <int>[];
  int creates = 0, updates = 0, deletes = 0;
  num? lastAmount;
  DateTime? lastTime;
  @override
  Future<num> dailyTotal(WaterDayRange day) async {
    days.add(day);
    if (failure != null) throw failure!;
    return pendingTotal ?? total;
  }

  @override
  Future<WaterLogPage> list({int page = 1}) async {
    pages.add(page);
    if (failure != null) throw failure!;
    return (items: rows, totalCount: count ?? rows.length);
  }

  @override
  Future<WaterLog> get(String id) async {
    if (failure != null) throw failure!;
    return rows.single;
  }

  @override
  Future<WaterLog> create({
    required num amountMl,
    required DateTime consumedAt,
  }) async {
    creates++;
    lastAmount = amountMl;
    lastTime = consumedAt;
    if (failure != null) throw failure!;
    final row =
        await (pendingWrite ?? Future.value(waterSample(amount: amountMl)));
    rows = [row, ...rows];
    total += row.amountMl;
    return row;
  }

  @override
  Future<WaterLog> update(
    String id, {
    required num amountMl,
    required DateTime consumedAt,
  }) async {
    updates++;
    lastAmount = amountMl;
    lastTime = consumedAt;
    if (failure != null) throw failure!;
    final row =
        await (pendingWrite ?? Future.value(waterSample(amount: amountMl)));
    rows = [row];
    total = row.amountMl;
    return row;
  }

  @override
  Future<void> delete(String id) async {
    deletes++;
    if (failure != null) throw failure!;
    rows = [];
    total = 0;
  }
}

class WaterMemoryStore implements RefreshTokenStore {
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
