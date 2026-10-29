using System.ComponentModel.DataAnnotations;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.Extensions.Options;
using OtpNet;

namespace SmartNutrition.Api.Features.Auth;

public sealed class AdminLoginRequest : IValidatableObject
{
    [JsonRequired, JsonIgnore(Condition = JsonIgnoreCondition.WhenWriting)] public string? Email { get; init; }
    [JsonRequired, JsonIgnore(Condition = JsonIgnoreCondition.WhenWriting)] public string? Password { get; init; }
    [JsonRequired, JsonIgnore(Condition = JsonIgnoreCondition.WhenWriting)] public string? MfaCode { get; init; }
    public IEnumerable<ValidationResult> Validate(ValidationContext context)
    {
        if (string.IsNullOrWhiteSpace(Email) || !RegisterUserRequest.IsValidEmail(Email)) yield return new("A valid email is required.");
        if (string.IsNullOrEmpty(Password)) yield return new("Password is required.");
        if (string.IsNullOrWhiteSpace(MfaCode) || MfaCode.Length > 128) yield return new("An MFA code is required.");
    }
}

public sealed class AdminMfaService(IDataProtectionProvider protection, IOptions<WebSessionOptions> options)
{
    private IDataProtector Protector(Guid id) => protection.CreateProtector("SmartNutrition.AdminMfa.v1", id.ToString("D"));

    // Returned only to the local bootstrap command, never through HTTP or logging.
    internal (string Key, string[] RecoveryCodes) Initialize(User user, DateTimeOffset now)
    {
        if (!options.Value.Enabled) throw new InvalidOperationException("Persistent protected web keys are required.");
        var key = Base32Encoding.ToString(RandomNumberGenerator.GetBytes(20));
        var codes = Enumerable.Range(0, 10).Select(_ => Convert.ToHexString(RandomNumberGenerator.GetBytes(16))).ToArray();
        user.ConfigureAdminMfa(Protector(user.Id).Protect(key), codes.Select(Hash).ToArray(), now);
        return (key, codes);
    }

    // Caller MUST hold the User row lock and commit consumption with the session.
    internal bool TryConsume(User user, string code, DateTimeOffset now)
    {
        if (!options.Value.Enabled || user.TotpSecretProtected is null) return false;
        code = code.Trim();
        if (code.Length == 6 && code.All(char.IsAsciiDigit))
        {
            try
            {
                var secret = Base32Encoding.ToBytes(Protector(user.Id).Unprotect(user.TotpSecretProtected));
                try
                {
                    var valid = new Totp(secret, step: 30, totpSize: 6).VerifyTotp(now.UtcDateTime, code,
                        out var step, new VerificationWindow(previous: 1, future: 1));
                    if (!valid || user.LastUsedTotpStep >= step) return false;
                    user.ConsumeTotp(step);
                    return true;
                }
                finally { CryptographicOperations.ZeroMemory(secret); }
            }
            catch (CryptographicException) { return false; }
            catch (FormatException) { return false; }
        }
        if (code.Length != 32 || !code.All(char.IsAsciiHexDigit)) return false;
        var candidate = SHA256.HashData(Encoding.ASCII.GetBytes(code));
        string? matched = null;
        foreach (var hash in user.MfaRecoveryCodeHashes)
            if (CryptographicOperations.FixedTimeEquals(candidate, Convert.FromHexString(hash))) matched = hash;
        if (matched is null) return false;
        user.ConsumeRecoveryCode(matched);
        return true;
    }

    private static string Hash(string value) => Convert.ToHexString(SHA256.HashData(Encoding.ASCII.GetBytes(value)));
}
