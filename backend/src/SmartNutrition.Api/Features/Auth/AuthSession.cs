using Microsoft.EntityFrameworkCore;

namespace SmartNutrition.Api.Features.Auth;

// Server-only record. The protected framework ticket carries its reference, never its secret.
public sealed class AuthSession
{
    private AuthSession() { }

    public AuthSession(Guid userId, DateTimeOffset now, bool isMfaVerified = false)
    {
        if (userId == Guid.Empty) throw new ArgumentException("A user is required.", nameof(userId));
        Id = Guid.NewGuid();
        UserId = userId;
        IsMfaVerified = isMfaVerified;
        CreatedAt = LastSeenAt = now;
        IdleExpiresAt = now.AddMinutes(30);
        AbsoluteExpiresAt = now.AddHours(8);
    }

    public Guid Id { get; private set; }
    public Guid UserId { get; private set; }
    public bool IsMfaVerified { get; private set; }
    public DateTimeOffset CreatedAt { get; private set; }
    public DateTimeOffset LastSeenAt { get; private set; }
    public DateTimeOffset IdleExpiresAt { get; private set; }
    public DateTimeOffset AbsoluteExpiresAt { get; private set; }
    public DateTimeOffset? RevokedAt { get; private set; }

    internal static void Configure(Microsoft.EntityFrameworkCore.ModelBuilder builder)
    {
        var sessions = builder.Entity<AuthSession>();
        sessions.ToTable("auth_sessions", table =>
        {
            table.HasCheckConstraint("ck_auth_sessions_times", "created_at <= last_seen_at AND last_seen_at < idle_expires_at AND idle_expires_at <= absolute_expires_at");
            table.HasCheckConstraint("ck_auth_sessions_revoked_at", "revoked_at IS NULL OR revoked_at >= created_at");
        });
        sessions.HasKey(session => session.Id).HasName("pk_auth_sessions");
        sessions.Property(session => session.Id).HasColumnName("id").ValueGeneratedNever();
        sessions.Property(session => session.UserId).HasColumnName("user_id");
        sessions.Property(session => session.IsMfaVerified).HasColumnName("is_mfa_verified").HasDefaultValue(false);
        sessions.Property(session => session.CreatedAt).HasColumnName("created_at");
        sessions.Property(session => session.LastSeenAt).HasColumnName("last_seen_at");
        sessions.Property(session => session.IdleExpiresAt).HasColumnName("idle_expires_at");
        sessions.Property(session => session.AbsoluteExpiresAt).HasColumnName("absolute_expires_at");
        sessions.Property(session => session.RevokedAt).HasColumnName("revoked_at");
        sessions.HasOne<User>().WithMany().HasForeignKey(session => session.UserId)
            .OnDelete(Microsoft.EntityFrameworkCore.DeleteBehavior.NoAction).HasConstraintName("fk_auth_sessions_users_user_id");
        sessions.HasIndex(session => session.UserId).HasDatabaseName("ix_auth_sessions_user_id");
        sessions.HasIndex(session => session.IdleExpiresAt).HasDatabaseName("ix_auth_sessions_idle_expires_at");
        sessions.HasIndex(session => session.RevokedAt).HasDatabaseName("ix_auth_sessions_revoked_at");
    }
}
