using System.Text;
using System.Text.Json.Serialization;
using Microsoft.EntityFrameworkCore;
using SmartNutrition.Api.Features.Auth;

namespace SmartNutrition.Api.Features.Dietitians;

public sealed class DietitianProfile
{
    private DietitianProfile() { }
    public DietitianProfile(User user, string displayName, string licenseInfo)
    {
        if (!ValidText(displayName, 120) || !ValidText(licenseInfo, 2000))
            throw new ArgumentException("Valid application text is required.");
        Id = Guid.NewGuid(); UserId = user.Id; User = user;
        DisplayName = displayName.Trim(); LicenseInfo = licenseInfo.Trim();
        user.AttachDietitianProfile(this);
    }
    public Guid Id { get; private set; }
    public Guid UserId { get; private set; }
    public string DisplayName { get; private set; } = null!;
    [JsonIgnore] public string LicenseInfo { get; private set; } = null!;
    public bool IsVerified { get; private set; }
    [JsonIgnore] public string? InvitationCodeHash { get; private set; }
    [JsonIgnore] public DateTimeOffset? InvitationCodeExpiresAt { get; private set; }
    internal void SetInvitation(string? hash, DateTimeOffset? expiresAt) { InvitationCodeHash = hash; InvitationCodeExpiresAt = expiresAt; }
    [JsonIgnore] public User User { get; private set; } = null!;
    internal static bool ValidText(string? text, int max) =>
        !string.IsNullOrWhiteSpace(text) && text.Trim().EnumerateRunes().Count() <= max;

    internal static void Configure(ModelBuilder builder)
    {
        var profile = builder.Entity<DietitianProfile>();
        profile.ToTable("dietitian_profiles", table =>
        {
            table.HasCheckConstraint("ck_dietitian_profiles_name", "char_length(btrim(display_name)) BETWEEN 1 AND 120");
            table.HasCheckConstraint("ck_dietitian_profiles_license", "char_length(btrim(license_info)) BETWEEN 1 AND 2000");
        });
        profile.HasKey(x => x.Id).HasName("pk_dietitian_profiles");
        profile.Property(x => x.Id).HasColumnName("id").ValueGeneratedNever();
        profile.Property(x => x.UserId).HasColumnName("user_id");
        profile.Property(x => x.DisplayName).HasColumnName("display_name").IsRequired();
        profile.Property(x => x.LicenseInfo).HasColumnName("license_info").IsRequired();
        profile.Property(x => x.IsVerified).HasColumnName("is_verified").HasDefaultValue(false);
        profile.Property(x => x.InvitationCodeHash).HasColumnName("invitation_code_hash").HasMaxLength(64);
        profile.Property(x => x.InvitationCodeExpiresAt).HasColumnName("invitation_code_expires_at");
        profile.HasIndex(x => x.InvitationCodeHash).IsUnique().HasDatabaseName("ux_dietitian_profiles_invitation_code_hash");
        profile.HasIndex(x => x.UserId).IsUnique().HasDatabaseName("ux_dietitian_profiles_user_id");
        profile.HasOne(x => x.User).WithOne(x => x.DietitianProfile).HasForeignKey<DietitianProfile>(x => x.UserId)
            .OnDelete(DeleteBehavior.NoAction).HasConstraintName("fk_dietitian_profiles_users_user_id");
    }
}
