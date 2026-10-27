using System.Security.Cryptography;
using SmartNutrition.Api.Features.Auth;

namespace SmartNutrition.Api.Tests;

internal sealed class JwtTestSettings
{
    // Ephemeral, independent of User Secrets; no usable signing secret is committed.
    public string SigningKeyBase64 { get; } = Convert.ToBase64String(RandomNumberGenerator.GetBytes(64));
    public string Issuer { get; } = "smart-nutrition-synthetic-tests";
    public string Audience { get; } = "smart-nutrition-synthetic-test-clients";
    public Dictionary<string, string?> Configuration => new()
    {
        ["Auth:Jwt:SigningKeyBase64"] = SigningKeyBase64,
        ["Auth:Jwt:Issuer"] = Issuer,
        ["Auth:Jwt:Audience"] = Audience
    };

    public JwtOptions Options => new() { SigningKeyBase64 = SigningKeyBase64, Issuer = Issuer, Audience = Audience };
}
