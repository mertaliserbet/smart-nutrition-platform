using System.Text.Json;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.Options;
using OtpNet;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Features.Dietitians;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Tests;

public sealed class AdminMfaTests
{
    private static readonly DateTimeOffset Now = DateTimeOffset.FromUnixTimeSeconds(1793275200);
    private static User Admin() => new(Guid.NewGuid(), "synthetic-admin@example.test", UserRole.Admin, "synthetic secret", Now, new PasswordHasher<User>());
    private static AdminMfaService Service(bool enabled = true) => new(new EphemeralDataProtectionProvider(),
        Options.Create(new WebSessionOptions { Origin = enabled ? "https://localhost" : "" }));

    [Fact]
    public void TotpIsUserBoundTimeLimitedAndCannotReplayAnAcceptedStep()
    {
        var service = Service(); var user = Admin();
        var setup = service.Initialize(user, Now);
        var totp = new Totp(Base32Encoding.ToBytes(setup.Key));
        var code = totp.ComputeTotp(Now.UtcDateTime);
        Assert.True(service.TryConsume(user, code, Now));
        Assert.False(service.TryConsume(user, code, Now));
        Assert.False(service.TryConsume(user, code, Now.AddMinutes(2)));
        Assert.True(service.TryConsume(user, totp.ComputeTotp(Now.AddSeconds(30).UtcDateTime), Now.AddSeconds(30)));
        Assert.DoesNotContain(setup.Key, user.TotpSecretProtected!);
        var other = Admin();
        other.ConfigureAdminMfa(user.TotpSecretProtected!, new string[10], Now);
        Assert.False(service.TryConsume(other, totp.ComputeTotp(Now.UtcDateTime), Now));
    }

    [Fact]
    public void RecoveryCodesAreHashedSingleUseAndNotExposedByEntitySerialization()
    {
        var service = Service(); var user = Admin(); var setup = service.Initialize(user, Now);
        Assert.Equal(10, setup.RecoveryCodes.Distinct().Count());
        Assert.All(user.MfaRecoveryCodeHashes, hash => Assert.Equal(64, hash.Length));
        Assert.True(service.TryConsume(user, setup.RecoveryCodes[0], Now));
        Assert.Equal(9, user.MfaRecoveryCodeHashes.Length);
        Assert.False(service.TryConsume(user, setup.RecoveryCodes[0], Now));
        var json = JsonSerializer.Serialize(user);
        foreach (var secret in setup.RecoveryCodes.Append(setup.Key).Append(user.PasswordHash).Append(user.TotpSecretProtected!))
            Assert.DoesNotContain(secret, json);
        Assert.DoesNotContain("Recovery", json); Assert.DoesNotContain("Totp", json);
    }

    [Theory]
    [InlineData("")][InlineData("12345")][InlineData("abcdef")][InlineData("00000000000000000000000000000000")]
    public void InvalidCodesNeverAuthorize(string code)
    { var service = Service(); var user = Admin(); service.Initialize(user, Now); Assert.False(service.TryConsume(user, code, Now)); }

    [Fact]
    public void MfaSetupCannotUseUnconfiguredWebKeysOrTurnAClientIntoAdmin()
    {
        Assert.Throws<InvalidOperationException>(() => Service(false).Initialize(Admin(), Now));
        var client = new User(Guid.NewGuid(), "synthetic@example.test", UserRole.Client, "synthetic secret", Now, new PasswordHasher<User>());
        Assert.Throws<InvalidOperationException>(() => Service().Initialize(client, Now));
    }

    [Fact]
    public void DietitianProfileEnforcesItsAccountRoleAndApprovedTextBounds()
    {
        var user = new User(Guid.NewGuid(), "expert@example.test", UserRole.Dietitian, "synthetic secret", Now, new PasswordHasher<User>());
        var profile = new DietitianProfile(user, "  Sentetik Uzman  ", "  Sentetik meslek kaydı  ");
        Assert.Equal("Sentetik Uzman", profile.DisplayName); Assert.False(profile.IsVerified);
        Assert.NotEqual(user.Id, profile.Id);
        Assert.DoesNotContain(profile.LicenseInfo, JsonSerializer.Serialize(profile));
        Assert.Throws<InvalidOperationException>(() => new DietitianProfile(user, "Second", "Synthetic"));
    }
}
