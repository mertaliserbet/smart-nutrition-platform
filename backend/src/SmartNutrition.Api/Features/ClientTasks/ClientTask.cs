using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Features.Relationships;

namespace SmartNutrition.Api.Features.ClientTasks;

[JsonConverter(typeof(ClientTaskStatusJsonConverter))]
public enum ClientTaskStatus { Pending, InProgress, Completed, Cancelled }
internal sealed class ClientTaskStatusJsonConverter : JsonStringEnumConverter<ClientTaskStatus>
{ public ClientTaskStatusJsonConverter() : base(JsonNamingPolicy.SnakeCaseLower, false) { } }

public sealed class ClientTask
{
    private ClientTask() { }
    internal ClientTask(Guid clientId, Guid dietitianId, Guid relationshipId, string description, DateTimeOffset? dueAt, DateTimeOffset now)
    {
        Id = Guid.NewGuid(); ClientId = clientId; DietitianId = dietitianId; RelationshipId = relationshipId;
        Description = description; DueAt = dueAt; CreatedAt = UpdatedAt = RecordTime.Normalize(now); VersionNumber = 1;
    }
    public Guid Id { get; private set; }
    public Guid ClientId { get; private set; }
    public Guid DietitianId { get; private set; }
    public Guid RelationshipId { get; private set; }
    public string Description { get; private set; } = null!;
    public ClientTaskStatus Status { get; private set; }
    public DateTimeOffset? DueAt { get; private set; }
    public bool IsReminderEnabled { get; private set; }
    public DateTimeOffset CreatedAt { get; private set; }
    public DateTimeOffset UpdatedAt { get; private set; }
    public int VersionNumber { get; private set; }
    internal bool IsClosed => Status is ClientTaskStatus.Completed or ClientTaskStatus.Cancelled;

    internal bool Revise(string description, DateTimeOffset? dueAt, ClientTaskStatus status, bool reminder, DateTimeOffset now)
    {
        if (Description == description && DueAt == dueAt && Status == status && IsReminderEnabled == reminder) return false;
        if (VersionNumber == int.MaxValue) throw new ResourceOperationException(409);
        Description = description; DueAt = dueAt; Status = status; IsReminderEnabled = reminder;
        var time = RecordTime.Normalize(now); UpdatedAt = time < UpdatedAt ? UpdatedAt : time; VersionNumber++;
        return true;
    }

    internal static void Configure(ModelBuilder builder)
    {
        // A task cannot point to another pair's relationship, even through direct SQL.
        builder.Entity<DietitianClientRelationship>().HasAlternateKey(x => new { x.Id, x.ClientId, x.DietitianId })
            .HasName("ak_relationships_id_client_dietitian");
        var rows = builder.Entity<ClientTask>();
        rows.Ignore(x => x.IsClosed);
        rows.ToTable("client_tasks", table =>
        {
            table.HasCheckConstraint("ck_client_tasks_description", "char_length(description) BETWEEN 1 AND 2000 AND description !~ '^[[:space:]]*$'");
            table.HasCheckConstraint("ck_client_tasks_status", "status IN ('pending','in_progress','completed','cancelled') AND version_number > 0");
            table.HasCheckConstraint("ck_client_tasks_times", "isfinite(created_at) AND isfinite(updated_at) AND updated_at >= created_at AND (due_at IS NULL OR (isfinite(due_at) AND due_at > created_at))");
            table.HasCheckConstraint("ck_client_tasks_reminder", "NOT is_reminder_enabled OR due_at IS NOT NULL");
        });
        rows.HasKey(x => x.Id).HasName("pk_client_tasks");
        rows.Property(x => x.Id).HasColumnName("id").ValueGeneratedNever();
        rows.Property(x => x.ClientId).HasColumnName("client_id");
        rows.Property(x => x.DietitianId).HasColumnName("dietitian_id");
        rows.Property(x => x.RelationshipId).HasColumnName("relationship_id");
        rows.Property(x => x.Description).HasColumnName("description").IsRequired();
        rows.Property(x => x.Status).HasColumnName("status").HasConversion(
            x => JsonNamingPolicy.SnakeCaseLower.ConvertName(x.ToString()),
            x => x == "in_progress" ? ClientTaskStatus.InProgress : Enum.Parse<ClientTaskStatus>(x, true));
        rows.Property(x => x.DueAt).HasColumnName("due_at");
        rows.Property(x => x.IsReminderEnabled).HasColumnName("is_reminder_enabled");
        rows.Property(x => x.CreatedAt).HasColumnName("created_at");
        rows.Property(x => x.UpdatedAt).HasColumnName("updated_at");
        rows.Property(x => x.VersionNumber).HasColumnName("version_number").IsConcurrencyToken();
        rows.HasOne<DietitianClientRelationship>().WithMany().HasForeignKey(x => new { x.RelationshipId, x.ClientId, x.DietitianId })
            .HasPrincipalKey(x => new { x.Id, x.ClientId, x.DietitianId }).OnDelete(DeleteBehavior.Restrict).HasConstraintName("fk_client_tasks_relationship_pair");
        rows.HasIndex(x => new { x.ClientId, x.CreatedAt, x.Id }).HasDatabaseName("ix_client_tasks_client_created_id");
        rows.HasIndex(x => new { x.RelationshipId, x.ClientId, x.DietitianId }).HasDatabaseName("ix_client_tasks_relationship_pair");
        foreach (var name in new[] { nameof(ClientId), nameof(DietitianId), nameof(RelationshipId), nameof(CreatedAt) })
            rows.Property(name).Metadata.SetAfterSaveBehavior(PropertySaveBehavior.Throw);
    }
}

public sealed class ClientTaskVersion
{
    internal static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web) { UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow };
    private ClientTaskVersion() { }
    internal ClientTaskVersion(ClientTask task, Guid actor)
    {
        Id = Guid.NewGuid(); ClientTaskId = task.Id; VersionNumber = task.VersionNumber;
        RecordedByUserId = actor; CreatedAt = task.UpdatedAt;
        SnapshotJson = JsonSerializer.Serialize(ClientTaskResponse.From(task), Json);
    }
    public Guid Id { get; private set; }
    public Guid ClientTaskId { get; private set; }
    public int VersionNumber { get; private set; }
    [JsonIgnore] public Guid RecordedByUserId { get; private set; }
    public DateTimeOffset CreatedAt { get; private set; }
    [JsonIgnore] public string SnapshotJson { get; private set; } = null!;
    internal static void Configure(ModelBuilder builder)
    {
        var rows = builder.Entity<ClientTaskVersion>();
        rows.ToTable("client_task_versions", table => table.HasCheckConstraint("ck_client_task_versions_snapshot",
            "(version_number > 0 AND jsonb_typeof(snapshot) = 'object' AND snapshot->>'id' = client_task_id::text AND (snapshot->>'versionNumber')::integer = version_number) IS TRUE"));
        rows.HasKey(x => x.Id).HasName("pk_client_task_versions");
        rows.Property(x => x.Id).HasColumnName("id").ValueGeneratedNever();
        rows.Property(x => x.ClientTaskId).HasColumnName("client_task_id");
        rows.Property(x => x.VersionNumber).HasColumnName("version_number");
        rows.Property(x => x.RecordedByUserId).HasColumnName("recorded_by_user_id");
        rows.Property(x => x.CreatedAt).HasColumnName("created_at");
        rows.Property(x => x.SnapshotJson).HasColumnName("snapshot").HasColumnType("jsonb").IsRequired();
        rows.HasOne<ClientTask>().WithMany().HasForeignKey(x => x.ClientTaskId).OnDelete(DeleteBehavior.Restrict).HasConstraintName("fk_client_task_versions_task");
        rows.HasOne<User>().WithMany().HasForeignKey(x => x.RecordedByUserId).OnDelete(DeleteBehavior.Restrict).HasConstraintName("fk_client_task_versions_actor");
        rows.HasIndex(x => new { x.ClientTaskId, x.VersionNumber }).IsUnique().HasDatabaseName("ux_client_task_versions_number");
        rows.HasIndex(x => x.RecordedByUserId).HasDatabaseName("ix_client_task_versions_actor");
        foreach (var property in rows.Metadata.GetProperties().Where(x => !x.IsPrimaryKey()))
            property.SetAfterSaveBehavior(PropertySaveBehavior.Throw);
    }
}
