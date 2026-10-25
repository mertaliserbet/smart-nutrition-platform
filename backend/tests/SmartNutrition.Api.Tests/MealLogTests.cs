using System.Text.Json;
using SmartNutrition.Api.Features.MealLogs;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Tests;

public sealed class MealLogTests
{
    private static readonly Guid LogId = Guid.Parse("10000000-0000-0000-0000-000000000001");
    private static readonly Guid ClientId = Guid.Parse("20000000-0000-0000-0000-000000000001");
    private static readonly Guid ItemId = Guid.Parse("30000000-0000-0000-0000-000000000001");
    private static readonly DateTimeOffset Instant = new(2026, 10, 25, 12, 30, 0, TimeSpan.Zero);

    [Theory]
    [InlineData(MealType.Breakfast)]
    [InlineData(MealType.Lunch)]
    [InlineData(MealType.Dinner)]
    [InlineData(MealType.Snack)]
    [InlineData(MealType.Other)]
    public void SupportsEveryCanonicalMealTypeWithoutRequiringDietitianOrFoodCatalog(MealType mealType)
    {
        var mealLog = NewLog(mealType: mealType);

        Assert.Equal(LogId, mealLog.Id);
        Assert.Equal(ClientId, mealLog.ClientId);
        Assert.Equal(mealType, mealLog.MealType);
        Assert.Equal(RecordSource.Manual, mealLog.Source);
        Assert.Null(mealLog.Note);
        Assert.Null(mealLog.FoodAnalysisId);
        Assert.Single(mealLog.Items);
        Assert.Equal(LogId, mealLog.Items[0].MealLogId);
    }

    [Theory]
    [InlineData("id")]
    [InlineData("clientId")]
    [InlineData("foodAnalysisId")]
    public void RejectsEmptyRequiredIdsAndEmptyOptionalReferences(string parameter)
    {
        var error = Assert.Throws<ArgumentException>(() => NewLog(
            id: parameter == "id" ? Guid.Empty : LogId,
            clientId: parameter == "clientId" ? Guid.Empty : ClientId,
            foodAnalysisId: parameter == "foodAnalysisId" ? Guid.Empty : null));

        Assert.Equal(parameter, error.ParamName);
    }

    [Theory]
    [InlineData(-1)]
    [InlineData(99)]
    public void RejectsUndefinedMealTypes(int value)
    {
        var error = Assert.Throws<ArgumentException>(() => NewLog(mealType: (MealType)value));
        Assert.Equal("mealType", error.ParamName);
    }

    [Theory]
    [InlineData(-1)]
    [InlineData(99)]
    public void RejectsUndefinedSources(int value)
    {
        var error = Assert.Throws<ArgumentException>(() => NewLog(source: (RecordSource)value));
        Assert.Equal("source", error.ParamName);
    }

    [Theory]
    [InlineData("consumedAt")]
    [InlineData("createdAt")]
    public void RequiresExplicitConsumptionAndCreationTimes(string parameter)
    {
        var error = Assert.Throws<ArgumentException>(() => NewLog(
            consumedAt: parameter == "consumedAt" ? default(DateTimeOffset) : Instant,
            createdAt: parameter == "createdAt" ? default(DateTimeOffset) : Instant));
        Assert.Equal(parameter, error.ParamName);
    }

    [Fact]
    public void StoresUtcInstantsWithoutImposingFutureOrHistoricalCutoffs()
    {
        var offsetTime = new DateTimeOffset(2035, 1, 2, 15, 30, 0, TimeSpan.FromHours(3));
        var mealLog = NewLog(consumedAt: offsetTime, createdAt: Instant.ToOffset(TimeSpan.FromHours(-4)));

        Assert.Equal(offsetTime.UtcDateTime, mealLog.ConsumedAt.UtcDateTime);
        Assert.Equal(TimeSpan.Zero, mealLog.ConsumedAt.Offset);
        Assert.Equal(Instant, mealLog.CreatedAt);
        Assert.Equal(TimeSpan.Zero, mealLog.CreatedAt.Offset);
        Assert.Equal(new DateTimeOffset(1900, 1, 1, 0, 0, 0, TimeSpan.Zero),
            NewLog(consumedAt: new DateTimeOffset(1900, 1, 1, 0, 0, 0, TimeSpan.Zero)).ConsumedAt);
    }

    [Fact]
    public void RequiresAtLeastOneNonNullItem()
    {
        Assert.Throws<ArgumentNullException>(() => new MealLog(
            LogId, ClientId, MealType.Lunch, Instant, RecordSource.Manual, Instant, null!));
        Assert.Equal("items", Assert.Throws<ArgumentException>(() => NewLog(items: [])).ParamName);
        Assert.Equal("items", Assert.Throws<ArgumentException>(() => NewLog(items: [null!])).ParamName);
    }

    [Fact]
    public void RejectsItemsBelongingToAnotherMealLogAndRepeatedItemIds()
    {
        var otherParent = new MealLogItem(ItemId,
            Guid.Parse("10000000-0000-0000-0000-000000000002"), "Synthetic item", false);
        Assert.Equal("items", Assert.Throws<ArgumentException>(() => NewLog(items: [otherParent])).ParamName);
        Assert.Equal("items", Assert.Throws<ArgumentException>(() => NewLog(items: [NewItem(), NewItem()])).ParamName);
    }

    [Fact]
    public void ItemCollectionCannotBeChangedThroughCallerOwnedCollections()
    {
        var items = new List<MealLogItem> { NewItem() };
        var mealLog = NewLog(items: items);
        items.Clear();

        Assert.Single(mealLog.Items);
        Assert.Throws<NotSupportedException>(() => ((IList<MealLogItem>)mealLog.Items).Clear());
    }

    [Fact]
    public void RetainsDefinedOptionalFieldsWithoutInterpretingOpenAuthorizationRules()
    {
        var analysisId = Guid.Parse("40000000-0000-0000-0000-000000000001");
        var mealLog = NewLog(source: RecordSource.AiAssisted, note: "Synthetic note", foodAnalysisId: analysisId);

        Assert.Equal(analysisId, mealLog.FoodAnalysisId);
        Assert.Equal("Synthetic note", mealLog.Note);
        // An optional reference is not proof of ownership, completion or user confirmation.
        Assert.Null(NewLog(source: RecordSource.AiAssisted).FoodAnalysisId);
    }

    [Theory]
    [InlineData(MealType.Breakfast, "breakfast")]
    [InlineData(MealType.Lunch, "lunch")]
    [InlineData(MealType.Dinner, "dinner")]
    [InlineData(MealType.Snack, "snack")]
    [InlineData(MealType.Other, "other")]
    public void MealTypeJsonUsesTheSharedStringVocabulary(MealType value, string expected)
    {
        Assert.Equal($"\"{expected}\"", JsonSerializer.Serialize(value));
        Assert.Equal(value, JsonSerializer.Deserialize<MealType>($"\"{expected}\""));
    }

    [Theory]
    [InlineData(RecordSource.Manual, "manual")]
    [InlineData(RecordSource.Wearable, "wearable")]
    [InlineData(RecordSource.AiAssisted, "ai_assisted")]
    public void SourceJsonUsesTheSharedStringVocabulary(RecordSource value, string expected)
    {
        Assert.Equal($"\"{expected}\"", JsonSerializer.Serialize(value));
        Assert.Equal(value, JsonSerializer.Deserialize<RecordSource>($"\"{expected}\""));
    }

    [Theory]
    [InlineData("0")]
    [InlineData("\"0\"")]
    [InlineData("\"unsupported\"")]
    [InlineData("null")]
    public void EnumsRejectNumbersAndUnknownJsonValues(string json)
    {
        Assert.Throws<JsonException>(() => JsonSerializer.Deserialize<MealType>(json));
        Assert.Throws<JsonException>(() => JsonSerializer.Deserialize<RecordSource>(json));
    }

    private static MealLogItem NewItem() => new(ItemId, LogId, "Synthetic item", false);

    private static MealLog NewLog(
        Guid? id = null, Guid? clientId = null, MealType mealType = MealType.Lunch,
        DateTimeOffset? consumedAt = null, RecordSource source = RecordSource.Manual,
        DateTimeOffset? createdAt = null, IEnumerable<MealLogItem>? items = null,
        string? note = null, Guid? foodAnalysisId = null) =>
        new(id ?? LogId, clientId ?? ClientId, mealType, consumedAt ?? Instant,
            source, createdAt ?? Instant, items ?? [NewItem()], note, foodAnalysisId);
}
