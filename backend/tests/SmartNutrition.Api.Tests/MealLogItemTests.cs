using SmartNutrition.Api.Features.MealLogs;

namespace SmartNutrition.Api.Tests;

public sealed class MealLogItemTests
{
    private static readonly Guid ItemId = Guid.Parse("30000000-0000-0000-0000-000000000001");
    private static readonly Guid LogId = Guid.Parse("10000000-0000-0000-0000-000000000001");

    [Fact]
    public void UnknownQuantityAndNutrientsRemainNullRatherThanZero()
    {
        var item = NewItem();

        Assert.Null(item.QuantityGrams);
        Assert.Null(item.CaloriesKcal);
        Assert.Null(item.ProteinGrams);
        Assert.Null(item.CarbsGrams);
        Assert.Null(item.FatGrams);
        Assert.Null(item.FoodItemId);
        Assert.Null(item.RecipeId);
        Assert.False(item.IsEstimated);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("  \t\r\n")]
    public void RequiresNonBlankDisplayName(string? value)
    {
        var error = Assert.ThrowsAny<ArgumentException>(() => NewItem(displayName: value!));
        Assert.Equal("displayName", error.ParamName);
    }

    [Theory]
    [InlineData("id")]
    [InlineData("mealLogId")]
    [InlineData("foodItemId")]
    [InlineData("recipeId")]
    public void RejectsEmptyIdsWithoutInventingMissingReferences(string parameter)
    {
        var error = Assert.Throws<ArgumentException>(() => NewItem(
            id: parameter == "id" ? Guid.Empty : ItemId,
            mealLogId: parameter == "mealLogId" ? Guid.Empty : LogId,
            foodItemId: parameter == "foodItemId" ? Guid.Empty : null,
            recipeId: parameter == "recipeId" ? Guid.Empty : null));
        Assert.Equal(parameter, error.ParamName);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    public void KnownQuantityMustBePositive(int value)
    {
        var error = Assert.Throws<ArgumentException>(() => NewItem(quantityGrams: value));
        Assert.Equal("quantityGrams", error.ParamName);
    }

    [Theory]
    [InlineData("caloriesKcal")]
    [InlineData("proteinGrams")]
    [InlineData("carbsGrams")]
    [InlineData("fatGrams")]
    public void KnownNutrientsCannotBeNegative(string parameter)
    {
        var error = Assert.Throws<ArgumentException>(() => NewItem(
            caloriesKcal: parameter == "caloriesKcal" ? -0.1m : null,
            proteinGrams: parameter == "proteinGrams" ? -0.1m : null,
            carbsGrams: parameter == "carbsGrams" ? -0.1m : null,
            fatGrams: parameter == "fatGrams" ? -0.1m : null));
        Assert.Equal(parameter, error.ParamName);
    }

    [Fact]
    public void MeasuredZeroNutrientsAreValidAndDistinctFromUnknown()
    {
        var item = NewItem(caloriesKcal: 0, proteinGrams: 0, carbsGrams: 0, fatGrams: 0);

        Assert.Equal(0m, item.CaloriesKcal);
        Assert.Equal(0m, item.ProteinGrams);
        Assert.Equal(0m, item.CarbsGrams);
        Assert.Equal(0m, item.FatGrams);
        Assert.Null(item.QuantityGrams);
    }

    [Fact]
    public void PreservesDecimalValuesWithoutRoundingCalculatingOrChangingTheEstimateFlag()
    {
        var item = new MealLogItem(ItemId, LogId, "Synthetic item", true,
            quantityGrams: 125.123456789m, caloriesKcal: 42.987654321m,
            proteinGrams: 1.23456789m, carbsGrams: 2.34567891m, fatGrams: 3.45678912m);

        Assert.Equal(125.123456789m, item.QuantityGrams);
        Assert.Equal(42.987654321m, item.CaloriesKcal);
        Assert.Equal(1.23456789m, item.ProteinGrams);
        Assert.Equal(2.34567891m, item.CarbsGrams);
        Assert.Equal(3.45678912m, item.FatGrams);
        Assert.True(item.IsEstimated);
        Assert.Equal(decimal.MaxValue, NewItem(quantityGrams: decimal.MaxValue).QuantityGrams);
    }

    private static MealLogItem NewItem(
        Guid? id = null, Guid? mealLogId = null, string displayName = "Synthetic item",
        decimal? quantityGrams = null, decimal? caloriesKcal = null,
        decimal? proteinGrams = null, decimal? carbsGrams = null, decimal? fatGrams = null,
        Guid? foodItemId = null, Guid? recipeId = null) =>
        new(id ?? ItemId, mealLogId ?? LogId, displayName, false, quantityGrams,
            caloriesKcal, proteinGrams, carbsGrams, fatGrams, foodItemId, recipeId);
}
