using System.Text.Json;
using System.Text.Json.Serialization;
using SmartNutrition.Api.Features.MealLogs;
using SmartNutrition.Api.Features.Relationships;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Features.BodyMeasurements;

[JsonNumberHandling(JsonNumberHandling.Strict)]
public sealed class CreateBodyMeasurementRequest
{
    [JsonRequired, JsonConverter(typeof(MealLogInstantJsonConverter))] public DateTimeOffset MeasuredAt { get; init; }
    [JsonRequired] public RecordSource Source { get; init; }
    public decimal? WeightKg { get; init; }
    public decimal? WaistCm { get; init; }
    public decimal? HipCm { get; init; }
    public decimal? ChestCm { get; init; }
    public decimal? BodyFatPercent { get; init; }
    public string? Note { get; init; }
}
public sealed class PatchBodyMeasurementRequest
{
    public JsonElement MeasuredAt { get; init; }
    public JsonElement WeightKg { get; init; }
    public JsonElement WaistCm { get; init; }
    public JsonElement HipCm { get; init; }
    public JsonElement ChestCm { get; init; }
    public JsonElement BodyFatPercent { get; init; }
    public JsonElement Note { get; init; }
}
public sealed record BodyMeasurementResponse(Guid Id, Guid ClientId, DateTimeOffset MeasuredAt, decimal? WeightKg,
    decimal? WaistCm, decimal? HipCm, decimal? ChestCm, decimal? BodyFatPercent, string? Note, RecordSource Source)
{
    internal static BodyMeasurementResponse From(BodyMeasurement row) => new(row.Id, row.ClientId, row.MeasuredAt,
        row.WeightKg, row.WaistCm, row.HipCm, row.ChestCm, row.BodyFatPercent, row.Note, row.Source);
}
internal static class BodyMeasurementValidation
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        NumberHandling = JsonNumberHandling.Strict,
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow,
        Converters = { new MealLogInstantJsonConverter() }
    };
    internal static BodyMeasurement Create(Guid id, Guid clientId, CreateBodyMeasurementRequest request)
    {
        if (request.Source != RecordSource.Manual || !BodyMeasurement.Valid(request.MeasuredAt, request.WeightKg,
            request.WaistCm, request.HipCm, request.ChestCm, request.BodyFatPercent, request.Note)) throw new ResourceOperationException(422);
        return new(id, clientId, request.MeasuredAt, request.Source, request.WeightKg, request.WaistCm, request.HipCm, request.ChestCm, request.BodyFatPercent, request.Note);
    }
    internal static BodyMeasurement Patch(BodyMeasurement row, PatchBodyMeasurementRequest request)
    {
        var fields = new[] { request.MeasuredAt, request.WeightKg, request.WaistCm, request.HipCm, request.ChestCm, request.BodyFatPercent, request.Note };
        if (fields.All(x => x.ValueKind == JsonValueKind.Undefined)) throw new ResourceOperationException(400);
        if (request.MeasuredAt.ValueKind == JsonValueKind.Null) throw new ResourceOperationException(422);
        try
        {
            T Read<T>(JsonElement field, T fallback) => field.ValueKind == JsonValueKind.Undefined ? fallback : field.Deserialize<T>(Json)!;
            return Create(row.Id, row.ClientId, new CreateBodyMeasurementRequest
            {
                MeasuredAt = Read(request.MeasuredAt, row.MeasuredAt), Source = row.Source,
                WeightKg = Read(request.WeightKg, row.WeightKg), WaistCm = Read(request.WaistCm, row.WaistCm),
                HipCm = Read(request.HipCm, row.HipCm), ChestCm = Read(request.ChestCm, row.ChestCm),
                BodyFatPercent = Read(request.BodyFatPercent, row.BodyFatPercent), Note = Read(request.Note, row.Note)
            });
        }
        catch (JsonException) { throw new ResourceOperationException(400); }
    }
}
