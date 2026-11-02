using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Features.Dietitians;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Tests;

public sealed class DualProfileApplicationTests
{
    private const string Password = " Synthetic parola 🔒 ";
    private const string Application = "/api/v1/dietitians/me/application";

    [PostgresFact]
    public async Task ApprovalAddsCapabilitiesWithoutChangingAccountTokensPersonalPlansOrRelationships()
    {
        await using var f = await RegistrationApiFactory.CreateAsync(webSessions: true);
        var owner = await Seed(f); var other = await Seed(f); var oldExpert = await Seed(f, true);
        using var personal = await Jwt(f, owner.Id); using var otherClient = await Jwt(f, other.Id); using var oldExpertClient = await Jwt(f, oldExpert.Id);
        using var plan = await personal.PostAsJsonAsync("/api/v1/nutrition-plans", Plan()); Assert.Equal(HttpStatusCode.Created, plan.StatusCode);
        var planId = (await Body(plan)).GetProperty("id").GetGuid();
        var existingRelation = await Connect(personal, oldExpertClient, oldExpert.Profile);
        using var web = f.Client(); await Login(web, owner.Email);
        using var applied = await Apply(web); Assert.Equal(HttpStatusCode.Created, applied.StatusCode);
        var expertId = (await Body(applied)).GetProperty("id").GetGuid();
        using var denied = await personal.GetAsync("/api/v1/dietitian/clients?page=1&pageSize=10"); Assert.Equal(HttpStatusCode.Forbidden, denied.StatusCode);
        personal.DefaultRequestHeaders.Add("X-Profile-Context", "dietitian");
        using var escalation = await personal.GetAsync("/api/v1/dietitian-relationships?page=1&pageSize=10"); Assert.Equal(HttpStatusCode.Forbidden, escalation.StatusCode);
        personal.DefaultRequestHeaders.Remove("X-Profile-Context");
        var adminSetup = await Admin(f); using var admin = f.Client(); await Login(admin, adminSetup.Email, adminSetup.Code);
        using var review = await admin.GetAsync("/api/v1/admin/dietitians?isVerified=false&page=1&pageSize=10");
        Assert.Contains((await Body(review)).GetProperty("items").EnumerateArray(), x => x.GetProperty("id").GetGuid() == expertId);
        using var approve = await Write(admin, $"/api/v1/admin/dietitians/{expertId}/verify"); Assert.Equal(HttpStatusCode.OK, approve.StatusCode);
        using var duplicate = await Apply(web); Assert.Equal(HttpStatusCode.Conflict, duplicate.StatusCode);
        using var account = await web.GetAsync("/api/v1/auth/me"); Assert.Equal("client", (await Body(account)).GetProperty("role").GetString());
        using var unchangedPlan = await personal.GetAsync($"/api/v1/nutrition-plans/{planId}"); Assert.Equal(HttpStatusCode.OK, unchangedPlan.StatusCode);
        using var own = await personal.GetAsync("/api/v1/dietitian-relationships?page=1&pageSize=10");
        Assert.Contains((await Body(own)).GetProperty("items").EnumerateArray(), x => x.GetProperty("id").GetGuid() == existingRelation);
        personal.DefaultRequestHeaders.Add("X-Profile-Context", "dietitian");
        using var professional = await personal.GetAsync("/api/v1/dietitian-relationships?page=1&pageSize=10"); Assert.Equal(0, (await Body(professional)).GetProperty("totalCount").GetInt32());
        using var privatePlan = await personal.GetAsync($"/api/v1/nutrition-plans/{planId}"); Assert.Equal(HttpStatusCode.NotFound, privatePlan.StatusCode);
        using var clients = await personal.GetAsync("/api/v1/dietitian/clients?page=1&pageSize=10"); Assert.Equal(HttpStatusCode.OK, clients.StatusCode);
        var relation = await Connect(otherClient, personal, expertId);
        using var permission = await otherClient.PostAsJsonAsync("/api/v1/data-sharing-permissions", new { relationshipId = relation, category = "nutrition_plans", isGranted = true });
        Assert.Equal(HttpStatusCode.Created, permission.StatusCode);
        using var assigned = await personal.PostAsJsonAsync("/api/v1/nutrition-plans", Plan(other.Profile)); Assert.Equal(HttpStatusCode.Created, assigned.StatusCode);
        var assignedId = (await Body(assigned)).GetProperty("id").GetGuid();
        using var otherRead = await otherClient.GetAsync($"/api/v1/nutrition-plans/{assignedId}"); Assert.Equal(HttpStatusCode.OK, otherRead.StatusCode);
        var permissionId = (await Body(permission)).GetProperty("id").GetGuid();
        using var revoked = await otherClient.PatchAsJsonAsync($"/api/v1/data-sharing-permissions/{permissionId}", new { isGranted = false }); Assert.Equal(HttpStatusCode.OK, revoked.StatusCode);
        using var deniedAfterRevoke = await personal.GetAsync($"/api/v1/nutrition-plans/{assignedId}"); Assert.Equal(HttpStatusCode.Forbidden, deniedAfterRevoke.StatusCode);
        personal.DefaultRequestHeaders.Remove("X-Profile-Context");
        using var self = await personal.PostAsJsonAsync("/api/v1/dietitian-relationships", new { dietitianId = expertId }); Assert.Equal(HttpStatusCode.Conflict, self.StatusCode);
        using var stillPersonal = await personal.GetAsync($"/api/v1/nutrition-plans/{planId}"); Assert.Equal(HttpStatusCode.OK, stillPersonal.StatusCode);
        await using var db = f.Database(); var user = await db.Users.SingleAsync(x => x.Id == owner.Id);
        Assert.Equal(owner.Hash, user.PasswordHash); Assert.Equal(UserRole.Client, user.Role); Assert.Equal(0, user.CredentialsVersion);
        Assert.Equal(owner.Profile, (await db.ClientProfiles.SingleAsync(x => x.UserId == owner.Id)).Id);
        Assert.Equal(1, await db.DietitianProfiles.CountAsync(x => x.UserId == owner.Id));
        Assert.Equal(4, await db.Users.CountAsync()); Assert.Single(await db.AuditEvents.ToArrayAsync());
    }

    [PostgresFact]
    public async Task ConcurrentApplicationsHaveOneProfileAndNeverGrantExpertAccess()
    {
        await using var f = await RegistrationApiFactory.CreateAsync(webSessions: true); var owner = await Seed(f);
        using var a = f.Client(); using var b = f.Client(); await Login(a, owner.Email); await Login(b, owner.Email);
        var at = await Csrf(a); var bt = await Csrf(b);
        var responses = await Task.WhenAll(Write(a, Application, new { displayName = "Synthetic", licenseInfo = "Synthetic license" }, at),
            Write(b, Application, new { displayName = "Synthetic", licenseInfo = "Synthetic license" }, bt));
        Assert.Equal(new[] { 201, 409 }, responses.Select(x => (int)x.StatusCode).Order().ToArray()); foreach (var response in responses) response.Dispose();
        await using var db = f.Database(); Assert.Single(await db.Users.ToArrayAsync()); Assert.Single(await db.ClientProfiles.ToArrayAsync());
        Assert.False((await db.DietitianProfiles.SingleAsync()).IsVerified);
        using var denied = await Write(a, "/api/v1/dietitians/me/invitation-code"); Assert.Equal(HttpStatusCode.Forbidden, denied.StatusCode);
    }

    [PostgresFact]
    public async Task ApplicationRequiresCookieCsrfAndCannotSelectEmailUserOrApproval()
    {
        foreach (var field in new[] { "email", "userId", "isVerified", "role", "password" })
        {
            await using var f = await RegistrationApiFactory.CreateAsync(webSessions: true); var owner = await Seed(f);
            using var web = f.Client(); using var anonymous = f.Client(false); using var bearer = await Jwt(f, owner.Id);
            using var noSession = await anonymous.PostAsJsonAsync(Application, new { displayName = "Synthetic", licenseInfo = "Synthetic" }); Assert.Equal(HttpStatusCode.Forbidden, noSession.StatusCode);
            using var wrongCredential = await bearer.PostAsJsonAsync(Application, new { displayName = "Synthetic", licenseInfo = "Synthetic" }); Assert.Equal(HttpStatusCode.BadRequest, wrongCredential.StatusCode);
            await Login(web, owner.Email);
            using var noCsrf = new HttpRequestMessage(HttpMethod.Post, Application) { Content = JsonContent.Create(new { displayName = "Synthetic", licenseInfo = "Synthetic" }) };
            noCsrf.Headers.Add("Origin", "https://localhost"); using var denied = await web.SendAsync(noCsrf); Assert.Equal(HttpStatusCode.BadRequest, denied.StatusCode);
            using var injected = await Write(web, Application, new Dictionary<string, object?> { ["displayName"] = "Synthetic", ["licenseInfo"] = "Synthetic", [field] = "injected" });
            Assert.Equal(HttpStatusCode.BadRequest, injected.StatusCode);
            await using var db = f.Database(); Assert.Empty(await db.DietitianProfiles.ToArrayAsync());
        }
    }

    [PostgresFact]
    public async Task ExistingApplicationRejectsInvalidShapesAdminAndUnverifiedSession()
    {
        await using var f = await RegistrationApiFactory.CreateAsync(webSessions: true); var owner = await Seed(f);
        using var web = f.Client(); await Login(web, owner.Email);
        using var invalid = await Write(web, Application, new { displayName = " ", licenseInfo = "Synthetic" }); Assert.Equal(HttpStatusCode.UnprocessableEntity, invalid.StatusCode);
        using var missing = await Write(web, Application, new { displayName = "Synthetic" }); Assert.Equal(HttpStatusCode.BadRequest, missing.StatusCode);
        using var query = await Write(web, Application + "?userId=" + owner.Id, new { displayName = "Synthetic", licenseInfo = "Synthetic" }); Assert.Equal(HttpStatusCode.BadRequest, query.StatusCode);
        var setup = await Admin(f); using var admin = f.Client(); await Login(admin, setup.Email, setup.Code);
        using var forbidden = await Apply(admin); Assert.Equal(HttpStatusCode.Forbidden, forbidden.StatusCode);
        await using var db = f.Database();
        await db.Users.Where(x => x.Id == owner.Id).ExecuteUpdateAsync(setters => setters.SetProperty(x => x.IsEmailVerified, false));
        using var unverified = await Apply(web); Assert.Equal(HttpStatusCode.Unauthorized, unverified.StatusCode);
        Assert.Empty(await db.DietitianProfiles.ToArrayAsync());
    }

    [PostgresFact]
    public async Task InvalidContextAndPendingOrRevokedCapabilityNeverBypassIsolation()
    {
        await using var f = await RegistrationApiFactory.CreateAsync(webSessions: true); var user = await Seed(f);
        using var jwt = await Jwt(f, user.Id);
        foreach (var value in new[] { "admin", "client,dietitian", "Dietitian", "dietitian" })
        {
            jwt.DefaultRequestHeaders.Remove("X-Profile-Context"); jwt.DefaultRequestHeaders.Add("X-Profile-Context", value);
            using var r = await jwt.GetAsync("/api/v1/nutrition-plans?page=1&pageSize=10");
            Assert.Equal(value == "dietitian" ? HttpStatusCode.Forbidden : HttpStatusCode.BadRequest, r.StatusCode);
        }
        await using var db = f.Database(); var account = await db.Users.SingleAsync(); var profile = new DietitianProfile(account, "Synthetic", "Synthetic");
        db.Entry(profile).Property(x => x.IsVerified).CurrentValue = true; await db.SaveChangesAsync();
        using var allowed = await jwt.GetAsync("/api/v1/dietitian/clients?page=1&pageSize=10"); Assert.Equal(HttpStatusCode.OK, allowed.StatusCode);
        jwt.DefaultRequestHeaders.Remove("X-Profile-Context");
        using var self = await jwt.PostAsJsonAsync("/api/v1/dietitian-relationships", new { dietitianId = profile.Id }); Assert.Equal(HttpStatusCode.UnprocessableEntity, self.StatusCode);
        await db.DietitianProfiles.ExecuteUpdateAsync(setters => setters.SetProperty(x => x.IsVerified, false));
        using var revoked = await jwt.GetAsync("/api/v1/dietitian/clients?page=1&pageSize=10"); Assert.Equal(HttpStatusCode.Forbidden, revoked.StatusCode);
    }

    private static object Plan(Guid? client = null)
    {
        var body = new Dictionary<string, object?> { ["title"] = "Synthetic history", ["startDate"] = "2026-11-02", ["items"] = new[] { new { dayOfWeek = (int?)null, mealType = "breakfast", description = "Synthetic meal", recommendedQuantity = "1", sortOrder = 0, recipeId = (Guid?)null, alternativeGroupId = (Guid?)null } } };
        if (client is not null) body["clientId"] = client; return body;
    }
    private static async Task<Guid> Connect(HttpClient client, HttpClient expert, Guid expertId)
    {
        using var r = await client.PostAsJsonAsync("/api/v1/dietitian-relationships", new { dietitianId = expertId }); Assert.Equal(HttpStatusCode.Created, r.StatusCode);
        var id = (await Body(r)).GetProperty("id").GetGuid(); using var accepted = await expert.PostAsync($"/api/v1/dietitian-relationships/{id}/accept", null); Assert.Equal(HttpStatusCode.OK, accepted.StatusCode); return id;
    }
    private static async Task<(Guid Id, Guid Profile, string Email, string Hash)> Seed(RegistrationApiFactory f, bool expert = false)
    {
        await using var db = f.Database(); var user = new User(Guid.NewGuid(), Guid.NewGuid().ToString("N") + "@example.test", expert ? UserRole.Dietitian : UserRole.Client, Password, DateTimeOffset.UtcNow, new PasswordHasher<User>());
        var id = expert ? new DietitianProfile(user, "Synthetic expert", "Synthetic").Id : new ClientProfile(Guid.NewGuid(), user, "Synthetic client").Id;
        db.Users.Add(user); db.Entry(user).Property(x => x.IsEmailVerified).CurrentValue = true;
        if (expert) db.Entry(user.DietitianProfile!).Property(x => x.IsVerified).CurrentValue = true;
        await db.SaveChangesAsync(); return (user.Id, id, user.Email, user.PasswordHash);
    }
    private static async Task<HttpClient> Jwt(RegistrationApiFactory f, Guid id)
    {
        await using var db = f.Database(); var user = await db.Users.SingleAsync(x => x.Id == id);
        var pair = new JwtAccessTokenService(Options.Create(f.Jwt.Options), TimeProvider.System).Issue(user); var client = f.Client(false); client.DefaultRequestHeaders.Authorization = new("Bearer", pair.AccessToken); return client;
    }
    private static async Task<(string Email, string Code)> Admin(RegistrationApiFactory f)
    {
        using var scope = f.Services.CreateScope(); var user = new User(Guid.NewGuid(), "admin@example.test", UserRole.Admin, Password, DateTimeOffset.UtcNow, new PasswordHasher<User>());
        var setup = scope.ServiceProvider.GetRequiredService<AdminMfaService>().Initialize(user, DateTimeOffset.UtcNow);
        await using var db = f.Database(); db.Users.Add(user); await db.SaveChangesAsync(); return (user.Email, setup.RecoveryCodes[0]);
    }
    private static async Task Login(HttpClient client, string email, string? code = null)
    { using var r = await Write(client, code is null ? "/api/v1/auth/web-session" : "/api/v1/auth/admin-web-session", code is null ? new { email, password = Password } : (object)new { email, password = Password, mfaCode = code }); Assert.Equal(HttpStatusCode.OK, r.StatusCode); }
    private static Task<HttpResponseMessage> Apply(HttpClient web) => Write(web, Application, new { displayName = "Synthetic professional", licenseInfo = "Synthetic license" });
    private static async Task<string> Csrf(HttpClient web) => (await web.GetFromJsonAsync<JsonElement>("/api/v1/auth/csrf")).GetProperty("requestToken").GetString()!;
    private static async Task<HttpResponseMessage> Write(HttpClient web, string path, object? body = null, string? csrf = null)
    { using var request = new HttpRequestMessage(HttpMethod.Post, path); if (body is not null) request.Content = JsonContent.Create(body); request.Headers.Add("Origin", "https://localhost"); request.Headers.Add("X-CSRF-TOKEN", csrf ?? await Csrf(web)); return await web.SendAsync(request); }
    private static Task<JsonElement> Body(HttpResponseMessage response) => response.Content.ReadFromJsonAsync<JsonElement>();
}
