using System.Text.Json;
using System.Text.Json.Serialization;
using SmartNutrition.Api.Features.MealLogs;
using SmartNutrition.Api.Features.Relationships;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Features.WaterLogs;

[JsonNumberHandling(JsonNumberHandling.Strict)]
public sealed class CreateWaterLogRequest
{
    [JsonRequired] public decimal AmountMl { get; init; }
    [JsonRequired, JsonConverter(typeof(MealLogInstantJsonConverter))] public DateTimeOffset ConsumedAt { get; init; }
    [JsonRequired] public RecordSource Source { get; init; }
}
public sealed class PatchWaterLogRequest
{
    public JsonElement AmountMl { get; init; }
    public JsonElement ConsumedAt { get; init; }
}
public sealed record WaterLogResponse(Guid Id, Guid ClientId, decimal AmountMl, DateTimeOffset ConsumedAt, RecordSource Source)
{
    internal static WaterLogResponse From(WaterLog row) => new(row.Id, row.ClientId, row.AmountMl, row.ConsumedAt, row.Source);
}
public sealed record WaterLogDailyTotalResponse(DateTimeOffset From, DateTimeOffset To, decimal TotalAmountMl);

internal static class WaterLogValidation
{
    // Reuse MealLog's explicit-offset parser unchanged; neither source changes Auth or its refresh behavior.
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        NumberHandling = JsonNumberHandling.Strict,
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow,
        Converters = { new MealLogInstantJsonConverter() }
    };
    internal static void Values(decimal amountMl, DateTimeOffset consumedAt)
    {
        if (amountMl <= 0 || consumedAt == default) throw new ResourceOperationException(422);
    }
    internal static (decimal AmountMl, DateTimeOffset ConsumedAt) Patch(WaterLog row, PatchWaterLogRequest request)
    {
        if (request.AmountMl.ValueKind == JsonValueKind.Undefined && request.ConsumedAt.ValueKind == JsonValueKind.Undefined)
            throw new ResourceOperationException(400);
        if (request.AmountMl.ValueKind == JsonValueKind.Null || request.ConsumedAt.ValueKind == JsonValueKind.Null)
            throw new ResourceOperationException(422);
        try
        {
            var amount = request.AmountMl.ValueKind == JsonValueKind.Undefined ? row.AmountMl : request.AmountMl.Deserialize<decimal>(Json);
            var consumedAt = request.ConsumedAt.ValueKind == JsonValueKind.Undefined ? row.ConsumedAt : request.ConsumedAt.Deserialize<DateTimeOffset>(Json);
            Values(amount, consumedAt);
            return (amount, consumedAt);
        }
        catch (JsonException) { throw new ResourceOperationException(400); }
    }
}
