using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using SmartNutrition.Api.Features.MealLogs;
using SmartNutrition.Api.Features.Relationships;

namespace SmartNutrition.Api.Features.NutritionPlans;

public sealed class NutritionPlanItemRequest
{
    public int? DayOfWeek { get; init; }
    [JsonRequired] public MealType MealType { get; init; }
    [JsonRequired] public string? Description { get; init; }
    public string? RecommendedQuantity { get; init; }
    [JsonRequired] public int SortOrder { get; init; }
    public Guid? RecipeId { get; init; }
    public Guid? AlternativeGroupId { get; init; }
}
public sealed class CreateNutritionPlanRequest
{
    private Guid? _clientId;
    public Guid? ClientId { get => _clientId; init { _clientId = value; ClientIdSpecified = true; } }
    internal bool ClientIdSpecified { get; private set; }
    [JsonRequired] public string? Title { get; init; }
    [JsonRequired] public DateOnly StartDate { get; init; }
    public DateOnly? EndDate { get; init; }
    public decimal? DailyCaloriesTargetKcal { get; init; }
    public decimal? DailyWaterTargetMl { get; init; }
    [JsonRequired] public IReadOnlyList<NutritionPlanItemRequest>? Items { get; init; }
}
public sealed class PatchNutritionPlanRequest
{
    public JsonElement Title { get; init; }
    public JsonElement StartDate { get; init; }
    public JsonElement EndDate { get; init; }
    public JsonElement DailyCaloriesTargetKcal { get; init; }
    public JsonElement DailyWaterTargetMl { get; init; }
    public JsonElement Items { get; init; }
}

internal static class NutritionPlanValidation
{
    private static bool Text(string? value, int max) => !string.IsNullOrWhiteSpace(value) && value.Trim().EnumerateRunes().Count() <= max;
    internal static NutritionPlanSnapshot Create(Guid planId, CreateNutritionPlanRequest request)
    {
        if (!Text(request.Title, 120) || request.EndDate < request.StartDate || request.DailyCaloriesTargetKcal <= 0 || request.DailyWaterTargetMl <= 0 ||
            request.Items is null || request.Items.Count is < 1 or > 100) throw new ResourceOperationException(422);
        var items = request.Items.Select(item =>
        {
            if (item is null || !Enum.IsDefined(item.MealType) || !Text(item.Description, 2000) || item.SortOrder < 0 || item.DayOfWeek is < 1 or > 7 ||
                item.RecipeId is not null || item.AlternativeGroupId == Guid.Empty || item.RecommendedQuantity?.Trim().EnumerateRunes().Count() > 200)
                throw new ResourceOperationException(422);
            return new NutritionPlanItem(Guid.NewGuid(), planId, item.DayOfWeek, item.MealType, item.Description!.Trim(),
                string.IsNullOrWhiteSpace(item.RecommendedQuantity) ? null : item.RecommendedQuantity.Trim(), item.SortOrder, null, item.AlternativeGroupId);
        }).OrderBy(x => x.SortOrder).ToList();
        if (items.Select(x => x.SortOrder).Distinct().Count() != items.Count || items.Where(x => x.AlternativeGroupId is not null).GroupBy(x => x.AlternativeGroupId)
            .Any(group => group.Count() < 2 || group.Select(x => (x.DayOfWeek, x.MealType)).Distinct().Count() != 1)) throw new ResourceOperationException(422);
        return new(request.Title!.Trim(), request.StartDate, request.EndDate, request.DailyCaloriesTargetKcal, request.DailyWaterTargetMl, items);
    }
    internal static NutritionPlanSnapshot Patch(NutritionPlan plan, PatchNutritionPlanRequest request)
    {
        var fields = new[] { request.Title, request.StartDate, request.EndDate, request.DailyCaloriesTargetKcal, request.DailyWaterTargetMl, request.Items };
        if (fields.All(x => x.ValueKind == JsonValueKind.Undefined)) throw new ResourceOperationException(400);
        if (request.Title.ValueKind == JsonValueKind.Null || request.StartDate.ValueKind == JsonValueKind.Null || request.Items.ValueKind == JsonValueKind.Null)
            throw new ResourceOperationException(422);
        var current = plan.Snapshot();
        try
        {
            T Read<T>(JsonElement field, T fallback) => field.ValueKind == JsonValueKind.Undefined ? fallback : field.Deserialize<T>(NutritionPlan.Json)!;
            var items = current.Items.Select(x => new NutritionPlanItemRequest { DayOfWeek = x.DayOfWeek, MealType = x.MealType, Description = x.Description,
                RecommendedQuantity = x.RecommendedQuantity, SortOrder = x.SortOrder, RecipeId = x.RecipeId, AlternativeGroupId = x.AlternativeGroupId }).ToList();
            return Create(plan.Id, new CreateNutritionPlanRequest { Title = Read(request.Title, current.Title), StartDate = Read(request.StartDate, current.StartDate),
                EndDate = Read(request.EndDate, current.EndDate), DailyCaloriesTargetKcal = Read(request.DailyCaloriesTargetKcal, current.DailyCaloriesTargetKcal),
                DailyWaterTargetMl = Read(request.DailyWaterTargetMl, current.DailyWaterTargetMl), Items = Read<IReadOnlyList<NutritionPlanItemRequest>>(request.Items, items) });
        }
        catch (JsonException) { throw new ResourceOperationException(400); }
    }
}
