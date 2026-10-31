using System.ComponentModel.DataAnnotations;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Microsoft.EntityFrameworkCore.Migrations.Operations;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.JsonWebTokens;
using SmartNutrition.Api.Data;
using SmartNutrition.Api.Data.Migrations;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Tests;

public sealed class RefreshTokenTests
{
    private const string Email = "synthetic-refresh@example.test";
    private const string Password = " Sentetik şifre 🔒 ";

    [Fact]
    public void RequestsAndResponsesCannotSerializeOrPrintInputSecrets()
    {
        const string secret = "synthetic-refresh-secret";
        var request = new RefreshTokenRequest { RefreshToken = secret };
        Assert.Equal("{}", JsonSerializer.Serialize(request, JsonSerializerOptions.Web));
        Assert.DoesNotContain(secret, request.ToString());
        Assert.Empty(request.Validate(new ValidationContext(request)));
        Assert.NotEmpty(new RefreshTokenRequest().Validate(new ValidationContext(request)));
        Assert.Throws<JsonException>(() => JsonSerializer.Deserialize<RefreshTokenRequest>("{}", JsonSerializerOptions.Web));
        Assert.Throws<JsonException>(() => JsonSerializer.Deserialize<RefreshTokenRequest>("{\"refreshToken\":\"synthetic\",\"familyId\":\"synthetic\"}", JsonSerializerOptions.Web));
        Assert.DoesNotContain(secret, new LoginUserResponse("synthetic-access", DateTimeOffset.UtcNow, secret, DateTimeOffset.UtcNow.AddDays(30)).ToString());
        Assert.Equal(30, new RefreshTokenOptions().LifetimeDays);
        Assert.Equal(30, new RefreshTokenOptions().RequestsPerMinute);
    }

    [Fact]
    public void MigrationOnlyAddsRefreshTableAndIndexes()
    {
        var operations = new AddRefreshTokens().UpOperations;
        Assert.Equal("refresh_tokens", Assert.Single(operations.OfType<CreateTableOperation>()).Name);
        Assert.All(operations, operation => Assert.True(operation is CreateTableOperation or CreateIndexOperation));
        var table = operations.OfType<CreateTableOperation>().Single();
        Assert.DoesNotContain(table.Columns, column => column.Name is "refresh_token" or "access_token");
        Assert.Contains(operations.OfType<CreateIndexOperation>(), index => index.IsUnique && index.Name == "ux_refresh_tokens_active_family" && index.Filter == "consumed_at IS NULL AND revoked_at IS NULL");
    }

    [PostgresFact]
    public async Task LoginStoresOnlyHashAndRefreshRotatesAtomicallyWithoutExtendingFamilyLifetime()
    {
        var clock = new MutableClock();
        await using var factory = await RegistrationApiFactory.CreateAsync(clock: clock);
        var userId = await Seed(factory);
        using var client = factory.Client();
        var initial = await Login(client);
        Assert.Matches("^[A-Za-z0-9_-]{43}$", initial.Refresh);
        Assert.Equal(clock.GetUtcNow().AddTicks(-clock.GetUtcNow().Ticks % 10).AddDays(30), initial.RefreshExpiry);
        await using (var database = factory.Database())
        {
            var saved = await database.RefreshTokens.SingleAsync();
            Assert.Equal(userId, saved.UserId);
            Assert.Equal(Hash(initial.Refresh), saved.TokenHash);
            Assert.NotEqual(initial.Refresh, saved.TokenHash);
            Assert.DoesNotContain(initial.Refresh, JsonSerializer.Serialize(saved));
        }
        clock.Advance(TimeSpan.FromSeconds(2));
        using var refreshed = await Refresh(client, initial.Refresh);
        var rotated = await ReadPair(refreshed);
        Assert.NotEqual(initial.Refresh, rotated.Refresh);
        Assert.NotEqual(initial.Access, rotated.Access);
        Assert.Equal(initial.RefreshExpiry, rotated.RefreshExpiry);
        var jwt = new JsonWebToken(rotated.Access);
        Assert.Equal(TimeSpan.FromMinutes(15), jwt.ValidTo - jwt.ValidFrom);
        Assert.Equal(rotated.AccessExpiry.UtcDateTime, jwt.ValidTo);
        await using (var database = factory.Database())
        {
            var history = await database.RefreshTokens.ToListAsync();
            Assert.Equal(2, history.Count);
            Assert.Single(history.Select(token => token.FamilyId).Distinct());
            Assert.Single(history, token => token.ConsumedAt is null && token.RevokedAt is null);
            Assert.NotNull(history.Single(token => token.TokenHash == Hash(initial.Refresh)).ConsumedAt);
        }
        Assert.DoesNotContain(initial.Refresh, factory.Logs);
        Assert.DoesNotContain(rotated.Refresh, factory.Logs);
        Assert.DoesNotContain(initial.Access, factory.Logs);
        Assert.DoesNotContain(rotated.Access, factory.Logs);
    }

    [PostgresFact]
    public async Task AncestorReuseRevokesEntireFamilyButDoesNotRevokeOtherLogins()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync();
        await Seed(factory);
        using var client = factory.Client();
        var first = await Login(client);
        var independent = await Login(client);
        using var secondResponse = await Refresh(client, first.Refresh);
        var second = await ReadPair(secondResponse);
        using var thirdResponse = await Refresh(client, second.Refresh);
        var third = await ReadPair(thirdResponse);
        using var replay = await Refresh(client, first.Refresh);
        await AssertError(replay, HttpStatusCode.Unauthorized, "unauthenticated");
        using var blocked = await Refresh(client, third.Refresh);
        Assert.Equal(HttpStatusCode.Unauthorized, blocked.StatusCode);
        using var unaffected = await Refresh(client, independent.Refresh);
        Assert.Equal(HttpStatusCode.OK, unaffected.StatusCode);
        await using var database = factory.Database();
        var family = await database.RefreshTokens.Where(value => value.TokenHash == Hash(first.Refresh)).Select(value => value.FamilyId).SingleAsync();
        Assert.All(await database.RefreshTokens.Where(value => value.FamilyId == family).ToListAsync(), value => Assert.NotNull(value.RevokedAt));
    }

    [PostgresFact]
    public async Task ExactAbsoluteExpiryIsRejectedAndConfiguredLifetimeIsApplied()
    {
        var clock = new MutableClock();
        await using var factory = await RegistrationApiFactory.CreateAsync(clock: clock);
        factory.Services.GetRequiredService<IOptions<RefreshTokenOptions>>().Value.LifetimeDays = 3;
        await Seed(factory);
        using var client = factory.Client();
        var pair = await Login(client);
        Assert.Equal(clock.GetUtcNow().AddTicks(-clock.GetUtcNow().Ticks % 10).AddDays(3), pair.RefreshExpiry);
        clock.Advance(TimeSpan.FromDays(3));
        using var expired = await Refresh(client, pair.Refresh);
        await AssertError(expired, HttpStatusCode.Unauthorized, "unauthenticated");
        await using var database = factory.Database();
        Assert.Single(await database.RefreshTokens.ToListAsync());
    }

    [PostgresFact]
    public async Task LogoutIsIdempotentRevokesOnlyCurrentFamilyAndDoesNotInstantlyRevokeAccessJwt()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(includeAuthProbe: true);
        await Seed(factory);
        using var client = factory.Client();
        var pair = await Login(client);
        var other = await Login(client);
        using var rotatedResponse = await Refresh(client, pair.Refresh);
        var rotated = await ReadPair(rotatedResponse);
        foreach (var token in new[] { pair.Refresh, pair.Refresh, new string('A', 43) })
        {
            using var response = await client.PostAsJsonAsync("/api/v1/auth/logout", new { refreshToken = token });
            Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);
            Assert.True(response.Headers.CacheControl?.NoStore);
            Assert.Empty(await response.Content.ReadAsByteArrayAsync());
        }
        using var denied = await Refresh(client, rotated.Refresh);
        Assert.Equal(HttpStatusCode.Unauthorized, denied.StatusCode);
        using var permitted = await Refresh(client, other.Refresh);
        Assert.Equal(HttpStatusCode.OK, permitted.StatusCode);
        using var probe = new HttpRequestMessage(HttpMethod.Get, "/__tests/auth");
        probe.Headers.Authorization = new AuthenticationHeaderValue("Bearer", rotated.Access);
        using var access = await client.SendAsync(probe);
        Assert.Equal(HttpStatusCode.OK, access.StatusCode);
    }

    [PostgresFact]
    public async Task ConcurrentReuseHasOneWinnerAndRevokesItsDescendant()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync();
        await Seed(factory);
        using var client = factory.Client();
        var pair = await Login(client);
        var responses = await Task.WhenAll(Refresh(client, pair.Refresh), Refresh(client, pair.Refresh));
        try
        {
            Assert.Single(responses, response => response.StatusCode == HttpStatusCode.OK);
            Assert.Single(responses, response => response.StatusCode == HttpStatusCode.Unauthorized);
            var winning = await ReadPair(responses.Single(response => response.StatusCode == HttpStatusCode.OK));
            using var denied = await Refresh(client, winning.Refresh);
            Assert.Equal(HttpStatusCode.Unauthorized, denied.StatusCode);
            await using var database = factory.Database();
            Assert.Equal(2, await database.RefreshTokens.CountAsync());
            Assert.All(await database.RefreshTokens.ToListAsync(), value => Assert.NotNull(value.RevokedAt));
        }
        finally { foreach (var response in responses) response.Dispose(); }
    }

    [PostgresFact]
    public async Task LogoutAndRefreshRaceCannotLeaveAUsableDescendant()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync();
        await Seed(factory);
        using var client = factory.Client();
        var pair = await Login(client);
        var refreshTask = Refresh(client, pair.Refresh);
        var logoutTask = client.PostAsJsonAsync("/api/v1/auth/logout", new { refreshToken = pair.Refresh });
        await Task.WhenAll(refreshTask, logoutTask);
        using var refresh = await refreshTask;
        using var logout = await logoutTask;
        Assert.Equal(HttpStatusCode.NoContent, logout.StatusCode);
        Assert.Contains(refresh.StatusCode, new[] { HttpStatusCode.OK, HttpStatusCode.Unauthorized });
        var lastToken = refresh.IsSuccessStatusCode ? (await ReadPair(refresh)).Refresh : pair.Refresh;
        using var denied = await Refresh(client, lastToken);
        Assert.Equal(HttpStatusCode.Unauthorized, denied.StatusCode);
        await using var database = factory.Database();
        Assert.All(await database.RefreshTokens.ToListAsync(), value => Assert.NotNull(value.RevokedAt));
    }

    [PostgresFact]
    public async Task FailedRotationRollsBackConsumptionAndAllowsTheOriginalTokenToRetry()
    {
        var interceptor = new FailRefreshInsert();
        await using var factory = await RegistrationApiFactory.CreateAsync(interceptor: interceptor);
        await Seed(factory);
        using var client = factory.Client();
        var pair = await Login(client);
        interceptor.Fail = true;
        using var failure = await Refresh(client, pair.Refresh);
        await AssertError(failure, HttpStatusCode.InternalServerError, "internal_error");
        await using (var database = factory.Database())
        {
            var token = await database.RefreshTokens.SingleAsync();
            Assert.Null(token.ConsumedAt); Assert.Null(token.RevokedAt);
        }
        interceptor.Fail = false;
        using var recovered = await Refresh(client, pair.Refresh);
        Assert.Equal(HttpStatusCode.OK, recovered.StatusCode);
        Assert.DoesNotContain(pair.Refresh, factory.Logs);
    }

    [PostgresFact]
    public async Task RevokedEmailOrChangedRoleIncludingAdminCannotRefresh()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync();
        var userId = await Seed(factory);
        using var client = factory.Client();
        foreach (var mutation in new[] { "email", "admin", "dietitian" })
        {
            await using var database = factory.Database();
            await database.Users.Where(value => value.Id == userId).ExecuteUpdateAsync(setters => setters
                .SetProperty(value => value.IsEmailVerified, true).SetProperty(value => value.Role, UserRole.Client));
            var pair = await Login(client);
            if (mutation == "email")
                await database.Users.Where(value => value.Id == userId).ExecuteUpdateAsync(setters => setters.SetProperty(value => value.IsEmailVerified, false));
            else
                await database.Users.Where(value => value.Id == userId).ExecuteUpdateAsync(setters => setters.SetProperty(value => value.Role, mutation == "admin" ? UserRole.Admin : UserRole.Dietitian));
            using var denied = await Refresh(client, pair.Refresh);
            Assert.Equal(HttpStatusCode.Unauthorized, denied.StatusCode);
            Assert.NotNull((await database.RefreshTokens.SingleAsync(value => value.TokenHash == Hash(pair.Refresh))).RevokedAt);
        }
    }

    [PostgresFact]
    public async Task InvalidBodiesMixedCredentialsUnknownTokensAndLimitsUseSharedErrors()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync();
        using var client = factory.Client();
        foreach (var route in new[] { "refresh", "logout" })
        {
            foreach (var json in new[] { "{}", "{", "null", "{\"refreshToken\":null}", "{\"refreshToken\":42}", "{\"refreshToken\":\" \"}", "{\"refreshToken\":\"synthetic\",\"userId\":\"synthetic\"}" })
            {
                using var response = await client.PostAsync("/api/v1/auth/" + route, new StringContent(json, Encoding.UTF8, "application/json"));
                await AssertError(response, HttpStatusCode.BadRequest, "invalid_request");
            }
            using var unsupported = await client.PostAsync("/api/v1/auth/" + route, new StringContent("synthetic"));
            await AssertError(unsupported, HttpStatusCode.UnsupportedMediaType, "unsupported_media_type");
            foreach (var header in new[] { "Authorization", "Cookie" })
            {
                using var request = new HttpRequestMessage(HttpMethod.Post, "/api/v1/auth/" + route) { Content = JsonContent.Create(new { refreshToken = new string('A', 43) }) };
                request.Headers.TryAddWithoutValidation(header, header == "Cookie" ? "synthetic=value" : "Bearer synthetic");
                using var rejected = await client.SendAsync(request);
                await AssertError(rejected, HttpStatusCode.BadRequest, "invalid_request");
            }
            using var query = await client.PostAsJsonAsync("/api/v1/auth/" + route + "?userId=synthetic", new { refreshToken = new string('A', 43) });
            await AssertError(query, HttpStatusCode.BadRequest, "invalid_request");
        }
        using var unknown = await Refresh(client, new string('A', 43));
        await AssertError(unknown, HttpStatusCode.Unauthorized, "unauthenticated");
        HttpResponseMessage? last = null;
        for (var attempt = 0; attempt < 31; attempt++)
        {
            last?.Dispose(); last = await Refresh(client, new string('B', 43));
            if (last.StatusCode == HttpStatusCode.TooManyRequests) break;
        }
        using (last) { await AssertError(last!, HttpStatusCode.TooManyRequests, "rate_limited"); }
        await using var database = factory.Database();
        Assert.Empty(await database.RefreshTokens.ToListAsync());
    }

    [PostgresFact]
    public async Task CleanupDeletesExpiredFamiliesButRetainsActiveAncestorsForReplayDetection()
    {
        var clock = new MutableClock();
        await using var factory = await RegistrationApiFactory.CreateAsync(clock: clock);
        await Seed(factory);
        using var client = factory.Client();
        var initial = await Login(client);
        using var rotated = await Refresh(client, initial.Refresh);
        Assert.Equal(HttpStatusCode.OK, rotated.StatusCode);
        clock.Advance(TimeSpan.FromDays(1));
        var active = await Login(client);
        clock.Advance(TimeSpan.FromDays(29));
        await using var database = factory.Database();
        Assert.Equal(2, await RefreshTokenCleanup.DeleteExpiredAsync(database, clock.GetUtcNow(), default));
        Assert.Equal(Hash(active.Refresh), (await database.RefreshTokens.SingleAsync()).TokenHash);
        using var renewed = await Refresh(client, active.Refresh);
        var current = await ReadPair(renewed);
        Assert.Equal(0, await RefreshTokenCleanup.DeleteExpiredAsync(database, clock.GetUtcNow(), default));
        Assert.Equal(2, await database.RefreshTokens.CountAsync());
        using var replay = await Refresh(client, active.Refresh);
        Assert.Equal(HttpStatusCode.Unauthorized, replay.StatusCode);
        using var denied = await Refresh(client, current.Refresh);
        Assert.Equal(HttpStatusCode.Unauthorized, denied.StatusCode);
    }

    [PostgresFact]
    public async Task AdditiveMigrationPreservesExistingUsersProfilesAndWebSessions()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync();
        await using var database = factory.Database();
        var migrations = (await database.Database.GetAppliedMigrationsAsync()).ToArray();
        await database.GetService<IMigrator>().MigrateAsync(migrations[^2]);
        var id = await Seed(factory);
        database.AuthSessions.Add(new AuthSession(id, DateTimeOffset.UtcNow));
        await database.SaveChangesAsync();
        await database.Database.MigrateAsync();
        Assert.Equal(id, (await database.Users.SingleAsync()).Id);
        Assert.Single(await database.ClientProfiles.ToListAsync());
        Assert.Single(await database.AuthSessions.ToListAsync());
        Assert.Empty(await database.RefreshTokens.ToListAsync());
        Assert.False(database.Database.HasPendingModelChanges());
    }

    private static async Task<Guid> Seed(RegistrationApiFactory factory)
    {
        await using var database = factory.Database();
        var user = new User(Guid.NewGuid(), Email.ToUpperInvariant(), UserRole.Client, Password,
            DateTimeOffset.UtcNow, new PasswordHasher<User>());
        _ = new ClientProfile(Guid.NewGuid(), user, "Synthetic refresh client");
        database.Users.Add(user);
        database.Entry(user).Property(value => value.IsEmailVerified).CurrentValue = true;
        await database.SaveChangesAsync();
        return user.Id;
    }

    private static async Task<Pair> Login(HttpClient client)
    {
        using var response = await client.PostAsJsonAsync("/api/v1/auth/login", new { email = Email, password = Password });
        return await ReadPair(response);
    }
    private static Task<HttpResponseMessage> Refresh(HttpClient client, string token) => client.PostAsJsonAsync("/api/v1/auth/refresh", new { refreshToken = token });
    private static async Task<Pair> ReadPair(HttpResponseMessage response)
    {
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.True(response.Headers.CacheControl?.NoStore);
        Assert.False(response.Headers.Contains("Set-Cookie"));
        using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var body = document.RootElement;
        Assert.Equal(new[] { "accessToken", "expiresAt", "refreshToken", "refreshTokenExpiresAt", "tokenType" }, body.EnumerateObject().Select(value => value.Name).Order().ToArray());
        return new Pair(body.GetProperty("accessToken").GetString()!, body.GetProperty("refreshToken").GetString()!,
            body.GetProperty("expiresAt").GetDateTimeOffset(), body.GetProperty("refreshTokenExpiresAt").GetDateTimeOffset());
    }
    private static async Task AssertError(HttpResponseMessage response, HttpStatusCode status, string code)
    {
        Assert.Equal(status, response.StatusCode);
        Assert.True(response.Headers.CacheControl?.NoStore);
        using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal(code, document.RootElement.GetProperty("error").GetProperty("code").GetString());
        Assert.False(string.IsNullOrWhiteSpace(document.RootElement.GetProperty("requestId").GetString()));
        Assert.False(response.Headers.Contains("Set-Cookie"));
    }
    private static string Hash(string value) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value)));
    private sealed class Pair(string access, string refresh, DateTimeOffset accessExpiry, DateTimeOffset refreshExpiry)
    {
        public string Access { get; } = access;
        public string Refresh { get; } = refresh;
        public DateTimeOffset AccessExpiry { get; } = accessExpiry;
        public DateTimeOffset RefreshExpiry { get; } = refreshExpiry;
    }
    private sealed class MutableClock : TimeProvider
    {
        private DateTimeOffset _now = DateTimeOffset.UtcNow;
        public override DateTimeOffset GetUtcNow() => _now;
        public void Advance(TimeSpan duration) => _now += duration;
    }
    private sealed class FailRefreshInsert : SaveChangesInterceptor
    {
        public bool Fail { get; set; }
        public override ValueTask<InterceptionResult<int>> SavingChangesAsync(DbContextEventData eventData, InterceptionResult<int> result, CancellationToken cancellationToken = default)
        {
            if (Fail && eventData.Context!.ChangeTracker.Entries<RefreshToken>().Any(value => value.State == EntityState.Added))
                throw new InvalidOperationException("Synthetic refresh persistence failure.");
            return ValueTask.FromResult(result);
        }
    }
}
