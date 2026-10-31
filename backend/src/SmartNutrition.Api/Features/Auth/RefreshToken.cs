using System.Text.Json.Serialization;
using Microsoft.EntityFrameworkCore;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Features.Auth;

// Server-only rotation history. No plaintext refresh/access token is persisted.
public sealed class RefreshToken
{
    private RefreshToken() { }
    internal RefreshToken(Guid userId, UserRole role, Guid familyId, string tokenHash,
        DateTimeOffset createdAt, DateTimeOffset expiresAt)
    {
        Id = Guid.NewGuid(); UserId = userId; Role = role; FamilyId = familyId;
        TokenHash = tokenHash; CreatedAt = createdAt; ExpiresAt = expiresAt;
    }

    public Guid Id { get; private set; }
    public Guid UserId { get; private set; }
    public UserRole Role { get; private set; }
    public Guid FamilyId { get; private set; }
    [JsonIgnore] public string TokenHash { get; private set; } = null!;
    public DateTimeOffset CreatedAt { get; private set; }
    public DateTimeOffset ExpiresAt { get; private set; }
    public DateTimeOffset? ConsumedAt { get; private set; }
    public DateTimeOffset? RevokedAt { get; private set; }

    internal static void Configure(ModelBuilder builder)
    {
        var tokens = builder.Entity<RefreshToken>();
        tokens.ToTable("refresh_tokens", table =>
        {
            table.HasCheckConstraint("ck_refresh_tokens_role", "role IN ('client', 'dietitian')");
            table.HasCheckConstraint("ck_refresh_tokens_hash", "token_hash ~ '^[0-9A-F]{64}$'");
            table.HasCheckConstraint("ck_refresh_tokens_times", "created_at < expires_at AND (consumed_at IS NULL OR consumed_at >= created_at) AND (revoked_at IS NULL OR revoked_at >= created_at)");
        });
        tokens.HasKey(token => token.Id).HasName("pk_refresh_tokens");
        tokens.Property(token => token.Id).HasColumnName("id").ValueGeneratedNever();
        tokens.Property(token => token.UserId).HasColumnName("user_id");
        tokens.Property(token => token.Role).HasColumnName("role").HasConversion(
            role => role.ToString().ToLowerInvariant(), value => Enum.Parse<UserRole>(value, true));
        tokens.Property(token => token.FamilyId).HasColumnName("family_id");
        tokens.Property(token => token.TokenHash).HasColumnName("token_hash").HasMaxLength(64).IsRequired();
        tokens.Property(token => token.CreatedAt).HasColumnName("created_at");
        tokens.Property(token => token.ExpiresAt).HasColumnName("expires_at");
        tokens.Property(token => token.ConsumedAt).HasColumnName("consumed_at");
        tokens.Property(token => token.RevokedAt).HasColumnName("revoked_at");
        tokens.HasOne<User>().WithMany().HasForeignKey(token => token.UserId)
            .OnDelete(DeleteBehavior.NoAction).HasConstraintName("fk_refresh_tokens_users_user_id");
        tokens.HasIndex(token => token.TokenHash).IsUnique().HasDatabaseName("ux_refresh_tokens_token_hash");
        tokens.HasIndex(token => token.FamilyId, "ix_refresh_tokens_family_id");
        tokens.HasIndex(token => token.FamilyId, "ux_refresh_tokens_active_family").IsUnique()
            .HasFilter("consumed_at IS NULL AND revoked_at IS NULL");
        tokens.HasIndex(token => token.UserId).HasDatabaseName("ix_refresh_tokens_user_id");
        tokens.HasIndex(token => token.ExpiresAt).HasDatabaseName("ix_refresh_tokens_expires_at");
    }
}

public sealed class RefreshTokenOptions
{
    public const string SectionName = "Auth:RefreshTokens";
    public int LifetimeDays { get; set; } = 30;
    public int RequestsPerMinute { get; set; } = 30;
}
