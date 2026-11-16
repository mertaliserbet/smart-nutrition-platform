using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using SmartNutrition.Api.Features.Relationships;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Features.MealLogs;

[JsonNumberHandling(JsonNumberHandling.Strict)]
public sealed class MealLogItemRequest
{
    [JsonRequired] public string? DisplayName { get; init; }
    [JsonRequired] public bool IsEstimated { get; init; }
    public Guid? FoodItemId { get; init; }
    public Guid? RecipeId { get; init; }
    public decimal? QuantityGrams { get; init; }
    public decimal? CaloriesKcal { get; init; }
    public decimal? ProteinGrams { get; init; }
    public decimal? CarbsGrams { get; init; }
    public decimal? FatGrams { get; init; }
}

public sealed class CreateMealLogRequest
{
    [JsonRequired] public MealType MealType { get; init; }
    [JsonRequired, JsonConverter(typeof(MealLogInstantJsonConverter))] public DateTimeOffset ConsumedAt { get; init; }
    [JsonRequired] public RecordSource Source { get; init; }
    [JsonRequired] public IReadOnlyList<MealLogItemRequest>? Items { get; init; }
    public string? Note { get; init; }
    public Guid? FoodAnalysisId { get; init; }
}

public sealed class PatchMealLogRequest
{
    public JsonElement MealType { get; init; }
    public JsonElement ConsumedAt { get; init; }
    public JsonElement Items { get; init; }
    public JsonElement Note { get; init; }
    public JsonElement FoodAnalysisId { get; init; }
}

public sealed record MealLogItemResponse(Guid Id, Guid MealLogId, Guid? FoodItemId, Guid? RecipeId,
    string DisplayName, decimal? QuantityGrams, decimal? CaloriesKcal, decimal? ProteinGrams,
    decimal? CarbsGrams, decimal? FatGrams, bool IsEstimated);

public sealed record MealLogResponse(Guid Id, Guid ClientId, MealType MealType, DateTimeOffset ConsumedAt,
    string? Note, RecordSource Source, Guid? FoodAnalysisId, DateTimeOffset CreatedAt, IReadOnlyList<MealLogItemResponse> Items)
{
    internal static MealLogResponse From(MealLog log) => new(log.Id, log.ClientId, log.MealType, log.ConsumedAt,
        log.Note, log.Source, log.FoodAnalysisId, log.CreatedAt, log.Items.Select(item => new MealLogItemResponse(
            item.Id, item.MealLogId, item.FoodItemId, item.RecipeId, item.DisplayName, item.QuantityGrams,
            item.CaloriesKcal, item.ProteinGrams, item.CarbsGrams, item.FatGrams, item.IsEstimated)).ToArray());
}

public sealed class MealLogInstantJsonConverter : JsonConverter<DateTimeOffset>
{
    internal static bool TryParse(string? text, out DateTimeOffset result)
    {
        result = default;
        return text is not null && Regex.IsMatch(text,
            @"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?(?:Z|[+-]\d{2}:\d{2})$", RegexOptions.CultureInvariant) &&
            DateTimeOffset.TryParse(text, CultureInfo.InvariantCulture, DateTimeStyles.None, out result);
    }

    public override DateTimeOffset Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options) =>
        reader.TokenType == JsonTokenType.String && TryParse(reader.GetString(), out var value)
            ? value : throw new JsonException("An ISO 8601 instant with an explicit offset is required.");
    public override void Write(Utf8JsonWriter writer, DateTimeOffset value, JsonSerializerOptions options) => writer.WriteStringValue(value.ToUniversalTime());
}

internal static class MealLogValidation
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow,
        Converters = { new MealLogInstantJsonConverter() }
    };

    internal static MealLog Create(Guid id, Guid clientId, DateTimeOffset createdAt, CreateMealLogRequest request)
    {
        // Catalog/recipe/AI resources do not exist yet. An unverified UUID must not
        // create a dangling reference or imply an approved analysis/sync flow.
        if (!Enum.IsDefined(request.MealType) || request.ConsumedAt == default || request.Source != RecordSource.Manual ||
            request.FoodAnalysisId is not null || request.Items is null || request.Items.Count is < 1 or > 100 ||
            request.Note is not null && !ValidText(request.Note, allowEmpty: true))
            throw new ResourceOperationException(422);
        var items = request.Items.Select(item =>
        {
            if (item is null || !ValidText(item.DisplayName) || item.FoodItemId is not null || item.RecipeId is not null ||
                item.QuantityGrams <= 0 || item.CaloriesKcal < 0 || item.ProteinGrams < 0 || item.CarbsGrams < 0 || item.FatGrams < 0)
                throw new ResourceOperationException(422);
            return new MealLogItem(Guid.NewGuid(), id, item.DisplayName!.Trim(), item.IsEstimated, item.QuantityGrams,
                item.CaloriesKcal, item.ProteinGrams, item.CarbsGrams, item.FatGrams);
        }).ToArray();
        return new MealLog(id, clientId, request.MealType, RecordTime.Normalize(request.ConsumedAt), request.Source,
            createdAt, items, request.Note);
    }

    internal static MealLog Patch(MealLog current, PatchMealLogRequest request)
    {
        var fields = new[] { request.MealType, request.ConsumedAt, request.Items, request.Note, request.FoodAnalysisId };
        if (fields.All(x => x.ValueKind == JsonValueKind.Undefined)) throw new ResourceOperationException(400);
        if (request.MealType.ValueKind == JsonValueKind.Null || request.ConsumedAt.ValueKind == JsonValueKind.Null || request.Items.ValueKind == JsonValueKind.Null)
            throw new ResourceOperationException(422);
        try
        {
            T Read<T>(JsonElement field, T fallback) => field.ValueKind == JsonValueKind.Undefined ? fallback : field.Deserialize<T>(Json)!;
            var items = current.Items.Select(x => new MealLogItemRequest
            {
                DisplayName = x.DisplayName, IsEstimated = x.IsEstimated, FoodItemId = x.FoodItemId, RecipeId = x.RecipeId,
                QuantityGrams = x.QuantityGrams, CaloriesKcal = x.CaloriesKcal, ProteinGrams = x.ProteinGrams,
                CarbsGrams = x.CarbsGrams, FatGrams = x.FatGrams
            }).ToArray();
            return Create(current.Id, current.ClientId, current.CreatedAt, new CreateMealLogRequest
            {
                MealType = Read(request.MealType, current.MealType), ConsumedAt = Read(request.ConsumedAt, current.ConsumedAt),
                Source = current.Source, Items = Read<IReadOnlyList<MealLogItemRequest>>(request.Items, items),
                Note = Read(request.Note, current.Note), FoodAnalysisId = Read(request.FoodAnalysisId, current.FoodAnalysisId)
            });
        }
        catch (JsonException) { throw new ResourceOperationException(400); }
    }

    private static bool ValidText(string? text, bool allowEmpty = false) => text is not null &&
        (allowEmpty || !string.IsNullOrWhiteSpace(text)) && !text.Contains('\0') && text.EnumerateRunes().Count() <= 2000;
}
