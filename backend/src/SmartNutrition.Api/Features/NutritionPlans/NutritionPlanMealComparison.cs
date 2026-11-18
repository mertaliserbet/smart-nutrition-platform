using SmartNutrition.Api.Features.MealLogs;

namespace SmartNutrition.Api.Features.NutritionPlans;

public sealed record NutritionValueSummary(decimal KnownTotal, int MissingItemCount);
public sealed record MealLogNutritionSummary(int MealLogCount, int ItemCount, int EstimatedItemCount,
    NutritionValueSummary CaloriesKcal, NutritionValueSummary ProteinGrams,
    NutritionValueSummary CarbsGrams, NutritionValueSummary FatGrams);
public sealed record NutritionPlanMealComparison(MealType MealType, IReadOnlyList<NutritionPlanItem> PlannedItems,
    MealLogNutritionSummary Actual);
public sealed record NutritionPlanMealComparisonResponse(Guid ClientId, NutritionPlanVersionResponse NutritionPlanVersion,
    DateOnly Date, DateTimeOffset From, DateTimeOffset To, MealLogNutritionSummary Actual,
    decimal? CaloriesDifferenceKcal, IReadOnlyList<NutritionPlanMealComparison> Meals);
