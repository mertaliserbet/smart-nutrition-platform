using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata;
using SmartNutrition.Api.Features.Auth;

namespace SmartNutrition.Api.Features.HealthData;

public sealed class WearableConnection
{
    public Guid Id { get; internal set; }
    public Guid ClientId { get; internal set; }
    public string Provider { get; internal set; } = "";
    public string Status { get; internal set; } = "active";
    public int VersionNumber { get; internal set; } = 1;
    public DateTimeOffset? LastSyncedAt { get; internal set; }
    public DateTimeOffset? LastAttemptAt { get; internal set; }
    public string LastSyncStatus { get; internal set; } = "never";
    public string? LastErrorCode { get; internal set; }
}

// One native record can contain many heart-rate points. Its identity survives
// reconnects, edits and deletion; absence from a read window never deletes it.
public sealed class WearableRecord
{
    public Guid Id { get; internal set; }
    public Guid ClientId { get; internal set; }
    public Guid WearableConnectionId { get; internal set; }
    public string SourceId { get; internal set; } = "";
    public string ExternalRecordId { get; internal set; } = "";
    public string RawType { get; internal set; } = "";
    public string Metric { get; internal set; } = "";
    public string? SourceName { get; internal set; }
    public string? RecordingMethod { get; internal set; }
    public string? ExerciseType { get; internal set; }
    public string RawUnit { get; internal set; } = "";
    public int VersionNumber { get; internal set; }
    public bool IsDeleted { get; internal set; }
    public DateTimeOffset UpdatedAt { get; internal set; }
}

public sealed class HealthMetricSample
{
    public Guid Id { get; internal set; }
    public Guid ClientId { get; internal set; }
    public Guid WearableRecordId { get; internal set; }
    // "single" for scalar records; UTC ticks for points within a native HR record.
    public string SampleKey { get; internal set; } = "";
    public DateTimeOffset StartedAt { get; internal set; }
    public DateTimeOffset EndedAt { get; internal set; }
    public decimal RawValue { get; internal set; }
    public decimal Value { get; internal set; }
    public string Unit { get; internal set; } = "";
    public bool IsDeleted { get; internal set; }
}

public sealed class ActivityLog
{
    public Guid Id { get; internal set; }
    public Guid ClientId { get; internal set; }
    public string ActivityType { get; internal set; } = "";
    public DateTimeOffset StartedAt { get; internal set; }
    public DateTimeOffset? EndedAt { get; internal set; }
    public decimal? DurationMinutes { get; internal set; }
    public decimal? RawDurationMinutes { get; internal set; }
    public decimal? DistanceKm { get; internal set; }
    // Active energy only; never basal/total energy or a nutrition-target adjustment.
    public decimal? CaloriesKcal { get; internal set; }
    public string Source { get; internal set; } = "manual";
    public Guid? WearableConnectionId { get; internal set; }
    public Guid? WearableRecordId { get; internal set; }
    public string? ExternalRecordId { get; internal set; }
    public int VersionNumber { get; internal set; } = 1;
    public DateTimeOffset CreatedAt { get; internal set; }
    public DateTimeOffset UpdatedAt { get; internal set; }
    public bool IsDeleted { get; internal set; }
}

public sealed class WearableSyncBatch
{
    public Guid Id { get; internal set; }
    public Guid ClientId { get; internal set; }
    public Guid WearableConnectionId { get; internal set; }
    public Guid BatchId { get; internal set; }
    public string RequestHash { get; internal set; } = "";
    public string ResponseJson { get; internal set; } = "";
    public DateTimeOffset CommittedAt { get; internal set; }
}

internal static class HealthDataModel
{
    internal static void Configure(ModelBuilder builder)
    {
        var connections = builder.Entity<WearableConnection>();
        Map(connections, "wearable_connections");
        connections.HasAlternateKey(x => new { x.Id, x.ClientId });
        connections.HasIndex(x => new { x.ClientId, x.Provider }).IsUnique();
        connections.Property(x => x.Provider).HasMaxLength(20);
        connections.Property(x => x.Status).HasMaxLength(16);
        connections.Property(x => x.LastSyncStatus).HasMaxLength(16);
        connections.Property(x => x.LastErrorCode).HasMaxLength(64);
        connections.ToTable(t =>
        {
            t.HasCheckConstraint("ck_wearable_provider", "provider IN ('health_connect','health_kit')");
            t.HasCheckConstraint("ck_wearable_status", "status IN ('active','revoked') AND version_number > 0");
            t.HasCheckConstraint("ck_wearable_sync_status", "last_sync_status IN ('never','succeeded','failed') AND (last_sync_status <> 'succeeded' OR last_synced_at IS NOT NULL)");
        });

        var records = builder.Entity<WearableRecord>();
        Map(records, "wearable_records");
        records.HasAlternateKey(x => new { x.Id, x.ClientId });
        records.HasAlternateKey(x => new { x.Id, x.WearableConnectionId, x.ClientId });
        records.HasOne<WearableConnection>().WithMany().HasForeignKey(x => new { x.WearableConnectionId, x.ClientId })
            .HasPrincipalKey(x => new { x.Id, x.ClientId }).OnDelete(DeleteBehavior.Restrict);
        records.HasIndex(x => new { x.WearableConnectionId, x.SourceId, x.RawType, x.ExternalRecordId }).IsUnique();
        foreach (var name in new[] { nameof(WearableRecord.SourceId), nameof(WearableRecord.ExternalRecordId), nameof(WearableRecord.SourceName), nameof(WearableRecord.ExerciseType) })
            records.Property(name).HasMaxLength(200);
        foreach (var name in new[] { nameof(WearableRecord.RawType), nameof(WearableRecord.RecordingMethod), nameof(WearableRecord.RawUnit), nameof(WearableRecord.Metric) })
            records.Property(name).HasMaxLength(64);
        records.ToTable(t =>
        {
            t.HasCheckConstraint("ck_wearable_record_identity", "length(btrim(source_id)) > 0 AND length(btrim(external_record_id)) > 0 AND version_number > 0");
            t.HasCheckConstraint("ck_wearable_record_metric", "metric IN ('steps','distance','exercise','active_energy','heart_rate')");
            t.HasCheckConstraint("ck_wearable_record_unit", "(metric = 'steps' AND raw_unit = 'COUNT' AND raw_type = 'STEPS') OR (metric = 'distance' AND raw_unit = 'METER' AND raw_type IN ('DISTANCE_DELTA','DISTANCE_WALKING_RUNNING','DISTANCE_CYCLING','DISTANCE_SWIMMING')) OR (metric = 'exercise' AND raw_unit = 'MINUTE' AND raw_type = 'WORKOUT') OR (metric = 'active_energy' AND raw_unit = 'KILOCALORIE' AND raw_type = 'ACTIVE_ENERGY_BURNED') OR (metric = 'heart_rate' AND raw_unit = 'BEATS_PER_MINUTE' AND raw_type = 'HEART_RATE')");
        });

        var samples = builder.Entity<HealthMetricSample>();
        Map(samples, "health_metric_samples");
        samples.HasOne<WearableRecord>().WithMany().HasForeignKey(x => new { x.WearableRecordId, x.ClientId })
            .HasPrincipalKey(x => new { x.Id, x.ClientId }).OnDelete(DeleteBehavior.Restrict);
        samples.Property(x => x.SampleKey).HasMaxLength(32);
        samples.Property(x => x.Unit).HasMaxLength(16);
        samples.HasIndex(x => new { x.WearableRecordId, x.SampleKey }).IsUnique();
        samples.HasIndex(x => new { x.ClientId, x.StartedAt, x.Id });
        samples.ToTable(t =>
        {
            t.HasCheckConstraint("ck_health_sample_interval", "ended_at >= started_at AND ended_at - started_at <= interval '7 days'");
            t.HasCheckConstraint("ck_health_sample_value", "raw_value >= 0 AND raw_value <= 1000000000000 AND value >= 0 AND value <= 1000000000000 AND unit IN ('count','km','kcal','bpm') AND (unit <> 'count' OR value = trunc(value)) AND (unit <> 'bpm' OR value > 0)");
        });

        var activities = builder.Entity<ActivityLog>();
        Map(activities, "activity_logs");
        activities.Property(x => x.ActivityType).HasMaxLength(200);
        activities.Property(x => x.Source).HasMaxLength(16);
        activities.Property(x => x.ExternalRecordId).HasMaxLength(200);
        activities.HasOne<WearableConnection>().WithMany().HasForeignKey(x => new { x.WearableConnectionId, x.ClientId })
            .HasPrincipalKey(x => new { x.Id, x.ClientId }).OnDelete(DeleteBehavior.Restrict);
        activities.HasOne<WearableRecord>().WithMany().HasForeignKey(x => new { x.WearableRecordId, x.WearableConnectionId, x.ClientId })
            .HasPrincipalKey(x => new { x.Id, x.WearableConnectionId, x.ClientId }).OnDelete(DeleteBehavior.Restrict);
        activities.HasIndex(x => x.WearableRecordId).IsUnique();
        activities.HasIndex(x => new { x.ClientId, x.StartedAt, x.Id });
        activities.ToTable(t =>
        {
            t.HasCheckConstraint("ck_activity_source", "(source = 'manual' AND wearable_connection_id IS NULL AND wearable_record_id IS NULL AND external_record_id IS NULL AND raw_duration_minutes IS NULL) OR (source = 'wearable' AND wearable_connection_id IS NOT NULL AND wearable_record_id IS NOT NULL AND external_record_id IS NOT NULL AND raw_duration_minutes IS NOT NULL AND raw_duration_minutes > 0 AND raw_duration_minutes <= 10081)");
            t.HasCheckConstraint("ck_activity_values", "version_number > 0 AND length(btrim(activity_type)) > 0 AND (duration_minutes IS NOT NULL OR distance_km IS NOT NULL OR calories_kcal IS NOT NULL) AND (duration_minutes IS NULL OR (duration_minutes > 0 AND duration_minutes <= 10080)) AND (distance_km IS NULL OR (distance_km >= 0 AND distance_km <= 1000000000000)) AND (calories_kcal IS NULL OR (calories_kcal >= 0 AND calories_kcal <= 1000000000000))");
            t.HasCheckConstraint("ck_activity_interval", "(duration_minutes IS NULL AND ended_at IS NULL) OR (duration_minutes IS NOT NULL AND ended_at > started_at AND ended_at - started_at <= interval '7 days')");
        });

        var batches = builder.Entity<WearableSyncBatch>();
        Map(batches, "wearable_sync_batches");
        batches.HasOne<WearableConnection>().WithMany().HasForeignKey(x => new { x.WearableConnectionId, x.ClientId })
            .HasPrincipalKey(x => new { x.Id, x.ClientId }).OnDelete(DeleteBehavior.Restrict);
        batches.HasIndex(x => new { x.WearableConnectionId, x.BatchId }).IsUnique();
        batches.Property(x => x.RequestHash).HasMaxLength(64);
        batches.Property(x => x.ResponseJson).HasColumnType("jsonb");
        foreach (var entity in new[] { connections.Metadata, records.Metadata, samples.Metadata, activities.Metadata, batches.Metadata })
        {
            foreach (var name in new[] { "Id", "ClientId", "WearableConnectionId", "WearableRecordId", "Source", "SourceId", "ExternalRecordId", "RawType", "RawUnit", "Metric", "SampleKey", "Provider", "BatchId", "RequestHash", "ResponseJson", "CommittedAt" })
                entity.FindProperty(name)?.SetAfterSaveBehavior(PropertySaveBehavior.Throw);
        }
    }

    private static void Map<T>(Microsoft.EntityFrameworkCore.Metadata.Builders.EntityTypeBuilder<T> entity, string table) where T : class
    {
        entity.ToTable(table);
        entity.HasKey("Id");
        entity.Property<Guid>("Id").ValueGeneratedNever();
        entity.HasOne<ClientProfile>().WithMany().HasForeignKey("ClientId").OnDelete(DeleteBehavior.Restrict);
        foreach (var property in entity.Metadata.GetProperties())
            property.SetColumnName(string.Concat(property.Name.Select((c, i) => char.IsUpper(c) && i > 0 ? "_" + char.ToLowerInvariant(c) : char.ToLowerInvariant(c).ToString())));
    }
}
