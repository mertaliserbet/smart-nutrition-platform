using System.Data.Common;
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using Npgsql;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Features.Dietitians;
using SmartNutrition.Api.Features.Relationships;
using SmartNutrition.Api.Features.WaterLogs;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Tests;

public sealed class DietitianWaterLogApiTests
{
    private const string Password = "Synthetic water test password";
    private const string Permissions = "/api/v1/data-sharing-permissions";
    private static readonly DateTimeOffset Day = new(2026, 11, 10, 0, 0, 0, TimeSpan.FromHours(3));
    private sealed record Pair(User Owner, ClientProfile Client, User Expert, DietitianProfile Profile, DietitianClientRelationship Relationship);
    private static string Route(Guid id) => $"/api/v1/dietitian/clients/{id}/water-logs";
    private static string Bounds(DateTimeOffset? from = null, DateTimeOffset? to = null) => "from=" + Uri.EscapeDataString((from ?? Day).ToString("O")) + "&to=" + Uri.EscapeDataString((to ?? Day.AddDays(1)).ToString("O"));
    private static string[] Reads(Guid id) => [Route(id) + "?page=1&pageSize=10", Route(id) + "/daily-total?" + Bounds(), Route(id) + "/daily-history?page=1&pageSize=10&timeZone=Europe%2FIstanbul&" + Bounds()];

    [PostgresFact]
    public async Task CreateGrantCookieReadWithdrawAndOwnAccessUseRealApiAndIndependentPermissions()
    {
        await using var f = await RegistrationApiFactory.CreateAsync(waterLogSharing: true, webSessions: true);
        var pair = await Seed(f, dual: true); using var owner = Bearer(f, pair.Owner, "client"); using var expert = f.Client(); await Login(expert, pair.Expert.Email);
        var water = await Water(owner, Day.AddHours(10), 250.125m);
        using (var target = await owner.PatchAsJsonAsync("/api/v1/personal-nutrition-targets", new { dailyWaterTargetMl = 2345m })) Assert.Equal(HttpStatusCode.OK, target.StatusCode);
        foreach (var path in Reads(pair.Client.Id)) { using var denied = await expert.GetAsync(path); await Error(denied, 403); }
        var permission = await Grant(owner, pair);
        foreach (var path in Reads(pair.Client.Id))
        { using var read = await expert.GetAsync(path); Assert.Equal(HttpStatusCode.OK, read.StatusCode); Assert.Contains("no-store", read.Headers.CacheControl!.ToString()); Assert.DoesNotContain("2345", await read.Content.ReadAsStringAsync()); }
        var list = await expert.GetFromJsonAsync<JsonElement>(Reads(pair.Client.Id)[0]); Assert.Equal(water.Id, list.GetProperty("items")[0].GetProperty("id").GetGuid());
        Assert.Equal(new[] { "amountMl", "clientId", "consumedAt", "id", "source" }, list.GetProperty("items")[0].EnumerateObject().Select(p => p.Name).Order());
        var total = await expert.GetFromJsonAsync<WaterLogDailyTotalResponse>(Reads(pair.Client.Id)[1]); Assert.Equal(250.125m, total!.TotalAmountMl);
        // Water consent alone suffices for consumption; all other grants may be absent.
        await using (var db = f.Database()) await db.DataSharingPermissions.Where(p => p.RelationshipId == pair.Relationship.Id && p.Category != "water_logs").ExecuteDeleteAsync();
        using (var allowed = await expert.GetAsync(Reads(pair.Client.Id)[1])) Assert.Equal(HttpStatusCode.OK, allowed.StatusCode);
        using (var revoke = await owner.PatchAsJsonAsync(Permissions + "/" + permission, new { isGranted = false })) Assert.Equal(HttpStatusCode.OK, revoke.StatusCode);
        foreach (var path in Reads(pair.Client.Id)) { using var denied = await expert.GetAsync(path); await Error(denied, 403); }
        using (var own = await owner.GetAsync("/api/v1/water-logs/" + water.Id)) Assert.Equal(HttpStatusCode.OK, own.StatusCode);
        using var ownTarget = await owner.GetAsync("/api/v1/personal-nutrition-targets"); Assert.Contains("2345", await ownTarget.Content.ReadAsStringAsync());
    }

    [PostgresFact]
    public async Task DefaultRolloutDoesNotCreatePermissionsAndDisabledRolloutStillAllowsWithdrawal()
    {
        await using var f = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(f); using var owner = Bearer(f, pair.Owner, "client");
        foreach (var granted in new[] { true, false })
        { using var result = await owner.PostAsJsonAsync(Permissions, new { relationshipId = pair.Relationship.Id, category = "water_logs", isGranted = granted }); await Error(result, 422); }
        Guid id;
        await using (var db = f.Database())
        {
            Assert.False(await db.DataSharingPermissions.AnyAsync(p => p.Category == "water_logs"));
            var permission = new DataSharingPermission(pair.Relationship.Id, true, DateTimeOffset.UtcNow, "water_logs"); id = permission.Id;
            db.DataSharingPermissions.Add(permission); await db.SaveChangesAsync();
        }
        using (var result = await owner.PatchAsJsonAsync(Permissions + "/" + id, new { isGranted = true })) await Error(result, 422);
        using (var result = await owner.PatchAsJsonAsync(Permissions + "/" + id, new { isGranted = false })) Assert.Equal(HttpStatusCode.OK, result.StatusCode);
        using var expert = Bearer(f, pair.Expert);
        foreach (var path in Reads(pair.Client.Id)) { using var result = await expert.GetAsync(path); await Error(result, 403); }
        await using var check = f.Database(); Assert.Equal(4, await check.DataSharingPermissions.CountAsync(p => p.RelationshipId == pair.Relationship.Id && p.Category != "water_logs" && p.IsGranted));
    }

    [PostgresFact]
    public async Task RevocationPreservesOtherGrantsAndRelationshipEndPreservesOwnersWater()
    {
        await using var f = await RegistrationApiFactory.CreateAsync(waterLogSharing: true); var pair = await Seed(f);
        using var owner = Bearer(f, pair.Owner, "client"); using var expert = Bearer(f, pair.Expert); await Water(owner, Day, 200);
        var id = await Grant(owner, pair);
        using (var revoke = await owner.PatchAsJsonAsync(Permissions + "/" + id, new { isGranted = false })) Assert.Equal(HttpStatusCode.OK, revoke.StatusCode);
        await using (var db = f.Database()) Assert.Equal(4, await db.DataSharingPermissions.CountAsync(p => p.RelationshipId == pair.Relationship.Id && p.Category != "water_logs" && p.IsGranted));
        using (var enable = await owner.PatchAsJsonAsync(Permissions + "/" + id, new { isGranted = true })) Assert.Equal(HttpStatusCode.OK, enable.StatusCode);
        using (var end = await owner.PostAsync($"/api/v1/dietitian-relationships/{pair.Relationship.Id}/end", null)) Assert.Equal(HttpStatusCode.OK, end.StatusCode);
        foreach (var path in Reads(pair.Client.Id)) { using var response = await expert.GetAsync(path); await Error(response, 404); }
        using var own = await owner.GetAsync("/api/v1/water-logs/daily-total?" + Bounds()); Assert.Equal(HttpStatusCode.OK, own.StatusCode);
        Assert.Equal(200, (await own.Content.ReadFromJsonAsync<WaterLogDailyTotalResponse>())!.TotalAmountMl);
    }

    [PostgresFact]
    public async Task EveryReadRequiresCurrentVerifiedExpertAndItsOwnActiveRelationship()
    {
        await using var f = await RegistrationApiFactory.CreateAsync(waterLogSharing: true); var pair = await Seed(f); var other = await Seed(f); var pending = await Seed(f, active: false);
        using var owner = Bearer(f, pair.Owner, "client"); await Grant(owner, pair); using var expert = Bearer(f, pair.Expert);
        using var pendingOwner = Bearer(f, pending.Owner, "client"); using var pendingExpert = Bearer(f, pending.Expert);
        using var stranger = Bearer(f, other.Expert); using var anonymous = f.Client(false);
        foreach (var path in Reads(pair.Client.Id))
        {
            using (var response = await stranger.GetAsync(path)) await Error(response, 404);
            using (var response = await owner.GetAsync(path)) await Error(response, 403);
            using (var response = await anonymous.GetAsync(path)) await Error(response, 401);
        }
        foreach (var path in Reads(pending.Client.Id)) { using var response = await pendingExpert.GetAsync(path); await Error(response, 404); }
        using (var notActive = await pendingOwner.PostAsJsonAsync(Permissions, new { relationshipId = pending.Relationship.Id, category = "water_logs", isGranted = true })) await Error(notActive, 409);
        foreach (var id in new[] { other.Client.Id, pair.Owner.Id, Guid.NewGuid() })
            foreach (var path in Reads(id)) { using var response = await expert.GetAsync(path); await Error(response, 404); }
        await using (var db = f.Database()) await db.DietitianProfiles.Where(p => p.Id == pair.Profile.Id).ExecuteUpdateAsync(s => s.SetProperty(p => p.IsVerified, false));
        foreach (var path in Reads(pair.Client.Id)) { using var response = await expert.GetAsync(path); await Error(response, 403); }
    }

    [PostgresFact]
    public async Task MfaAdminCannotReadAndExpertCannotWriteWaterOrGrantConsent()
    {
        await using var f = await RegistrationApiFactory.CreateAsync(waterLogSharing: true, webSessions: true); var pair = await Seed(f);
        using var owner = Bearer(f, pair.Owner, "client"); using var expert = Bearer(f, pair.Expert); var permission = await Grant(owner, pair); var water = await Water(owner, Day, 200);
        using (var grant = await expert.PatchAsJsonAsync(Permissions + "/" + permission, new { isGranted = true })) await Error(grant, 403);
        using (var grant = await expert.PostAsJsonAsync(Permissions, new { relationshipId = pair.Relationship.Id, category = "water_logs", isGranted = true })) await Error(grant, 403);
        using (var create = await expert.PostAsJsonAsync("/api/v1/water-logs", new { amountMl = 500, consumedAt = Day, source = "manual" })) await Error(create, 403);
        using (var patch = await expert.PatchAsJsonAsync("/api/v1/water-logs/" + water.Id, new { amountMl = 500 })) await Error(patch, 403);
        using (var delete = await expert.DeleteAsync("/api/v1/water-logs/" + water.Id)) await Error(delete, 403);
        using (var create = await expert.PostAsJsonAsync(Route(pair.Client.Id), new { amountMl = 500, consumedAt = Day, source = "manual" })) Assert.Equal(HttpStatusCode.MethodNotAllowed, create.StatusCode);
        var admin = new User(Guid.NewGuid(), Guid.NewGuid().ToString("N") + "@EXAMPLE.TEST", UserRole.Admin, Password, DateTimeOffset.UtcNow, new PasswordHasher<User>());
        using var scope = f.Services.CreateScope(); var mfa = scope.ServiceProvider.GetRequiredService<AdminMfaService>().Initialize(admin, DateTimeOffset.UtcNow);
        await using (var db = f.Database()) { db.Users.Add(admin); await db.SaveChangesAsync(); }
        using var adminWeb = f.Client(); await Login(adminWeb, admin.Email, mfa.RecoveryCodes[0]);
        foreach (var path in Reads(pair.Client.Id)) { using var read = await adminWeb.GetAsync(path); await Error(read, 403); }
    }

    [PostgresFact]
    public async Task OffsetDailyTotalsHistoryPaginationSoftDeleteAndEmptyDaysAgree()
    {
        await using var f = await RegistrationApiFactory.CreateAsync(waterLogSharing: true); var pair = await Seed(f); var other = await Seed(f);
        using var owner = Bearer(f, pair.Owner, "client"); using var stranger = Bearer(f, other.Owner, "client"); using var expert = Bearer(f, pair.Expert); await Grant(owner, pair);
        await Water(owner, Day.AddTicks(-10), 99); var first = await Water(owner, Day, 250.125m); var second = await Water(owner, Day, 500);
        await Water(owner, Day.AddDays(1), 75); var removed = await Water(owner, Day.AddHours(1), 999);
        using (var delete = await owner.DeleteAsync("/api/v1/water-logs/" + removed.Id)) Assert.Equal(HttpStatusCode.NoContent, delete.StatusCode);
        await Water(stranger, Day, 888);
        var expected = new[] { first.Id, second.Id }.Order().ToArray();
        for (var page = 1; page <= 3; page++)
        {
            var rows = await expert.GetFromJsonAsync<JsonElement>(Route(pair.Client.Id) + $"?page={page}&pageSize=1&" + Bounds());
            Assert.Equal(2, rows.GetProperty("totalCount").GetInt32()); Assert.Equal(page <= 2 ? 1 : 0, rows.GetProperty("items").GetArrayLength());
            if (page <= 2) Assert.Equal(expected[page - 1], rows.GetProperty("items")[0].GetProperty("id").GetGuid());
        }
        var total = await expert.GetFromJsonAsync<WaterLogDailyTotalResponse>(Reads(pair.Client.Id)[1]); Assert.Equal(750.125m, total!.TotalAmountMl); Assert.Equal(Day.ToUniversalTime(), total.From);
        var history = await expert.GetFromJsonAsync<JsonElement>(Route(pair.Client.Id) + "/daily-history?page=1&pageSize=3&timeZone=Europe%2FIstanbul&" + Bounds(Day, Day.AddDays(3)));
        Assert.Equal(3, history.GetProperty("totalCount").GetInt32()); Assert.Equal(new[] { 750.125m, 75m, 0m }, history.GetProperty("items").EnumerateArray().Select(x => x.GetProperty("totalAmountMl").GetDecimal()));
        var secondPage = await expert.GetFromJsonAsync<JsonElement>(Route(pair.Client.Id) + "/daily-history?page=2&pageSize=2&timeZone=Europe%2FIstanbul&" + Bounds(Day, Day.AddDays(3)));
        Assert.Single(secondPage.GetProperty("items").EnumerateArray());
    }

    [PostgresFact]
    public async Task IanaHistoryUsesActualSpringAndFallBoundariesAndRejectsMismatchedOffsets()
    {
        await using var f = await RegistrationApiFactory.CreateAsync(waterLogSharing: true); var pair = await Seed(f);
        using var owner = Bearer(f, pair.Owner, "client"); using var expert = Bearer(f, pair.Expert); await Grant(owner, pair);
        foreach (var dates in new[] { (new DateTimeOffset(2026, 3, 28, 0, 0, 0, TimeSpan.FromHours(1)), new DateTimeOffset(2026, 3, 31, 0, 0, 0, TimeSpan.FromHours(2)), 23d),
                     (new DateTimeOffset(2026, 10, 24, 0, 0, 0, TimeSpan.FromHours(2)), new DateTimeOffset(2026, 10, 27, 0, 0, 0, TimeSpan.FromHours(1)), 25d) })
        {
            var rows = (await expert.GetFromJsonAsync<JsonElement>(Route(pair.Client.Id) + "/daily-history?page=1&pageSize=10&timeZone=Europe%2FBerlin&" + Bounds(dates.Item1, dates.Item2))).GetProperty("items");
            Assert.Equal(3, rows.GetArrayLength()); Assert.Equal(dates.Item3, (rows[1].GetProperty("to").GetDateTimeOffset() - rows[1].GetProperty("from").GetDateTimeOffset()).TotalHours);
        }
        foreach (var suffix in new[] { "", "&timeZone=unknown", "&timeZone=Europe%2FBerlin", "&timeZone=Turkey%20Standard%20Time" })
        { using var bad = await expert.GetAsync(Route(pair.Client.Id) + "/daily-history?page=1&pageSize=10&" + Bounds() + suffix); await Error(bad, 400); }
        using var tooLong = await expert.GetAsync(Route(pair.Client.Id) + "/daily-history?page=1&pageSize=10&timeZone=Europe%2FIstanbul&" + Bounds(Day, Day.AddDays(32))); await Error(tooLong, 400);
    }

    [PostgresFact]
    public async Task QueryValidationDoesNotPermitAlternateOwnershipOrSilentlyDefaultPaging()
    {
        await using var f = await RegistrationApiFactory.CreateAsync(waterLogSharing: true); var pair = await Seed(f); using var owner = Bearer(f, pair.Owner, "client"); using var expert = Bearer(f, pair.Expert); await Grant(owner, pair);
        foreach (var query in new[] { "page=0&pageSize=10", "page=1&pageSize=101", "page=1&pageSize=10&page=2", "pageSize=10", "page=2147483647&pageSize=100", "page=1&pageSize=10&clientId=" + pair.Client.Id, "page=1&pageSize=10&from=2026-11-10T00:00:00" })
        { using var bad = await expert.GetAsync(Route(pair.Client.Id) + "?" + query); await Error(bad, 400); }
        using var body = new HttpRequestMessage(HttpMethod.Get, Reads(pair.Client.Id)[0]) { Content = JsonContent.Create(new { }) };
        using var badBody = await expert.SendAsync(body); await Error(badBody, 400);
        using var invalidDay = await expert.GetAsync(Route(pair.Client.Id) + "/daily-total?" + Bounds(Day.AddHours(1), Day.AddDays(1))); await Error(invalidDay, 400);
        using var consent = await owner.PatchAsJsonAsync(Permissions + "/" + await PermissionId(f, pair), new { isGranted = true, consentRecordId = Guid.NewGuid() }); await Error(consent, 422);
    }

    [PostgresFact]
    public async Task StartedSnapshotMayCompleteButWithdrawalDeniesEveryNewRead()
    {
        var pause = new WaterReadInterceptor(); await using var f = await RegistrationApiFactory.CreateAsync(waterLogSharing: true, interceptor: pause);
        var pair = await Seed(f); using var owner = Bearer(f, pair.Owner, "client"); using var expert = Bearer(f, pair.Expert); await Water(owner, Day, 250); var id = await Grant(owner, pair);
        pause.Armed = true; var started = expert.GetAsync(Reads(pair.Client.Id)[1]); await pause.Entered.Task.WaitAsync(TimeSpan.FromSeconds(10));
        using (var revoke = await owner.PatchAsJsonAsync(Permissions + "/" + id, new { isGranted = false })) Assert.Equal(HttpStatusCode.OK, revoke.StatusCode);
        pause.Release.TrySetResult(); using var completed = await started; Assert.Equal(HttpStatusCode.OK, completed.StatusCode);
        Assert.Equal(250, (await completed.Content.ReadFromJsonAsync<WaterLogDailyTotalResponse>())!.TotalAmountMl);
        foreach (var path in Reads(pair.Client.Id)) { using var denied = await expert.GetAsync(path); await Error(denied, 403); }
    }

    [PostgresFact]
    public async Task ReadFailureIsAnErrorRatherThanZeroConsumption()
    {
        var failure = new WaterReadInterceptor { Fail = true }; await using var f = await RegistrationApiFactory.CreateAsync(waterLogSharing: true, interceptor: failure);
        var pair = await Seed(f); using var owner = Bearer(f, pair.Owner, "client"); using var expert = Bearer(f, pair.Expert); await Water(owner, Day, 250); await Grant(owner, pair);
        foreach (var path in Reads(pair.Client.Id)) { failure.Armed = true; using var failed = await expert.GetAsync(path); await Error(failed, 500); }
    }

    [PostgresFact]
    public async Task MigrationPreservesDataAddsNoDefaultGrantsAndRejectsLossyDowngrade()
    {
        await using var f = await RegistrationApiFactory.CreateAsync();
        await using (var db = f.Database()) await db.GetService<IMigrator>().MigrateAsync("20261118222117_AddHealthDataSync");
        var pair = await Seed(f); using var owner = Bearer(f, pair.Owner, "client"); await Water(owner, Day, 333.125m);
        await using var database = f.Database();
        var beforeWater = await database.WaterLogs.AsNoTracking().Select(w => new { w.Id, w.ClientId, w.AmountMl, w.ConsumedAt, w.Source }).ToListAsync();
        var beforePermissions = await database.DataSharingPermissions.AsNoTracking().OrderBy(p => p.Id).Select(p => new { p.Id, p.Category, p.IsGranted, p.CreatedAt, p.UpdatedAt }).ToListAsync();
        await database.Database.MigrateAsync();
        Assert.Equal(beforeWater, await database.WaterLogs.AsNoTracking().Select(w => new { w.Id, w.ClientId, w.AmountMl, w.ConsumedAt, w.Source }).ToListAsync());
        Assert.Equal(beforePermissions, await database.DataSharingPermissions.AsNoTracking().OrderBy(p => p.Id).Select(p => new { p.Id, p.Category, p.IsGranted, p.CreatedAt, p.UpdatedAt }).ToListAsync());
        Assert.False(await database.DataSharingPermissions.AnyAsync(p => p.Category == "water_logs"));
        database.DataSharingPermissions.Add(new DataSharingPermission(pair.Relationship.Id, false, DateTimeOffset.UtcNow, "water_logs")); await database.SaveChangesAsync();
        await Assert.ThrowsAsync<PostgresException>(() => database.GetService<IMigrator>().MigrateAsync("20261118222117_AddHealthDataSync"));
        Assert.Equal(333.125m, (await database.WaterLogs.SingleAsync()).AmountMl); Assert.False(database.Database.HasPendingModelChanges());
    }

    private static async Task<Guid> PermissionId(RegistrationApiFactory f, Pair p)
    { await using var db = f.Database(); return await db.DataSharingPermissions.Where(x => x.RelationshipId == p.Relationship.Id && x.Category == "water_logs").Select(x => x.Id).SingleAsync(); }
    private static async Task<Guid> Grant(HttpClient owner, Pair p)
    { using var result = await owner.PostAsJsonAsync(Permissions, new { relationshipId = p.Relationship.Id, category = "water_logs", isGranted = true }); Assert.Equal(HttpStatusCode.Created, result.StatusCode); return (await result.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid(); }
    private static async Task<WaterLogResponse> Water(HttpClient owner, DateTimeOffset time, decimal amount)
    { using var result = await owner.PostAsJsonAsync("/api/v1/water-logs", new { amountMl = amount, consumedAt = time, source = "manual" }); Assert.Equal(HttpStatusCode.Created, result.StatusCode); return (await result.Content.ReadFromJsonAsync<WaterLogResponse>())!; }
    private static async Task<Pair> Seed(RegistrationApiFactory f, bool dual = false, bool active = true)
    {
        var now = DateTimeOffset.UtcNow; var hasher = new PasswordHasher<User>();
        var owner = new User(Guid.NewGuid(), Guid.NewGuid().ToString("N") + "@EXAMPLE.TEST", UserRole.Client, Password, now, hasher); var client = new ClientProfile(Guid.NewGuid(), owner, "Synthetic water owner");
        var expert = new User(Guid.NewGuid(), Guid.NewGuid().ToString("N") + "@EXAMPLE.TEST", dual ? UserRole.Client : UserRole.Dietitian, Password, now, hasher); var profile = new DietitianProfile(expert, "Synthetic expert", "Synthetic license");
        if (dual) _ = new ClientProfile(Guid.NewGuid(), expert, "Synthetic dual client");
        await using var db = f.Database(); db.Users.AddRange(owner, expert); db.Entry(owner).Property(x => x.IsEmailVerified).CurrentValue = true; db.Entry(expert).Property(x => x.IsEmailVerified).CurrentValue = true; db.Entry(profile).Property(x => x.IsVerified).CurrentValue = true;
        var relation = new DietitianClientRelationship(client.Id, profile.Id, now); if (active) relation.Respond(RelationshipStatus.Active, now);
        db.DietitianClientRelationships.Add(relation);
        foreach (var category in new[] { "nutrition_plans", "meal_logs", "body_measurements", "client_tasks" }) db.DataSharingPermissions.Add(new DataSharingPermission(relation.Id, true, now, category));
        await db.SaveChangesAsync(); return new(owner, client, expert, profile, relation);
    }
    private static HttpClient Bearer(RegistrationApiFactory f, User user, string context = "dietitian")
    { var client = f.Client(false); client.DefaultRequestHeaders.Authorization = new("Bearer", new JwtAccessTokenService(Options.Create(f.Jwt.Options), TimeProvider.System).Issue(user).AccessToken); client.DefaultRequestHeaders.Add("X-Profile-Context", context); return client; }
    private static async Task Login(HttpClient web, string email, string? recovery = null)
    {
        var csrf = await web.GetFromJsonAsync<JsonElement>("/api/v1/auth/csrf");
        using var request = new HttpRequestMessage(HttpMethod.Post, recovery is null ? "/api/v1/auth/web-session" : "/api/v1/auth/admin-web-session")
        { Content = recovery is null ? JsonContent.Create(new { email, password = Password }) : JsonContent.Create(new { email, password = Password, mfaCode = recovery }) };
        request.Headers.Add("Origin", "https://localhost"); request.Headers.Add("X-CSRF-TOKEN", csrf.GetProperty("requestToken").GetString());
        using var result = await web.SendAsync(request); Assert.Equal(HttpStatusCode.OK, result.StatusCode);
    }
    private static async Task Error(HttpResponseMessage result, int expected)
    {
        var text = await result.Content.ReadAsStringAsync(); Assert.True((int)result.StatusCode == expected, $"Expected {expected}, got {result.StatusCode}: {text}");
        var body = JsonSerializer.Deserialize<JsonElement>(text); Assert.True(body.TryGetProperty("requestId", out _)); Assert.True(body.TryGetProperty("error", out _));
        Assert.False(body.TryGetProperty("totalAmountMl", out _)); Assert.False(body.TryGetProperty("items", out _)); Assert.Contains("no-store", result.Headers.CacheControl!.ToString());
    }
    private sealed class WaterReadInterceptor : DbCommandInterceptor
    {
        internal bool Armed; internal bool Fail;
        internal TaskCompletionSource Entered { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal TaskCompletionSource Release { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public override async ValueTask<InterceptionResult<DbDataReader>> ReaderExecutingAsync(DbCommand command, CommandEventData eventData, InterceptionResult<DbDataReader> result, CancellationToken cancellationToken = default)
        {
            if (Armed && command.CommandText.Contains("FROM water_logs", StringComparison.Ordinal))
            { Armed = false; if (Fail) throw new InvalidOperationException("Synthetic water read failure"); Entered.TrySetResult(); await Release.Task.WaitAsync(TimeSpan.FromSeconds(10), cancellationToken); }
            return result;
        }
    }
}
