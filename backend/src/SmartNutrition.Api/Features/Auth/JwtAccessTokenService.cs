using System.Security.Claims;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Features.Auth;

public sealed class JwtAccessTokenService(IOptions<JwtOptions> settings, TimeProvider clock)
{
    public static readonly TimeSpan TokenLifetime = TimeSpan.FromMinutes(15);

    public LoginUserResponse Issue(User user)
    {
        if (!user.IsEmailVerified || user.Role is not (UserRole.Client or UserRole.Dietitian))
            throw new InvalidOperationException("A verified non-admin account is required.");
        var jwt = settings.Value;
        // JWT NumericDate uses whole seconds; the response and signed expiry must agree exactly.
        var now = DateTimeOffset.FromUnixTimeSeconds(clock.GetUtcNow().ToUnixTimeSeconds());
        var expiresAt = now.Add(TokenLifetime);
        var token = new JsonWebTokenHandler().CreateToken(new SecurityTokenDescriptor
        {
            Issuer = jwt.Issuer, Audience = jwt.Audience,
            Subject = new ClaimsIdentity([new Claim("sub", user.Id.ToString("D")),
                new Claim("role", user.Role.ToString().ToLowerInvariant())]),
            IssuedAt = now.UtcDateTime, NotBefore = now.UtcDateTime, Expires = expiresAt.UtcDateTime,
            SigningCredentials = new SigningCredentials(jwt.CreateSigningKey(), SecurityAlgorithms.HmacSha256),
            TokenType = "at+jwt"
        });
        return new LoginUserResponse(token, expiresAt);
    }
}
