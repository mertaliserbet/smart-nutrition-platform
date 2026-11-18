import 'package:smart_nutrition_mobile/features/auth/auth_session.dart';
import 'package:smart_nutrition_mobile/features/auth/login_api.dart';
import 'package:smart_nutrition_mobile/features/nutrition/meal_log_api.dart';

const mealId = '11111111-1111-4111-8111-111111111111';
const mealClientId = '22222222-2222-4222-8222-222222222222';
Map<String, Object?> mealJson() => {
  'id': mealId,
  'clientId': mealClientId,
  'mealType': 'lunch',
  'consumedAt': '2026-11-16T12:00:00Z',
  'note': null,
  'source': 'manual',
  'foodAnalysisId': null,
  'createdAt': '2026-11-16T12:00:00Z',
  'items': [
    <String, Object?>{
      'id': '33333333-3333-4333-8333-333333333333',
      'mealLogId': mealId,
      'foodItemId': null,
      'recipeId': null,
      'displayName': 'Sentetik çorba',
      'quantityGrams': null,
      'caloriesKcal': 0,
      'proteinGrams': 12.5,
      'carbsGrams': null,
      'fatGrams': 0,
      'isEstimated': true,
    },
  ],
};
MealLog sampleMeal({String name = 'Sentetik çorba'}) => MealLog(
  id: mealId,
  clientId: mealClientId,
  mealType: 'lunch',
  consumedAt: DateTime.utc(2026, 11, 16, 12),
  createdAt: DateTime.utc(2026, 11, 16, 12),
  source: 'manual',
  items: [
    MealLogItem(
      id: '33333333-3333-4333-8333-333333333333',
      mealLogId: mealId,
      displayName: name,
      isEstimated: true,
      caloriesKcal: 0,
      proteinGrams: 12.5,
      fatGrams: 0,
    ),
  ],
);

class MealTestSession extends AuthSession {
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

class MealTestApi extends MealLogApi {
  MealTestApi(super.session);
  List<MealLog> rows = [sampleMeal()];
  List<int> pages = [];
  Map<String, Object?>? lastBody;
  int creates = 0, updates = 0, deletes = 0, reads = 0;
  MealLogApiException? failure;
  Future<MealLog>? pendingCreate;
  Future<MealLogPage>? pendingList;
  @override
  Future<MealLogPage> list({int page = 1, DateTime? from, DateTime? to}) async {
    pages.add(page);
    if (failure != null) throw failure!;
    return pendingList ?? (items: rows, totalCount: rows.length);
  }

  @override
  Future<MealLog> get(String id) async {
    reads++;
    if (failure != null) throw failure!;
    return rows.single;
  }

  @override
  Future<MealLog> create(Map<String, Object?> body) async {
    creates++;
    lastBody = body;
    if (failure != null) throw failure!;
    return pendingCreate ?? sampleMeal();
  }

  @override
  Future<MealLog> update(String id, Map<String, Object?> body) async {
    updates++;
    lastBody = body;
    if (failure != null) throw failure!;
    return sampleMeal();
  }

  @override
  Future<void> delete(String id) async {
    deletes++;
    if (failure != null) throw failure!;
    rows = [];
  }
}
