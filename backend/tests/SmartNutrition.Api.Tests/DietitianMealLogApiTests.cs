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

public sealed class DietitianMealLogApiTests
{
    private const string Password = "Synthetic G2 test password";
    private const string PrivateNote = "Synthetic private G2 note";
    private sealed record Pair(User Owner, ClientProfile Client, User Expert, DietitianClientRelationship Relationship, DataSharingPermission Permission);
    private static string Route(Guid clientId, string query = "page=1&pageSize=10") => $"/api/v1/dietitian/clients/{clientId}/meal-logs?{query}";

    [PostgresFact]
    public async Task ListReturnsExistingFullDetailWithoutChangingClientCrudOrFlag()
    {
        // The rollout flag controls permission writes, not access to an existing explicit grant.
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory);
        using var owner = Bearer(factory, pair.Owner, "client"); using var expert = Bearer(factory, pair.Expert);
        var original = await Meal(owner);
        using var response = await expert.GetAsync(Route(pair.Client.Id)); Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Contains("no-store", response.Headers.CacheControl!.ToString());
        var page = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal(1, page.GetProperty("totalCount").GetInt32());
        Assert.Equal(original.GetRawText(), page.GetProperty("items")[0].GetRawText());
        Assert.Equal(JsonValueKind.Null, page.GetProperty("items")[0].GetProperty("items")[0].GetProperty("caloriesKcal").ValueKind);
        using var grant = await owner.PatchAsJsonAsync($"/api/v1/data-sharing-permissions/{pair.Permission.Id}", new { isGranted = true });
        Assert.Equal(HttpStatusCode.UnprocessableEntity, grant.StatusCode);
        Assert.DoesNotContain(PrivateNote, factory.Logs);
    }

    [PostgresFact]
    public async Task DateRangePagingOrderAndSoftDeleteUseOnlyRequestedClientsRows()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory);
        using var owner = Bearer(factory, pair.Owner, "client"); using var expert = Bearer(factory, pair.Expert);
        await Meal(owner, "2026-11-17T23:59:59Z");
        var first = await Meal(owner, "2026-11-18T00:00:00Z");
        var second = await Meal(owner, "2026-11-18T00:00:00Z");
        await Meal(owner, "2026-11-19T00:00:00Z");
        var removed = await Meal(owner, "2026-11-18T12:00:00Z");
        using var deleted = await owner.DeleteAsync($"/api/v1/meal-logs/{removed.GetProperty("id").GetGuid()}");
        Assert.Equal(HttpStatusCode.NoContent, deleted.StatusCode);
        var stranger = await Seed(factory); using var other = Bearer(factory, stranger.Owner, "client"); await Meal(other);
        var expected = new[] { first.GetProperty("id").GetGuid(), second.GetProperty("id").GetGuid() }.Order().ToArray();
        const string filter = "&from=2026-11-18T03%3A00%3A00%2B03%3A00&to=2026-11-19T03%3A00%3A00%2B03%3A00";
        for (var index = 0; index < 3; index++)
        {
            var page = await expert.GetFromJsonAsync<JsonElement>(Route(pair.Client.Id, $"page={index + 1}&pageSize=1{filter}"));
            Assert.Equal(2, page.GetProperty("totalCount").GetInt32());
            var rows = page.GetProperty("items"); Assert.Equal(index < 2 ? 1 : 0, rows.GetArrayLength());
            if (index < 2) Assert.Equal(expected[index], rows[0].GetProperty("id").GetGuid());
        }
        var all = await expert.GetFromJsonAsync<JsonElement>(Route(pair.Client.Id));
        Assert.Equal(4, all.GetProperty("totalCount").GetInt32());
        var ordered = all.GetProperty("items").EnumerateArray().Select(x => x.GetProperty("consumedAt").GetDateTimeOffset()).ToArray();
        Assert.Equal(ordered.OrderDescending(), ordered);
        Assert.All(all.GetProperty("items").EnumerateArray(), row => Assert.Equal(pair.Client.Id, row.GetProperty("clientId").GetGuid()));
    }

    [PostgresFact]
    public async Task AuthorizedEmptyClientReturnsRealEmptyPage()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory);
        using var expert = Bearer(factory, pair.Expert);
        var page = await expert.GetFromJsonAsync<JsonElement>(Route(pair.Client.Id));
        Assert.Equal(0, page.GetProperty("totalCount").GetInt32()); Assert.Empty(page.GetProperty("items").EnumerateArray());
    }

    [PostgresFact]
    public async Task NutritionPermissionDoesNotGrantMealsAndRevocationClosesNextRead()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(mealLogSharing: true); var pair = await Seed(factory);
        using var owner = Bearer(factory, pair.Owner, "client"); using var expert = Bearer(factory, pair.Expert); await Meal(owner);
        using var before = await expert.GetAsync(Route(pair.Client.Id)); Assert.Equal(HttpStatusCode.OK, before.StatusCode);
        using var revoked = await owner.PatchAsJsonAsync($"/api/v1/data-sharing-permissions/{pair.Permission.Id}", new { isGranted = false });
        Assert.Equal(HttpStatusCode.OK, revoked.StatusCode);
        using var after = await expert.GetAsync(Route(pair.Client.Id)); await Error(after, HttpStatusCode.Forbidden, "forbidden");
        await using (var db = factory.Database())
        { db.DataSharingPermissions.Remove(await db.DataSharingPermissions.SingleAsync(x => x.Id == pair.Permission.Id)); await db.SaveChangesAsync(); }
        using var absent = await expert.GetAsync(Route(pair.Client.Id)); await Error(absent, HttpStatusCode.Forbidden, "forbidden");
        using var own = await owner.GetAsync("/api/v1/meal-logs?page=1&pageSize=10"); Assert.Equal(HttpStatusCode.OK, own.StatusCode);
    }

    [PostgresFact]
    public async Task ForeignMissingPendingAndEndedRelationshipsHideExistence()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory); var other = await Seed(factory);
        using var expert = Bearer(factory, pair.Expert); using var owner = Bearer(factory, pair.Owner, "client"); await Meal(owner);
        foreach (var id in new[] { other.Client.Id, pair.Owner.Id, Guid.NewGuid() })
        { using var response = await expert.GetAsync(Route(id)); await Error(response, HttpStatusCode.NotFound, "not_found"); }
        using var ended = await owner.PostAsync($"/api/v1/dietitian-relationships/{pair.Relationship.Id}/end", null);
        Assert.Equal(HttpStatusCode.OK, ended.StatusCode);
        using var afterEnd = await expert.GetAsync(Route(pair.Client.Id)); await Error(afterEnd, HttpStatusCode.NotFound, "not_found");
        await using (var db = factory.Database())
        {
            var pending = new DietitianClientRelationship(pair.Client.Id, pair.Relationship.DietitianId, DateTimeOffset.UtcNow);
            db.DietitianClientRelationships.Add(pending);
            db.DataSharingPermissions.Add(new DataSharingPermission(pending.Id, true, DateTimeOffset.UtcNow, "meal_logs"));
            await db.SaveChangesAsync();
        }
        using var pendingRead = await expert.GetAsync(Route(pair.Client.Id)); await Error(pendingRead, HttpStatusCode.NotFound, "not_found");
    }

    [PostgresFact]
    public async Task HeaderAloneCannotAuthorizeClientsUnverifiedExpertsOrAdmin()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(webSessions: true); var pair = await Seed(factory);
        using var anonymous = factory.Client(false); using var noSession = await anonymous.GetAsync(Route(pair.Client.Id));
        await Error(noSession, HttpStatusCode.Unauthorized, "unauthenticated");
        using var client = Bearer(factory, pair.Owner); using var forged = await client.GetAsync(Route(pair.Client.Id));
        await Error(forged, HttpStatusCode.Forbidden, "forbidden");
        using var expert = Bearer(factory, pair.Expert);
        await using (var db = factory.Database())
            await db.DietitianProfiles.Where(x => x.Id == pair.Relationship.DietitianId).ExecuteUpdateAsync(x => x.SetProperty(p => p.IsVerified, false));
        using var unverified = await expert.GetAsync(Route(pair.Client.Id)); await Error(unverified, HttpStatusCode.Forbidden, "forbidden");
        await using (var db = factory.Database())
        {
            var admin = new User(Guid.NewGuid(), Guid.NewGuid().ToString("N") + "@EXAMPLE.TEST", UserRole.Admin, Password, DateTimeOffset.UtcNow, new PasswordHasher<User>());
            using var scope = factory.Services.CreateScope();
            var setup = scope.ServiceProvider.GetRequiredService<AdminMfaService>().Initialize(admin, DateTimeOffset.UtcNow);
            db.Users.Add(admin); db.Entry(admin).Property(x => x.IsEmailVerified).CurrentValue = true; await db.SaveChangesAsync();
            using var adminClient = factory.Client();
            var csrf = await adminClient.GetFromJsonAsync<JsonElement>("/api/v1/auth/csrf");
            using var login = new HttpRequestMessage(HttpMethod.Post, "/api/v1/auth/admin-web-session")
            { Content = JsonContent.Create(new { email = admin.Email, password = Password, mfaCode = setup.RecoveryCodes[0] }) };
            login.Headers.Add("Origin", "https://localhost"); login.Headers.Add("X-CSRF-TOKEN", csrf.GetProperty("requestToken").GetString());
            using var signed = await adminClient.SendAsync(login); Assert.Equal(HttpStatusCode.OK, signed.StatusCode);
            using var denied = await adminClient.GetAsync(Route(pair.Client.Id));
            await Error(denied, HttpStatusCode.Forbidden, "forbidden");
        }
        await using (var db = factory.Database())
            await db.Users.Where(x => x.Id == pair.Expert.Id).ExecuteUpdateAsync(x => x.SetProperty(p => p.IsEmailVerified, false));
        using var stale = await expert.GetAsync(Route(pair.Client.Id)); await Error(stale, HttpStatusCode.Unauthorized, "unauthenticated");
    }

    [PostgresFact]
    public async Task VerifiedDualProfileAndHttpsCookieUseSameConsentRules()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(webSessions: true); var pair = await Seed(factory, dual: true);
        using var jwt = Bearer(factory, pair.Expert); using var jwtRead = await jwt.GetAsync(Route(pair.Client.Id));
        Assert.Equal(HttpStatusCode.OK, jwtRead.StatusCode);
        using var web = factory.Client();
        var csrf = await web.GetFromJsonAsync<JsonElement>("/api/v1/auth/csrf");
        using var login = new HttpRequestMessage(HttpMethod.Post, "/api/v1/auth/web-session")
        { Content = JsonContent.Create(new { email = pair.Expert.Email, password = Password }) };
        login.Headers.Add("Origin", "https://localhost"); login.Headers.Add("X-CSRF-TOKEN", csrf.GetProperty("requestToken").GetString());
        using var signed = await web.SendAsync(login); Assert.Equal(HttpStatusCode.OK, signed.StatusCode);
        using var read = await web.GetAsync(Route(pair.Client.Id)); Assert.Equal(HttpStatusCode.OK, read.StatusCode);
        using var owner = Bearer(factory, pair.Owner, "client");
        using var revoke = await owner.PatchAsJsonAsync($"/api/v1/data-sharing-permissions/{pair.Permission.Id}", new { isGranted = false });
        Assert.Equal(HttpStatusCode.OK, revoke.StatusCode);
        using var denied = await web.GetAsync(Route(pair.Client.Id)); await Error(denied, HttpStatusCode.Forbidden, "forbidden");
        web.DefaultRequestHeaders.Add("X-Profile-Context", "client");
        using var context = await web.GetAsync(Route(pair.Client.Id)); await Error(context, HttpStatusCode.Forbidden, "forbidden");
    }

    [PostgresFact]
    public async Task StrictQueryAndReadOnlyRoutesRejectUnsupportedInputs()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory); using var expert = Bearer(factory, pair.Expert);
        foreach (var query in new[] { "", "page=1", "pageSize=10", "page=0&pageSize=10", "page=1&pageSize=101", "page=2147483647&pageSize=100",
            "page=x&pageSize=10", "page=1&pageSize=10&page=2", "page=1&pageSize=10&clientId=other", "page=1&pageSize=10&from=",
            "page=1&pageSize=10&from=2026-11-18T00:00:00", "page=1&pageSize=10&to=invalid",
            "page=1&pageSize=10&from=2026-11-19T00:00:00Z&to=2026-11-18T00:00:00Z",
            "page=1&pageSize=10&from=2026-11-18T00:00:00Z&to=2026-11-18T00:00:00Z" })
        { using var response = await expert.GetAsync(Route(pair.Client.Id, query)); await Error(response, HttpStatusCode.BadRequest, "invalid_request"); }
        using var body = new HttpRequestMessage(HttpMethod.Get, Route(pair.Client.Id)) { Content = JsonContent.Create(new { }) };
        using var bodyRead = await expert.SendAsync(body); await Error(bodyRead, HttpStatusCode.BadRequest, "invalid_request");
        foreach (var method in new[] { HttpMethod.Post, HttpMethod.Patch, HttpMethod.Delete })
        {
            using var request = new HttpRequestMessage(method, Route(pair.Client.Id)); using var response = await expert.SendAsync(request);
            Assert.Equal(HttpStatusCode.MethodNotAllowed, response.StatusCode);
        }
        using var ownWrite = await expert.PostAsJsonAsync("/api/v1/meal-logs", new { mealType = "lunch", consumedAt = "2026-11-18T00:00:00Z", source = "manual", items = new[] { new { displayName = "Synthetic", isEstimated = false } } });
        await Error(ownWrite, HttpStatusCode.Forbidden, "forbidden");
        expert.DefaultRequestHeaders.Remove("X-Profile-Context"); expert.DefaultRequestHeaders.Add("X-Profile-Context", "admin");
        using var invalidHeader = await expert.GetAsync(Route(pair.Client.Id)); await Error(invalidHeader, HttpStatusCode.BadRequest, "invalid_request");
    }

    [PostgresFact]
    public async Task InFlightReadKeepsAuthorizationCountAndRowsInOneSnapshotAndNextReadSeesWithdrawal()
    {
        var pause = new CountPause(); await using var factory = await RegistrationApiFactory.CreateAsync(interceptor: pause);
        var pair = await Seed(factory); using var owner = Bearer(factory, pair.Owner, "client"); await Meal(owner);
        using var expert = Bearer(factory, pair.Expert); pause.Armed = true;
        var reading = expert.GetAsync(Route(pair.Client.Id));
        try
        {
            await pause.Entered.Task.WaitAsync(TimeSpan.FromSeconds(10));
            await Meal(owner);
            using var revoke = await owner.PatchAsJsonAsync($"/api/v1/data-sharing-permissions/{pair.Permission.Id}", new { isGranted = false });
            Assert.Equal(HttpStatusCode.OK, revoke.StatusCode);
        }
        finally { pause.Release.TrySetResult(true); }
        using var response = await reading; Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var page = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal(1, page.GetProperty("totalCount").GetInt32()); Assert.Single(page.GetProperty("items").EnumerateArray());
        using var next = await expert.GetAsync(Route(pair.Client.Id)); await Error(next, HttpStatusCode.Forbidden, "forbidden");
    }

    [PostgresFact]
    public async Task StorageFailureDoesNotReturnOrLogMealData()
    {
        var failure = new ReadFailure(); await using var factory = await RegistrationApiFactory.CreateAsync(interceptor: failure);
        var pair = await Seed(factory); using var owner = Bearer(factory, pair.Owner, "client"); await Meal(owner);
        using var expert = Bearer(factory, pair.Expert); failure.Armed = true;
        using var response = await expert.GetAsync(Route(pair.Client.Id)); await Error(response, HttpStatusCode.InternalServerError, "internal_error");
        Assert.DoesNotContain(PrivateNote, factory.Logs);
    }

    private static async Task<Pair> Seed(RegistrationApiFactory factory, bool dual = false)
    {
        await using var db = factory.Database();
        var owner = new User(Guid.NewGuid(), Guid.NewGuid().ToString("N") + "@EXAMPLE.TEST", UserRole.Client, Password, DateTimeOffset.UtcNow, new PasswordHasher<User>());
        var client = new ClientProfile(Guid.NewGuid(), owner, "Synthetic G2 client");
        var expert = new User(Guid.NewGuid(), Guid.NewGuid().ToString("N") + "@EXAMPLE.TEST", dual ? UserRole.Client : UserRole.Dietitian, Password, DateTimeOffset.UtcNow, new PasswordHasher<User>());
        var profile = new DietitianProfile(expert, "Synthetic G2 expert", "Synthetic license");
        if (dual) _ = new ClientProfile(Guid.NewGuid(), expert, "Synthetic dual client");
        db.Users.AddRange(owner, expert); db.Entry(owner).Property(x => x.IsEmailVerified).CurrentValue = true;
        db.Entry(expert).Property(x => x.IsEmailVerified).CurrentValue = true; db.Entry(profile).Property(x => x.IsVerified).CurrentValue = true;
        var relation = new DietitianClientRelationship(client.Id, profile.Id, DateTimeOffset.UtcNow); relation.Respond(RelationshipStatus.Active, DateTimeOffset.UtcNow);
        var permission = new DataSharingPermission(relation.Id, true, DateTimeOffset.UtcNow, "meal_logs");
        db.DietitianClientRelationships.Add(relation); db.DataSharingPermissions.AddRange(permission, new DataSharingPermission(relation.Id, true, DateTimeOffset.UtcNow));
        await db.SaveChangesAsync(); return new(owner, client, expert, relation, permission);
    }

    private static HttpClient Bearer(RegistrationApiFactory factory, User user, string context = "dietitian")
    {
        var client = factory.Client(false); var jwt = new JwtAccessTokenService(Options.Create(factory.Jwt.Options), TimeProvider.System).Issue(user);
        client.DefaultRequestHeaders.Authorization = new("Bearer", jwt.AccessToken); client.DefaultRequestHeaders.Add("X-Profile-Context", context); return client;
    }

    private static async Task<JsonElement> Meal(HttpClient owner, string time = "2026-11-18T12:00:00Z")
    {
        using var response = await owner.PostAsJsonAsync("/api/v1/meal-logs", new
        {
            mealType = "lunch", consumedAt = time, source = "manual", note = PrivateNote,
            items = new[] { new { displayName = "Synthetic G2 food", isEstimated = true, quantityGrams = 123.125m, proteinGrams = 12.345m, fatGrams = 0m },
                new { displayName = "Synthetic second food", isEstimated = false, quantityGrams = 25m, proteinGrams = 1m, fatGrams = 2m } }
        });
        Assert.Equal(HttpStatusCode.Created, response.StatusCode); return await response.Content.ReadFromJsonAsync<JsonElement>();
    }

    private static async Task Error(HttpResponseMessage response, HttpStatusCode status, string code)
    {
        Assert.Equal(status, response.StatusCode); var body = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal(code, body.GetProperty("error").GetProperty("code").GetString());
        Assert.False(string.IsNullOrWhiteSpace(body.GetProperty("requestId").GetString())); Assert.DoesNotContain(PrivateNote, body.GetRawText());
        Assert.False(body.TryGetProperty("totalCount", out _)); Assert.False(body.TryGetProperty("items", out _));
    }

    private sealed class ReadFailure : DbCommandInterceptor
    {
        public bool Armed { get; set; }
        public override ValueTask<InterceptionResult<DbDataReader>> ReaderExecutingAsync(DbCommand command, CommandEventData eventData,
            InterceptionResult<DbDataReader> result, CancellationToken cancellationToken = default)
        {
            if (Armed && command.CommandText.Contains("FROM meal_logs", StringComparison.Ordinal)) throw new InvalidOperationException("Synthetic G2 database failure");
            return base.ReaderExecutingAsync(command, eventData, result, cancellationToken);
        }
    }

    private sealed class CountPause : DbCommandInterceptor
    {
        public bool Armed { get; set; }
        public TaskCompletionSource<bool> Entered { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public TaskCompletionSource<bool> Release { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public override async ValueTask<InterceptionResult<DbDataReader>> ReaderExecutingAsync(DbCommand command, CommandEventData eventData,
            InterceptionResult<DbDataReader> result, CancellationToken cancellationToken = default)
        {
            if (Armed && command.CommandText.Contains("count(", StringComparison.Ordinal) && command.CommandText.Contains("FROM meal_logs", StringComparison.Ordinal))
            {
                Armed = false; Entered.TrySetResult(true);
                await Release.Task.WaitAsync(TimeSpan.FromSeconds(10), cancellationToken);
            }
            return result;
        }
    }
}
