import 'package:smart_nutrition_mobile/features/personal_nutrition_targets/personal_nutrition_target_api.dart';

PersonalNutritionTargetResponse targetResponse(Map<String, num?> values) =>
    PersonalNutritionTargetResponse(
      dailyCaloriesTargetKcal: values['dailyCaloriesTargetKcal'],
      dailyProteinTargetGrams: values['dailyProteinTargetGrams'],
      dailyCarbsTargetGrams: values['dailyCarbsTargetGrams'],
      dailyFatTargetGrams: values['dailyFatTargetGrams'],
      dailyWaterTargetMl: values['dailyWaterTargetMl'],
    );

class TargetTestApi extends PersonalNutritionTargetApi {
  TargetTestApi(super.session);
  PersonalNutritionTargetResponse value =
      const PersonalNutritionTargetResponse();
  Future<PersonalNutritionTargetResponse>? pendingRead, pendingWrite;
  PersonalNutritionTargetApiException? readFailure, writeFailure;
  int reads = 0;
  final writes = <Map<String, num?>>[];
  @override
  Future<PersonalNutritionTargetResponse> get() async {
    reads++;
    if (readFailure != null) throw readFailure!;
    return pendingRead ?? value;
  }

  @override
  Future<PersonalNutritionTargetResponse> patch(
    Map<String, num?> changes,
  ) async {
    writes.add(Map.of(changes));
    if (writeFailure != null) throw writeFailure!;
    value = pendingWrite == null
        ? targetResponse({...value.values, ...changes})
        : await pendingWrite!;
    return value;
  }
}
