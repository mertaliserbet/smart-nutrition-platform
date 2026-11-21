using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Features.Dietitians;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Tests;

public sealed partial class PasswordResetTests
{
    [PostgresFact]
    public async Task AdminResetPreservesMfaAndRevokesOldAdminCookieWithoutEnablingNormalLogin()
    {
        var sender = new ResetSender(); await using var factory = await RegistrationApiFactory.CreateAsync(resetSender: sender, webSessions: true);
        var id = await Seed(factory, role: UserRole.Admin); string[] recovery;
        await using (var db = factory.Database())
        {
            var admin = await db.Users.SingleAsync(u => u.Id == id);
            using var scope = factory.Services.CreateScope();
            recovery = scope.ServiceProvider.GetRequiredService<AdminMfaService>().Initialize(admin, DateTimeOffset.UtcNow).RecoveryCodes;
            await db.SaveChangesAsync();
        }
        using var oldWeb = factory.Client(); using (var login = await AdminLogin(oldWeb, Password, recovery[0])) Assert.Equal(HttpStatusCode.OK, login.StatusCode);
        string? secret; long? lastStep; string[] hashes;
        await using (var db = factory.Database())
        { var admin = await db.Users.SingleAsync(u => u.Id == id); secret = admin.TotpSecretProtected; lastStep = admin.LastUsedTotpStep; hashes = admin.MfaRecoveryCodeHashes.ToArray(); }
        var token = await Send(factory, sender); using var anonymous = factory.Client(false);
        using (var reset = await anonymous.PostAsJsonAsync(ResetRoute, new { token, password = NewPassword })) Assert.Equal(HttpStatusCode.NoContent, reset.StatusCode);
        using (var rejected = await oldWeb.GetAsync("/api/v1/auth/me")) Assert.Equal(HttpStatusCode.Unauthorized, rejected.StatusCode);
        await using (var db = factory.Database())
        {
            var admin = await db.Users.SingleAsync(u => u.Id == id);
            Assert.Equal(UserRole.Admin, admin.Role); Assert.True(admin.IsEmailVerified); Assert.Equal(1, admin.CredentialsVersion);
            Assert.True(secret == admin.TotpSecretProtected); Assert.True(lastStep == admin.LastUsedTotpStep);
            Assert.True(hashes.SequenceEqual(admin.MfaRecoveryCodeHashes));
        }
        using var web = factory.Client();
        using (var oldPassword = await AdminLogin(web, Password, recovery[1])) Assert.Equal(HttpStatusCode.Unauthorized, oldPassword.StatusCode);
        using (var missingMfa = await AdminLogin(web, NewPassword, "")) Assert.Contains(missingMfa.StatusCode, new[] { HttpStatusCode.BadRequest, HttpStatusCode.Unauthorized });
        using (var badMfa = await AdminLogin(web, NewPassword, "invalid")) Assert.Contains(badMfa.StatusCode, new[] { HttpStatusCode.BadRequest, HttpStatusCode.Unauthorized });
        using (var valid = await AdminLogin(web, NewPassword, recovery[1])) Assert.Equal(HttpStatusCode.OK, valid.StatusCode);
        using (var ordinary = await anonymous.PostAsJsonAsync("/api/v1/auth/login", new { email = Email, password = NewPassword })) Assert.Equal(HttpStatusCode.Unauthorized, ordinary.StatusCode);
        var csrf = await web.GetFromJsonAsync<JsonElement>("/api/v1/auth/csrf");
        using var normal = new HttpRequestMessage(HttpMethod.Post, "/api/v1/auth/web-session") { Content = JsonContent.Create(new { email = Email, password = NewPassword }) };
        normal.Headers.Add("Origin", "https://localhost"); normal.Headers.Add("X-CSRF-TOKEN", csrf.GetProperty("requestToken").GetString());
        using var normalLogin = await web.SendAsync(normal); Assert.NotEqual(HttpStatusCode.OK, normalLogin.StatusCode);
        SecretAbsent(factory.Logs, token); SecretAbsent(factory.Logs, NewPassword);
    }

    [MailpitFact]
    public async Task RealMailpitLinkUsesExistingReactRouteAndRevokesCookieAccessAndRefreshCredentials()
    {
        using var mail = new HttpClient { BaseAddress = new Uri(Environment.GetEnvironmentVariable("SMART_NUTRITION_TEST_MAILPIT_URL")!) };
        await using var factory = await RegistrationApiFactory.CreateAsync(useSmtp: true, webSessions: true);
        var email = "synthetic-u5-web-reset-" + Guid.NewGuid().ToString("N") + "@example.test";
        var id = await Seed(factory, email, UserRole.Dietitian);
        await using (var db = factory.Database())
        { var user = await db.Users.SingleAsync(u => u.Id == id); db.DietitianProfiles.Add(new DietitianProfile(user, "Synthetic U5 expert", "Synthetic U5 license")); await db.SaveChangesAsync(); }
        using var mobile = factory.Client(false); using var web = factory.Client(); using var anonymous = factory.Client(false);
        using var previous = await mobile.PostAsJsonAsync("/api/v1/auth/login", new { email, password = Password }); Assert.Equal(HttpStatusCode.OK, previous.StatusCode);
        var identity = await previous.Content.ReadFromJsonAsync<JsonElement>();
        using (var signedIn = await ExpertLogin(web, email, Password)) Assert.Equal(HttpStatusCode.OK, signedIn.StatusCode);
        var ids = new HashSet<string>();
        try
        {
            using var requested = await anonymous.PostAsJsonAsync(RequestRoute, new { email }); Assert.Equal(HttpStatusCode.Accepted, requested.StatusCode);
            var text = await ReadMail(mail, email, "Parola sıfırlama", ids);
            var link = new Uri(Assert.Single(Regex.Matches(text, @"https://[^\s]+").Select(m => m.Value)));
            Assert.Equal("https://localhost", link.GetLeftPart(UriPartial.Authority)); Assert.Equal("/sifremi-unuttum", link.AbsolutePath);
            Assert.Equal("", link.Query); var hasTokenFragment = link.Fragment.StartsWith("#token=", StringComparison.Ordinal); Assert.True(hasTokenFragment);
            var token = Uri.UnescapeDataString(link.Fragment[7..]); Assert.True(PasswordResetService.ValidToken(token));
            var code = Assert.Single(text.Split('\n').Select(line => line.Trim()), PasswordResetService.ValidToken);
            Assert.True(token == code); SecretAbsent(text, Password);
            using (var reset = await anonymous.PostAsJsonAsync(ResetRoute, new { token, password = NewPassword })) Assert.Equal(HttpStatusCode.NoContent, reset.StatusCode);
            using (var oldCookie = await web.GetAsync("/api/v1/auth/me")) Assert.Equal(HttpStatusCode.Unauthorized, oldCookie.StatusCode);
            mobile.DefaultRequestHeaders.Authorization = new("Bearer", identity.GetProperty("accessToken").GetString());
            using (var oldAccess = await mobile.GetAsync("/api/v1/auth/me")) Assert.Equal(HttpStatusCode.Unauthorized, oldAccess.StatusCode);
            mobile.DefaultRequestHeaders.Authorization = null;
            using (var oldRefresh = await mobile.PostAsJsonAsync("/api/v1/auth/refresh", new { refreshToken = identity.GetProperty("refreshToken").GetString() })) Assert.Equal(HttpStatusCode.Unauthorized, oldRefresh.StatusCode);
            using (var oldPassword = await anonymous.PostAsJsonAsync("/api/v1/auth/login", new { email, password = Password })) Assert.Equal(HttpStatusCode.Unauthorized, oldPassword.StatusCode);
            using (var newPassword = await anonymous.PostAsJsonAsync("/api/v1/auth/login", new { email, password = NewPassword })) Assert.Equal(HttpStatusCode.OK, newPassword.StatusCode);
            using (var reused = await anonymous.PostAsJsonAsync(ResetRoute, new { token, password = NewPassword })) Assert.Equal(HttpStatusCode.UnprocessableEntity, reused.StatusCode);
            var notice = await ReadMail(mail, email, "Parolanız değiştirildi", ids);
            SecretAbsent(notice, token); SecretAbsent(notice, NewPassword); SecretAbsent(factory.Logs, token); SecretAbsent(factory.Logs, NewPassword);
        }
        finally
        {
            if (ids.Count > 0)
            {
                using var cleanup = new HttpRequestMessage(HttpMethod.Delete, "/api/v1/messages") { Content = JsonContent.Create(new { IDs = ids }) };
                using var removed = await mail.SendAsync(cleanup); removed.EnsureSuccessStatusCode();
            }
        }
    }
    private static void SecretAbsent(string text, string secret)
    {
        // Unlike string assertion diagnostics, a boolean never prints live SMTP credentials on failure.
        var containsSecret = text.Contains(secret, StringComparison.Ordinal); Assert.False(containsSecret);
    }
    private static async Task<HttpResponseMessage> AdminLogin(HttpClient client, string password, string mfaCode)
    {
        var csrf = await client.GetFromJsonAsync<JsonElement>("/api/v1/auth/csrf");
        using var input = new HttpRequestMessage(HttpMethod.Post, "/api/v1/auth/admin-web-session") { Content = JsonContent.Create(new { email = Email, password, mfaCode }) };
        input.Headers.Add("Origin", "https://localhost"); input.Headers.Add("X-CSRF-TOKEN", csrf.GetProperty("requestToken").GetString());
        return await client.SendAsync(input);
    }
    private static async Task<HttpResponseMessage> ExpertLogin(HttpClient client, string email, string password)
    {
        var csrf = await client.GetFromJsonAsync<JsonElement>("/api/v1/auth/csrf");
        using var input = new HttpRequestMessage(HttpMethod.Post, "/api/v1/auth/web-session") { Content = JsonContent.Create(new { email, password }) };
        input.Headers.Add("Origin", "https://localhost"); input.Headers.Add("X-CSRF-TOKEN", csrf.GetProperty("requestToken").GetString());
        return await client.SendAsync(input);
    }
    private static async Task<string> ReadMail(HttpClient mail, string email, string subject, HashSet<string> ids)
    {
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(20));
        while (true)
        {
            var body = await mail.GetFromJsonAsync<JsonElement>("/api/v1/search?query=" + Uri.EscapeDataString("to:" + email), timeout.Token);
            foreach (var message in body.GetProperty("messages").EnumerateArray())
            {
                var id = message.GetProperty("ID").GetString()!; ids.Add(id);
                if (!message.GetProperty("Subject").GetString()!.Contains(subject, StringComparison.Ordinal)) continue;
                var detail = await mail.GetFromJsonAsync<JsonElement>("/api/v1/message/" + id, timeout.Token);
                return detail.GetProperty("Text").GetString()!;
            }
            await Task.Delay(50, timeout.Token);
        }
    }
}
