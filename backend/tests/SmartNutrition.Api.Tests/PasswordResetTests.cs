using System.Data.Common;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading.Channels;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Tests;

public sealed class PasswordResetTests
{
    private const string Email = "synthetic-reset@example.test";
    private const string Password = " Sentetik şifre 🔒 ";
    private const string NewPassword = " Yeni parola 🔑 ";
    private const string RequestRoute = "/api/v1/auth/password-reset-requests";
    private const string ResetRoute = "/api/v1/auth/reset-password";

    [Fact]
    public void InputsAreSecretAndDefaultsAreBounded()
    {
        var input = new ResetPasswordRequest { Token = "sensitive-code", Password = Password };
        Assert.Equal("{}", JsonSerializer.Serialize(input, JsonSerializerOptions.Web));
        Assert.DoesNotContain(Password, input.ToString());
        Assert.DoesNotContain(input.Token, input.ToString());
        Assert.Equal("{}", JsonSerializer.Serialize(new PasswordResetRequest { Email = Email }, JsonSerializerOptions.Web));
        Assert.Throws<JsonException>(() => JsonSerializer.Deserialize<ResetPasswordRequest>("{}", JsonSerializerOptions.Web));
        Assert.Throws<JsonException>(() => JsonSerializer.Deserialize<ResetPasswordRequest>("{\"token\":\"x\",\"password\":\"x\",\"role\":\"admin\"}", JsonSerializerOptions.Web));
        var options = new PasswordResetOptions();
        Assert.Equal(60, options.ResendCooldownSeconds); Assert.Equal(5, options.RequestsPerMinute);
        Assert.Equal(10, options.ConsumeRequestsPerMinute); Assert.Equal(100, options.QueueCapacity);
    }

    [PostgresFact]
    public async Task ResetRevokesEverySessionAndFamilyAndOldJwtWithoutChangingOtherAccounts()
    {
        var sender = new ResetSender();
        await using var factory = await RegistrationApiFactory.CreateAsync(resetSender: sender, includeAuthProbe: true);
        var id = await Seed(factory); var other = await Seed(factory, "other@example.test");
        using var client = factory.Client(false);
        var pair = await Login(client); var second = await Login(client);
        await using (var db = factory.Database())
        {
            db.AuthSessions.AddRange(new AuthSession(id, DateTimeOffset.UtcNow), new AuthSession(other, DateTimeOffset.UtcNow));
            await db.SaveChangesAsync();
        }
        var token = await Send(factory, sender);
        await using (var db = factory.Database())
        {
            var user = await db.Users.SingleAsync(x => x.Id == id);
            Assert.Equal(Hash(token), user.PasswordResetTokenHash);
            Assert.NotEqual(token, user.PasswordResetTokenHash);
            Assert.DoesNotContain(token, JsonSerializer.Serialize(user));
        }
        using var reset = await client.PostAsJsonAsync(ResetRoute, new { token, password = NewPassword });
        Assert.Equal(HttpStatusCode.NoContent, reset.StatusCode); Assert.True(reset.Headers.CacheControl?.NoStore);
        Assert.Empty(await reset.Content.ReadAsByteArrayAsync()); Assert.False(reset.Headers.Contains("Set-Cookie"));
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", pair.Access);
        using var denied = await client.GetAsync("/__tests/auth"); Assert.Equal(HttpStatusCode.Unauthorized, denied.StatusCode);
        client.DefaultRequestHeaders.Authorization = null;
        foreach (var refresh in new[] { pair.Refresh, second.Refresh })
        {
            using var rejected = await client.PostAsJsonAsync("/api/v1/auth/refresh", new { refreshToken = refresh });
            Assert.Equal(HttpStatusCode.Unauthorized, rejected.StatusCode);
        }
        using var oldLogin = await client.PostAsJsonAsync("/api/v1/auth/login", new { email = Email, password = Password });
        Assert.Equal(HttpStatusCode.Unauthorized, oldLogin.StatusCode);
        var next = await Login(client, NewPassword); Assert.Equal("1", new JsonWebToken(next.Access).GetClaim("credentialsVersion").Value);
        using var rotated = await client.PostAsJsonAsync("/api/v1/auth/refresh", new { refreshToken = next.Refresh });
        var rotatedBody = await rotated.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal("1", new JsonWebToken(rotatedBody.GetProperty("accessToken").GetString()!).GetClaim("credentialsVersion").Value);
        await using (var db = factory.Database())
        {
            var user = await db.Users.SingleAsync(x => x.Id == id);
            Assert.Equal(1, user.CredentialsVersion); Assert.Null(user.PasswordResetTokenHash); Assert.Null(user.PasswordResetExpiresAt);
            Assert.NotNull(user.PasswordResetLastSentAt);
            Assert.NotEqual(PasswordVerificationResult.Failed, new PasswordHasher<User>().VerifyHashedPassword(user, user.PasswordHash, NewPassword));
            Assert.All(await db.AuthSessions.Where(x => x.UserId == id).ToArrayAsync(), x => Assert.NotNull(x.RevokedAt));
            Assert.Null((await db.AuthSessions.SingleAsync(x => x.UserId == other)).RevokedAt);
            Assert.Equal(0, (await db.Users.SingleAsync(x => x.Id == other)).CredentialsVersion);
        }
        using var replay = await client.PostAsJsonAsync(ResetRoute, new { token, password = NewPassword });
        Assert.Equal(HttpStatusCode.UnprocessableEntity, replay.StatusCode);
        Assert.DoesNotContain(token, factory.Logs); Assert.DoesNotContain(NewPassword, factory.Logs);
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        Assert.Equal(Email.ToUpperInvariant(), await sender.Completed.Reader.ReadAsync(timeout.Token));
    }

    [PostgresFact]
    public async Task CooldownRotationPurposeExpiryAndPolicyDoNotConsumeValidCode()
    {
        var sender = new ResetSender(); var clock = new ResetClock();
        await using var factory = await RegistrationApiFactory.CreateAsync(resetSender: sender, clock: clock);
        await Seed(factory); var token = await Send(factory, sender);
        await using (var scope = factory.Services.CreateAsyncScope())
            await scope.ServiceProvider.GetRequiredService<PasswordResetService>().SendAsync(Email);
        Assert.False(sender.Tokens.Reader.TryRead(out _));
        using var client = factory.Client(false);
        foreach (var password in new[] { "short", new string('x', 129), "\ud800" })
        {
            // Invalid UTF-16 cannot be JSON encoded, so exercise policy through the service directly.
            await using var scope = factory.Services.CreateAsyncScope();
            Assert.Null(await scope.ServiceProvider.GetRequiredService<PasswordResetService>().ResetAsync(token, password));
        }
        var verificationToken = new string('x', 43);
        await using (var db = factory.Database())
        {
            var verificationHash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(verificationToken)));
            await db.Users.ExecuteUpdateAsync(setters => setters
                .SetProperty(x => x.EmailVerificationTokenHash, verificationHash)
                .SetProperty(x => x.EmailVerificationLastSentAt, clock.GetUtcNow())
                .SetProperty(x => x.EmailVerificationExpiresAt, clock.GetUtcNow().AddMinutes(30)));
        }
        using var wrongPurpose = await client.PostAsJsonAsync(ResetRoute, new { token = verificationToken, password = NewPassword });
        Assert.Equal(HttpStatusCode.UnprocessableEntity, wrongPurpose.StatusCode);
        clock.Advance(TimeSpan.FromSeconds(60)); var replacement = await Send(factory, sender);
        Assert.NotEqual(token, replacement);
        using var old = await client.PostAsJsonAsync(ResetRoute, new { token, password = NewPassword });
        Assert.Equal(HttpStatusCode.UnprocessableEntity, old.StatusCode);
        clock.Advance(TimeSpan.FromMinutes(30));
        using var expired = await client.PostAsJsonAsync(ResetRoute, new { token = replacement, password = NewPassword });
        Assert.Equal(HttpStatusCode.UnprocessableEntity, expired.StatusCode);
        await using var context = factory.Database();
        Assert.Equal(0, (await context.Users.SingleAsync()).CredentialsVersion);
    }

    [PostgresFact]
    public async Task RequestsHideEligibilityAndRateLimitsAreAccountIndependent()
    {
        var sender = new ResetSender();
        await using var factory = await RegistrationApiFactory.CreateAsync(resetSender: sender);
        await Seed(factory); await Seed(factory, "admin@example.test", UserRole.Admin);
        await Seed(factory, "unverified@example.test", verified: false);
        using var client = factory.Client(false);
        foreach (var email in new[] { Email, "missing@example.test", "admin@example.test", "unverified@example.test", Email })
        {
            using var response = await client.PostAsJsonAsync(RequestRoute, new { email });
            Assert.Equal(HttpStatusCode.Accepted, response.StatusCode); Assert.Empty(await response.Content.ReadAsByteArrayAsync());
        }
        using var limited = await client.PostAsJsonAsync(RequestRoute, new { email = "missing2@example.test" });
        Assert.Equal(HttpStatusCode.TooManyRequests, limited.StatusCode);
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        _ = await sender.Tokens.Reader.ReadAsync(timeout.Token);
        for (var n = 0; n < 10; n++)
        {
            using var invalid = await client.PostAsJsonAsync(ResetRoute, new { token = "invalid", password = NewPassword });
            Assert.Equal(HttpStatusCode.UnprocessableEntity, invalid.StatusCode);
        }
        using var consumedLimit = await client.PostAsJsonAsync(ResetRoute, new { token = "invalid", password = NewPassword });
        Assert.Equal(HttpStatusCode.TooManyRequests, consumedLimit.StatusCode);
        await using var db = factory.Database();
        Assert.Equal(1, await db.Users.CountAsync(x => x.PasswordResetTokenHash != null));
        Assert.All(await db.Users.ToArrayAsync(), x => Assert.Equal(0, x.CredentialsVersion));
    }

    [PostgresFact]
    public async Task ConcurrentResetHasExactlyOneWinner()
    {
        var sender = new ResetSender();
        await using var factory = await RegistrationApiFactory.CreateAsync(resetSender: sender);
        await Seed(factory); var token = await Send(factory, sender);
        using var a = factory.Client(false); using var b = factory.Client(false);
        var results = await Task.WhenAll(a.PostAsJsonAsync(ResetRoute, new { token, password = NewPassword }),
            b.PostAsJsonAsync(ResetRoute, new { token, password = NewPassword }));
        Assert.Equal(new[] { 204, 422 }, results.Select(x => (int)x.StatusCode).Order().ToArray());
        foreach (var result in results) result.Dispose();
        await using var db = factory.Database(); Assert.Equal(1, (await db.Users.SingleAsync()).CredentialsVersion);
    }

    [PostgresFact]
    public async Task ExistingProtectedWebCookieIsRejectedImmediatelyAfterReset()
    {
        var sender = new ResetSender();
        await using var factory = await RegistrationApiFactory.CreateAsync(resetSender: sender, webSessions: true);
        await Seed(factory); using var web = factory.Client(); using var anonymous = factory.Client(false);
        var csrf = await web.GetFromJsonAsync<JsonElement>("/api/v1/auth/csrf");
        using var request = new HttpRequestMessage(HttpMethod.Post, "/api/v1/auth/web-session")
            { Content = JsonContent.Create(new { email = Email, password = Password }) };
        request.Headers.Add("Origin", "https://localhost"); request.Headers.Add("X-CSRF-TOKEN", csrf.GetProperty("requestToken").GetString());
        using var login = await web.SendAsync(request); Assert.Equal(HttpStatusCode.OK, login.StatusCode);
        using var before = await web.GetAsync("/api/v1/auth/me"); Assert.Equal(HttpStatusCode.OK, before.StatusCode);
        var token = await Send(factory, sender);
        using var reset = await anonymous.PostAsJsonAsync(ResetRoute, new { token, password = NewPassword }); Assert.Equal(HttpStatusCode.NoContent, reset.StatusCode);
        using var after = await web.GetAsync("/api/v1/auth/me"); Assert.Equal(HttpStatusCode.Unauthorized, after.StatusCode);
    }

    [PostgresFact]
    public async Task MigrationPreservesExistingHashesProfilesSessionsAndRefreshHistory()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync();
        var id = await Seed(factory); using var client = factory.Client(false); _ = await Login(client);
        await using var db = factory.Database();
        var user = await db.Users.SingleAsync(); var hash = user.PasswordHash;
        _ = new ClientProfile(Guid.NewGuid(), user, "Synthetic reset migration");
        db.AuthSessions.Add(new AuthSession(id, DateTimeOffset.UtcNow)); await db.SaveChangesAsync();
        await db.GetService<IMigrator>().MigrateAsync("20261031054305_AddRefreshTokens");
        await db.Database.MigrateAsync(); db.ChangeTracker.Clear();
        var restored = await db.Users.SingleAsync(); Assert.Equal(id, restored.Id); Assert.Equal(hash, restored.PasswordHash);
        Assert.Equal(0, restored.CredentialsVersion); Assert.Null(restored.PasswordResetTokenHash);
        Assert.Single(await db.ClientProfiles.ToArrayAsync()); Assert.Single(await db.AuthSessions.ToArrayAsync()); Assert.Single(await db.RefreshTokens.ToArrayAsync());
        Assert.False(db.Database.HasPendingModelChanges());
    }

    [PostgresFact]
    public async Task CleanupAndVersionOverflowNeverChangePasswordOrDeleteAccounts()
    {
        var clock = new ResetClock(); var sender = new ResetSender();
        await using var factory = await RegistrationApiFactory.CreateAsync(resetSender: sender, clock: clock);
        var id = await Seed(factory); var token = await Send(factory, sender);
        await using (var db = factory.Database())
            await db.Users.ExecuteUpdateAsync(setters => setters.SetProperty(x => x.CredentialsVersion, long.MaxValue));
        using var client = factory.Client(false);
        using var failed = await client.PostAsJsonAsync(ResetRoute, new { token, password = NewPassword }); Assert.Equal(HttpStatusCode.InternalServerError, failed.StatusCode);
        await using var context = factory.Database(); var unchanged = await context.Users.SingleAsync();
        Assert.Equal(Hash(token), unchanged.PasswordResetTokenHash); Assert.Equal(long.MaxValue, unchanged.CredentialsVersion);
        clock.Advance(TimeSpan.FromMinutes(30)); await PasswordResetCleanup.DeleteExpiredAsync(context, clock.GetUtcNow(), default);
        context.ChangeTracker.Clear(); var expired = await context.Users.SingleAsync(); Assert.Null(expired.PasswordResetTokenHash); Assert.NotNull(expired.PasswordResetLastSentAt);
        clock.Advance(TimeSpan.FromHours(24)); await PasswordResetCleanup.DeleteExpiredAsync(context, clock.GetUtcNow(), default);
        context.ChangeTracker.Clear(); var cleaned = await context.Users.SingleAsync(); Assert.Equal(id, cleaned.Id); Assert.Null(cleaned.PasswordResetLastSentAt);
        Assert.NotEqual(PasswordVerificationResult.Failed, new PasswordHasher<User>().VerifyHashedPassword(cleaned, cleaned.PasswordHash, Password));
    }

    [PostgresFact]
    public async Task DatabaseFailureRollsBackPasswordTokenAndBothSessionKinds()
    {
        var sender = new ResetSender(); var failure = new FailureInterceptor();
        await using var factory = await RegistrationApiFactory.CreateAsync(resetSender: sender, interceptor: failure);
        var id = await Seed(factory); using var client = factory.Client(false); _ = await Login(client);
        await using (var db = factory.Database()) { db.AuthSessions.Add(new AuthSession(id, DateTimeOffset.UtcNow)); await db.SaveChangesAsync(); }
        var token = await Send(factory, sender);
        failure.FailRevoke = true;
        using var reset = await client.PostAsJsonAsync(ResetRoute, new { token, password = NewPassword });
        Assert.Equal(HttpStatusCode.InternalServerError, reset.StatusCode); failure.FailRevoke = false;
        await using var context = factory.Database(); var user = await context.Users.SingleAsync();
        Assert.Equal(0, user.CredentialsVersion); Assert.Equal(Hash(token), user.PasswordResetTokenHash);
        Assert.Null((await context.AuthSessions.SingleAsync()).RevokedAt); Assert.Null((await context.RefreshTokens.SingleAsync()).RevokedAt);
        Assert.NotEqual(PasswordVerificationResult.Failed, new PasswordHasher<User>().VerifyHashedPassword(user, user.PasswordHash, Password));
    }

    [PostgresFact]
    public async Task BearerRejectsMissingMalformedStaleVersionsAndFailsClosedOnDatabaseOutage()
    {
        var failure = new FailureInterceptor();
        await using var factory = await RegistrationApiFactory.CreateAsync(includeAuthProbe: true, interceptor: failure);
        var id = await Seed(factory); using var client = factory.Client(false);
        foreach (var version in new string?[] { null, "", "-1", "+0", "00", "0.0", "9223372036854775808", "1", "duplicate" })
        {
            var claims = new List<Claim> { new("sub", id.ToString()), new("role", "client") };
            if (version is not null) claims.Add(new("credentialsVersion", version == "duplicate" ? "0" : version));
            if (version == "duplicate") claims.Add(new("credentialsVersion", "0"));
            client.DefaultRequestHeaders.Authorization = new("Bearer", Signed(factory, claims));
            using var denied = await client.GetAsync("/__tests/auth"); Assert.Equal(HttpStatusCode.Unauthorized, denied.StatusCode);
        }
        client.DefaultRequestHeaders.Authorization = new("Bearer", Signed(factory,
            [new("sub", id.ToString()), new("role", "client"), new("credentialsVersion", "0", ClaimValueTypes.Integer64)]));
        using var numeric = await client.GetAsync("/__tests/auth"); Assert.Equal(HttpStatusCode.Unauthorized, numeric.StatusCode);
        var pair = await Login(client); client.DefaultRequestHeaders.Authorization = new("Bearer", pair.Access);
        failure.FailRead = true;
        using var unavailable = await client.GetAsync("/__tests/auth"); Assert.Equal(HttpStatusCode.InternalServerError, unavailable.StatusCode);
        failure.FailRead = false;
        using var allowed = await client.GetAsync("/__tests/auth"); Assert.Equal(HttpStatusCode.OK, allowed.StatusCode);
    }

    private static string Signed(RegistrationApiFactory factory, IEnumerable<Claim> claims) => new JsonWebTokenHandler().CreateToken(new SecurityTokenDescriptor
    { Issuer = factory.Jwt.Issuer, Audience = factory.Jwt.Audience, Subject = new ClaimsIdentity(claims),
        Expires = DateTime.UtcNow.AddMinutes(15), SigningCredentials = new(factory.Jwt.Options.CreateSigningKey(), SecurityAlgorithms.HmacSha256), TokenType = "at+jwt" });

    [PostgresFact]
    public async Task ResetRacingOldPasswordLoginAndRefreshLeavesNoUsableOldIdentity()
    {
        var sender = new ResetSender();
        await using var factory = await RegistrationApiFactory.CreateAsync(resetSender: sender, includeAuthProbe: true);
        await Seed(factory); using var a = factory.Client(false); using var b = factory.Client(false); using var c = factory.Client(false);
        var previous = await Login(a); var token = await Send(factory, sender);
        var reset = a.PostAsJsonAsync(ResetRoute, new { token, password = NewPassword });
        var login = b.PostAsJsonAsync("/api/v1/auth/login", new { email = Email, password = Password });
        var refresh = c.PostAsJsonAsync("/api/v1/auth/refresh", new { refreshToken = previous.Refresh });
        using var resetResponse = await reset; Assert.Equal(HttpStatusCode.NoContent, resetResponse.StatusCode);
        foreach (var response in await Task.WhenAll(login, refresh))
        {
            using (response)
            {
                Assert.Contains(response.StatusCode, new[] { HttpStatusCode.OK, HttpStatusCode.Unauthorized });
                if (response.StatusCode == HttpStatusCode.OK)
                {
                    var pair = await response.Content.ReadFromJsonAsync<JsonElement>();
                    c.DefaultRequestHeaders.Authorization = new("Bearer", pair.GetProperty("accessToken").GetString());
                    using var denied = await c.GetAsync("/__tests/auth"); Assert.Equal(HttpStatusCode.Unauthorized, denied.StatusCode);
                    c.DefaultRequestHeaders.Authorization = null;
                    using var rejected = await c.PostAsJsonAsync("/api/v1/auth/refresh", new { refreshToken = pair.GetProperty("refreshToken").GetString() });
                    Assert.Equal(HttpStatusCode.Unauthorized, rejected.StatusCode);
                }
            }
        }
        await using var db = factory.Database(); Assert.All(await db.RefreshTokens.ToArrayAsync(), x => Assert.NotNull(x.RevokedAt));
    }

    [PostgresFact]
    public async Task ResetPayloadErrorsNeverRevealTokensAndCannotSelectAnotherAccount()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); using var client = factory.Client(false);
        foreach (var json in new[] { "{}", "null", "{", "{\"token\":null,\"password\":\"abc\"}",
                     "{\"token\":42,\"password\":\"abc\"}", "{\"token\":\"x\",\"password\":null}",
                     "{\"token\":\"x\",\"password\":\"abc\",\"userId\":\"x\"}" })
        {
            using var response = await client.PostAsync(ResetRoute, new StringContent(json, Encoding.UTF8, "application/json"));
            Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
            var body = await response.Content.ReadFromJsonAsync<JsonElement>(); Assert.Equal("invalid_request", body.GetProperty("error").GetProperty("code").GetString());
        }
        using var query = await client.PostAsJsonAsync(ResetRoute + "?token=ignored", new { token = "x", password = NewPassword });
        Assert.Equal(HttpStatusCode.BadRequest, query.StatusCode);
        using var unsupported = await client.PostAsync(ResetRoute, new StringContent("x")); Assert.Equal(HttpStatusCode.UnsupportedMediaType, unsupported.StatusCode);
        client.DefaultRequestHeaders.Authorization = new("Bearer", "not-a-reset-identity");
        client.DefaultRequestHeaders.Add("Cookie", "untrusted=ignored");
        using var anonymous = await client.PostAsJsonAsync(RequestRoute, new { email = Email });
        Assert.Equal(HttpStatusCode.Accepted, anonymous.StatusCode);
    }

    [PostgresFact]
    public async Task FailedEmailDoesNotChangeGenericRequestOrRollBackSuccessfulReset()
    {
        var sender = new ResetSender { Fail = true };
        await using var factory = await RegistrationApiFactory.CreateAsync(resetSender: sender);
        await Seed(factory); using var client = factory.Client(false);
        using var requested = await client.PostAsJsonAsync(RequestRoute, new { email = Email });
        Assert.Equal(HttpStatusCode.Accepted, requested.StatusCode);
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        var token = await sender.Tokens.Reader.ReadAsync(timeout.Token);
        using var reset = await client.PostAsJsonAsync(ResetRoute, new { token, password = NewPassword });
        Assert.Equal(HttpStatusCode.NoContent, reset.StatusCode);
        _ = await sender.Completed.Reader.ReadAsync(timeout.Token);
        await using var db = factory.Database(); Assert.Equal(1, (await db.Users.SingleAsync()).CredentialsVersion);
        Assert.DoesNotContain("synthetic-private-smtp-detail", factory.Logs);
    }

    [MailpitFact]
    public async Task RealMailpitDeliversResetCodeAndNoticeWithoutLeakingPassword()
    {
        var uri = new Uri(Environment.GetEnvironmentVariable("SMART_NUTRITION_TEST_MAILPIT_URL")!); Assert.True(uri.IsLoopback);
        using var mail = new HttpClient { BaseAddress = uri };
        await using var factory = await RegistrationApiFactory.CreateAsync(useSmtp: true);
        var email = "synthetic-reset-" + Guid.NewGuid().ToString("N") + "@example.test";
        await Seed(factory, email); using var client = factory.Client(false); var ids = new HashSet<string>();
        try
        {
            using var requested = await client.PostAsJsonAsync(RequestRoute, new { email }); Assert.Equal(HttpStatusCode.Accepted, requested.StatusCode);
            var text = await ReadMail("Parola sıfırlama");
            var token = Assert.Single(text.Split('\n').Select(x => x.Trim()), x => PasswordResetService.ValidToken(x));
            Assert.Contains("30 dakika", text); Assert.DoesNotContain(Password, text);
            using var reset = await client.PostAsJsonAsync(ResetRoute, new { token, password = NewPassword }); Assert.Equal(HttpStatusCode.NoContent, reset.StatusCode);
            var notice = await ReadMail("Parolanız değiştirildi"); Assert.DoesNotContain(token, notice); Assert.DoesNotContain(NewPassword, notice);
            Assert.DoesNotContain(token, factory.Logs);
        }
        finally
        {
            if (ids.Count > 0)
            {
                using var cleanup = new HttpRequestMessage(HttpMethod.Delete, "/api/v1/messages") { Content = JsonContent.Create(new { IDs = ids }) };
                using var removed = await mail.SendAsync(cleanup); removed.EnsureSuccessStatusCode();
            }
        }
        async Task<string> ReadMail(string subject)
        {
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(20));
            while (true)
            {
                using var response = await mail.GetAsync("/api/v1/search?query=" + Uri.EscapeDataString("to:" + email), timeout.Token);
                var body = await response.Content.ReadFromJsonAsync<JsonElement>(timeout.Token);
                foreach (var message in body.GetProperty("messages").EnumerateArray())
                {
                    var id = message.GetProperty("ID").GetString()!; ids.Add(id);
                    if (!message.GetProperty("Subject").GetString()!.Contains(subject)) continue;
                    var detail = await mail.GetFromJsonAsync<JsonElement>("/api/v1/message/" + id, timeout.Token);
                    return detail.GetProperty("Text").GetString()!;
                }
                await Task.Delay(50, timeout.Token);
            }
        }
    }
    private static async Task<Guid> Seed(RegistrationApiFactory factory, string email = Email, UserRole role = UserRole.Client, bool verified = true)
    {
        await using var db = factory.Database(); var user = new User(Guid.NewGuid(), email.ToUpperInvariant(), role, Password, DateTimeOffset.UtcNow, new PasswordHasher<User>());
        db.Users.Add(user); db.Entry(user).Property(x => x.IsEmailVerified).CurrentValue = verified; await db.SaveChangesAsync(); return user.Id;
    }
    private static async Task<string> Send(RegistrationApiFactory factory, ResetSender sender)
    {
        await using var scope = factory.Services.CreateAsyncScope(); await scope.ServiceProvider.GetRequiredService<PasswordResetService>().SendAsync(Email);
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(10)); return await sender.Tokens.Reader.ReadAsync(timeout.Token);
    }
    private static async Task<(string Access, string Refresh)> Login(HttpClient client, string password = Password)
    {
        using var response = await client.PostAsJsonAsync("/api/v1/auth/login", new { email = Email, password });
        Assert.Equal(HttpStatusCode.OK, response.StatusCode); var body = await response.Content.ReadFromJsonAsync<JsonElement>();
        return (body.GetProperty("accessToken").GetString()!, body.GetProperty("refreshToken").GetString()!);
    }
    private static string Hash(string token) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes("password-reset:v1:" + token)));
    private sealed class ResetSender : IPasswordResetEmailSender
    {
        public bool Fail { get; set; }
        public Channel<string> Tokens { get; } = Channel.CreateUnbounded<string>();
        public Channel<string> Completed { get; } = Channel.CreateUnbounded<string>();
        public Task SendResetAsync(string recipient, string token, CancellationToken cancellationToken) { Tokens.Writer.TryWrite(token); if (Fail) throw new InvalidOperationException("synthetic-private-smtp-detail"); return Task.CompletedTask; }
        public Task SendResetCompletedAsync(string recipient, CancellationToken cancellationToken) { Completed.Writer.TryWrite(recipient); if (Fail) throw new InvalidOperationException("synthetic-private-smtp-detail"); return Task.CompletedTask; }
    }
    private sealed class ResetClock : TimeProvider
    {
        private DateTimeOffset _now = DateTimeOffset.UtcNow;
        public override DateTimeOffset GetUtcNow() => _now;
        public void Advance(TimeSpan duration) => _now += duration;
    }
    private sealed class FailureInterceptor : DbCommandInterceptor
    {
        public bool FailRevoke { get; set; }
        public bool FailRead { get; set; }
        public override ValueTask<InterceptionResult<int>> NonQueryExecutingAsync(DbCommand command, CommandEventData eventData, InterceptionResult<int> result, CancellationToken cancellationToken = default)
        { if (FailRevoke && command.CommandText.Contains("UPDATE refresh_tokens")) throw new InvalidOperationException("Synthetic failure."); return ValueTask.FromResult(result); }
        public override ValueTask<InterceptionResult<DbDataReader>> ReaderExecutingAsync(DbCommand command, CommandEventData eventData, InterceptionResult<DbDataReader> result, CancellationToken cancellationToken = default)
        { if (FailRead && command.CommandText.Contains("FROM users")) throw new InvalidOperationException("Synthetic failure."); return ValueTask.FromResult(result); }
    }
}
