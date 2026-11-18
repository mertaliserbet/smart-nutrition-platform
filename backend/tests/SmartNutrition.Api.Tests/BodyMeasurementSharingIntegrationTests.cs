using System.Data.Common;
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Microsoft.EntityFrameworkCore.Migrations.Operations;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using Npgsql;
using SmartNutrition.Api.Data.Migrations;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Features.Dietitians;
using SmartNutrition.Api.Features.Relationships;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Tests;

public sealed class BodyMeasurementSharingIntegrationTests
{
    private const string Password = "Synthetic G2 test password";
    private const string PrivateNote = "Synthetic private G2 note";
    private sealed record Pair(User Owner, ClientProfile Client, User Expert, DietitianClientRelationship Relationship, DataSharingPermission Permission);
    private static string Route(Guid clientId, string query = "page=1&pageSize=10") => $"/api/v1/dietitian/clients/{clientId}/body-measurements?{query}";

    [Fact]
    public void SharingMigrationOnlyChangesCategoryCheckAndGuardsDataPreservingRollback()
    {
        var migration = new AddBodyMeasurementSharingCategory(); Assert.Equal(2, migration.UpOperations.Count);
        Assert.IsType<DropCheckConstraintOperation>(migration.UpOperations[0]);
        var constraint = Assert.IsType<AddCheckConstraintOperation>(migration.UpOperations[1]);
        Assert.Equal("data_sharing_permissions", constraint.Table);
        Assert.Equal("category IN ('nutrition_plans','meal_logs','body_measurements') AND consent_record_id IS NULL", constraint.Sql);
        Assert.Equal(2, migration.DownOperations.Count);
        Assert.Equal("category IN ('nutrition_plans','meal_logs') AND consent_record_id IS NULL", Assert.IsType<AddCheckConstraintOperation>(migration.DownOperations[1]).Sql);
    }

    [PostgresFact]
    public async Task DefaultAndProductionRolloutsKeepLegacyListsUnchangedButPermitExistingWithdrawal()
    {
        foreach (var (environment, enabled) in new[] { ("Production", false), ("Development", false), ("Production", true) })
        {
            await using var factory = await RegistrationApiFactory.CreateAsync(environment: environment, bodyMeasurementSharing: enabled);
            var pair = await Seed(factory); using var client = Bearer(factory, pair.Owner, "client");
            await using (var db = factory.Database())
            { db.DataSharingPermissions.Remove(await db.DataSharingPermissions.SingleAsync(x => x.Id == pair.Permission.Id)); await db.SaveChangesAsync(); }
            foreach (var isGranted in new[] { false, true })
            {
                using var created = await client.PostAsJsonAsync("/api/v1/data-sharing-permissions", new { relationshipId = pair.Relationship.Id, category = "body_measurements", isGranted });
                await Error(created, HttpStatusCode.UnprocessableEntity, "validation_failed");
            }
            var list = await client.GetFromJsonAsync<JsonElement>($"/api/v1/data-sharing-permissions?relationshipId={pair.Relationship.Id}&page=1&pageSize=10");
            Assert.Equal(2, list.GetProperty("totalCount").GetInt32());
            Assert.All(list.GetProperty("items").EnumerateArray(), row => Assert.NotEqual("body_measurements", row.GetProperty("category").GetString()));
            await using (var db = factory.Database())
            { db.DataSharingPermissions.Add(new DataSharingPermission(pair.Relationship.Id, true, DateTimeOffset.UtcNow, "body_measurements")); await db.SaveChangesAsync(); }
            await using var check = factory.Database(); var permission = await check.DataSharingPermissions.SingleAsync(x => x.Category == "body_measurements");
            using var grant = await client.PatchAsJsonAsync($"/api/v1/data-sharing-permissions/{permission.Id}", new { isGranted = true });
            await Error(grant, HttpStatusCode.UnprocessableEntity, "validation_failed");
            using var revoke = await client.PatchAsJsonAsync($"/api/v1/data-sharing-permissions/{permission.Id}", new { isGranted = false }); Assert.Equal(HttpStatusCode.OK, revoke.StatusCode);
            var visible = await client.GetFromJsonAsync<JsonElement>($"/api/v1/data-sharing-permissions?relationshipId={pair.Relationship.Id}&page=1&pageSize=10");
            Assert.Equal(3, visible.GetProperty("totalCount").GetInt32());
        }
    }

    [PostgresFact]
    public async Task DevelopmentGrantAndRevokeAreIndependentAndListsRetainAllCategoriesWithPaging()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(environment: "Development", bodyMeasurementSharing: true);
        var pair = await Seed(factory); using var client = Bearer(factory, pair.Owner, "client"); using var expert = Bearer(factory, pair.Expert);
        await using (var db = factory.Database())
        { db.DataSharingPermissions.Remove(await db.DataSharingPermissions.SingleAsync(x => x.Id == pair.Permission.Id)); await db.SaveChangesAsync(); }
        using var denied = await expert.GetAsync(Route(pair.Client.Id)); await Error(denied, HttpStatusCode.Forbidden, "forbidden");
        using var created = await client.PostAsJsonAsync("/api/v1/data-sharing-permissions", new { relationshipId = pair.Relationship.Id, category = "body_measurements", isGranted = true });
        Assert.Equal(HttpStatusCode.Created, created.StatusCode); var permission = await created.Content.ReadFromJsonAsync<JsonElement>();
        var id = permission.GetProperty("id").GetGuid(); Assert.Equal(JsonValueKind.Null, permission.GetProperty("consentRecordId").ValueKind);
        using var duplicate = await client.PostAsJsonAsync("/api/v1/data-sharing-permissions", new { relationshipId = pair.Relationship.Id, category = "body_measurements", isGranted = false });
        await Error(duplicate, HttpStatusCode.Conflict, "conflict");
        var categories = new HashSet<string>();
        for (var page = 1; page <= 3; page++)
        {
            var data = await client.GetFromJsonAsync<JsonElement>($"/api/v1/data-sharing-permissions?relationshipId={pair.Relationship.Id}&page={page}&pageSize=1");
            Assert.Equal(3, data.GetProperty("totalCount").GetInt32()); categories.Add(data.GetProperty("items")[0].GetProperty("category").GetString()!);
        }
        Assert.Equal(new[] { "body_measurements", "meal_logs", "nutrition_plans" }, categories.Order());
        using var granted = await expert.GetAsync(Route(pair.Client.Id)); Assert.Equal(HttpStatusCode.OK, granted.StatusCode);
        using var revoke = await client.PatchAsJsonAsync($"/api/v1/data-sharing-permissions/{id}", new { isGranted = false }); Assert.Equal(HttpStatusCode.OK, revoke.StatusCode);
        using var after = await expert.GetAsync(Route(pair.Client.Id)); await Error(after, HttpStatusCode.Forbidden, "forbidden");
        using var meals = await expert.GetAsync($"/api/v1/dietitian/clients/{pair.Client.Id}/meal-logs?page=1&pageSize=10"); Assert.Equal(HttpStatusCode.OK, meals.StatusCode);
        using var regrant = await client.PatchAsJsonAsync($"/api/v1/data-sharing-permissions/{id}", new { isGranted = true }); Assert.Equal(HttpStatusCode.OK, regrant.StatusCode);
        await using (var db = factory.Database())
            await db.DataSharingPermissions.Where(x => x.RelationshipId == pair.Relationship.Id && x.Category == "meal_logs").ExecuteUpdateAsync(x => x.SetProperty(p => p.IsGranted, false));
        using var stillGranted = await expert.GetAsync(Route(pair.Client.Id)); Assert.Equal(HttpStatusCode.OK, stillGranted.StatusCode);
        using var closedMeals = await expert.GetAsync($"/api/v1/dietitian/clients/{pair.Client.Id}/meal-logs?page=1&pageSize=10"); await Error(closedMeals, HttpStatusCode.Forbidden, "forbidden");
        await using var check = factory.Database(); Assert.True((await check.DataSharingPermissions.SingleAsync(x => x.RelationshipId == pair.Relationship.Id && x.Category == "nutrition_plans")).IsGranted);
    }

    [PostgresFact]
    public async Task OnlyOwnActiveClientCanGrantAndConsentOrCategoryMutationsAreRejected()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(environment: "Development", bodyMeasurementSharing: true);
        var pair = await Seed(factory); var other = await Seed(factory);
        using var client = Bearer(factory, pair.Owner, "client"); using var foreign = Bearer(factory, other.Owner, "client"); using var expert = Bearer(factory, pair.Expert);
        using var stranger = await foreign.PatchAsJsonAsync($"/api/v1/data-sharing-permissions/{pair.Permission.Id}", new { isGranted = false }); await Error(stranger, HttpStatusCode.NotFound, "not_found");
        using var expertGrant = await expert.PostAsJsonAsync("/api/v1/data-sharing-permissions", new { relationshipId = pair.Relationship.Id, category = "body_measurements", isGranted = true }); await Error(expertGrant, HttpStatusCode.Forbidden, "forbidden");
        using var expertRevoke = await expert.PatchAsJsonAsync($"/api/v1/data-sharing-permissions/{pair.Permission.Id}", new { isGranted = false }); await Error(expertRevoke, HttpStatusCode.Forbidden, "forbidden");
        using var consent = await client.PatchAsJsonAsync($"/api/v1/data-sharing-permissions/{pair.Permission.Id}", new { isGranted = true, consentRecordId = Guid.NewGuid() }); await Error(consent, HttpStatusCode.UnprocessableEntity, "validation_failed");
        using var category = await client.PatchAsJsonAsync($"/api/v1/data-sharing-permissions/{pair.Permission.Id}", new { isGranted = true, category = "nutrition_plans" }); await Error(category, HttpStatusCode.BadRequest, "invalid_request");
        Guid pendingId;
        await using (var db = factory.Database())
        { var pending = new DietitianClientRelationship(pair.Client.Id, pair.Relationship.DietitianId, DateTimeOffset.UtcNow); pendingId = pending.Id; db.DietitianClientRelationships.Add(pending); await db.SaveChangesAsync(); }
        using var pendingGrant = await client.PostAsJsonAsync("/api/v1/data-sharing-permissions", new { relationshipId = pendingId, category = "body_measurements", isGranted = true }); await Error(pendingGrant, HttpStatusCode.Conflict, "conflict");
        using var end = await client.PostAsync($"/api/v1/dietitian-relationships/{pair.Relationship.Id}/end", null); Assert.Equal(HttpStatusCode.OK, end.StatusCode);
        using var endedGrant = await client.PatchAsJsonAsync($"/api/v1/data-sharing-permissions/{pair.Permission.Id}", new { isGranted = true }); await Error(endedGrant, HttpStatusCode.Conflict, "conflict");
    }

    [PostgresFact]
    public async Task ChronologicalGraphReadsKeepNullsAndUseStableIdTies()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory); using var client = Bearer(factory, pair.Owner, "client"); using var expert = Bearer(factory, pair.Expert);
        var newer = await Measurement(client, "2026-11-19T00:00:00Z"); var first = await Measurement(client, "2026-11-18T00:00:00Z"); var second = await Measurement(client, "2026-11-18T00:00:00Z");
        var expected = new[] { first.GetProperty("id").GetGuid(), second.GetProperty("id").GetGuid() }.Order().Append(newer.GetProperty("id").GetGuid()).ToArray();
        var ids = new List<Guid>();
        for (var page = 1; page <= 3; page++)
        {
            var response = await expert.GetFromJsonAsync<JsonElement>(Route(pair.Client.Id, $"page={page}&pageSize=1&sortOrder=asc"));
            Assert.Equal(3, response.GetProperty("totalCount").GetInt32()); var row = response.GetProperty("items")[0]; ids.Add(row.GetProperty("id").GetGuid());
            Assert.Equal(JsonValueKind.Null, row.GetProperty("bodyFatPercent").ValueKind); Assert.Equal(73.125m, row.GetProperty("weightKg").GetDecimal());
        }
        Assert.Equal(expected, ids);
    }

    [PostgresFact]
    public async Task SharingMigrationPreservesAllDataNeverBackfillsAndBlocksRollbackEvenForDeniedRows()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(environment: "Development", bodyMeasurementSharing: true);
        var pair = await Seed(factory); using var client = Bearer(factory, pair.Owner, "client"); await Measurement(client);
        using var meal = await client.PostAsJsonAsync("/api/v1/meal-logs", new { mealType = "lunch", consumedAt = "2026-11-18T12:00:00Z", source = "manual", items = new[] { new { displayName = "Synthetic preserved meal", isEstimated = true } } }); Assert.Equal(HttpStatusCode.Created, meal.StatusCode);
        using var water = await client.PostAsJsonAsync("/api/v1/water-logs", new { amountMl = 250.125m, consumedAt = "2026-11-18T12:00:00Z", source = "manual" }); Assert.Equal(HttpStatusCode.Created, water.StatusCode);
        using var target = await client.PatchAsJsonAsync("/api/v1/personal-nutrition-targets", new { dailyWaterTargetMl = 2100m }); Assert.Equal(HttpStatusCode.OK, target.StatusCode);
        using var plan = await client.PostAsJsonAsync("/api/v1/nutrition-plans", new { title = "Synthetic preserved sharing plan", startDate = "2026-11-18", items = new[] { new { mealType = "lunch", description = "Synthetic recommendation", sortOrder = 0 } } }); Assert.Equal(HttpStatusCode.Created, plan.StatusCode);
        await using var db = factory.Database(); db.DataSharingPermissions.Remove(await db.DataSharingPermissions.SingleAsync(x => x.Id == pair.Permission.Id)); await db.SaveChangesAsync();
        var migrator = db.GetService<IMigrator>(); await migrator.MigrateAsync("20261118121322_AddBodyMeasurements");
        var before = await Snapshot(db); await migrator.MigrateAsync(); Assert.Equal(before, await Snapshot(db));
        Assert.False(await db.DataSharingPermissions.AnyAsync(x => x.Category == "body_measurements")); Assert.False(db.Database.HasPendingModelChanges());
        await migrator.MigrateAsync("20261118121322_AddBodyMeasurements"); Assert.Equal(before, await Snapshot(db));
        await migrator.MigrateAsync(); Assert.Equal(before, await Snapshot(db));
        using var denied = await client.PostAsJsonAsync("/api/v1/data-sharing-permissions", new { relationshipId = pair.Relationship.Id, category = "body_measurements", isGranted = false }); Assert.Equal(HttpStatusCode.Created, denied.StatusCode);
        var withDenied = await Snapshot(db);
        var rollback = await Assert.ThrowsAsync<PostgresException>(() => migrator.MigrateAsync("20261118121322_AddBodyMeasurements")); Assert.Equal(PostgresErrorCodes.CheckViolation, rollback.SqlState);
        Assert.Equal(withDenied, await Snapshot(db));
        var invalid = await Assert.ThrowsAsync<PostgresException>(() => db.Database.ExecuteSqlInterpolatedAsync($"UPDATE data_sharing_permissions SET category={"all"} WHERE relationship_id={pair.Relationship.Id}")); Assert.Equal(PostgresErrorCodes.CheckViolation, invalid.SqlState);
    }

    private static async Task<string[]> Snapshot(SmartNutrition.Api.Data.AppDbContext db)
    {
        var values = new List<string>(); var connection = db.Database.GetDbConnection(); await connection.OpenAsync();
        try
        {
            foreach (var table in new[] { "users", "client_profiles", "dietitian_profiles", "dietitian_client_relationships", "data_sharing_permissions", "body_measurements", "meal_logs", "meal_log_items", "water_logs", "personal_nutrition_targets", "nutrition_plans", "nutrition_plan_versions", "auth_sessions", "refresh_tokens", "audit_events" })
            {
                await using var command = connection.CreateCommand(); command.CommandText = $"SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text), '[]'::jsonb)::text FROM {table} t";
                values.Add((string)(await command.ExecuteScalarAsync())!);
            }
        }
        finally { await connection.CloseAsync(); }
        return values.ToArray();
    }

    [PostgresFact]
    public async Task ListReturnsExistingFullDetailWithoutChangingClientCrudOrFlag()
    {
        // The rollout flag controls permission writes, not access to an existing explicit grant.
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory);
        using var owner = Bearer(factory, pair.Owner, "client"); using var expert = Bearer(factory, pair.Expert);
        var original = await Measurement(owner);
        using var response = await expert.GetAsync(Route(pair.Client.Id)); Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Contains("no-store", response.Headers.CacheControl!.ToString());
        var page = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal(1, page.GetProperty("totalCount").GetInt32());
        Assert.Equal(original.GetRawText(), page.GetProperty("items")[0].GetRawText());
        Assert.Equal(JsonValueKind.Null, page.GetProperty("items")[0].GetProperty("bodyFatPercent").ValueKind);
        using var grant = await owner.PatchAsJsonAsync($"/api/v1/data-sharing-permissions/{pair.Permission.Id}", new { isGranted = true });
        Assert.Equal(HttpStatusCode.UnprocessableEntity, grant.StatusCode);
        Assert.DoesNotContain(PrivateNote, factory.Logs);
    }

    [PostgresFact]
    public async Task DateRangePagingOrderAndSoftDeleteUseOnlyRequestedClientsRows()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory);
        using var owner = Bearer(factory, pair.Owner, "client"); using var expert = Bearer(factory, pair.Expert);
        await Measurement(owner, "2026-11-17T23:59:59Z");
        var first = await Measurement(owner, "2026-11-18T00:00:00Z");
        var second = await Measurement(owner, "2026-11-18T00:00:00Z");
        await Measurement(owner, "2026-11-19T00:00:00Z");
        var removed = await Measurement(owner, "2026-11-18T12:00:00Z");
        using var deleted = await owner.DeleteAsync($"/api/v1/body-measurements/{removed.GetProperty("id").GetGuid()}");
        Assert.Equal(HttpStatusCode.NoContent, deleted.StatusCode);
        var stranger = await Seed(factory); using var other = Bearer(factory, stranger.Owner, "client"); await Measurement(other);
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
        var ordered = all.GetProperty("items").EnumerateArray().Select(x => x.GetProperty("measuredAt").GetDateTimeOffset()).ToArray();
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
    public async Task NutritionPermissionDoesNotGrantMeasurementsAndRevocationClosesNextRead()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(bodyMeasurementSharing: true, environment: "Development"); var pair = await Seed(factory);
        using var owner = Bearer(factory, pair.Owner, "client"); using var expert = Bearer(factory, pair.Expert); await Measurement(owner);
        using var before = await expert.GetAsync(Route(pair.Client.Id)); Assert.Equal(HttpStatusCode.OK, before.StatusCode);
        using var revoked = await owner.PatchAsJsonAsync($"/api/v1/data-sharing-permissions/{pair.Permission.Id}", new { isGranted = false });
        Assert.Equal(HttpStatusCode.OK, revoked.StatusCode);
        using var after = await expert.GetAsync(Route(pair.Client.Id)); await Error(after, HttpStatusCode.Forbidden, "forbidden");
        await using (var db = factory.Database())
        { db.DataSharingPermissions.Remove(await db.DataSharingPermissions.SingleAsync(x => x.Id == pair.Permission.Id)); await db.SaveChangesAsync(); }
        using var absent = await expert.GetAsync(Route(pair.Client.Id)); await Error(absent, HttpStatusCode.Forbidden, "forbidden");
        using var own = await owner.GetAsync("/api/v1/body-measurements?page=1&pageSize=10"); Assert.Equal(HttpStatusCode.OK, own.StatusCode);
    }

    [PostgresFact]
    public async Task ForeignMissingPendingAndEndedRelationshipsHideExistence()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory); var other = await Seed(factory);
        using var expert = Bearer(factory, pair.Expert); using var owner = Bearer(factory, pair.Owner, "client"); await Measurement(owner);
        foreach (var id in new[] { other.Client.Id, pair.Owner.Id, Guid.NewGuid() })
        { using var response = await expert.GetAsync(Route(id)); await Error(response, HttpStatusCode.NotFound, "not_found"); }
        using var ended = await owner.PostAsync($"/api/v1/dietitian-relationships/{pair.Relationship.Id}/end", null);
        Assert.Equal(HttpStatusCode.OK, ended.StatusCode);
        using var afterEnd = await expert.GetAsync(Route(pair.Client.Id)); await Error(afterEnd, HttpStatusCode.NotFound, "not_found");
        await using (var db = factory.Database())
        {
            var pending = new DietitianClientRelationship(pair.Client.Id, pair.Relationship.DietitianId, DateTimeOffset.UtcNow);
            db.DietitianClientRelationships.Add(pending);
            db.DataSharingPermissions.Add(new DataSharingPermission(pending.Id, true, DateTimeOffset.UtcNow, "body_measurements"));
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
            "page=x&pageSize=10", "page=1&pageSize=10&page=2", "page=1&pageSize=10&clientId=other", "page=1&pageSize=10&from=", "page=1&pageSize=10&sortOrder=", "page=1&pageSize=10&sortOrder=invalid", "page=1&pageSize=10&sortOrder=asc&sortOrder=desc",
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
        using var ownWrite = await expert.PostAsJsonAsync("/api/v1/body-measurements", new { measuredAt = "2026-11-18T00:00:00Z", source = "manual", weightKg = 73.125m });
        await Error(ownWrite, HttpStatusCode.Forbidden, "forbidden");
        using var owner = Bearer(factory, pair.Owner, "client"); var original = await Measurement(owner); var id = original.GetProperty("id").GetGuid();
        using var forbiddenPatch = await expert.PatchAsJsonAsync($"/api/v1/body-measurements/{id}", new { weightKg = 80 }); await Error(forbiddenPatch, HttpStatusCode.Forbidden, "forbidden");
        using var forbiddenDelete = await expert.DeleteAsync($"/api/v1/body-measurements/{id}"); await Error(forbiddenDelete, HttpStatusCode.Forbidden, "forbidden");
        Assert.Equal(original.GetRawText(), (await owner.GetFromJsonAsync<JsonElement>($"/api/v1/body-measurements/{id}")).GetRawText());
        expert.DefaultRequestHeaders.Remove("X-Profile-Context"); expert.DefaultRequestHeaders.Add("X-Profile-Context", "admin");
        using var invalidHeader = await expert.GetAsync(Route(pair.Client.Id)); await Error(invalidHeader, HttpStatusCode.BadRequest, "invalid_request");
    }

    [PostgresFact]
    public async Task InFlightReadKeepsAuthorizationCountAndRowsInOneSnapshotAndNextReadSeesWithdrawal()
    {
        var pause = new CountPause(); await using var factory = await RegistrationApiFactory.CreateAsync(interceptor: pause);
        var pair = await Seed(factory); using var owner = Bearer(factory, pair.Owner, "client"); await Measurement(owner);
        using var expert = Bearer(factory, pair.Expert); pause.Armed = true;
        var reading = expert.GetAsync(Route(pair.Client.Id));
        try
        {
            await pause.Entered.Task.WaitAsync(TimeSpan.FromSeconds(10));
            await Measurement(owner);
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
    public async Task StorageFailureDoesNotReturnOrLogMeasurementData()
    {
        var failure = new ReadFailure(); await using var factory = await RegistrationApiFactory.CreateAsync(interceptor: failure);
        var pair = await Seed(factory); using var owner = Bearer(factory, pair.Owner, "client"); await Measurement(owner);
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
        var permission = new DataSharingPermission(relation.Id, true, DateTimeOffset.UtcNow, "body_measurements");
        db.DietitianClientRelationships.Add(relation); db.DataSharingPermissions.AddRange(permission, new DataSharingPermission(relation.Id, true, DateTimeOffset.UtcNow), new DataSharingPermission(relation.Id, true, DateTimeOffset.UtcNow, "meal_logs"));
        await db.SaveChangesAsync(); return new(owner, client, expert, relation, permission);
    }

    private static HttpClient Bearer(RegistrationApiFactory factory, User user, string context = "dietitian")
    {
        var client = factory.Client(false); var jwt = new JwtAccessTokenService(Options.Create(factory.Jwt.Options), TimeProvider.System).Issue(user);
        client.DefaultRequestHeaders.Authorization = new("Bearer", jwt.AccessToken); client.DefaultRequestHeaders.Add("X-Profile-Context", context); return client;
    }

    private static async Task<JsonElement> Measurement(HttpClient owner, string time = "2026-11-18T12:00:00Z")
    {
        using var response = await owner.PostAsJsonAsync("/api/v1/body-measurements", new
        {
            measuredAt = time, source = "manual", weightKg = 73.125m, waistCm = 83.5m,
            hipCm = 97.75m, chestCm = 91.25m, note = PrivateNote
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
            if (Armed && command.CommandText.Contains("FROM body_measurements", StringComparison.Ordinal)) throw new InvalidOperationException("Synthetic G2 database failure");
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
            if (Armed && command.CommandText.Contains("count(", StringComparison.Ordinal) && command.CommandText.Contains("FROM body_measurements", StringComparison.Ordinal))
            {
                Armed = false; Entered.TrySetResult(true);
                await Release.Task.WaitAsync(TimeSpan.FromSeconds(10), cancellationToken);
            }
            return result;
        }
    }
}
