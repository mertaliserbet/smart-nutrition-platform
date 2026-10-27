using Microsoft.IdentityModel.Tokens;

namespace SmartNutrition.Api.Features.Auth;

public sealed class JwtOptions
{
    public const string SectionName = "Auth:Jwt";
    public string? Issuer { get; set; }
    public string? Audience { get; set; }
    public string? SigningKeyBase64 { get; set; }

    public bool IsValid()
    {
        if (string.IsNullOrWhiteSpace(Issuer) || string.IsNullOrWhiteSpace(Audience) ||
            Issuer != Issuer.Trim() || Audience != Audience.Trim()) return false;
        try { return !string.IsNullOrEmpty(SigningKeyBase64) && Convert.FromBase64String(SigningKeyBase64).Length >= 32; }
        catch (FormatException) { return false; }
    }

    public SymmetricSecurityKey CreateSigningKey()
    {
        if (!IsValid()) throw new InvalidOperationException("JWT settings are missing or invalid.");
        return new SymmetricSecurityKey(Convert.FromBase64String(SigningKeyBase64!));
    }
}

public sealed class LoginOptions
{
    public const string SectionName = "Auth:Login";
    public int RequestsPerMinute { get; set; } = 10;
}
