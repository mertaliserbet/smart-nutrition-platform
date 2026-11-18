using System.Text.Json;
using System.Text.Json.Serialization;
using SmartNutrition.Api.Features.MealLogs;

namespace SmartNutrition.Api.Features.HealthData;

public sealed class CreateWearableConnectionRequest
{
    [JsonRequired] public string Provider { get; init; } = "";
}
[JsonNumberHandling(JsonNumberHandling.Strict)]
public sealed class PatchWearableConnectionRequest
{
    [JsonRequired] public int ExpectedVersionNumber { get; init; }
    [JsonRequired] public string Status { get; init; } = "";
}
public sealed record WearableConnectionResponse(Guid Id, Guid ClientId, string Provider, string Status, int VersionNumber,
    DateTimeOffset? LastSyncedAt, DateTimeOffset? LastAttemptAt, string LastSyncStatus, string? LastErrorCode)
{
    internal static WearableConnectionResponse From(WearableConnection c) => new(c.Id, c.ClientId, c.Provider, c.Status,
        c.VersionNumber, c.LastSyncedAt, c.LastAttemptAt, c.LastSyncStatus, c.LastErrorCode);
}
public sealed class WearableSyncRequest
{
    [JsonRequired] public Guid WearableConnectionId { get; init; }
    [JsonRequired] public Guid BatchId { get; init; }
    [JsonRequired] public List<WearableRecordChange> Changes { get; init; } = [];
}
[JsonNumberHandling(JsonNumberHandling.Strict)]
public sealed class WearableRecordChange
{
    [JsonRequired] public string Operation { get; init; } = "";
    [JsonRequired] public string Metric { get; init; } = "";
    [JsonRequired] public string SourceId { get; init; } = "";
    [JsonRequired] public string ExternalRecordId { get; init; } = "";
    [JsonRequired] public string RawType { get; init; } = "";
    [JsonRequired] public int ExpectedVersionNumber { get; init; }
    public string? SourceName { get; init; }
    public string? RecordingMethod { get; init; }
    public string? ExerciseType { get; init; }
    public string? RawUnit { get; init; }
    public List<HealthSampleInput>? Samples { get; init; }
    // Explicit point removal; an omitted point is never interpreted as deletion.
    public List<string>? DeletedSampleStarts { get; init; }
}
[JsonNumberHandling(JsonNumberHandling.Strict)]
public sealed class HealthSampleInput
{
    [JsonRequired, JsonConverter(typeof(MealLogInstantJsonConverter))] public DateTimeOffset StartedAt { get; init; }
    [JsonRequired, JsonConverter(typeof(MealLogInstantJsonConverter))] public DateTimeOffset EndedAt { get; init; }
    [JsonRequired] public decimal RawValue { get; init; }
}
public sealed record WearableSyncResult(Guid BatchId, Guid WearableConnectionId, DateTimeOffset CommittedAt, IReadOnlyList<WearableRecordResponse> Records);
public sealed record WearableRecordResponse(Guid Id, Guid ClientId, Guid WearableConnectionId, string Provider, string Metric,
    string SourceId, string ExternalRecordId, string RawType, string RawUnit, string? SourceName, string? RecordingMethod,
    string? ExerciseType, int VersionNumber, bool IsDeleted, DateTimeOffset UpdatedAt)
{
    internal static WearableRecordResponse From(WearableRecord r, string provider) => new(r.Id, r.ClientId, r.WearableConnectionId,
        provider, r.Metric, r.SourceId, r.ExternalRecordId, r.RawType, r.RawUnit, r.SourceName, r.RecordingMethod,
        r.ExerciseType, r.VersionNumber, r.IsDeleted, r.UpdatedAt);
}
public sealed record HealthMetricSampleResponse(Guid Id, Guid WearableRecordId, string Metric, DateTimeOffset StartedAt,
    DateTimeOffset EndedAt, decimal RawValue, string RawUnit, decimal Value, string Unit, bool IsDeleted);

[JsonNumberHandling(JsonNumberHandling.Strict)]
public class ActivityInput
{
    [JsonRequired] public string ActivityType { get; init; } = "";
    [JsonRequired, JsonConverter(typeof(MealLogInstantJsonConverter))] public DateTimeOffset StartedAt { get; init; }
    [JsonRequired] public decimal? DurationMinutes { get; init; }
    [JsonRequired] public decimal? DistanceKm { get; init; }
    [JsonRequired] public decimal? CaloriesKcal { get; init; }
}
public sealed class CreateActivityLogRequest : ActivityInput
{
    [JsonRequired] public string Source { get; init; } = "";
}
public sealed class PatchActivityLogRequest : ActivityInput
{
    [JsonRequired] public int ExpectedVersionNumber { get; init; }
}
public sealed record ActivityLogResponse(Guid Id, Guid ClientId, string ActivityType, DateTimeOffset StartedAt, DateTimeOffset? EndedAt,
    decimal? DurationMinutes, decimal? RawDurationMinutes, decimal? DistanceKm, decimal? CaloriesKcal, string Source, Guid? WearableConnectionId,
    Guid? WearableRecordId, string? ExternalRecordId, int VersionNumber, DateTimeOffset CreatedAt, DateTimeOffset UpdatedAt)
{
    internal static ActivityLogResponse From(ActivityLog r) => new(r.Id, r.ClientId, r.ActivityType, r.StartedAt, r.EndedAt,
        r.DurationMinutes, r.RawDurationMinutes, r.DistanceKm, r.CaloriesKcal, r.Source, r.WearableConnectionId, r.WearableRecordId,
        r.ExternalRecordId, r.VersionNumber, r.CreatedAt, r.UpdatedAt);
}
public sealed record ActivityDailySummaryResponse(DateTimeOffset From, DateTimeOffset To, decimal? Steps, decimal? DistanceKm,
    decimal? ActiveEnergyKcal, decimal? ExerciseMinutes, int ExerciseCount, int HeartRateSampleCount, decimal? HeartRateMeanBpm,
    decimal? HeartRateMinBpm, decimal? HeartRateMaxBpm, int ExcludedOverlapCount, int UnallocatedCount, bool IsPartial, string CalculationPolicy);

internal static class HealthJson
{
    internal static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web);
}
