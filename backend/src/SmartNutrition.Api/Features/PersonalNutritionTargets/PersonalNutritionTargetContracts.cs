using System.Text.Json;
using SmartNutrition.Api.Features.Relationships;

namespace SmartNutrition.Api.Features.PersonalNutritionTargets;

public sealed class PatchPersonalNutritionTargetRequest
{
    public JsonElement DailyCaloriesTargetKcal { get; init; }
    public JsonElement DailyProteinTargetGrams { get; init; }
    public JsonElement DailyCarbsTargetGrams { get; init; }
    public JsonElement DailyFatTargetGrams { get; init; }
    public JsonElement DailyWaterTargetMl { get; init; }

    internal void Apply(PersonalNutritionTarget row)
    {
        if (new[] { DailyCaloriesTargetKcal, DailyProteinTargetGrams, DailyCarbsTargetGrams, DailyFatTargetGrams, DailyWaterTargetMl }
            .All(value => value.ValueKind == JsonValueKind.Undefined)) throw new ResourceOperationException(400);
        row.Revise(Read(DailyCaloriesTargetKcal, row.DailyCaloriesTargetKcal, PersonalNutritionTarget.MaxCaloriesKcal),
            Read(DailyProteinTargetGrams, row.DailyProteinTargetGrams, PersonalNutritionTarget.MaxMacroGrams),
            Read(DailyCarbsTargetGrams, row.DailyCarbsTargetGrams, PersonalNutritionTarget.MaxMacroGrams),
            Read(DailyFatTargetGrams, row.DailyFatTargetGrams, PersonalNutritionTarget.MaxMacroGrams),
            Read(DailyWaterTargetMl, row.DailyWaterTargetMl, PersonalNutritionTarget.MaxWaterMl));
    }
    private static decimal? Read(JsonElement input, decimal? current, decimal maximum)
    {
        if (input.ValueKind == JsonValueKind.Undefined) return current;
        if (input.ValueKind == JsonValueKind.Null) return null;
        if (input.ValueKind != JsonValueKind.Number || !input.TryGetDecimal(out var value)) throw new ResourceOperationException(400);
        if (!PersonalNutritionTarget.Valid(value, maximum)) throw new ResourceOperationException(422);
        return value;
    }
}

public sealed record PersonalNutritionTargetResponse(decimal? DailyCaloriesTargetKcal, decimal? DailyProteinTargetGrams,
    decimal? DailyCarbsTargetGrams, decimal? DailyFatTargetGrams, decimal? DailyWaterTargetMl, string Source = "personal")
{
    internal static PersonalNutritionTargetResponse From(PersonalNutritionTarget? row) => new(row?.DailyCaloriesTargetKcal,
        row?.DailyProteinTargetGrams, row?.DailyCarbsTargetGrams, row?.DailyFatTargetGrams, row?.DailyWaterTargetMl);
}
