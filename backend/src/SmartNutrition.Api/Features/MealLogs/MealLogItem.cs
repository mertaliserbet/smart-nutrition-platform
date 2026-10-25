namespace SmartNutrition.Api.Features.MealLogs;

public sealed class MealLogItem
{
    public MealLogItem(
        Guid id,
        Guid mealLogId,
        string displayName,
        bool isEstimated,
        decimal? quantityGrams = null,
        decimal? caloriesKcal = null,
        decimal? proteinGrams = null,
        decimal? carbsGrams = null,
        decimal? fatGrams = null,
        Guid? foodItemId = null,
        Guid? recipeId = null)
    {
        if (id == Guid.Empty)
            throw new ArgumentException("An item ID is required.", nameof(id));
        if (mealLogId == Guid.Empty)
            throw new ArgumentException("A parent meal-log ID is required.", nameof(mealLogId));
        if (foodItemId == Guid.Empty)
            throw new ArgumentException("A food reference must be a non-empty ID.", nameof(foodItemId));
        if (recipeId == Guid.Empty)
            throw new ArgumentException("A recipe reference must be a non-empty ID.", nameof(recipeId));
        ArgumentException.ThrowIfNullOrWhiteSpace(displayName);
        if (quantityGrams is <= 0)
            throw new ArgumentException("Known quantity must be positive, in grams.", nameof(quantityGrams));
        ValidateNonNegative(caloriesKcal, nameof(caloriesKcal));
        ValidateNonNegative(proteinGrams, nameof(proteinGrams));
        ValidateNonNegative(carbsGrams, nameof(carbsGrams));
        ValidateNonNegative(fatGrams, nameof(fatGrams));

        Id = id;
        MealLogId = mealLogId;
        DisplayName = displayName;
        IsEstimated = isEstimated;
        QuantityGrams = quantityGrams;
        CaloriesKcal = caloriesKcal;
        ProteinGrams = proteinGrams;
        CarbsGrams = carbsGrams;
        FatGrams = fatGrams;
        FoodItemId = foodItemId;
        RecipeId = recipeId;
    }

    public Guid Id { get; }
    public Guid MealLogId { get; }
    public Guid? FoodItemId { get; }
    public Guid? RecipeId { get; }
    public string DisplayName { get; }
    // Nullable decimal keeps unknown values distinct from measured zero; no rounding is chosen.
    public decimal? QuantityGrams { get; }
    public decimal? CaloriesKcal { get; }
    public decimal? ProteinGrams { get; }
    public decimal? CarbsGrams { get; }
    public decimal? FatGrams { get; }
    public bool IsEstimated { get; }

    private static void ValidateNonNegative(decimal? value, string parameterName)
    {
        if (value is < 0)
            throw new ArgumentException("Known energy and macro values cannot be negative.", parameterName);
    }
}
