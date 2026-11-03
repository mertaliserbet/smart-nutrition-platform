using System.Net;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Options;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Tests;

public sealed class AdminEmailCodeTests
{
    private static readonly DateTimeOffset Now = DateTimeOffset.Parse("2026-11-03T08:00:00Z");
    private const string Email = "SYNTHETIC-EMAIL-ADMIN@EXAMPLE.TEST", Password = "synthetic admin password";
    private const string CodePath = "/api/v1/auth/admin-email-code", LoginPath = "/api/v1/auth/admin-web-session";
    private static User Admin()
    {
        var user = new User(Guid.NewGuid(), Email, UserRole.Admin, Password, Now, new PasswordHasher<User>());
        new AdminMfaService(new EphemeralDataProtectionProvider(), Options.Create(new WebSessionOptions { Origin = "https://localhost" }))
            .Initialize(user, Now);
        return user;
    }
    private static AdminEmailCodeStore Store(string environment = "Development", bool enabled = true,
        string host = "127.0.0.1", int port = 1025) => new(new TestEnvironment { EnvironmentName = environment },
        Options.Create(new AdminEmailCodeOptions { Enabled = enabled }), Options.Create(new SmtpOptions { Host = host, Port = port }));

    [Theory]
    [InlineData("Production", true, "127.0.0.1", 1025)]
    [InlineData("Staging", true, "127.0.0.1", 1025)]
    [InlineData("Development", false, "127.0.0.1", 1025)]
    [InlineData("Development", true, "smtp.example.test", 1025)]
    [InlineData("Development", true, "localhost", 587)]
    public void DevelopmentAlternativeIsClosedOutsideExplicitLocalMailpit(string environment, bool enabled, string host, int port)
    {
        var store = Store(environment, enabled, host, port);
        Assert.False(store.Enabled);
        Assert.Null(store.Issue(Admin(), Now));
        Assert.False(store.AllowsPrincipal(new(new ClaimsIdentity([new Claim(AdminEmailCodeStore.DevelopmentClaim, "true")], "WebSession"))));
    }

    [Fact]
    public void CodesRequireDeliveryAreUserBoundSingleUseAndRespectCooldown()
    {
        var store = Store(); var admin = Admin(); var challenge = store.Issue(admin, Now)!.Value;
        Assert.Matches("^[0-9]{6}$", challenge.Code);
        Assert.False(store.TryConsume(admin, challenge.Code, Now));
        store.Delivered(admin.Id, challenge.Ticket, true);
        Assert.Null(store.Issue(admin, Now.AddSeconds(59)));
        Assert.False(store.TryConsume(Admin(), challenge.Code, Now));
        Assert.True(store.TryConsume(admin, challenge.Code, Now));
        Assert.False(store.TryConsume(admin, challenge.Code, Now));
        var next = store.Issue(admin, Now.AddSeconds(60))!.Value;
        store.Delivered(admin.Id, next.Ticket, true);
        Assert.True(store.TryConsume(admin, next.Code, Now.AddSeconds(60)));
    }

    [Fact]
    public void ExpiryAndFiveIncorrectAttemptsPermanentlyRejectTheChallenge()
    {
        var store = Store(); var admin = Admin(); var challenge = store.Issue(admin, Now)!.Value;
        store.Delivered(admin.Id, challenge.Ticket, true);
        Assert.False(store.TryConsume(admin, challenge.Code, Now.AddMinutes(5)));
        challenge = store.Issue(admin, Now.AddMinutes(5))!.Value;
        store.Delivered(admin.Id, challenge.Ticket, true);
        var wrong = challenge.Code == "000000" ? "111111" : "000000";
        for (var i = 0; i < 5; i++) Assert.False(store.TryConsume(admin, wrong, Now.AddMinutes(5)));
        Assert.False(store.TryConsume(admin, challenge.Code, Now.AddMinutes(5)));
    }

    [Fact]
    public void ReenrollingMfaInvalidatesAnOutstandingEmailCode()
    {
        var store = Store(); var admin = Admin(); var challenge = store.Issue(admin, Now)!.Value;
        store.Delivered(admin.Id, challenge.Ticket, true);
        new AdminMfaService(new EphemeralDataProtectionProvider(), Options.Create(new WebSessionOptions { Origin = "https://localhost" }))
            .Initialize(admin, Now.AddSeconds(1));
        Assert.False(store.TryConsume(admin, challenge.Code, Now.AddSeconds(1)));
    }

    [Fact]
    public async Task ConcurrentConsumptionHasExactlyOneWinnerAndDeliveryFailureNeverAuthorizes()
    {
        var store = Store(); var admin = Admin(); var challenge = store.Issue(admin, Now)!.Value;
        store.Delivered(admin.Id, challenge.Ticket, true);
        var results = await Task.WhenAll(Enumerable.Range(0, 10).Select(_ => Task.Run(() => store.TryConsume(admin, challenge.Code, Now))));
        Assert.Equal(1, results.Count(x => x));
        var failed = store.Issue(admin, Now.AddSeconds(60))!.Value;
        store.Delivered(admin.Id, failed.Ticket, false);
        Assert.False(store.TryConsume(admin, failed.Code, Now.AddSeconds(60)));
    }

    [PostgresFact]
    public async Task EmailCodeLogsIntoExistingAdminOnceWithoutChangingTotpAndCookieFailsClosedOutsideDevelopment()
    {
        var sender = new CaptureSender();
        await using var factory = await RegistrationApiFactory.CreateAsync(webSessions: true, adminEmailCodes: true, adminCodeSender: sender);
        var admin = Admin(); var originalSecret = admin.TotpSecretProtected;
        // Use this host's key protection for the real account; the email alternative does not modify it.
        using (var scope = factory.Services.CreateScope()) scope.ServiceProvider.GetRequiredService<AdminMfaService>().Initialize(admin, Now);
        originalSecret = admin.TotpSecretProtected;
        await using (var db = factory.Database()) { db.Users.Add(admin); await db.SaveChangesAsync(); }
        using var client = factory.Client();
        using var sent = await Write(client, CodePath, new { email = Email, password = Password });
        Assert.Equal(HttpStatusCode.Accepted, sent.StatusCode); Assert.Equal(1, sender.Count);
        Assert.Empty(await sent.Content.ReadAsStringAsync());
        using var cooldown = await Write(client, CodePath, new { email = Email, password = Password });
        Assert.Equal(HttpStatusCode.Accepted, cooldown.StatusCode); Assert.Equal(1, sender.Count);
        using var login = await Write(client, LoginPath, new { email = Email, password = Password, mfaCode = sender.Code });
        Assert.Equal(HttpStatusCode.OK, login.StatusCode);
        using var me = await client.GetAsync("/api/v1/auth/me"); Assert.Equal(HttpStatusCode.OK, me.StatusCode);
        using var other = factory.Client();
        using var replay = await Write(other, LoginPath, new { email = Email, password = Password, mfaCode = sender.Code });
        Assert.Equal(HttpStatusCode.Unauthorized, replay.StatusCode);
        await using (var db = factory.Database())
        {
            var stored = await db.Users.FindAsync(admin.Id);
            Assert.Equal(originalSecret, stored!.TotpSecretProtected);
            Assert.Null(stored.LastUsedTotpStep); Assert.Equal(10, stored.MfaRecoveryCodeHashes.Length);
        }
        Assert.DoesNotContain(sender.Code!, factory.Logs);
        factory.Services.GetRequiredService<IHostEnvironment>().EnvironmentName = "Production";
        factory.Services.GetRequiredService<IWebHostEnvironment>().EnvironmentName = "Production";
        Assert.False(factory.Services.GetRequiredService<AdminEmailCodeStore>().Enabled);
        using var productionMe = await client.GetAsync("/api/v1/auth/me");
        Assert.Equal(HttpStatusCode.Unauthorized, productionMe.StatusCode);
    }

    [PostgresFact]
    public async Task RequestRequiresOriginCsrfAndPasswordDoesNotRevealUnknownAccountsAndNeverLogsAnSmtpFailure()
    {
        var sender = new CaptureSender { Fail = true };
        await using var factory = await RegistrationApiFactory.CreateAsync(webSessions: true, adminEmailCodes: true, adminCodeSender: sender);
        var admin = Admin(); await using (var db = factory.Database()) { db.Users.Add(admin); await db.SaveChangesAsync(); }
        using var client = factory.Client();
        using var noOrigin = await client.PostAsJsonAsync(CodePath, new { email = Email, password = Password });
        Assert.Equal(HttpStatusCode.Forbidden, noOrigin.StatusCode);
        using var noCsrfRequest = new HttpRequestMessage(HttpMethod.Post, CodePath) { Content = JsonContent.Create(new { email = Email, password = Password }) };
        noCsrfRequest.Headers.Add("Origin", "https://localhost");
        using var noCsrf = await client.SendAsync(noCsrfRequest); Assert.Equal(HttpStatusCode.BadRequest, noCsrf.StatusCode);
        using var unknown = await Write(client, CodePath, new { email = "unknown@example.test", password = Password });
        Assert.Equal(HttpStatusCode.Accepted, unknown.StatusCode); Assert.Equal(0, sender.Count);
        using var wrong = await Write(client, CodePath, new { email = Email, password = "incorrect password" });
        Assert.Equal(HttpStatusCode.Accepted, wrong.StatusCode); Assert.Equal(0, sender.Count);
        using var smtpFailure = await Write(client, CodePath, new { email = Email, password = Password });
        Assert.Equal(HttpStatusCode.Accepted, smtpFailure.StatusCode); Assert.Equal(1, sender.Count);
        Assert.DoesNotContain("synthetic smtp failure", factory.Logs);
        using var cannotLogin = await Write(client, LoginPath, new { email = Email, password = Password, mfaCode = sender.Code });
        Assert.Equal(HttpStatusCode.Unauthorized, cannotLogin.StatusCode);
    }

    [PostgresFact]
    public async Task ProductionEndpointCannotBeUsedAndRequestsHaveAnIpLimit()
    {
        await using (var factory = await RegistrationApiFactory.CreateAsync(webSessions: true))
        {
            using var client = factory.Client();
            using var closed = await Write(client, CodePath, new { email = Email, password = Password });
            Assert.Equal(HttpStatusCode.NotFound, closed.StatusCode);
        }
        await using var development = await RegistrationApiFactory.CreateAsync(webSessions: true, adminEmailCodes: true, adminCodeSender: new CaptureSender());
        using var browser = development.Client();
        for (var i = 0; i < 5; i++)
        {
            using var sent = await Write(browser, CodePath, new { email = "unknown@example.test", password = Password });
            Assert.Equal(HttpStatusCode.Accepted, sent.StatusCode);
        }
        using var limited = await Write(browser, CodePath, new { email = Email, password = Password });
        Assert.Equal(HttpStatusCode.TooManyRequests, limited.StatusCode);
    }

    private static async Task<HttpResponseMessage> Write(HttpClient client, string path, object body)
    {
        using var csrf = await client.GetAsync("/api/v1/auth/csrf");
        var token = (await csrf.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("requestToken").GetString()!;
        using var request = new HttpRequestMessage(HttpMethod.Post, path) { Content = JsonContent.Create(body) };
        request.Headers.Add("Origin", "https://localhost"); request.Headers.Add("X-CSRF-TOKEN", token);
        return await client.SendAsync(request);
    }
    private sealed class CaptureSender : IAdminEmailCodeSender
    {
        public int Count { get; private set; }
        public string? Code { get; private set; }
        public bool Fail { get; init; }
        public Task SendAdminCodeAsync(string recipient, string code, CancellationToken cancellationToken)
        { Count++; Code = code; if (Fail) throw new InvalidOperationException("synthetic smtp failure"); return Task.CompletedTask; }
    }
    private sealed class TestEnvironment : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = "Development";
        public string ApplicationName { get; set; } = "Synthetic tests";
        public string ContentRootPath { get; set; } = "";
        public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
    }
}
