using System.Globalization;
using SmartNutrition.Api.Features.MealLogs;
using SmartNutrition.Api.Features.Relationships;

namespace SmartNutrition.Api.Features.HealthData;

internal sealed record NormalizedSample(string Key, DateTimeOffset StartedAt, DateTimeOffset EndedAt, decimal RawValue, decimal Value, string Unit);
internal sealed record NormalizedChange(string Operation, string Metric, string SourceId, string ExternalRecordId, string RawType,
    int ExpectedVersionNumber, string? SourceName, string? RecordingMethod, string? ExerciseType, string RawUnit,
    NormalizedSample[] Samples, string[] DeletedKeys);

internal static class HealthDataValidation
{
    internal const int MaximumChanges = 100;
    internal const int MaximumSamples = 1000;
    internal const int MaximumSummaryRows = 100000;
    internal static void Fail(string code, int status = 422) => throw new ResourceOperationException(status, code);
    internal static bool Text(string? text, int maximum = 200) => !string.IsNullOrWhiteSpace(text) && text == text.Trim() &&
        !text.Any(char.IsControl) && text.EnumerateRunes().Count() <= maximum;
    internal static bool OptionalText(string? text, int maximum = 200) => text is null || Text(text, maximum);
    internal static void Provider(string value)
    {
        if (value is not ("health_connect" or "health_kit")) Fail("unsupported_provider");
    }
    internal static string RawUnit(string metric) => metric switch
    {
        "steps" => "COUNT", "distance" => "METER", "exercise" => "MINUTE", "active_energy" => "KILOCALORIE",
        "heart_rate" => "BEATS_PER_MINUTE", _ => throw new ResourceOperationException(422, "unsupported_metric")
    };
    internal static NormalizedChange[] Normalize(WearableSyncRequest request, string provider, DateTimeOffset now)
    {
        if (request.BatchId == Guid.Empty || request.WearableConnectionId == Guid.Empty || request.Changes is null || request.Changes.Count == 0)
            Fail("invalid_sync_batch");
        if (request.Changes!.Count > MaximumChanges || request.Changes.Sum(c => (long)(c?.Samples?.Count ?? 0) + (c?.DeletedSampleStarts?.Count ?? 0)) > MaximumSamples)
            Fail("sync_batch_limit", 413);
        var result = request.Changes.Select(c => Normalize(c, provider, now)).ToArray();
        if (result.Select(c => (c.SourceId, c.RawType, c.ExternalRecordId)).Distinct().Count() != result.Length) Fail("duplicate_source_record");
        return result;
    }
    private static NormalizedChange Normalize(WearableRecordChange? c, string provider, DateTimeOffset now)
    {
        if (c is null) throw new ResourceOperationException(422, "invalid_sync_batch");
        var rawUnit = RawUnit(c.Metric);
        if (!Text(c.SourceId) || !Text(c.ExternalRecordId) || !Text(c.RawType, 64)) Fail("invalid_source_identity");
        var validType = c.Metric switch
        {
            "steps" => c.RawType == "STEPS",
            "exercise" => c.RawType == "WORKOUT",
            "active_energy" => c.RawType == "ACTIVE_ENERGY_BURNED",
            "heart_rate" => c.RawType == "HEART_RATE",
            "distance" => provider == "health_connect" ? c.RawType == "DISTANCE_DELTA" : c.RawType is "DISTANCE_WALKING_RUNNING" or "DISTANCE_CYCLING" or "DISTANCE_SWIMMING",
            _ => false
        };
        if (!validType) Fail("unsupported_source_type");
        if (c.ExpectedVersionNumber < 0 || c.Operation is not ("upsert" or "delete")) Fail("invalid_sync_batch");
        if (c.Operation == "delete")
        {
            if (c.Samples is not null || c.DeletedSampleStarts is not null || c.RawUnit is not null || c.SourceName is not null || c.RecordingMethod is not null || c.ExerciseType is not null)
                Fail("invalid_sync_batch");
            return new(c.Operation, c.Metric, c.SourceId, c.ExternalRecordId, c.RawType, c.ExpectedVersionNumber, null, null, null, rawUnit, [], []);
        }
        if (c.RawUnit != rawUnit) Fail("unsupported_unit");
        if (!Text(c.SourceName) || !Text(c.RecordingMethod, 64) || !OptionalText(c.ExerciseType) || (c.Metric == "exercise") != (c.ExerciseType is not null)) Fail("invalid_source_identity");
        var samples = (c.Samples ?? []).Select(s => Sample(s, c.Metric, now)).OrderBy(s => s.Key, StringComparer.Ordinal).ToArray();
        var deleted = (c.DeletedSampleStarts ?? []).Select(t =>
        {
            if (!MealLogInstantJsonConverter.TryParse(t, out var instant) || instant == default) throw new ResourceOperationException(422, "invalid_interval");
            return PointKey(RecordTime.Normalize(instant));
        }).Order(StringComparer.Ordinal).ToArray();
        if (c.Metric != "heart_rate" && (samples.Length != 1 || deleted.Length != 0) || samples.Length + deleted.Length == 0 ||
            samples.Select(s => s.Key).Distinct().Count() != samples.Length || deleted.Distinct().Count() != deleted.Length || samples.Any(s => deleted.Contains(s.Key))) Fail("invalid_sync_batch");
        return new(c.Operation, c.Metric, c.SourceId, c.ExternalRecordId, c.RawType, c.ExpectedVersionNumber, c.SourceName,
            c.RecordingMethod, c.ExerciseType, rawUnit, samples, deleted);
    }
    internal static string PointKey(DateTimeOffset value) => value.UtcTicks.ToString(CultureInfo.InvariantCulture);
    private static NormalizedSample Sample(HealthSampleInput? sample, string metric, DateTimeOffset now)
    {
        if (sample is null) throw new ResourceOperationException(422, "invalid_value");
        var start = RecordTime.Normalize(sample.StartedAt); var end = RecordTime.Normalize(sample.EndedAt);
        Interval(start, end, now, metric == "heart_rate");
        if (metric == "heart_rate" && start != end) Fail("invalid_interval");
        if (sample.RawValue is < 0 or > 1000000000000m || metric == "steps" && decimal.Truncate(sample.RawValue) != sample.RawValue || metric is "heart_rate" or "exercise" && sample.RawValue == 0) Fail("invalid_value");
        var duration = (end - start).Ticks / (decimal)TimeSpan.TicksPerMinute;
        if (metric == "exercise" && Math.Abs(sample.RawValue - duration) > 1m / 60000m) Fail("duration_mismatch");
        return new(metric == "heart_rate" ? PointKey(start) : "single", start, end, sample.RawValue,
            metric == "distance" ? sample.RawValue / 1000m : metric == "exercise" ? duration : sample.RawValue,
            metric switch { "steps" => "count", "distance" => "km", "active_energy" => "kcal", "heart_rate" => "bpm", _ => "minutes" });
    }
    private static void Interval(DateTimeOffset start, DateTimeOffset end, DateTimeOffset now, bool allowPoint = false)
    {
        if (start == default || end == default || end < start || !allowPoint && end == start || end - start > TimeSpan.FromDays(7) || end > now.AddMinutes(5)) Fail("invalid_interval");
    }
    internal static (DateTimeOffset Start, DateTimeOffset? End) Activity(ActivityInput input, DateTimeOffset now)
    {
        if (!Text(input.ActivityType) || input.DurationMinutes is null && input.DistanceKm is null && input.CaloriesKcal is null ||
            input.DurationMinutes is <= 0 or > 10080 || input.DistanceKm is < 0 or > 1000000000000m || input.CaloriesKcal is < 0 or > 1000000000000m) Fail("invalid_value");
        var start = RecordTime.Normalize(input.StartedAt);
        DateTimeOffset? end = null;
        if (input.DurationMinutes is { } duration)
        {
            try { end = RecordTime.Normalize(start.AddTicks(decimal.ToInt64(decimal.Round(duration * TimeSpan.TicksPerMinute, 0)))); }
            catch (ArgumentOutOfRangeException) { Fail("invalid_interval"); }
            Interval(start, end!.Value, now);
        }
        else if (start == default || start > now.AddMinutes(5)) Fail("invalid_interval");
        return (start, end);
    }
}

internal static class HealthDataErrors
{
    internal static readonly IReadOnlyDictionary<string, string> Messages = new Dictionary<string, string>
    {
        ["unsupported_provider"] = "Use health_connect or health_kit.",
        ["unsupported_metric"] = "The health metric is not supported.",
        ["unsupported_source_type"] = "The native record type does not match this provider and metric.",
        ["unsupported_unit"] = "Use the documented raw unit for this metric.",
        ["invalid_source_identity"] = "Valid source application, record identity and metadata are required.",
        ["invalid_interval"] = "Use explicit-offset instants, a valid interval of at most seven days, and no future data beyond five minutes.",
        ["invalid_value"] = "The measurement or activity value is invalid.",
        ["duration_mismatch"] = "Exercise minutes must match its start/end interval within one millisecond.",
        ["invalid_sync_batch"] = "Provide a non-empty, valid batch with explicit operations.",
        ["sync_batch_limit"] = "At most 100 record changes and 1000 sample operations are allowed.",
        ["duplicate_source_record"] = "Combine changes for each native record into a single operation.",
        ["sync_batch_conflict"] = "This batch ID was already used with a different request.",
        ["source_version_conflict"] = "Read the current record version before retrying this change.",
        ["sync_disabled"] = "Transfer is revoked for this connection.",
        ["source_record_read_only"] = "Change a wearable activity through native-record synchronization.",
        ["aggregation_limit_exceeded"] = "This summary exceeds the bounded calculation limit.",
    };
}
