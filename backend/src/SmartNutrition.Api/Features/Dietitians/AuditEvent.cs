using Microsoft.EntityFrameworkCore;
using SmartNutrition.Api.Features.Auth;

namespace SmartNutrition.Api.Features.Dietitians;

// No health values, submitted text or secrets are included in this approved event.
public sealed class AuditEvent
{
    public Guid Id { get; private set; } = Guid.NewGuid();
    public Guid ActorUserId { get; private set; }
    public string Action { get; private set; } = "dietitian_verified";
    public string ResourceType { get; private set; } = "DietitianProfile";
    public Guid ResourceId { get; private set; }
    public DateTimeOffset CreatedAt { get; private set; }
    public string? Metadata { get; private set; }
    private AuditEvent() { }
    internal AuditEvent(Guid actor, Guid resource, DateTimeOffset now)
    { ActorUserId = actor; ResourceId = resource; CreatedAt = now; }
    internal static void Configure(ModelBuilder builder)
    {
        var events = builder.Entity<AuditEvent>();
        events.ToTable("audit_events");
        events.HasKey(x => x.Id).HasName("pk_audit_events");
        events.Property(x => x.Id).HasColumnName("id").ValueGeneratedNever();
        events.Property(x => x.ActorUserId).HasColumnName("actor_user_id");
        events.Property(x => x.Action).HasColumnName("action").IsRequired();
        events.Property(x => x.ResourceType).HasColumnName("resource_type").IsRequired();
        events.Property(x => x.ResourceId).HasColumnName("resource_id");
        events.Property(x => x.CreatedAt).HasColumnName("created_at");
        events.Property(x => x.Metadata).HasColumnName("metadata").HasColumnType("jsonb");
        events.HasOne<User>().WithMany().HasForeignKey(x => x.ActorUserId).OnDelete(DeleteBehavior.NoAction)
            .HasConstraintName("fk_audit_events_users_actor_user_id");
        events.HasIndex(x => x.ActorUserId).HasDatabaseName("ix_audit_events_actor_user_id");
    }
}
