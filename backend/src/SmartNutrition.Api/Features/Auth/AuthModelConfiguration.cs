using Microsoft.EntityFrameworkCore;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Features.Auth;

internal static class AuthModelConfiguration
{
    public const string EmailCollation = "users_email_case_insensitive";

    public static void Configure(ModelBuilder modelBuilder)
    {
        modelBuilder.HasCollation(EmailCollation, locale: "und-u-ks-level2", provider: "icu", deterministic: false);
        var users = modelBuilder.Entity<User>();
        users.ToTable("users", table =>
        {
            table.HasCheckConstraint("ck_users_email_not_blank", "btrim(email) <> ''");
            table.HasCheckConstraint("ck_users_password_hash_not_blank", "btrim(password_hash) <> ''");
            table.HasCheckConstraint("ck_users_role", "role IN ('client', 'dietitian', 'admin')");
            table.HasCheckConstraint("ck_users_email_verification", "(email_verification_token_hash IS NULL AND email_verification_expires_at IS NULL) OR (email_verification_token_hash IS NOT NULL AND email_verification_token_hash ~ '^[0-9A-F]{64}$' AND email_verification_expires_at IS NOT NULL AND email_verification_last_sent_at IS NOT NULL)");
        });
        users.HasKey(user => user.Id).HasName("pk_users");
        users.Property(user => user.Id).HasColumnName("id").ValueGeneratedNever();
        users.Property(user => user.Email).HasColumnName("email").UseCollation(EmailCollation).IsRequired();
        users.Property(user => user.PasswordHash).HasColumnName("password_hash").IsRequired();
        users.Property(user => user.IsEmailVerified).HasColumnName("is_email_verified").HasDefaultValue(false).IsRequired();
        users.Property(user => user.EmailVerificationTokenHash).HasColumnName("email_verification_token_hash").HasMaxLength(64);
        users.Property(user => user.EmailVerificationExpiresAt).HasColumnName("email_verification_expires_at");
        users.Property(user => user.EmailVerificationLastSentAt).HasColumnName("email_verification_last_sent_at");
        users.HasIndex(user => user.EmailVerificationTokenHash).IsUnique().HasDatabaseName("ux_users_email_verification_token_hash");
        users.Property(user => user.Role).HasColumnName("role").IsRequired()
            .HasConversion(role => role.ToString().ToLowerInvariant(), value => Enum.Parse<UserRole>(value, true));
        users.Property(user => user.CreatedAt).HasColumnName("created_at").IsRequired();
        users.Property(user => user.UpdatedAt).HasColumnName("updated_at").IsRequired();
        users.Property(user => user.TotpSecretProtected).HasColumnName("totp_secret_protected");
        users.Property(user => user.LastUsedTotpStep).HasColumnName("last_used_totp_step");
        users.Property(user => user.MfaRecoveryCodeHashes).HasColumnName("mfa_recovery_code_hashes").HasColumnType("text[]").IsRequired();
        // Case-insensitive equality and uniqueness are enforced by the same column collation.
        users.HasIndex(user => user.Email).IsUnique().HasDatabaseName("ux_users_email");

        var profiles = modelBuilder.Entity<ClientProfile>();
        profiles.ToTable("client_profiles", table =>
        {
            table.HasCheckConstraint("ck_client_profiles_display_name_not_blank", "btrim(display_name) <> ''");
            table.HasCheckConstraint("ck_client_profiles_height_cm", "height_cm IS NULL OR (height_cm > 0 AND height_cm < 'Infinity'::numeric)");
        });
        profiles.HasKey(profile => profile.Id).HasName("pk_client_profiles");
        profiles.Property(profile => profile.Id).HasColumnName("id").ValueGeneratedNever();
        profiles.Property(profile => profile.UserId).HasColumnName("user_id").IsRequired();
        profiles.Property(profile => profile.DisplayName).HasColumnName("display_name").IsRequired();
        profiles.Property(profile => profile.BirthDate).HasColumnName("birth_date").HasColumnType("date");
        // Unconstrained numeric: precision/scale and rounding have not been approved.
        profiles.Property(profile => profile.HeightCm).HasColumnName("height_cm").HasColumnType("numeric");
        profiles.HasIndex(profile => profile.UserId).IsUnique().HasDatabaseName("ux_client_profiles_user_id");
        profiles.HasOne(profile => profile.User).WithOne(user => user.ClientProfile)
            .HasForeignKey<ClientProfile>(profile => profile.UserId)
            .HasConstraintName("fk_client_profiles_users_user_id")
            // No automatic deletion while retention/account deletion rules remain open.
            .OnDelete(DeleteBehavior.NoAction);
    }
}
