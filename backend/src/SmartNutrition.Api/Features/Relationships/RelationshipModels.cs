using System.Text.Json.Serialization;
using Microsoft.EntityFrameworkCore;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Features.Dietitians;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Features.Relationships;

public sealed class DietitianClientRelationship
{
    private DietitianClientRelationship() { }
    internal DietitianClientRelationship(Guid clientId, Guid dietitianId, DateTimeOffset now)
    { Id = Guid.NewGuid(); ClientId = clientId; DietitianId = dietitianId; RequestedAt = RecordTime.Normalize(now); }
    public Guid Id { get; private set; }
    public Guid ClientId { get; private set; }
    public Guid DietitianId { get; private set; }
    public RelationshipStatus Status { get; private set; }
    public DateTimeOffset RequestedAt { get; private set; }
    public DateTimeOffset? RespondedAt { get; private set; }
    public DateTimeOffset? EndedAt { get; private set; }
    internal void Respond(RelationshipStatus status, DateTimeOffset now) { Status = status; RespondedAt = RecordTime.Normalize(now); }
    internal void End(DateTimeOffset now) { Status = RelationshipStatus.Ended; EndedAt = RecordTime.Normalize(now); }

    internal static void Configure(ModelBuilder builder)
    {
        var rows = builder.Entity<DietitianClientRelationship>();
        rows.ToTable("dietitian_client_relationships", table =>
        {
            table.HasCheckConstraint("ck_relationships_status", "status IN ('pending','active','rejected','ended')");
            table.HasCheckConstraint("ck_relationships_times", "(responded_at IS NULL OR responded_at >= requested_at) AND (ended_at IS NULL OR ended_at >= requested_at)");
        });
        rows.HasKey(x => x.Id).HasName("pk_dietitian_client_relationships");
        rows.Property(x => x.Id).HasColumnName("id").ValueGeneratedNever();
        rows.Property(x => x.ClientId).HasColumnName("client_id"); rows.Property(x => x.DietitianId).HasColumnName("dietitian_id");
        rows.Property(x => x.Status).HasColumnName("status").HasConversion(x => x.ToString().ToLowerInvariant(), x => Enum.Parse<RelationshipStatus>(x, true));
        rows.Property(x => x.RequestedAt).HasColumnName("requested_at"); rows.Property(x => x.RespondedAt).HasColumnName("responded_at"); rows.Property(x => x.EndedAt).HasColumnName("ended_at");
        rows.HasIndex(x => x.ClientId).IsUnique().HasFilter("status = 'active'").HasDatabaseName("ux_relationships_active_client");
        rows.HasIndex(x => new { x.ClientId, x.DietitianId }).IsUnique().HasFilter("status = 'pending'").HasDatabaseName("ux_relationships_pending_pair");
        rows.HasIndex(x => x.DietitianId).HasDatabaseName("ix_relationships_dietitian_id");
        rows.HasOne<ClientProfile>().WithMany().HasForeignKey(x => x.ClientId).OnDelete(DeleteBehavior.NoAction).HasConstraintName("fk_relationships_client_id");
        rows.HasOne<DietitianProfile>().WithMany().HasForeignKey(x => x.DietitianId).OnDelete(DeleteBehavior.NoAction).HasConstraintName("fk_relationships_dietitian_id");
    }
}

public sealed class DataSharingPermission
{
    private DataSharingPermission() { }
    internal DataSharingPermission(Guid relationshipId, bool isGranted, DateTimeOffset now)
    { Id = Guid.NewGuid(); RelationshipId = relationshipId; IsGranted = isGranted; CreatedAt = UpdatedAt = RecordTime.Normalize(now); }
    public Guid Id { get; private set; }
    public Guid RelationshipId { get; private set; }
    public string Category { get; private set; } = "nutrition_plans";
    public bool IsGranted { get; private set; }
    public Guid? ConsentRecordId { get; private set; }
    public DateTimeOffset CreatedAt { get; private set; }
    public DateTimeOffset UpdatedAt { get; private set; }
    internal void SetGranted(bool value, DateTimeOffset now) { IsGranted = value; UpdatedAt = RecordTime.Normalize(now); }
    internal static void Configure(ModelBuilder builder)
    {
        var rows = builder.Entity<DataSharingPermission>();
        rows.ToTable("data_sharing_permissions", table =>
        {
            table.HasCheckConstraint("ck_permissions_category", "category = 'nutrition_plans' AND consent_record_id IS NULL");
            table.HasCheckConstraint("ck_permissions_times", "updated_at >= created_at");
        });
        rows.HasKey(x => x.Id).HasName("pk_data_sharing_permissions");
        rows.Property(x => x.Id).HasColumnName("id").ValueGeneratedNever(); rows.Property(x => x.RelationshipId).HasColumnName("relationship_id");
        rows.Property(x => x.Category).HasColumnName("category").IsRequired(); rows.Property(x => x.IsGranted).HasColumnName("is_granted");
        rows.Property(x => x.ConsentRecordId).HasColumnName("consent_record_id"); rows.Property(x => x.CreatedAt).HasColumnName("created_at"); rows.Property(x => x.UpdatedAt).HasColumnName("updated_at");
        rows.HasIndex(x => new { x.RelationshipId, x.Category }).IsUnique().HasDatabaseName("ux_permissions_relationship_category");
        rows.HasOne<DietitianClientRelationship>().WithMany().HasForeignKey(x => x.RelationshipId).OnDelete(DeleteBehavior.NoAction).HasConstraintName("fk_permissions_relationship_id");
    }
}

public sealed record RelationshipRequest
{
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWriting)] public Guid? DietitianId { get; init; }
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWriting)] public string? InvitationCode { get; init; }
    // Explicitly avoid the record-generated secret dump.
    public override string ToString() => nameof(RelationshipRequest);
}
public sealed record RelationshipResponse(Guid Id, Guid ClientId, Guid DietitianId, RelationshipStatus Status,
    DateTimeOffset RequestedAt, DateTimeOffset? RespondedAt, DateTimeOffset? EndedAt)
{
    internal static RelationshipResponse From(DietitianClientRelationship row) => new(row.Id, row.ClientId, row.DietitianId, row.Status, row.RequestedAt, row.RespondedAt, row.EndedAt);
}
public sealed class InvitationCodeResponse(string code, DateTimeOffset expiresAt)
{ public string InvitationCode { get; } = code; public DateTimeOffset ExpiresAt { get; } = expiresAt; }

internal sealed class ResourceOperationException(int statusCode) : Exception("Resource operation could not be completed.")
{ public int StatusCode { get; } = statusCode; }

// Match PostgreSQL timestamp microseconds before returning a newly persisted instant.
// This keeps first and repeated responses identical without changing measurement precision.
internal static class RecordTime
{
    internal static DateTimeOffset Normalize(DateTimeOffset value)
    { var utc = value.ToUniversalTime(); return utc.AddTicks(-(utc.Ticks % 10)); }
}
