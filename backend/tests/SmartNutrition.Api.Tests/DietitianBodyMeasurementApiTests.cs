using System.Data.Common;
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Features.Dietitians;
using SmartNutrition.Api.Features.Relationships;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Tests;

public sealed class DietitianBodyMeasurementApiTests
{
    private const string Password = "Synthetic measurement expert password";
    private const string Note = "Synthetic private measurement note";
    private sealed record Pair(User Owner, ClientProfile Client, User Expert, DietitianClientRelationship Relationship, DataSharingPermission Permission);
    private static string Route(Guid clientId, string query = "page=1&pageSize=10") => $"/api/v1/dietitian/clients/{clientId}/body-measurements?{query}";

    [PostgresFact]
    public async Task OwnManualRecordIsReadWithIdenticalNullableFieldsAndNoStore()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory);
        using var owner = Bearer(factory, pair.Owner, "client"); using var expert = Bearer(factory, pair.Expert);
        var original = await Measurement(owner);
        using var response = await expert.GetAsync(Route(pair.Client.Id)); Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Contains("no-store", response.Headers.CacheControl!.ToString());
        var page = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal(1, page.GetProperty("totalCount").GetInt32());
        Assert.Equal(original.GetRawText(), page.GetProperty("items")[0].GetRawText());
        Assert.Equal(JsonValueKind.Null, page.GetProperty("items")[0].GetProperty("waistCm").ValueKind);
        Assert.Equal(0, page.GetProperty("items")[0].GetProperty("bodyFatPercent").GetDecimal());
        using var flag = await owner.PatchAsJsonAsync($"/api/v1/data-sharing-permissions/{pair.Permission.Id}", new { isGranted = true });
        Assert.Equal(HttpStatusCode.UnprocessableEntity, flag.StatusCode);
        Assert.DoesNotContain(Note, factory.Logs);
    }

    [PostgresFact]
    public async Task PagingAndOffsetBoundariesExcludeDeletedAndForeignRowsAndStabilizeTies()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory);
        using var owner = Bearer(factory, pair.Owner, "client"); using var expert = Bearer(factory, pair.Expert);
        await Measurement(owner, "2026-11-17T23:59:59Z");
        var first = await Measurement(owner, "2026-11-18T00:00:00Z"); var second = await Measurement(owner, "2026-11-18T00:00:00Z");
        await Measurement(owner, "2026-11-19T00:00:00Z"); var removed = await Measurement(owner);
        using var deleted = await owner.DeleteAsync($"/api/v1/body-measurements/{removed.GetProperty("id").GetGuid()}"); Assert.Equal(HttpStatusCode.NoContent, deleted.StatusCode);
        var other = await Seed(factory); using var stranger = Bearer(factory, other.Owner, "client"); await Measurement(stranger);
        var expected = new[] { first.GetProperty("id").GetGuid(), second.GetProperty("id").GetGuid() }.Order().ToArray();
        const string filter = "&from=2026-11-18T03%3A00%3A00%2B03%3A00&to=2026-11-19T03%3A00%3A00%2B03%3A00";
        for (var index = 0; index < 3; index++)
        {
            var page = await expert.GetFromJsonAsync<JsonElement>(Route(pair.Client.Id, $"page={index + 1}&pageSize=1{filter}"));
            Assert.Equal(2, page.GetProperty("totalCount").GetInt32());
            Assert.Equal(index < 2 ? 1 : 0, page.GetProperty("items").GetArrayLength());
            if (index < 2) Assert.Equal(expected[index], page.GetProperty("items")[0].GetProperty("id").GetGuid());
        }
        var all = await expert.GetFromJsonAsync<JsonElement>(Route(pair.Client.Id)); Assert.Equal(4, all.GetProperty("totalCount").GetInt32());
        var times = all.GetProperty("items").EnumerateArray().Select(x => x.GetProperty("measuredAt").GetDateTimeOffset()).ToArray();
        Assert.Equal(times.OrderDescending(), times);
    }

    [PostgresFact]
    public async Task ProgramAndMealGrantsDoNotOpenMeasurementsAndWithdrawalClosesNextRead()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(bodyMeasurementSharing: true, environment: "Development"); var pair = await Seed(factory);
        using var owner = Bearer(factory, pair.Owner, "client"); using var expert = Bearer(factory, pair.Expert); await Measurement(owner);
        using var revoked = await owner.PatchAsJsonAsync($"/api/v1/data-sharing-permissions/{pair.Permission.Id}", new { isGranted = false }); Assert.Equal(HttpStatusCode.OK, revoked.StatusCode);
        using var denied = await expert.GetAsync(Route(pair.Client.Id)); await Error(denied, HttpStatusCode.Forbidden);
        await using (var db = factory.Database())
        { db.DataSharingPermissions.Remove(await db.DataSharingPermissions.SingleAsync(x => x.Id == pair.Permission.Id)); await db.SaveChangesAsync(); }
        using var absent = await expert.GetAsync(Route(pair.Client.Id)); await Error(absent, HttpStatusCode.Forbidden);
        using var grant = await owner.PostAsJsonAsync("/api/v1/data-sharing-permissions", new { relationshipId = pair.Relationship.Id, category = "body_measurements", isGranted = true }); Assert.Equal(HttpStatusCode.Created, grant.StatusCode);
        using var allowed = await expert.GetAsync(Route(pair.Client.Id)); Assert.Equal(HttpStatusCode.OK, allowed.StatusCode);
        using var ended = await owner.PostAsync($"/api/v1/dietitian-relationships/{pair.Relationship.Id}/end", null); Assert.Equal(HttpStatusCode.OK, ended.StatusCode);
        using var own = await owner.GetAsync("/api/v1/body-measurements?page=1&pageSize=10"); Assert.Equal(HttpStatusCode.OK, own.StatusCode);
    }

    [PostgresFact]
    public async Task MissingForeignPendingAndEndedRelationshipsHideExistence()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory); var other = await Seed(factory);
        using var expert = Bearer(factory, pair.Expert); using var owner = Bearer(factory, pair.Owner, "client");
        foreach (var id in new[] { Guid.NewGuid(), other.Client.Id, pair.Owner.Id })
        { using var response = await expert.GetAsync(Route(id)); await Error(response, HttpStatusCode.NotFound); }
        using var ended = await owner.PostAsync($"/api/v1/dietitian-relationships/{pair.Relationship.Id}/end", null); Assert.Equal(HttpStatusCode.OK, ended.StatusCode);
        using var after = await expert.GetAsync(Route(pair.Client.Id)); await Error(after, HttpStatusCode.NotFound);
        await using var db = factory.Database(); var pending = new DietitianClientRelationship(pair.Client.Id, pair.Relationship.DietitianId, DateTimeOffset.UtcNow);
        db.DietitianClientRelationships.Add(pending); db.DataSharingPermissions.Add(new DataSharingPermission(pending.Id, true, DateTimeOffset.UtcNow, "body_measurements")); await db.SaveChangesAsync();
        using var pendingRead = await expert.GetAsync(Route(pair.Client.Id)); await Error(pendingRead, HttpStatusCode.NotFound);
    }

    [PostgresFact]
    public async Task AuthenticationAndCurrentExpertVerificationCannotBeReplacedByHeaders()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory);
        using var anonymous = factory.Client(false); using var unauthenticated = await anonymous.GetAsync(Route(pair.Client.Id)); await Error(unauthenticated, HttpStatusCode.Unauthorized);
        using var owner = Bearer(factory, pair.Owner); using var forged = await owner.GetAsync(Route(pair.Client.Id)); await Error(forged, HttpStatusCode.Forbidden);
        using var expert = Bearer(factory, pair.Expert);
        await using (var db = factory.Database()) await db.DietitianProfiles.Where(x => x.Id == pair.Relationship.DietitianId).ExecuteUpdateAsync(x => x.SetProperty(p => p.IsVerified, false));
        using var unverified = await expert.GetAsync(Route(pair.Client.Id)); await Error(unverified, HttpStatusCode.Forbidden);
        await using (var db = factory.Database()) await db.Users.Where(x => x.Id == pair.Expert.Id).ExecuteUpdateAsync(x => x.SetProperty(p => p.IsEmailVerified, false));
        using var stale = await expert.GetAsync(Route(pair.Client.Id)); await Error(stale, HttpStatusCode.Unauthorized);
    }

    [PostgresFact]
    public async Task VerifiedDualProfileCookieCanReadButMfaAdminCannot()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(webSessions: true); var pair = await Seed(factory, dual: true);
        using var web = factory.Client(); await Login(web, pair.Expert.Email);
        using var read = await web.GetAsync(Route(pair.Client.Id)); Assert.Equal(HttpStatusCode.OK, read.StatusCode);
        var empty = await read.Content.ReadFromJsonAsync<JsonElement>(); Assert.Equal(0, empty.GetProperty("totalCount").GetInt32()); Assert.Empty(empty.GetProperty("items").EnumerateArray());
        web.DefaultRequestHeaders.Add("X-Profile-Context", "client");
        using var wrongContext = await web.GetAsync(Route(pair.Client.Id)); await Error(wrongContext, HttpStatusCode.Forbidden);
        var admin = new User(Guid.NewGuid(), Guid.NewGuid().ToString("N") + "@EXAMPLE.TEST", UserRole.Admin, Password, DateTimeOffset.UtcNow, new PasswordHasher<User>());
        using var scope = factory.Services.CreateScope(); var mfa = scope.ServiceProvider.GetRequiredService<AdminMfaService>().Initialize(admin, DateTimeOffset.UtcNow);
        await using (var db = factory.Database()) { db.Users.Add(admin); await db.SaveChangesAsync(); }
        using var adminWeb = factory.Client(); await Login(adminWeb, admin.Email, mfa.RecoveryCodes[0]);
        using var forbidden = await adminWeb.GetAsync(Route(pair.Client.Id)); await Error(forbidden, HttpStatusCode.Forbidden);
        using var adminGrant = await adminWeb.PostAsJsonAsync("/api/v1/data-sharing-permissions", new { relationshipId = pair.Relationship.Id, category = "body_measurements", isGranted = true });
        await Error(adminGrant, HttpStatusCode.Forbidden);
    }

    [PostgresFact]
    public async Task StrictQueryAndReadOnlyRouteRejectUnsupportedInputs()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory); using var expert = Bearer(factory, pair.Expert);
        foreach (var query in new[] { "", "page=1", "pageSize=10", "page=0&pageSize=10", "page=1&pageSize=101", "page=2147483647&pageSize=100", "page=1&pageSize=10&page=2",
            "page=1&pageSize=10&sortOrder=invalid", "page=1&pageSize=10&from=", "page=1&pageSize=10&from=2026-11-18T00:00:00", "page=1&pageSize=10&to=bad",
            "page=1&pageSize=10&from=2026-11-19T00:00:00Z&to=2026-11-18T00:00:00Z", "page=1&pageSize=10&from=2026-11-18T00:00:00Z&to=2026-11-18T00:00:00Z" })
        { using var response = await expert.GetAsync(Route(pair.Client.Id, query)); await Error(response, HttpStatusCode.BadRequest); }
        using var body = new HttpRequestMessage(HttpMethod.Get, Route(pair.Client.Id)) { Content = JsonContent.Create(new { }) };
        using var bodyRead = await expert.SendAsync(body); await Error(bodyRead, HttpStatusCode.BadRequest);
        foreach (var method in new[] { HttpMethod.Post, HttpMethod.Patch, HttpMethod.Delete })
        { using var request = new HttpRequestMessage(method, Route(pair.Client.Id)); using var response = await expert.SendAsync(request); Assert.Equal(HttpStatusCode.MethodNotAllowed, response.StatusCode); }
    }

    [PostgresFact]
    public async Task InFlightSnapshotIsConsistentAndNextReadSeesWithdrawal()
    {
        var pause = new ReadInterceptor(pause: true); await using var factory = await RegistrationApiFactory.CreateAsync(interceptor: pause);
        var pair = await Seed(factory); using var owner = Bearer(factory, pair.Owner, "client"); using var expert = Bearer(factory, pair.Expert);
        await Measurement(owner); pause.Armed = true; var reading = expert.GetAsync(Route(pair.Client.Id));
        try
        {
            await pause.Entered.Task.WaitAsync(TimeSpan.FromSeconds(10)); await Measurement(owner);
            using var revoked = await owner.PatchAsJsonAsync($"/api/v1/data-sharing-permissions/{pair.Permission.Id}", new { isGranted = false }); Assert.Equal(HttpStatusCode.OK, revoked.StatusCode);
        }
        finally { pause.Release.TrySetResult(true); }
        using var response = await reading; Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var page = await response.Content.ReadFromJsonAsync<JsonElement>(); Assert.Equal(1, page.GetProperty("totalCount").GetInt32()); Assert.Single(page.GetProperty("items").EnumerateArray());
        using var next = await expert.GetAsync(Route(pair.Client.Id)); await Error(next, HttpStatusCode.Forbidden);
    }

    [PostgresFact]
    public async Task DatabaseFailureDoesNotExposeMeasurementsOrLogs()
    {
        var failure = new ReadInterceptor(pause: false); await using var factory = await RegistrationApiFactory.CreateAsync(interceptor: failure);
        var pair = await Seed(factory); using var owner = Bearer(factory, pair.Owner, "client"); await Measurement(owner);
        using var expert = Bearer(factory, pair.Expert); failure.Armed = true;
        using var response = await expert.GetAsync(Route(pair.Client.Id)); await Error(response, HttpStatusCode.InternalServerError); Assert.DoesNotContain(Note, factory.Logs);
    }

    private static async Task<Pair> Seed(RegistrationApiFactory factory, bool dual = false)
    {
        var now = DateTimeOffset.UtcNow; var hasher = new PasswordHasher<User>();
        var owner = new User(Guid.NewGuid(), Guid.NewGuid().ToString("N") + "@EXAMPLE.TEST", UserRole.Client, Password, now, hasher);
        var client = new ClientProfile(Guid.NewGuid(), owner, "Synthetic measurement client");
        var expert = new User(Guid.NewGuid(), Guid.NewGuid().ToString("N") + "@EXAMPLE.TEST", dual ? UserRole.Client : UserRole.Dietitian, Password, now, hasher);
        var profile = new DietitianProfile(expert, "Synthetic expert", "Synthetic license"); if (dual) _ = new ClientProfile(Guid.NewGuid(), expert, "Synthetic dual client");
        await using var db = factory.Database(); db.Users.AddRange(owner, expert);
        db.Entry(owner).Property(x => x.IsEmailVerified).CurrentValue = true; db.Entry(expert).Property(x => x.IsEmailVerified).CurrentValue = true; db.Entry(profile).Property(x => x.IsVerified).CurrentValue = true;
        var relation = new DietitianClientRelationship(client.Id, profile.Id, now); relation.Respond(RelationshipStatus.Active, now);
        var permission = new DataSharingPermission(relation.Id, true, now, "body_measurements"); db.DietitianClientRelationships.Add(relation);
        db.DataSharingPermissions.AddRange(permission, new DataSharingPermission(relation.Id, true, now), new DataSharingPermission(relation.Id, true, now, "meal_logs"));
        await db.SaveChangesAsync(); return new(owner, client, expert, relation, permission);
    }
    private static HttpClient Bearer(RegistrationApiFactory factory, User user, string context = "dietitian")
    {
        var client = factory.Client(false); var jwt = new JwtAccessTokenService(Options.Create(factory.Jwt.Options), TimeProvider.System).Issue(user);
        client.DefaultRequestHeaders.Authorization = new("Bearer", jwt.AccessToken); client.DefaultRequestHeaders.Add("X-Profile-Context", context); return client;
    }
    private static async Task<JsonElement> Measurement(HttpClient owner, string measuredAt = "2026-11-18T12:00:00Z")
    {
        using var created = await owner.PostAsJsonAsync("/api/v1/body-measurements", new { measuredAt, source = "manual", weightKg = 73.123456789m, hipCm = 98.125m, chestCm = 91.25m, bodyFatPercent = 0m, note = Note });
        Assert.Equal(HttpStatusCode.Created, created.StatusCode); return await created.Content.ReadFromJsonAsync<JsonElement>();
    }
    private static async Task Login(HttpClient web, string email, string? recovery = null)
    {
        var csrf = await web.GetFromJsonAsync<JsonElement>("/api/v1/auth/csrf");
        using var request = new HttpRequestMessage(HttpMethod.Post, recovery is null ? "/api/v1/auth/web-session" : "/api/v1/auth/admin-web-session")
        { Content = recovery is null ? JsonContent.Create(new { email, password = Password }) : JsonContent.Create(new { email, password = Password, mfaCode = recovery }) };
        request.Headers.Add("Origin", "https://localhost"); request.Headers.Add("X-CSRF-TOKEN", csrf.GetProperty("requestToken").GetString());
        using var response = await web.SendAsync(request); Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }
    private static async Task Error(HttpResponseMessage response, HttpStatusCode status)
    {
        Assert.Equal(status, response.StatusCode); var body = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.False(string.IsNullOrWhiteSpace(body.GetProperty("error").GetProperty("code").GetString())); Assert.True(body.TryGetProperty("requestId", out _));
        Assert.DoesNotContain(Note, body.GetRawText()); Assert.False(body.TryGetProperty("items", out _)); Assert.False(body.TryGetProperty("totalCount", out _));
    }
    private sealed class ReadInterceptor(bool pause) : DbCommandInterceptor
    {
        public bool Armed { get; set; }
        public TaskCompletionSource<bool> Entered { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public TaskCompletionSource<bool> Release { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public override async ValueTask<InterceptionResult<DbDataReader>> ReaderExecutingAsync(DbCommand command, CommandEventData eventData,
            InterceptionResult<DbDataReader> result, CancellationToken cancellationToken = default)
        {
            if (Armed && command.CommandText.Contains("FROM body_measurements", StringComparison.Ordinal))
            {
                if (!pause) throw new InvalidOperationException("Synthetic measurement read failure");
                if (command.CommandText.Contains("count(", StringComparison.Ordinal))
                { Armed = false; Entered.TrySetResult(true); await Release.Task.WaitAsync(TimeSpan.FromSeconds(10), cancellationToken); }
            }
            return result;
        }
    }
}
