using System.Data.Common;
using System.Net;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using Npgsql;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Features.Dietitians;
using SmartNutrition.Api.Features.Relationships;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Tests;

public sealed class RelationshipApiTests
{
    private const string Password = "synthetic relationship password";
    private const string Root = "/api/v1/dietitian-relationships";
    private const string Invite = "/api/v1/dietitians/me/invitation-code";
    private const string Permissions = "/api/v1/data-sharing-permissions";
    private sealed record Actor(Guid UserId, Guid ProfileId, string Email, UserRole Role);

    [Fact]
    public void MutationLimitsApplyToAnAccountAcrossIpsAndAnIpAcrossAccounts()
    {
        using var accounts = new RelationshipMutationLimits(Options.Create(new RelationshipLimitOptions { RequestsPerMinute = 2 }));
        var user = Guid.NewGuid(); accounts.Acquire("request", user, "one"); accounts.Acquire("request", user, "two");
        Assert.Equal(429, Assert.Throws<ResourceOperationException>(() => accounts.Acquire("request", user, "three")).StatusCode);
        using var ips = new RelationshipMutationLimits(Options.Create(new RelationshipLimitOptions { RequestsPerMinute = 2 }));
        ips.Acquire("request", Guid.NewGuid(), "one"); ips.Acquire("request", Guid.NewGuid(), "one");
        Assert.Equal(429, Assert.Throws<ResourceOperationException>(() => ips.Acquire("request", Guid.NewGuid(), "one")).StatusCode);
    }

    [PostgresFact]
    public async Task InvitationRotationConsumptionAndExpiryRequireAnIndependentMutualApproval()
    {
        var clock = new TestClock(); await using var factory = await RegistrationApiFactory.CreateAsync(clock: clock);
        var expert = await Seed(factory, UserRole.Dietitian); var client = await Seed(factory, UserRole.Client);
        using var dietitian = await Client(factory, expert); using var applicant = await Client(factory, client);
        var old = await Code(dietitian); var code = await Code(dietitian);
        using var rotated = await applicant.PostAsJsonAsync(Root, new { invitationCode = old }); Assert.Equal(HttpStatusCode.UnprocessableEntity, rotated.StatusCode);
        using var requested = await applicant.PostAsJsonAsync(Root, new { invitationCode = code }); Assert.Equal(HttpStatusCode.Created, requested.StatusCode);
        var row = await requested.Content.ReadFromJsonAsync<JsonElement>(); Assert.Equal("pending", row.GetProperty("status").GetString());
        using var other = await Client(factory, await Seed(factory, UserRole.Client));
        using var replay = await other.PostAsJsonAsync(Root, new { invitationCode = code }); Assert.Equal(HttpStatusCode.UnprocessableEntity, replay.StatusCode);
        var next = await Code(dietitian); clock.Now = clock.Now.AddHours(24);
        using var expired = await other.PostAsJsonAsync(Root, new { invitationCode = next }); Assert.Equal(HttpStatusCode.UnprocessableEntity, expired.StatusCode);
        await using var db = factory.Database(); Assert.Equal(0, await db.DietitianClientRelationships.CountAsync(x => x.Status == RelationshipStatus.Active));
        Assert.DoesNotContain(code, factory.Logs); Assert.DoesNotContain(next, factory.Logs);
        Assert.NotEqual(next, (await db.DietitianProfiles.SingleAsync()).InvitationCodeHash);
    }

    [PostgresFact]
    public async Task ConcurrentAcceptsPreserveOneActiveRelationshipAndTransitionsAreIdempotent()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync();
        var client = await Seed(factory, UserRole.Client); var first = await Seed(factory, UserRole.Dietitian); var second = await Seed(factory, UserRole.Dietitian);
        using var applicant = await Client(factory, client); using var a = await Client(factory, first); using var b = await Client(factory, second);
        var id1 = await Request(applicant, first.ProfileId); var id2 = await Request(applicant, second.ProfileId);
        var responses = await Task.WhenAll(a.PostAsync($"{Root}/{id1}/accept", null), b.PostAsync($"{Root}/{id2}/accept", null));
        try { Assert.Single(responses, x => x.StatusCode == HttpStatusCode.OK); Assert.Single(responses, x => x.StatusCode == HttpStatusCode.Conflict); }
        finally { foreach (var response in responses) response.Dispose(); }
        await using var db = factory.Database(); var active = await db.DietitianClientRelationships.SingleAsync(x => x.Status == RelationshipStatus.Active);
        using var repeat = await (active.DietitianId == first.ProfileId ? a : b).PostAsync($"{Root}/{active.Id}/accept", null);
        Assert.Equal(HttpStatusCode.OK, repeat.StatusCode);
        using var ended = await applicant.PostAsync($"{Root}/{active.Id}/end", null); using var endedAgain = await applicant.PostAsync($"{Root}/{active.Id}/end", null);
        Assert.Equal(HttpStatusCode.OK, ended.StatusCode); Assert.Equal(await ended.Content.ReadAsStringAsync(), await endedAgain.Content.ReadAsStringAsync());
        using var illegal = await (active.DietitianId == first.ProfileId ? a : b).PostAsync($"{Root}/{active.Id}/accept", null); Assert.Equal(HttpStatusCode.Conflict, illegal.StatusCode);
    }

    [PostgresFact]
    public async Task PermissionDefaultsClosedCanOnlyBeChangedByTheClientAndStopsAtRevocationOrEnd()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var client = await Seed(factory, UserRole.Client); var expert = await Seed(factory, UserRole.Dietitian);
        using var applicant = await Client(factory, client); using var dietitian = await Client(factory, expert);
        var id = await Request(applicant, expert.ProfileId);
        using var pending = await Grant(applicant, id); Assert.Equal(HttpStatusCode.Conflict, pending.StatusCode);
        using var accepted = await dietitian.PostAsync($"{Root}/{id}/accept", null); Assert.Equal(HttpStatusCode.OK, accepted.StatusCode);
        Assert.False(await CanAccess(factory, expert, client.ProfileId)); Assert.True(await CanAccess(factory, client, client.ProfileId));
        using var granted = await Grant(applicant, id); Assert.Equal(HttpStatusCode.Created, granted.StatusCode);
        var permission = (await granted.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid();
        Assert.True(await CanAccess(factory, expert, client.ProfileId));
        using var duplicate = await Grant(applicant, id); Assert.Equal(HttpStatusCode.Conflict, duplicate.StatusCode);
        using var impersonation = await Grant(dietitian, id); Assert.Equal(HttpStatusCode.Forbidden, impersonation.StatusCode);
        using var unrelated = await Client(factory, await Seed(factory, UserRole.Client));
        using var foreign = await unrelated.GetAsync($"{Permissions}/{permission}"); Assert.Equal(HttpStatusCode.NotFound, foreign.StatusCode);
        using var revoked = await applicant.PatchAsJsonAsync($"{Permissions}/{permission}", new { isGranted = false }); Assert.Equal(HttpStatusCode.OK, revoked.StatusCode);
        Assert.False(await CanAccess(factory, expert, client.ProfileId));
        using var restored = await applicant.PatchAsJsonAsync($"{Permissions}/{permission}", new { isGranted = true }); Assert.Equal(HttpStatusCode.OK, restored.StatusCode);
        using var ended = await applicant.PostAsync($"{Root}/{id}/end", null); Assert.Equal(HttpStatusCode.OK, ended.StatusCode);
        Assert.False(await CanAccess(factory, expert, client.ProfileId)); Assert.True(await CanAccess(factory, client, client.ProfileId));
        using var afterEnd = await applicant.PatchAsJsonAsync($"{Permissions}/{permission}", new { isGranted = false }); Assert.Equal(HttpStatusCode.Conflict, afterEnd.StatusCode);
        await using var db = factory.Database(); Assert.Single(await db.DataSharingPermissions.ToListAsync());
    }

    [PostgresFact]
    public async Task ResourceOwnershipAndMinimalClientViewsNeverExposeUnrelatedOrUnapprovedHealthData()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var client = await Seed(factory, UserRole.Client); var expert = await Seed(factory, UserRole.Dietitian);
        using var applicant = await Client(factory, client); using var dietitian = await Client(factory, expert);
        var id = await Request(applicant, expert.ProfileId);
        using var clientAccept = await applicant.PostAsync($"{Root}/{id}/accept", null); Assert.Equal(HttpStatusCode.Forbidden, clientAccept.StatusCode);
        using var other = await Client(factory, await Seed(factory, UserRole.Dietitian));
        using var foreign = await other.PostAsync($"{Root}/{id}/accept", null); Assert.Equal(HttpStatusCode.NotFound, foreign.StatusCode);
        using var pendingView = await dietitian.GetAsync($"/api/v1/dietitian/clients/{client.ProfileId}/dashboard"); Assert.Equal(HttpStatusCode.NotFound, pendingView.StatusCode);
        using var accepted = await dietitian.PostAsync($"{Root}/{id}/accept", null); Assert.Equal(HttpStatusCode.OK, accepted.StatusCode);
        using var list = await dietitian.GetAsync("/api/v1/dietitian/clients?page=1&pageSize=10&query=synthetic&sortOrder=desc");
        var body = await list.Content.ReadFromJsonAsync<JsonElement>(); var item = body.GetProperty("items")[0];
        Assert.Equal(new[] { "displayName", "id" }, item.EnumerateObject().Select(x => x.Name).Order());
        using var detail = await dietitian.GetAsync($"/api/v1/dietitian/clients/{client.ProfileId}/dashboard");
        var dashboard = await detail.Content.ReadFromJsonAsync<JsonElement>(); Assert.Equal(new[] { "clientId", "displayName" }, dashboard.EnumerateObject().Select(x => x.Name).Order());
        using var unseen = await other.GetAsync($"/api/v1/dietitian/clients/{client.ProfileId}/dashboard"); Assert.Equal(HttpStatusCode.NotFound, unseen.StatusCode);
        using var all = await other.GetAsync(Root + "?page=1&pageSize=10"); Assert.Equal(0, (await all.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("totalCount").GetInt32());
    }

    [PostgresFact]
    public async Task CookieMutationsRequireCsrfAndOriginAndCannotMixBearerWithCookie()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(webSessions: true); var expert = await Seed(factory, UserRole.Dietitian);
        using var client = factory.Client();
        var csrf = await Csrf(client);
        using var login = new HttpRequestMessage(HttpMethod.Post, "/api/v1/auth/web-session") { Content = JsonContent.Create(new { email = expert.Email, password = Password }) };
        login.Headers.Add("Origin", "https://localhost"); login.Headers.Add("X-CSRF-TOKEN", csrf);
        using var logged = await client.SendAsync(login); Assert.Equal(HttpStatusCode.OK, logged.StatusCode);
        using var noOrigin = await client.PostAsync(Invite, null); Assert.Equal(HttpStatusCode.Forbidden, noOrigin.StatusCode);
        using var missing = new HttpRequestMessage(HttpMethod.Post, Invite); missing.Headers.Add("Origin", "https://localhost");
        using var noCsrf = await client.SendAsync(missing); Assert.Equal(HttpStatusCode.BadRequest, noCsrf.StatusCode);
        using var valid = new HttpRequestMessage(HttpMethod.Post, Invite); valid.Headers.Add("Origin", "https://localhost"); valid.Headers.Add("X-CSRF-TOKEN", await Csrf(client));
        using var created = await client.SendAsync(valid); Assert.Equal(HttpStatusCode.OK, created.StatusCode);
        client.DefaultRequestHeaders.Authorization = new("Bearer", "synthetic-invalid");
        using var mixed = await client.GetAsync(Root + "?page=1&pageSize=10"); Assert.Equal(HttpStatusCode.BadRequest, mixed.StatusCode);
    }

    [PostgresFact]
    public async Task InvitationIsNotConsumedWhenTheRelationshipInsertRollsBack()
    {
        var failure = new RelationshipWriteFailure();
        await using var factory = await RegistrationApiFactory.CreateAsync(interceptor: failure);
        using var expert = await Client(factory, await Seed(factory, UserRole.Dietitian));
        using var applicant = await Client(factory, await Seed(factory, UserRole.Client));
        var code = await Code(expert); failure.Armed = true;
        using var failed = await applicant.PostAsJsonAsync(Root, new { invitationCode = code }); Assert.Equal(HttpStatusCode.InternalServerError, failed.StatusCode);
        failure.Armed = false;
        using var accepted = await applicant.PostAsJsonAsync(Root, new { invitationCode = code }); Assert.Equal(HttpStatusCode.Created, accepted.StatusCode);
    }

    [PostgresFact]
    public async Task DatabaseIndexPreventsASecondActiveRelationshipEvenWithoutTheServiceLock()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var client = await Seed(factory, UserRole.Client); var a = await Seed(factory, UserRole.Dietitian); var b = await Seed(factory, UserRole.Dietitian);
        await using var db = factory.Database();
        var first = new DietitianClientRelationship(client.ProfileId, a.ProfileId, DateTimeOffset.UtcNow); first.Respond(RelationshipStatus.Active, DateTimeOffset.UtcNow);
        var second = new DietitianClientRelationship(client.ProfileId, b.ProfileId, DateTimeOffset.UtcNow); second.Respond(RelationshipStatus.Active, DateTimeOffset.UtcNow);
        db.DietitianClientRelationships.Add(first); await db.SaveChangesAsync(); db.DietitianClientRelationships.Add(second);
        var error = await Assert.ThrowsAsync<DbUpdateException>(() => db.SaveChangesAsync()); Assert.Equal(PostgresErrorCodes.UniqueViolation, Assert.IsType<PostgresException>(error.InnerException).SqlState);
    }

    [PostgresFact]
    public async Task UnsupportedConsentCategoriesAndClientIdentityInjectionAreRejected()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var client = await Seed(factory, UserRole.Client); var expert = await Seed(factory, UserRole.Dietitian);
        using var applicant = await Client(factory, client); using var dietitian = await Client(factory, expert);
        using var injected = await applicant.PostAsJsonAsync(Root, new { dietitianId = expert.ProfileId, clientId = Guid.NewGuid() }); Assert.Equal(HttpStatusCode.BadRequest, injected.StatusCode);
        using var both = await applicant.PostAsJsonAsync(Root, new { dietitianId = expert.ProfileId, invitationCode = "AAAAAAAAAAAAAAAA" }); Assert.Equal(HttpStatusCode.BadRequest, both.StatusCode);
        var id = await Request(applicant, expert.ProfileId); using var accepted = await dietitian.PostAsync($"{Root}/{id}/accept", null);
        using var lab = await applicant.PostAsJsonAsync(Permissions, new { relationshipId = id, category = "lab_reports", isGranted = true }); Assert.Equal(HttpStatusCode.UnprocessableEntity, lab.StatusCode);
        using var consent = await applicant.PostAsJsonAsync(Permissions, new { relationshipId = id, category = "nutrition_plans", isGranted = true, consentRecordId = Guid.NewGuid() }); Assert.Equal(HttpStatusCode.UnprocessableEntity, consent.StatusCode);
        using var malformed = await applicant.GetAsync(Root + "?page=1&pageSize=10&status=1"); Assert.Equal(HttpStatusCode.BadRequest, malformed.StatusCode);
    }

    private static async Task<Actor> Seed(RegistrationApiFactory factory, UserRole role)
    {
        var email = Guid.NewGuid().ToString("N") + "@example.test";
        await using var db = factory.Database(); var user = new User(Guid.NewGuid(), email.ToUpperInvariant(), role, Password, DateTimeOffset.UtcNow, new PasswordHasher<User>());
        Guid id;
        if (role == UserRole.Client) id = new ClientProfile(Guid.NewGuid(), user, "Synthetic client").Id;
        else { var profile = new DietitianProfile(user, "Synthetic expert", "Synthetic license"); id = profile.Id; db.Entry(profile).Property(x => x.IsVerified).CurrentValue = true; }
        db.Users.Add(user); db.Entry(user).Property(x => x.IsEmailVerified).CurrentValue = true; await db.SaveChangesAsync();
        return new(user.Id, id, email, role);
    }
    private static async Task<HttpClient> Client(RegistrationApiFactory factory, Actor actor)
    {
        await using var db = factory.Database(); var user = await db.Users.SingleAsync(x => x.Id == actor.UserId);
        var jwt = new JwtAccessTokenService(Options.Create(factory.Jwt.Options), TimeProvider.System).Issue(user);
        var client = factory.Client(false); client.DefaultRequestHeaders.Authorization = new("Bearer", jwt.AccessToken); return client;
    }
    private static async Task<Guid> Request(HttpClient client, Guid dietitianId)
    { using var response = await client.PostAsJsonAsync(Root, new { dietitianId }); Assert.Equal(HttpStatusCode.Created, response.StatusCode); return (await response.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid(); }
    private static async Task<string> Code(HttpClient client)
    { using var response = await client.PostAsync(Invite, null); Assert.Equal(HttpStatusCode.OK, response.StatusCode); return (await response.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("invitationCode").GetString()!; }
    private static Task<HttpResponseMessage> Grant(HttpClient client, Guid id) => client.PostAsJsonAsync(Permissions, new { relationshipId = id, category = "nutrition_plans", isGranted = true });
    private static async Task<string> Csrf(HttpClient client)
    { using var response = await client.GetAsync("/api/v1/auth/csrf"); return (await response.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("requestToken").GetString()!; }
    private static async Task<bool> CanAccess(RegistrationApiFactory factory, Actor actor, Guid clientId)
    {
        using var scope = factory.Services.CreateScope(); var service = scope.ServiceProvider.GetRequiredService<RelationshipAccessService>();
        var principal = new ClaimsPrincipal(new ClaimsIdentity([new("sub", actor.UserId.ToString()), new("role", actor.Role.ToString().ToLowerInvariant())], "Bearer"));
        return await service.CanAccessNutritionPlansAsync(await service.RequireAsync(principal, default), clientId);
    }
    private sealed class TestClock : TimeProvider
    { public DateTimeOffset Now { get; set; } = DateTimeOffset.UtcNow; public override DateTimeOffset GetUtcNow() => Now; }
    private sealed class RelationshipWriteFailure : DbCommandInterceptor
    {
        public bool Armed { get; set; }
        public override ValueTask<InterceptionResult<DbDataReader>> ReaderExecutingAsync(DbCommand command, CommandEventData eventData, InterceptionResult<DbDataReader> result, CancellationToken cancellationToken = default)
        { if (Armed && command.CommandText.Contains("INSERT INTO dietitian_client_relationships")) throw new InvalidOperationException("Synthetic relationship failure"); return base.ReaderExecutingAsync(command, eventData, result, cancellationToken); }
    }
}
