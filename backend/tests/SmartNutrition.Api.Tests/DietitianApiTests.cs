using System.Data.Common;
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.Extensions.DependencyInjection;
using OtpNet;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Tests;

public sealed class DietitianApiTests
{
    private const string Password = "sentetik uzman parolası 🔒";
    private const string AdminEmail = "synthetic-admin@example.test";
    private const string Apply = "/api/v1/dietitians/apply";
    private const string Review = "/api/v1/admin/dietitians";
    private const string AdminLogin = "/api/v1/auth/admin-web-session";

    [PostgresFact]
    public async Task LocalBootstrapCreatesPrivateEnrollmentWithoutOverwritingAndResetRevokesSessions()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(webSessions: true);
        var directory = Path.Combine(Path.GetTempPath(), "nutrition-bootstrap-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        var input = Path.Combine(directory, "input.json"); var output = Path.Combine(directory, "enrollment.json");
        try
        {
            await File.WriteAllTextAsync(input, JsonSerializer.Serialize(new { email = AdminEmail, password = Password }));
            Assert.Equal(0, await AdminBootstrap.RunAsync(factory.Services, input, output));
            var enrollment = JsonSerializer.Deserialize<JsonElement>(await File.ReadAllTextAsync(output));
            Assert.Equal(10, enrollment.GetProperty("recoveryCodes").GetArrayLength());
            Assert.DoesNotContain(Password, await File.ReadAllTextAsync(output));
            var code = enrollment.GetProperty("recoveryCodes")[0].GetString()!;
            using var admin = factory.Client(); using var login = await SignIn(admin, code);
            Assert.Equal(HttpStatusCode.OK, login.StatusCode);
            Assert.Equal(1, await AdminBootstrap.RunAsync(factory.Services, input, output));
            File.Delete(output);
            Assert.Equal(0, await AdminBootstrap.RunAsync(factory.Services, input, output));
            using var oldSession = await admin.GetAsync("/api/v1/auth/me"); Assert.Equal(HttpStatusCode.Unauthorized, oldSession.StatusCode);
            using var other = factory.Client(); using var oldCode = await SignIn(other, code); Assert.Equal(HttpStatusCode.Unauthorized, oldCode.StatusCode);
        }
        finally { File.Delete(input); File.Delete(output); Directory.Delete(directory); }
    }

    [PostgresFact]
    public async Task ApplicationFailureRollsBackUserAndClientSessionsCannotReviewApplications()
    {
        var failure = new WriteFailure { Target = "dietitian_profiles" };
        await using var factory = await RegistrationApiFactory.CreateAsync(webSessions: true, interceptor: failure);
        using var client = factory.Client(); using var failed = await Application(client);
        Assert.Equal(HttpStatusCode.InternalServerError, failed.StatusCode);
        await using var db = factory.Database(); Assert.Empty(await db.Users.ToListAsync()); Assert.Empty(await db.DietitianProfiles.ToListAsync());
        failure.Target = null;
        using var registration = await client.PostAsJsonAsync("/api/v1/auth/register", new { email = "client@example.test", password = Password, displayName = "Synthetic client" });
        Assert.Equal(HttpStatusCode.Created, registration.StatusCode);
        await db.Users.ExecuteUpdateAsync(setters => setters.SetProperty(x => x.IsEmailVerified, true));
        using var request = new HttpRequestMessage(HttpMethod.Post, "/api/v1/auth/web-session")
        { Content = JsonContent.Create(new { email = "client@example.test", password = Password }) };
        request.Headers.Add("Origin", "https://localhost"); request.Headers.Add("X-CSRF-TOKEN", await Csrf(client));
        using var login = await client.SendAsync(request); Assert.Equal(HttpStatusCode.OK, login.StatusCode);
        using var forbidden = await client.GetAsync(Review + "?isVerified=false&page=1&pageSize=10"); Assert.Equal(HttpStatusCode.Forbidden, forbidden.StatusCode);
    }

    [PostgresFact]
    public async Task ApplicationCreatesSeparateUnverifiedProfileAndPreservesMinimalContract()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(webSessions: true);
        using var client = factory.Client();
        using var response = await Application(client);
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Single(json.RootElement.EnumerateObject());
        var id = json.RootElement.GetProperty("id").GetGuid();
        await using var db = factory.Database();
        var user = await db.Users.Include(x => x.DietitianProfile).SingleAsync(x => x.Id == id);
        Assert.Equal(UserRole.Dietitian, user.Role); Assert.False(user.IsEmailVerified);
        Assert.False(user.DietitianProfile!.IsVerified); Assert.NotEqual(id, user.DietitianProfile.Id);
        Assert.Equal("Sentetik Uzman", user.DietitianProfile.DisplayName);
        Assert.Equal("Sentetik mesleki açıklama", user.DietitianProfile.LicenseInfo);
        Assert.Empty(await db.ClientProfiles.ToListAsync());
        using var duplicate = await Application(client); Assert.Equal(HttpStatusCode.Conflict, duplicate.StatusCode);
        using var login = await client.PostAsJsonAsync("/api/v1/auth/login", new { email = "expert@example.test", password = Password });
        Assert.Equal(HttpStatusCode.Unauthorized, login.StatusCode);
        using var search = await client.GetAsync("/api/v1/dietitians?page=1&pageSize=10");
        Assert.DoesNotContain("Sentetik Uzman", await search.Content.ReadAsStringAsync());
    }

    [PostgresFact]
    public async Task ApplicationRejectsPrivilegeInjectionAndOverlongTextWithoutEchoingSecrets()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); using var client = factory.Client();
        using var injected = await client.PostAsJsonAsync(Apply, new { email = "expert@example.test", password = Password, displayName = "Test", licenseInfo = "Synthetic", isVerified = true });
        Assert.Equal(HttpStatusCode.BadRequest, injected.StatusCode);
        using var tooLong = await client.PostAsJsonAsync(Apply, new { email = "expert@example.test", password = Password, displayName = new string('x', 121), licenseInfo = "Synthetic" });
        Assert.Equal(HttpStatusCode.UnprocessableEntity, tooLong.StatusCode);
        using var weak = await client.PostAsJsonAsync(Apply, new { email = "expert@example.test", password = "short", displayName = "Test", licenseInfo = "Synthetic" });
        Assert.Equal(HttpStatusCode.UnprocessableEntity, weak.StatusCode);
        Assert.DoesNotContain(Password, factory.Logs);
    }

    [PostgresFact]
    public async Task AdminMfaCreatesServerProofWhileOrdinaryAndBearerAdminLoginsStayClosed()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(webSessions: true);
        var setup = await SeedAdmin(factory); using var client = factory.Client();
        using var ordinary = await client.PostAsJsonAsync("/api/v1/auth/login", new { email = AdminEmail, password = Password });
        Assert.Equal(HttpStatusCode.Unauthorized, ordinary.StatusCode);
        using var wrong = await SignIn(client, "bad-code"); Assert.Equal(HttpStatusCode.Unauthorized, wrong.StatusCode);
        using var login = await SignIn(client, setup.Codes[0]); Assert.Equal(HttpStatusCode.OK, login.StatusCode);
        using var me = await client.GetAsync("/api/v1/auth/me"); Assert.Equal(HttpStatusCode.OK, me.StatusCode);
        Assert.Contains("\"role\":\"admin\"", await me.Content.ReadAsStringAsync());
        await using var db = factory.Database(); Assert.True((await db.AuthSessions.SingleAsync()).IsMfaVerified);
        using var another = factory.Client(); using var replay = await SignIn(another, setup.Codes[0]);
        Assert.Equal(HttpStatusCode.Unauthorized, replay.StatusCode);
        foreach (var secret in setup.Codes.Append(setup.Key).Append(Password)) Assert.DoesNotContain(secret, factory.Logs);
    }

    [PostgresFact]
    public async Task TotpAndConcurrentRecoveryReplayOnlyCreateOneSession()
    {
        var clock = new FixedClock();
        await using var factory = await RegistrationApiFactory.CreateAsync(webSessions: true, clock: clock);
        var setup = await SeedAdmin(factory);
        var code = new Totp(Base32Encoding.ToBytes(setup.Key)).ComputeTotp(clock.GetUtcNow().UtcDateTime);
        using var first = factory.Client(); using var second = factory.Client();
        using var accepted = await SignIn(first, code); using var replay = await SignIn(second, code);
        Assert.Equal(HttpStatusCode.OK, accepted.StatusCode); Assert.Equal(HttpStatusCode.Unauthorized, replay.StatusCode);
        using var third = factory.Client(); using var fourth = factory.Client();
        var results = await Task.WhenAll(SignIn(third, setup.Codes[0]), SignIn(fourth, setup.Codes[0]));
        try { Assert.Single(results, result => result.StatusCode == HttpStatusCode.OK); Assert.Single(results, result => result.StatusCode == HttpStatusCode.Unauthorized); }
        finally { foreach (var response in results) response.Dispose(); }
    }

    [PostgresFact]
    public async Task ApprovalIsIdempotentAtomicAuditedAndMakesOnlyVerifiedExpertsSearchable()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(webSessions: true);
        var setup = await SeedAdmin(factory); using var admin = factory.Client();
        using var login = await SignIn(admin, setup.Codes[0]); Assert.Equal(HttpStatusCode.OK, login.StatusCode);
        using var applicant = factory.Client(); using var applied = await Application(applicant);
        await using var db = factory.Database(); var profile = await db.DietitianProfiles.SingleAsync();
        using var early = await Verify(admin, profile.Id); Assert.Equal(HttpStatusCode.Conflict, early.StatusCode);
        await db.Users.Where(x => x.Id == profile.UserId).ExecuteUpdateAsync(setters => setters.SetProperty(x => x.IsEmailVerified, true));
        using var list = await admin.GetAsync(Review + "?isVerified=false&page=1&pageSize=10");
        Assert.Equal(HttpStatusCode.OK, list.StatusCode); Assert.Contains(profile.LicenseInfo, await list.Content.ReadAsStringAsync());
        using var approved = await Verify(admin, profile.Id); using var repeated = await Verify(admin, profile.Id);
        Assert.Equal(HttpStatusCode.OK, approved.StatusCode); Assert.Equal(HttpStatusCode.OK, repeated.StatusCode);
        Assert.Single(await db.AuditEvents.ToListAsync());
        var audit = await db.AuditEvents.SingleAsync(); Assert.Null(audit.Metadata); Assert.Equal(profile.Id, audit.ResourceId);
        using var search = await applicant.GetAsync("/api/v1/dietitians?query=Sentetik&page=1&pageSize=10");
        var body = await search.Content.ReadAsStringAsync(); Assert.Contains(profile.DisplayName, body); Assert.DoesNotContain("licenseInfo", body);
        using var token = await applicant.PostAsJsonAsync("/api/v1/auth/login", new { email = "expert@example.test", password = Password });
        var jwt = (await token.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("accessToken").GetString();
        applicant.DefaultRequestHeaders.Authorization = new("Bearer", jwt);
        using var own = await applicant.GetAsync("/api/v1/dietitians/me"); Assert.Equal(HttpStatusCode.OK, own.StatusCode);
        using var account = await applicant.GetAsync("/api/v1/auth/me"); Assert.Contains(profile.DisplayName, await account.Content.ReadAsStringAsync());
        using var forbidden = await applicant.GetAsync(Review + "?isVerified=false&page=1&pageSize=10");
        Assert.Equal(HttpStatusCode.BadRequest, forbidden.StatusCode); // Bearer is not an Admin web credential.
    }

    [PostgresFact]
    public async Task MissingCsrfOrOriginCannotCreateAdminSessionsOrApproveAnExpert()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(webSessions: true);
        var setup = await SeedAdmin(factory); using var client = factory.Client();
        using var noOrigin = await client.PostAsJsonAsync(AdminLogin, new { email = AdminEmail, password = Password, mfaCode = setup.Codes[0] });
        Assert.Equal(HttpStatusCode.Forbidden, noOrigin.StatusCode);
        using var request = new HttpRequestMessage(HttpMethod.Post, AdminLogin)
        { Content = JsonContent.Create(new { email = AdminEmail, password = Password, mfaCode = setup.Codes[0] }) };
        request.Headers.Add("Origin", "https://localhost");
        using var noCsrf = await client.SendAsync(request); Assert.Equal(HttpStatusCode.BadRequest, noCsrf.StatusCode);
        using var unauthenticated = await client.GetAsync(Review + "?isVerified=false&page=1&pageSize=10");
        Assert.Equal(HttpStatusCode.Unauthorized, unauthenticated.StatusCode);
    }

    [PostgresFact]
    public async Task AuditFailureRollsBackApprovalAndMfaConsumptionRollsBackWithFailedLogin()
    {
        var failure = new WriteFailure();
        await using var factory = await RegistrationApiFactory.CreateAsync(webSessions: true, interceptor: failure);
        var setup = await SeedAdmin(factory); using var admin = factory.Client();
        failure.Target = "auth_sessions";
        using var failedLogin = await SignIn(admin, setup.Codes[0]); Assert.Equal(HttpStatusCode.InternalServerError, failedLogin.StatusCode);
        failure.Target = null;
        using var login = await SignIn(admin, setup.Codes[0]); Assert.Equal(HttpStatusCode.OK, login.StatusCode);
        using var applicant = factory.Client(); using var applied = await Application(applicant);
        await using var db = factory.Database(); var profile = await db.DietitianProfiles.SingleAsync();
        await db.Users.Where(x => x.Id == profile.UserId).ExecuteUpdateAsync(setters => setters.SetProperty(x => x.IsEmailVerified, true));
        failure.Target = "audit_events";
        using var failedApproval = await Verify(admin, profile.Id); Assert.Equal(HttpStatusCode.InternalServerError, failedApproval.StatusCode);
        Assert.False(await db.DietitianProfiles.Where(x => x.Id == profile.Id).Select(x => x.IsVerified).SingleAsync());
        Assert.Empty(await db.AuditEvents.ToListAsync());
    }

    private static Task<HttpResponseMessage> Application(HttpClient client) => client.PostAsJsonAsync(Apply,
        new { email = "expert@example.test", password = Password, displayName = " Sentetik Uzman ", licenseInfo = " Sentetik mesleki açıklama " });

    private static async Task<(string Key, string[] Codes)> SeedAdmin(RegistrationApiFactory factory)
    {
        using var scope = factory.Services.CreateScope(); var services = scope.ServiceProvider;
        var user = new User(Guid.NewGuid(), "SYNTHETIC-ADMIN@EXAMPLE.TEST", UserRole.Admin, Password, DateTimeOffset.UtcNow, new PasswordHasher<User>());
        var setup = services.GetRequiredService<AdminMfaService>().Initialize(user, DateTimeOffset.UtcNow);
        await using var db = factory.Database(); db.Users.Add(user); await db.SaveChangesAsync();
        return (setup.Key, setup.RecoveryCodes);
    }

    private static async Task<string> Csrf(HttpClient client)
    {
        using var response = await client.GetAsync("/api/v1/auth/csrf");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        return (await response.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("requestToken").GetString()!;
    }
    private static async Task<HttpResponseMessage> SignIn(HttpClient client, string code)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, AdminLogin)
        { Content = JsonContent.Create(new { email = AdminEmail, password = Password, mfaCode = code }) };
        request.Headers.Add("Origin", "https://localhost"); request.Headers.Add("X-CSRF-TOKEN", await Csrf(client));
        return await client.SendAsync(request);
    }
    private static async Task<HttpResponseMessage> Verify(HttpClient client, Guid id)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, $"{Review}/{id}/verify");
        request.Headers.Add("Origin", "https://localhost"); request.Headers.Add("X-CSRF-TOKEN", await Csrf(client));
        return await client.SendAsync(request);
    }
    private sealed class FixedClock : TimeProvider
    { public override DateTimeOffset GetUtcNow() => DateTimeOffset.FromUnixTimeSeconds(DateTimeOffset.UtcNow.ToUnixTimeSeconds()); }
    private sealed class WriteFailure : DbCommandInterceptor
    {
        public string? Target { get; set; }
        public override ValueTask<InterceptionResult<DbDataReader>> ReaderExecutingAsync(DbCommand command, CommandEventData eventData,
            InterceptionResult<DbDataReader> result, CancellationToken cancellationToken = default)
        {
            if (Target is not null && command.CommandText.Contains("INSERT INTO " + Target)) throw new InvalidOperationException("Synthetic write failure");
            return base.ReaderExecutingAsync(command, eventData, result, cancellationToken);
        }
    }
}
