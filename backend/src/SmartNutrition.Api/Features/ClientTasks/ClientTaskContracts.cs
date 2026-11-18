using System.Text.Json;
using System.Text.Json.Serialization;
using SmartNutrition.Api.Features.MealLogs;
using SmartNutrition.Api.Features.Relationships;

namespace SmartNutrition.Api.Features.ClientTasks;

public sealed class CreateClientTaskRequest
{
    [JsonRequired] public Guid ClientId { get; init; }
    [JsonRequired] public string? Description { get; init; }
    [JsonConverter(typeof(ClientTaskDueAtJsonConverter))] public DateTimeOffset? DueAt { get; init; }
}
public sealed class PatchClientTaskRequest
{
    [JsonRequired] public int ExpectedVersionNumber { get; init; }
    public JsonElement Description { get; init; }
    public JsonElement DueAt { get; init; }
    public JsonElement Status { get; init; }
    public JsonElement IsReminderEnabled { get; init; }
}
public sealed record ClientTaskResponse(Guid Id, Guid ClientId, Guid DietitianId, Guid RelationshipId, string Description,
    ClientTaskStatus Status, DateTimeOffset? DueAt, bool IsReminderEnabled, DateTimeOffset CreatedAt, DateTimeOffset UpdatedAt, int VersionNumber)
{
    internal static ClientTaskResponse From(ClientTask row) => new(row.Id, row.ClientId, row.DietitianId, row.RelationshipId,
        row.Description, row.Status, row.DueAt, row.IsReminderEnabled, row.CreatedAt, row.UpdatedAt, row.VersionNumber);
}
public sealed record ClientTaskVersionResponse(Guid Id, Guid ClientTaskId, int VersionNumber, DateTimeOffset CreatedAt, ClientTaskResponse Snapshot)
{
    internal static ClientTaskVersionResponse From(ClientTaskVersion row) => new(row.Id, row.ClientTaskId, row.VersionNumber, row.CreatedAt,
        JsonSerializer.Deserialize<ClientTaskResponse>(row.SnapshotJson, ClientTaskVersion.Json) ?? throw new InvalidOperationException("Task history is unavailable."));
}
internal sealed class ClientTaskDueAtJsonConverter : JsonConverter<DateTimeOffset?>
{
    public override DateTimeOffset? Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options) =>
        reader.TokenType == JsonTokenType.Null ? null : reader.TokenType == JsonTokenType.String && MealLogInstantJsonConverter.TryParse(reader.GetString(), out var time)
            ? time : throw new JsonException("An ISO 8601 instant with an explicit offset is required.");
    public override void Write(Utf8JsonWriter writer, DateTimeOffset? value, JsonSerializerOptions options)
    { if (value is null) writer.WriteNullValue(); else writer.WriteStringValue(value.Value.ToUniversalTime()); }
}
internal static class ClientTaskValidation
{
    internal static string Description(string? text)
    {
        var value = text?.Trim();
        if (string.IsNullOrWhiteSpace(value) || value.Contains('\0') || value.EnumerateRunes().Count() > 2000) throw new ResourceOperationException(422);
        return value;
    }
    internal static DateTimeOffset? DueAt(DateTimeOffset? time, DateTimeOffset now)
    {
        if (time is null) return null;
        var value = RecordTime.Normalize(time.Value);
        if (value <= now || value >= RecordTime.Normalize(DateTimeOffset.MaxValue)) throw new ResourceOperationException(422);
        return value;
    }
    internal static DateTimeOffset? ReadDueAt(JsonElement field)
    {
        if (field.ValueKind == JsonValueKind.Null) return null;
        if (field.ValueKind != JsonValueKind.String || !MealLogInstantJsonConverter.TryParse(field.GetString(), out var value)) throw new ResourceOperationException(400);
        return value;
    }
}
