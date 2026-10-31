using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text;
using System.Text.Json;
using System.Threading.Channels;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Tests;

public sealed class LoginApiTests
{
    private const string Route = "/api/v1/auth/login";
    private const string Password = " sentetik şifre 🔒 ";

    [PostgresFact]
    public async Task RegistrationVerificationAndLoginYieldMinimalJwtAndTrustedUserIdentity()
    {
        var sender = new CapturingSender();
        await using var factory = await RegistrationApiFactory.CreateAsync(sender: sender, includeAuthProbe: true);
        using var client = factory.Client();
        using var registered = await client.PostAsJsonAsync("/api/v1/auth/register", new
        { email = "synthetic@example.test", password = Password, displayName = "Synthetic client" });
        Assert.Equal(HttpStatusCode.Created, registered.StatusCode);
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        var verificationToken = await sender.Tokens.Reader.ReadAsync(timeout.Token);
        using var verified = await client.PostAsJsonAsync("/api/v1/auth/verify-email", new { token = verificationToken });
        Assert.Equal(HttpStatusCode.NoContent, verified.StatusCode);

        using var response = await Login(client, "  Synthetic@EXAMPLE.TEST  ");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.True(response.Headers.CacheControl?.NoStore);
        Assert.False(response.Headers.Contains("Set-Cookie"));
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal(["accessToken", "expiresAt", "refreshToken", "refreshTokenExpiresAt", "tokenType"], body.RootElement.EnumerateObject().Select(field => field.Name).Order().ToArray());
        var accessToken = body.RootElement.GetProperty("accessToken").GetString()!;
        var token = new JsonWebToken(accessToken);
        Assert.Equal("Bearer", body.RootElement.GetProperty("tokenType").GetString());
        Assert.Equal(token.ValidTo, body.RootElement.GetProperty("expiresAt").GetDateTimeOffset().UtcDateTime);
        Assert.Equal(TimeSpan.FromMinutes(15), token.ValidTo - token.ValidFrom);
        await using var database = factory.Database();
        var user = await database.Users.Include(account => account.ClientProfile).SingleAsync();
        Assert.Equal(user.Id.ToString(), token.Subject);
        Assert.NotEqual(user.ClientProfile!.Id.ToString(), token.Subject);
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
        using var probe = await client.GetAsync("/__tests/auth");
        Assert.Equal(HttpStatusCode.OK, probe.StatusCode);
        using var identity = JsonDocument.Parse(await probe.Content.ReadAsStringAsync());
        Assert.Equal(user.Id.ToString(), identity.RootElement.GetProperty("userId").GetString());
        Assert.Equal("client", identity.RootElement.GetProperty("role").GetString());
        Assert.DoesNotContain(accessToken, factory.Logs);
        Assert.DoesNotContain(verificationToken, factory.Logs);
        Assert.DoesNotContain(Password, factory.Logs);
        Assert.DoesNotContain(user.PasswordHash, factory.Logs);
    }

    [PostgresFact]
    public async Task MissingAccountWrongPasswordUnverifiedEmailAndAdminHaveTheSameFailure()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync();
        await Seed(factory, "verified@example.test", verified: true);
        await Seed(factory, "unverified@example.test", verified: false);
        await Seed(factory, "admin@example.test", verified: true, role: UserRole.Admin);
        using var client = factory.Client();
        string? expectedError = null;
        foreach (var (email, password) in new[]
        {
            ("missing@example.test", Password), ("verified@example.test", "wrong password"),
            ("unverified@example.test", Password), ("admin@example.test", Password),
            ("verified@example.test", Password.Trim())
        })
        {
            using var response = await Login(client, email, password);
            await AssertError(response, HttpStatusCode.Unauthorized, "unauthenticated");
            Assert.Equal("Bearer", response.Headers.WwwAuthenticate.Single().Scheme);
            Assert.False(response.Headers.Contains("Set-Cookie"));
            using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
            var error = body.RootElement.GetProperty("error").GetRawText();
            expectedError ??= error;
            Assert.Equal(expectedError, error);
            Assert.DoesNotContain("accessToken", body.RootElement.GetRawText());
            Assert.DoesNotContain(password, body.RootElement.GetRawText());
        }
        Assert.DoesNotContain(Password, factory.Logs);
    }

    [PostgresFact]
    public async Task IdentityRehashUpdatesOnlyTheSuccessfullyAuthenticatedAccount()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync();
        var oldHasher = new PasswordHasher<User>(Options.Create(new PasswordHasherOptions { IterationCount = 1000 }));
        var id = await Seed(factory, "legacy@example.test", verified: true, hasher: oldHasher);
        await using var database = factory.Database();
        var user = await database.Users.SingleAsync(account => account.Id == id);
        var previousHash = user.PasswordHash;
        using var client = factory.Client();
        using var failed = await Login(client, user.Email, "wrong password");
        Assert.Equal(HttpStatusCode.Unauthorized, failed.StatusCode);
        await database.Entry(user).ReloadAsync();
        Assert.Equal(previousHash, user.PasswordHash);
        using var success = await Login(client, user.Email);
        Assert.Equal(HttpStatusCode.OK, success.StatusCode);
        await database.Entry(user).ReloadAsync();
        Assert.NotEqual(previousHash, user.PasswordHash);
        Assert.Equal(PasswordVerificationResult.Success, new PasswordHasher<User>().VerifyHashedPassword(user, user.PasswordHash, Password));
        Assert.DoesNotContain(user.PasswordHash, factory.Logs);
    }

    [PostgresFact]
    public async Task BearerMiddlewareEnforcesAuthenticationAndCanonicalRoleAuthorization()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(includeAuthProbe: true);
        await Seed(factory, "client@example.test", verified: true);
        await Seed(factory, "dietitian@example.test", verified: true, role: UserRole.Dietitian);
        using var client = factory.Client();
        using var missing = await client.GetAsync("/__tests/auth");
        await AssertError(missing, HttpStatusCode.Unauthorized, "unauthenticated");
        foreach (var (email, expected) in new[] { ("client@example.test", HttpStatusCode.Forbidden), ("dietitian@example.test", HttpStatusCode.NoContent) })
        {
            using var login = await Login(client, email);
            Assert.Equal(HttpStatusCode.OK, login.StatusCode);
            using var body = JsonDocument.Parse(await login.Content.ReadAsStringAsync());
            var token = body.RootElement.GetProperty("accessToken").GetString()!;
            client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
            using var authorized = await client.GetAsync("/__tests/auth/dietitian");
            Assert.Equal(expected, authorized.StatusCode);
            if (expected == HttpStatusCode.Forbidden) await AssertError(authorized, expected, "forbidden");
            Assert.DoesNotContain(token, factory.Logs);
        }
    }

    [PostgresFact]
    public async Task InvalidExpiredAndMfaBypassingTokensAreRejectedByRealMiddleware()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(includeAuthProbe: true);
        using var client = factory.Client();
        foreach (var variant in new[] { "malformed", "bad-signature", "wrong-issuer", "wrong-audience", "audience-slash",
            "expired", "missing-expiry", "not-yet-valid", "unsigned", "wrong-algorithm", "wrong-type", "admin",
            "unknown-role", "duplicate-role", "missing-role", "invalid-sub", "empty-sub", "missing-sub" })
        {
            var token = TokenVariant(factory.Jwt, variant);
            client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
            using var response = await client.GetAsync("/__tests/auth");
            await AssertError(response, HttpStatusCode.Unauthorized, "unauthenticated");
            Assert.Equal("Bearer", response.Headers.WwwAuthenticate.Single().ToString());
            Assert.DoesNotContain(token, await response.Content.ReadAsStringAsync());
            Assert.DoesNotContain(token, factory.Logs);
        }
    }

    [PostgresFact]
    public async Task LoginRateLimitDoesNotDependOnAccountExistence()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync();
        using var client = factory.Client();
        for (var attempt = 0; attempt < 10; attempt++)
        {
            using var response = await Login(client, $"missing-{attempt}@example.test");
            Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        }
        using var limited = await Login(client, "another-missing@example.test");
        await AssertError(limited, HttpStatusCode.TooManyRequests, "rate_limited");
    }

    [PostgresFact]
    public async Task InvalidLoginPayloadsCannotInjectIdentityOrRole()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync();
        using var client = factory.Client();
        foreach (var json in new[] { "{}", "{", "null", "{\"email\":\"synthetic@example.test\"}",
            "{\"email\":\"invalid\",\"password\":\"synthetic\"}",
            "{\"email\":\"synthetic@example.test\",\"password\":\"\"}",
            "{\"email\":\"synthetic@example.test\",\"password\":\"synthetic\",\"role\":\"admin\"}",
            "{\"email\":\"synthetic@example.test\",\"password\":\"synthetic\",\"userId\":\"synthetic\"}" })
        {
            using var response = await client.PostAsync(Route, new StringContent(json, Encoding.UTF8, "application/json"));
            await AssertError(response, HttpStatusCode.BadRequest, "invalid_request");
        }
        using var unsupported = await client.PostAsync(Route, new StringContent("synthetic plaintext"));
        await AssertError(unsupported, HttpStatusCode.UnsupportedMediaType, "unsupported_media_type");
        await using var database = factory.Database();
        Assert.Empty(await database.Users.ToListAsync());
    }

    private static Task<HttpResponseMessage> Login(HttpClient client, string email, string password = Password) =>
        client.PostAsJsonAsync(Route, new { email, password });

    private static async Task<Guid> Seed(RegistrationApiFactory factory, string email, bool verified,
        UserRole role = UserRole.Client, IPasswordHasher<User>? hasher = null)
    {
        await using var database = factory.Database();
        var user = new User(Guid.NewGuid(), email.ToUpperInvariant(), role, Password, DateTimeOffset.UtcNow, hasher ?? new PasswordHasher<User>());
        database.Users.Add(user);
        database.Entry(user).Property(account => account.IsEmailVerified).CurrentValue = verified;
        await database.SaveChangesAsync();
        return user.Id;
    }

    private static string TokenVariant(JwtTestSettings settings, string variant)
    {
        if (variant == "malformed") return "synthetic-invalid-token";
        var now = DateTime.UtcNow;
        var claims = new Dictionary<string, object> { ["sub"] = Guid.NewGuid().ToString("D"), ["role"] = "client" };
        if (variant == "admin") claims["role"] = "admin";
        if (variant == "unknown-role") claims["role"] = "unknown";
        if (variant == "duplicate-role") claims["role"] = new[] { "client", "dietitian" };
        if (variant == "missing-role") claims.Remove("role");
        if (variant == "invalid-sub") claims["sub"] = "not-a-uuid";
        if (variant == "empty-sub") claims["sub"] = Guid.Empty.ToString();
        if (variant == "missing-sub") claims.Remove("sub");
        var key = variant == "bad-signature" ? new JwtTestSettings().Options.CreateSigningKey() : settings.Options.CreateSigningKey();
        return new JsonWebTokenHandler { SetDefaultTimesOnTokenCreation = false }.CreateToken(new SecurityTokenDescriptor
        {
            Issuer = variant == "wrong-issuer" ? "synthetic-wrong-issuer" : settings.Issuer,
            Audience = variant == "wrong-audience" ? "synthetic-wrong-audience" : settings.Audience + (variant == "audience-slash" ? "/" : ""),
            Claims = claims, IssuedAt = now.AddMinutes(-20),
            NotBefore = variant == "not-yet-valid" ? now.AddMinutes(1) : now.AddMinutes(-20),
            Expires = variant == "missing-expiry" ? null : variant == "expired" ? now.AddSeconds(-1) : now.AddMinutes(15),
            SigningCredentials = variant == "unsigned" ? null : new SigningCredentials(key,
                variant == "wrong-algorithm" ? SecurityAlgorithms.HmacSha512 : SecurityAlgorithms.HmacSha256),
            TokenType = variant == "wrong-type" ? "JWT" : "at+jwt"
        });
    }

    private static async Task AssertError(HttpResponseMessage response, HttpStatusCode status, string code)
    {
        Assert.Equal(status, response.StatusCode);
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal(code, body.RootElement.GetProperty("error").GetProperty("code").GetString());
        Assert.False(string.IsNullOrWhiteSpace(body.RootElement.GetProperty("requestId").GetString()));
    }

    private sealed class CapturingSender : IVerificationEmailSender
    {
        public Channel<string> Tokens { get; } = Channel.CreateUnbounded<string>();
        public Task SendAsync(string recipient, string token, CancellationToken cancellationToken)
        { Tokens.Writer.TryWrite(token); return Task.CompletedTask; }
    }
}

// Registered explicitly by the test factory only. Production API has no diagnostic identity endpoint.
[ApiController]
[Authorize]
[Route("__tests/auth")]
public sealed class LoginProbeController : ControllerBase
{
    [HttpGet]
    public object Identity() => new { userId = User.FindFirstValue("sub"), role = User.FindFirstValue("role") };

    [HttpGet("dietitian")]
    [Authorize(Roles = "dietitian")]
    public IActionResult Dietitian() => NoContent();
}
