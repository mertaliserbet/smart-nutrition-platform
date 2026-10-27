using System.Data.Common;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.Extensions.Options;
using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.Extensions.DependencyInjection;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Tests;

public sealed class WebSessionApiTests
{
    private const string Password = "sentetik web parolası 🔒";
    private const string Session = "/api/v1/auth/web-session";
    private const string Csrf = "/api/v1/auth/csrf";
    private const string Me = "/api/v1/auth/me";
    private const string CookieName = "__Host-smart-nutrition-session";

    [PostgresFact]
    public async Task LoginUsesProtectedSessionCookiesAndOnlyTheFiveApprovedAccountFields()
    {
        var clock = new SessionClock();
        await using var factory = await RegistrationApiFactory.CreateAsync(clock: clock, webSessions: true, includeAuthProbe: true);
        var user = await Seed(factory);
        using var client = factory.Client();
        using var login = await SignIn(client);
        Assert.Equal(HttpStatusCode.OK, login.StatusCode);
        Assert.True(login.Headers.CacheControl?.NoStore);
        using var json = JsonDocument.Parse(await login.Content.ReadAsStringAsync());
        Assert.Equal(["displayName", "email", "id", "isEmailVerified", "role"], json.RootElement.EnumerateObject().Select(p => p.Name).Order());
        Assert.Equal(user.Id, json.RootElement.GetProperty("id").GetGuid());
        var cookie = Assert.Single(login.Headers.GetValues("Set-Cookie"), value => value.StartsWith(CookieName + "="));
        foreach (var flag in new[] { "path=/", "secure", "samesite=strict", "httponly" }) Assert.Contains(flag, cookie.ToLowerInvariant());
        foreach (var forbidden in new[] { "expires=", "max-age=", "domain=", Password, "accessToken" }) Assert.DoesNotContain(forbidden, cookie);
        await using var database = factory.Database();
        var row = await database.AuthSessions.SingleAsync();
        Assert.Equal(user.Id, row.UserId);
        Assert.Equal(clock.Now.AddMinutes(30), row.IdleExpiresAt);
        Assert.Equal(clock.Now.AddHours(8), row.AbsoluteExpiresAt);
        Assert.DoesNotContain(row.Id.ToString(), await login.Content.ReadAsStringAsync());
        clock.Now = clock.Now.AddMinutes(20);
        using var csrf = await client.GetAsync(Csrf);
        Assert.Equal(HttpStatusCode.OK, csrf.StatusCode);
        await database.Entry(row).ReloadAsync();
        Assert.Equal(row.CreatedAt.AddMinutes(30), row.IdleExpiresAt);
        using var me = await client.GetAsync(Me);
        Assert.Equal(HttpStatusCode.OK, me.StatusCode);
        await database.Entry(row).ReloadAsync();
        Assert.Equal(clock.Now.AddMinutes(30), row.IdleExpiresAt);
        Assert.Equal(clock.Now, row.LastSeenAt);
        using var probe = await client.GetAsync("/__tests/auth");
        Assert.NotEqual(HttpStatusCode.OK, probe.StatusCode);
        foreach (var secret in new[] { Password, cookie.Split(';')[0], user.PasswordHash }) Assert.DoesNotContain(secret, factory.Logs);
    }

    [PostgresFact]
    public async Task LogoutRevokesOnlyTheCurrentSessionAndRejectsCookieReplay()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(webSessions: true);
        await Seed(factory);
        using var first = factory.Client();
        using var second = factory.Client();
        using var login = await SignIn(first);
        using var otherLogin = await SignIn(second);
        var cookie = login.Headers.GetValues("Set-Cookie").Single(value => value.StartsWith(CookieName + "=")).Split(';')[0];
        var token = await Token(first);
        using var deleted = await Delete(first, token);
        Assert.Equal(HttpStatusCode.NoContent, deleted.StatusCode);
        Assert.Equal(2, deleted.Headers.GetValues("Set-Cookie").Count());
        using var replay = factory.Client(false);
        replay.DefaultRequestHeaders.Add("Cookie", cookie);
        using var replayResponse = await replay.GetAsync(Me);
        Assert.Equal(HttpStatusCode.Unauthorized, replayResponse.StatusCode);
        using var remaining = await second.GetAsync(Me);
        Assert.Equal(HttpStatusCode.OK, remaining.StatusCode);
        using var repeated = await Delete(first, await Token(first));
        Assert.Equal(HttpStatusCode.NoContent, repeated.StatusCode);
        await using var database = factory.Database();
        Assert.Equal(1, await database.AuthSessions.CountAsync(row => row.RevokedAt != null));
        Assert.Equal(1, await database.AuthSessions.CountAsync(row => row.RevokedAt == null));
    }

    [PostgresFact]
    public async Task CsrfAndExactOriginAreRequiredBeforeCreatingOrDeletingSessions()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(webSessions: true);
        await Seed(factory);
        using var client = factory.Client();
        var token = await Token(client);
        foreach (var origin in new string?[] { null, "null", "https://localhost.evil.test", "http://localhost", "https://localhost:443" })
        {
            using var request = LoginRequest(token);
            request.Headers.Remove("Origin");
            if (origin is not null) request.Headers.Add("Origin", origin);
            using var response = await client.SendAsync(request);
            Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
        }
        using (var request = LoginRequest("invalid-csrf"))
        using (var response = await client.SendAsync(request)) Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        using (var request = LoginRequest(token))
        {
            request.Headers.Add("Sec-Fetch-Site", "cross-site");
            using var response = await client.SendAsync(request);
            Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
        }
        await using var database = factory.Database();
        Assert.Empty(await database.AuthSessions.ToListAsync());
    }

    [PostgresFact]
    public async Task OldCsrfCannotCrossLoginOrANewSessionForTheSameUser()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(webSessions: true);
        await Seed(factory);
        using var client = factory.Client();
        var anonymousToken = await Token(client);
        using (var response = await client.SendAsync(LoginRequest(anonymousToken))) Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using (var response = await Delete(client, anonymousToken)) Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        var firstSessionToken = await Token(client);
        using (var response = await client.SendAsync(LoginRequest(firstSessionToken))) Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
        using (var response = await Delete(client, firstSessionToken)) Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);
        using (var response = await SignIn(client)) Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using (var response = await Delete(client, firstSessionToken)) Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        using var me = await client.GetAsync(Me);
        Assert.Equal(HttpStatusCode.OK, me.StatusCode);
    }

    [PostgresFact]
    public async Task MixedCredentialsAndBearerOnWebResourcesAreRejectedWithoutFallback()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(webSessions: true);
        await Seed(factory);
        using var client = factory.Client();
        using var login = await SignIn(client);
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", "invalid");
        foreach (var path in new[] { Csrf, Me })
        {
            using var response = await client.GetAsync(path);
            Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        }
        using var delete = await Delete(client, "irrelevant");
        Assert.Equal(HttpStatusCode.BadRequest, delete.StatusCode);
        using var bearerOnly = factory.Client();
        bearerOnly.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", "invalid");
        using var responseOnly = await bearerOnly.GetAsync(Csrf);
        Assert.Equal(HttpStatusCode.BadRequest, responseOnly.StatusCode);
    }

    [PostgresFact]
    public async Task IdleExpiryIsExactAndCsrfRequestsDoNotKeepASessionAlive()
    {
        var clock = new SessionClock();
        await using var factory = await RegistrationApiFactory.CreateAsync(clock: clock, webSessions: true);
        await Seed(factory);
        using var client = factory.Client();
        using var login = await SignIn(client);
        clock.Now = clock.Now.AddMinutes(29);
        await Token(client);
        clock.Now = clock.Now.AddMinutes(1);
        using var expired = await client.GetAsync(Me);
        Assert.Equal(HttpStatusCode.Unauthorized, expired.StatusCode);
        Assert.Contains(expired.Headers.GetValues("Set-Cookie"), cookie => cookie.StartsWith(CookieName + "="));
    }

    [PostgresFact]
    public async Task AbsoluteExpiryCannotBeExtendedByActiveUse()
    {
        var clock = new SessionClock();
        await using var factory = await RegistrationApiFactory.CreateAsync(clock: clock, webSessions: true);
        await Seed(factory);
        using var client = factory.Client();
        using var login = await SignIn(client);
        for (var i = 0; i < 23; i++)
        {
            clock.Now = clock.Now.AddMinutes(20);
            using var active = await client.GetAsync(Me);
            Assert.Equal(HttpStatusCode.OK, active.StatusCode);
        }
        await using var database = factory.Database();
        var row = await database.AuthSessions.SingleAsync();
        Assert.Equal(row.AbsoluteExpiresAt, row.IdleExpiresAt);
        clock.Now = row.AbsoluteExpiresAt;
        using var expired = await client.GetAsync(Me);
        Assert.Equal(HttpStatusCode.Unauthorized, expired.StatusCode);
    }

    [PostgresFact]
    public async Task CurrentRoleVerificationAndAdminRestrictionsApplyOnEveryRead()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(webSessions: true);
        var user = await Seed(factory);
        using var client = factory.Client();
        using var login = await SignIn(client);
        await using var database = factory.Database();
        await database.Users.Where(row => row.Id == user.Id).ExecuteUpdateAsync(setters => setters.SetProperty(row => row.IsEmailVerified, false));
        using var response = await client.GetAsync(Me);
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        using var unverifiedLogin = await SignIn(client);
        Assert.Equal(HttpStatusCode.Unauthorized, unverifiedLogin.StatusCode);
        await database.Users.Where(row => row.Id == user.Id).ExecuteUpdateAsync(setters => setters
            .SetProperty(row => row.IsEmailVerified, true).SetProperty(row => row.Role, UserRole.Admin));
        using var adminLogin = await SignIn(client);
        Assert.Equal(HttpStatusCode.Unauthorized, adminLogin.StatusCode);
    }

    [PostgresFact]
    public async Task LoginAndJwtRoutesShareOneIpCounterAndCsrfHasItsOwnLimit()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(webSessions: true);
        using var client = factory.Client();
        for (var i = 0; i < 10; i++)
        {
            using var request = new HttpRequestMessage(HttpMethod.Post, i % 2 == 0 ? Session : "/api/v1/auth/login")
            { Content = JsonContent.Create(new { }) };
            request.Headers.Add("Origin", "https://localhost");
            using var response = await client.SendAsync(request);
            Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        }
        using var limited = await client.SendAsync(LoginRequest("invalid"));
        Assert.Equal(HttpStatusCode.TooManyRequests, limited.StatusCode);
        for (var i = 0; i < 30; i++) await Token(client);
        using var csrfLimited = await client.GetAsync(Csrf);
        Assert.Equal(HttpStatusCode.TooManyRequests, csrfLimited.StatusCode);
    }

    [PostgresFact]
    public async Task LogoutRacingAccountReadCannotResurrectASession()
    {
        var clock = new SessionClock();
        await using var factory = await RegistrationApiFactory.CreateAsync(clock: clock, webSessions: true);
        await Seed(factory);
        using var client = factory.Client();
        using var login = await SignIn(client);
        var token = await Token(client);
        clock.Now = clock.Now.AddMinutes(20);
        var results = await Task.WhenAll(client.GetAsync(Me), Delete(client, token));
        Assert.Equal(HttpStatusCode.NoContent, results[1].StatusCode);
        foreach (var response in results) response.Dispose();
        using var after = await client.GetAsync(Me);
        Assert.Equal(HttpStatusCode.Unauthorized, after.StatusCode);
        await using var database = factory.Database();
        Assert.NotNull((await database.AuthSessions.SingleAsync()).RevokedAt);
    }

    [PostgresFact]
    public async Task PasswordChangeTransactionRejectsLoginThatAlreadyVerifiedTheOldHash()
    {
        var gate = new LoginLockProbe();
        await using var factory = await RegistrationApiFactory.CreateAsync(interceptor: gate, webSessions: true);
        var user = await Seed(factory);
        await using var scope = factory.Services.CreateAsyncScope();
        var database = scope.ServiceProvider.GetRequiredService<SmartNutrition.Api.Data.AppDbContext>();
        await using var transaction = await database.Database.BeginTransactionAsync();
        await scope.ServiceProvider.GetRequiredService<WebSessionService>().RevokeAllAsync(user.Id, default);
        using var client = factory.Client();
        gate.Armed = true;
        var attempt = SignIn(client);
        await gate.Entered.Task.WaitAsync(TimeSpan.FromSeconds(10));
        var replacement = new PasswordHasher<User>().HashPassword(user, "different synthetic password");
        await database.Users.Where(row => row.Id == user.Id).ExecuteUpdateAsync(setters => setters.SetProperty(row => row.PasswordHash, replacement));
        await transaction.CommitAsync();
        using var response = await attempt;
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        Assert.Empty(await database.AuthSessions.ToListAsync());
    }

    [PostgresFact]
    public async Task SecurityRevocationRollsBackWithTheUserChangeAndCommitsForAllWebSessions()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(webSessions: true);
        var user = await Seed(factory);
        using var first = factory.Client();
        using var second = factory.Client();
        using var firstLogin = await SignIn(first);
        using var secondLogin = await SignIn(second);
        await using var scope = factory.Services.CreateAsyncScope();
        var database = scope.ServiceProvider.GetRequiredService<SmartNutrition.Api.Data.AppDbContext>();
        var service = scope.ServiceProvider.GetRequiredService<WebSessionService>();
        await Assert.ThrowsAsync<InvalidOperationException>(() => service.RevokeAllAsync(user.Id, default));
        await using (var transaction = await database.Database.BeginTransactionAsync())
        {
            await service.RevokeAllAsync(user.Id, default);
            await database.Users.Where(row => row.Id == user.Id).ExecuteUpdateAsync(setters => setters.SetProperty(row => row.Role, UserRole.Dietitian));
            await transaction.RollbackAsync();
        }
        using (var response = await first.GetAsync(Me)) Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        await using (var transaction = await database.Database.BeginTransactionAsync())
        {
            await service.RevokeAllAsync(user.Id, default);
            await database.Users.Where(row => row.Id == user.Id).ExecuteUpdateAsync(setters => setters.SetProperty(row => row.Role, UserRole.Dietitian));
            await transaction.CommitAsync();
        }
        using (var response = await first.GetAsync(Me)) Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        using (var response = await second.GetAsync(Me)) Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        Assert.Equal(2, await database.AuthSessions.CountAsync(row => row.RevokedAt != null));
    }

    [PostgresFact]
    public async Task DatabaseFailureNeverFallsBackToTheProtectedTicketOrReturnsAccountData()
    {
        var failure = new SessionDatabaseFailure();
        await using var factory = await RegistrationApiFactory.CreateAsync(interceptor: failure, webSessions: true);
        await Seed(factory);
        using var client = factory.Client();
        using var login = await SignIn(client);
        var token = await Token(client);
        failure.Armed = true;
        using var me = await client.GetAsync(Me);
        using var logout = await Delete(client, token);
        foreach (var response in new[] { me, logout })
        {
            Assert.Equal(HttpStatusCode.InternalServerError, response.StatusCode);
            Assert.True(response.Headers.CacheControl?.NoStore);
            var text = await response.Content.ReadAsStringAsync();
            Assert.Contains("internal_error", text);
            Assert.DoesNotContain("SYNTHETIC@EXAMPLE.TEST", text);
            Assert.DoesNotContain("synthetic database failure", text);
        }
        failure.Armed = false;
        await using var database = factory.Database();
        Assert.Null((await database.AuthSessions.SingleAsync()).RevokedAt);
    }

    [PostgresFact]
    public async Task RouteVariantsShapesAndInsecureTransportCannotBypassWebGuards()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(webSessions: true);
        await Seed(factory);
        using var client = factory.Client();
        foreach (var path in new[] { Session, "/API/v1/auth/WEB-SESSION/" })
        {
            using var response = await client.PostAsJsonAsync(path, new { email = "synthetic@example.test", password = Password });
            Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
        }
        using (var response = await client.GetAsync("http://localhost" + Csrf)) Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
        using (var response = await client.GetAsync(Csrf + "?userId=" + Guid.NewGuid())) Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        using (var request = new HttpRequestMessage(HttpMethod.Get, Csrf) { Content = JsonContent.Create(new { }) })
        using (var response = await client.SendAsync(request)) Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        var token = await Token(client);
        foreach (var content in new[] { "{}", "{\"email\":\"synthetic@example.test\",\"password\":\"x\",\"role\":\"admin\"}" })
        {
            using var request = LoginRequest(token);
            request.Content = new StringContent(content, System.Text.Encoding.UTF8, "application/json");
            using var response = await client.SendAsync(request);
            Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        }
        await using var database = factory.Database();
        Assert.Empty(await database.AuthSessions.ToListAsync());
    }

    [PostgresFact]
    public async Task TamperedAndMalformedProtectedIdentitiesAndForeignSessionReferencesAreRejected()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(webSessions: true);
        var user = await Seed(factory);
        using var client = factory.Client();
        using var login = await SignIn(client);
        await using var database = factory.Database();
        var row = await database.AuthSessions.SingleAsync();
        var format = factory.Services.GetRequiredService<IOptionsMonitor<CookieAuthenticationOptions>>().Get("WebSession").TicketDataFormat;
        foreach (var claims in new Claim[][]
        {
            [new("sub", user.Id.ToString()), new("sid", row.Id.ToString()), new("role", "admin")],
            [new("sub", Guid.NewGuid().ToString()), new("sid", row.Id.ToString()), new("role", "client")],
            [new("sub", user.Id.ToString()), new("sid", Guid.Empty.ToString()), new("role", "client")],
            [new("sub", user.Id.ToString()), new("sid", row.Id.ToString()), new("sid", row.Id.ToString()), new("role", "client")],
        })
        {
            var principal = new ClaimsPrincipal(new ClaimsIdentity(claims, "WebSession", "sub", "role"));
            var cookie = format.Protect(new AuthenticationTicket(principal, new AuthenticationProperties
            { IssuedUtc = DateTimeOffset.UtcNow, ExpiresUtc = DateTimeOffset.UtcNow.AddHours(8) }, "WebSession"));
            using var forged = factory.Client(false);
            forged.DefaultRequestHeaders.Add("Cookie", CookieName + "=" + cookie);
            using var response = await forged.GetAsync(Me);
            Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        }
        using var tampered = factory.Client(false);
        tampered.DefaultRequestHeaders.Add("Cookie", CookieName + "=invalid-ticket");
        using var invalid = await tampered.GetAsync(Me);
        Assert.Equal(HttpStatusCode.Unauthorized, invalid.StatusCode);
    }

    [PostgresFact]
    public Task ProtectedPersistentKeysAllowAnotherApiInstanceToReadTheSameSession() => SharedKeys(false);

    [PostgresFact]
    public Task CertificateProtectedKeysAlsoWorkWithoutAnOsCertificateStoreEntry() => SharedKeys(true);

    private static async Task SharedKeys(bool useCertificate)
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(webSessions: true, webCertificate: useCertificate);
        await Seed(factory);
        using var client = factory.Client();
        using var login = await SignIn(client);
        var cookie = login.Headers.GetValues("Set-Cookie").Single(value => value.StartsWith(CookieName + "=")).Split(';')[0];
        var key = Assert.Single(Directory.GetFiles(factory.KeyRing, "key-*.xml"));
        var xml = await File.ReadAllTextAsync(key);
        Assert.Contains("encryptedSecret", xml);
        Assert.DoesNotContain("<masterKey", xml);
        await using var another = factory.WithWebHostBuilder(_ => { });
        using var replay = another.CreateClient(new Microsoft.AspNetCore.Mvc.Testing.WebApplicationFactoryClientOptions
        { BaseAddress = new Uri("https://localhost"), HandleCookies = false, AllowAutoRedirect = false });
        replay.DefaultRequestHeaders.Add("Cookie", cookie);
        using var response = await replay.GetAsync(Me);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [PostgresFact]
    public async Task CleanupOnlyRemovesExpiredSessionRowsWithinTheRetentionBoundary()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(webSessions: true);
        var user = await Seed(factory);
        var now = DateTimeOffset.FromUnixTimeSeconds(DateTimeOffset.UtcNow.ToUnixTimeSeconds());
        await using var database = factory.Database();
        var old = new AuthSession(user.Id, now.AddHours(-25));
        var recent = new AuthSession(user.Id, now.AddHours(-24).AddMinutes(-19));
        var active = new AuthSession(user.Id, now);
        database.AuthSessions.AddRange(old, recent, active);
        await database.SaveChangesAsync();
        Assert.Equal(1, await AuthSessionCleanup.DeleteExpiredAsync(database, now, default));
        Assert.Equal(2, await database.AuthSessions.CountAsync());
        Assert.Single(await database.Users.ToListAsync());
        Assert.DoesNotContain(await database.AuthSessions.ToListAsync(), row => row.Id == old.Id);
    }

    private static async Task<User> Seed(RegistrationApiFactory factory)
    {
        var user = new User(Guid.NewGuid(), "SYNTHETIC@EXAMPLE.TEST", UserRole.Client, Password, DateTimeOffset.UtcNow, new PasswordHasher<User>());
        await using var database = factory.Database();
        database.Users.Add(user);
        await database.SaveChangesAsync();
        await database.Users.Where(row => row.Id == user.Id).ExecuteUpdateAsync(setters => setters.SetProperty(row => row.IsEmailVerified, true));
        return user;
    }

    private static async Task<string> Token(HttpClient client)
    {
        using var response = await client.GetAsync(Csrf);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        return body.RootElement.GetProperty("requestToken").GetString()!;
    }

    private static HttpRequestMessage LoginRequest(string token)
    {
        var request = new HttpRequestMessage(HttpMethod.Post, Session)
        { Content = JsonContent.Create(new { email = "synthetic@example.test", password = Password }) };
        request.Headers.Add("Origin", "https://localhost");
        request.Headers.Add("X-CSRF-TOKEN", token);
        return request;
    }

    private static async Task<HttpResponseMessage> SignIn(HttpClient client)
    {
        using var request = LoginRequest(await Token(client));
        return await client.SendAsync(request);
    }

    private static async Task<HttpResponseMessage> Delete(HttpClient client, string token)
    {
        using var request = new HttpRequestMessage(HttpMethod.Delete, Session);
        request.Headers.Add("Origin", "https://localhost");
        request.Headers.Add("X-CSRF-TOKEN", token);
        return await client.SendAsync(request);
    }

    private sealed class SessionClock : TimeProvider
    {
        public DateTimeOffset Now { get; set; } = DateTimeOffset.FromUnixTimeSeconds(DateTimeOffset.UtcNow.ToUnixTimeSeconds());
        public override DateTimeOffset GetUtcNow() => Now;
    }

    private sealed class LoginLockProbe : DbCommandInterceptor
    {
        public bool Armed { get; set; }
        public TaskCompletionSource Entered { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public override ValueTask<InterceptionResult<DbDataReader>> ReaderExecutingAsync(DbCommand command, CommandEventData eventData,
            InterceptionResult<DbDataReader> result, CancellationToken cancellationToken = default)
        {
            if (Armed && command.CommandText.Contains("FOR UPDATE")) Entered.TrySetResult();
            return base.ReaderExecutingAsync(command, eventData, result, cancellationToken);
        }
    }

    private sealed class SessionDatabaseFailure : DbCommandInterceptor
    {
        public bool Armed { get; set; }
        public override ValueTask<InterceptionResult<DbDataReader>> ReaderExecutingAsync(DbCommand command, CommandEventData eventData,
            InterceptionResult<DbDataReader> result, CancellationToken cancellationToken = default)
        {
            if (Armed && command.CommandText.Contains("auth_sessions")) throw new InvalidOperationException("synthetic database failure");
            return base.ReaderExecutingAsync(command, eventData, result, cancellationToken);
        }
    }
}
