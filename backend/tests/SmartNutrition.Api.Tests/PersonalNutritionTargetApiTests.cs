using System.Data.Common;
using System.Net;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Microsoft.Extensions.Options;
using Npgsql;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Features.Dietitians;
using SmartNutrition.Api.Features.PersonalNutritionTargets;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Tests;

public sealed class PersonalNutritionTargetApiTests
{
    private const string Root = "/api/v1/personal-nutrition-targets";
    private const string Password = "synthetic personal target test password";
    private const string PreviousMigration = "20261116203303_AddWaterLogs";
    private static readonly (string Name, string Column, decimal Maximum)[] Fields =
    [
        ("dailyCaloriesTargetKcal", "daily_calories_target_kcal", 10000),
        ("dailyProteinTargetGrams", "daily_protein_target_grams", 1000),
        ("dailyCarbsTargetGrams", "daily_carbs_target_grams", 1000),
        ("dailyFatTargetGrams", "daily_fat_target_grams", 1000),
        ("dailyWaterTargetMl", "daily_water_target_ml", 15000)
    ];
    private sealed record Actor(Guid UserId, Guid ProfileId);

    [Fact]
    public void DomainKeepsTargetsOptionalAndIndependentAndRejectsInvalidValues()
    {
        Assert.Throws<ArgumentException>(() => new PersonalNutritionTarget(Guid.Empty));
        var row = new PersonalNutritionTarget(Guid.NewGuid());
        row.Revise(null, null, null, null, null); Assert.Null(row.DailyCaloriesTargetKcal);
        row.Revise(1500.125m, null, 125.5m, null, 2000); Assert.Null(row.DailyProteinTargetGrams);
        Assert.Equal(125.5m, row.DailyCarbsTargetGrams);
        Assert.Throws<ArgumentOutOfRangeException>(() => row.Revise(0, null, null, null, null));
        Assert.Throws<ArgumentOutOfRangeException>(() => row.Revise(null, 1001, null, null, null));
        Assert.Throws<ArgumentOutOfRangeException>(() => row.Revise(null, null, -1, null, null));
        Assert.Throws<ArgumentOutOfRangeException>(() => row.Revise(null, null, null, 1001, null));
        Assert.Throws<ArgumentOutOfRangeException>(() => row.Revise(null, null, null, null, 15001));
        Assert.Equal(1500.125m, row.DailyCaloriesTargetKcal); // Rejected mutations are atomic.
    }

    [PostgresFact]
    public async Task NewUserReadReturnsAllNullAndPersonalSourceWithoutCreatingDefaultsOrOtherRecords()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var actor = await Seed(factory);
        using var client = await Client(factory, actor); using var response = await client.GetAsync(Root);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode); Assert.Contains("no-store", response.Headers.CacheControl!.ToString());
        var result = await response.Content.ReadFromJsonAsync<JsonElement>(); AssertShape(result);
        foreach (var field in Fields) Assert.Equal(JsonValueKind.Null, result.GetProperty(field.Name).ValueKind);
        await using var db = factory.Database(); Assert.Empty(await db.PersonalNutritionTargets.ToListAsync());
        Assert.Empty(await db.NutritionPlans.ToListAsync()); Assert.Empty(await db.MealLogs.ToListAsync()); Assert.Empty(await db.WaterLogs.ToListAsync());
    }

    [PostgresFact]
    public async Task FirstPatchPersistsExactNullableDecimalsAndFollowingPartialPatchesOnlyChangeSuppliedFields()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var actor = await Seed(factory); using var client = await Client(factory, actor);
        var first = await Patch(client, new { dailyCaloriesTargetKcal = 1800.123456789m, dailyProteinTargetGrams = (decimal?)null, dailyCarbsTargetGrams = 150.5m });
        AssertShape(first); Assert.Equal(1800.123456789m, first.GetProperty("dailyCaloriesTargetKcal").GetDecimal());
        Assert.Equal(JsonValueKind.Null, first.GetProperty("dailyWaterTargetMl").ValueKind);
        var second = await Patch(client, new { dailyWaterTargetMl = 2100.125m, dailyFatTargetGrams = 60m });
        Assert.Equal(1800.123456789m, second.GetProperty("dailyCaloriesTargetKcal").GetDecimal());
        Assert.Equal(150.5m, second.GetProperty("dailyCarbsTargetGrams").GetDecimal());
        var cleared = await Patch(client, new { dailyCaloriesTargetKcal = (decimal?)null });
        Assert.Equal(JsonValueKind.Null, cleared.GetProperty("dailyCaloriesTargetKcal").ValueKind);
        Assert.Equal(2100.125m, cleared.GetProperty("dailyWaterTargetMl").GetDecimal());
        using var invalid = await client.PatchAsJsonAsync(Root, new { dailyFatTargetGrams = 70, dailyWaterTargetMl = -1 }); await Error(invalid, 422);
        Assert.Equal(cleared.GetRawText(), (await client.GetFromJsonAsync<JsonElement>(Root)).GetRawText());
        await using var db = factory.Database(); var saved = await db.PersonalNutritionTargets.SingleAsync();
        Assert.Equal(actor.ProfileId, saved.ClientId); Assert.NotEqual(actor.UserId, saved.ClientId); Assert.Equal(60m, saved.DailyFatTargetGrams);
        Assert.Equal(150.5m, saved.DailyCarbsTargetGrams); Assert.Null(saved.DailyProteinTargetGrams);
    }

    [PostgresFact]
    public async Task AllNullFirstPatchAndClearingEveryTargetAreValidAndNeverBecomeZero()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); using var client = await Client(factory, await Seed(factory));
        var empty = Fields.ToDictionary(x => x.Name, _ => (object?)null);
        var first = await Patch(client, empty);
        foreach (var field in Fields) Assert.Equal(JsonValueKind.Null, first.GetProperty(field.Name).ValueKind);
        await Patch(client, Fields.ToDictionary(x => x.Name, x => (object?)x.Maximum));
        var cleared = await Patch(client, empty); Assert.Equal(first.GetRawText(), cleared.GetRawText());
        await using var db = factory.Database(); Assert.Single(await db.PersonalNutritionTargets.ToListAsync());
    }

    [PostgresFact]
    public async Task OwnershipIsAlwaysServerResolvedAndNoInputOrAlternatePathCanSelectAnotherClient()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var actor = await Seed(factory);
        using var owner = await Client(factory, actor); using var other = await Client(factory, await Seed(factory));
        var original = await Patch(owner, new { dailyWaterTargetMl = 2345.625m });
        Assert.Equal(JsonValueKind.Null, (await other.GetFromJsonAsync<JsonElement>(Root)).GetProperty("dailyWaterTargetMl").ValueKind);
        await Patch(other, new { dailyWaterTargetMl = 1111 });
        foreach (var extra in new[] { new { clientId = (Guid?)actor.ProfileId, dailyWaterTargetMl = 999 }, new { clientId = (Guid?)null, dailyWaterTargetMl = 999 } })
        { using var response = await other.PatchAsJsonAsync(Root, extra); await Error(response, 400); }
        using var readQuery = await other.GetAsync($"{Root}?clientId={actor.ProfileId}"); await Error(readQuery, 400);
        using var writeQuery = await other.PatchAsJsonAsync($"{Root}?clientId={actor.ProfileId}", new { dailyWaterTargetMl = 999 }); await Error(writeQuery, 400);
        using var arbitraryId = await other.GetAsync($"{Root}/{actor.ProfileId}"); await Error(arbitraryId, 404);
        Assert.Equal(original.GetRawText(), (await owner.GetFromJsonAsync<JsonElement>(Root)).GetRawText());
        await using var db = factory.Database(); Assert.Equal(2, await db.PersonalNutritionTargets.CountAsync());
    }

    [PostgresFact]
    public async Task BothEndpointsRequireCurrentJwtAndClientContextIncludingDualProfileAccounts()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var actor = await Seed(factory);
        using var client = await Client(factory, actor); using var anonymous = factory.Client(false);
        using var get = await anonymous.GetAsync(Root); await Error(get, 401);
        using var patch = await anonymous.PatchAsJsonAsync(Root, new { dailyWaterTargetMl = 2000 }); await Error(patch, 401);
        anonymous.DefaultRequestHeaders.Authorization = new("Bearer", "invalid-token");
        using var invalid = await anonymous.GetAsync(Root); await Error(invalid, 401);
        using var expert = await Client(factory, await Seed(factory, expert: true));
        using var expertRead = await expert.GetAsync(Root); await Error(expertRead, 403);
        using var expertWrite = await expert.PatchAsJsonAsync(Root, new { dailyWaterTargetMl = 2000 }); await Error(expertWrite, 403);
        client.DefaultRequestHeaders.Remove("X-Profile-Context");
        AssertShape(await client.GetFromJsonAsync<JsonElement>(Root)); // Existing headerless client context is preserved.
        client.DefaultRequestHeaders.Add("X-Profile-Context", "invalid");
        using var malformed = await client.GetAsync(Root); await Error(malformed, 400);
        client.DefaultRequestHeaders.Remove("X-Profile-Context"); client.DefaultRequestHeaders.Add("X-Profile-Context", new[] { "client", "dietitian" });
        using var multiple = await client.GetAsync(Root); await Error(multiple, 400);
        await using (var db = factory.Database())
        {
            var user = await db.Users.SingleAsync(x => x.Id == actor.UserId);
            var profile = new DietitianProfile(user, "Synthetic target dual profile", "Synthetic license");
            db.DietitianProfiles.Add(profile); db.Entry(profile).Property(x => x.IsVerified).CurrentValue = true; await db.SaveChangesAsync();
        }
        client.DefaultRequestHeaders.Remove("X-Profile-Context"); client.DefaultRequestHeaders.Add("X-Profile-Context", "dietitian");
        using var wrongRead = await client.GetAsync(Root); await Error(wrongRead, 403);
        using var wrongWrite = await client.PatchAsJsonAsync(Root, new { dailyWaterTargetMl = 2000 }); await Error(wrongWrite, 403);
        client.DefaultRequestHeaders.Remove("X-Profile-Context"); client.DefaultRequestHeaders.Add("X-Profile-Context", "client");
        await Patch(client, new { dailyWaterTargetMl = 2000 });
        await using (var db = factory.Database())
        { var user = await db.Users.SingleAsync(x => x.Id == actor.UserId); db.Entry(user).Property(x => x.CredentialsVersion).CurrentValue++; await db.SaveChangesAsync(); }
        using var revokedRead = await client.GetAsync(Root); await Error(revokedRead, 401);
        using var revokedWrite = await client.PatchAsJsonAsync(Root, new { dailyWaterTargetMl = 2100 }); await Error(revokedWrite, 401);
    }

    [PostgresFact]
    public async Task ValidWebSessionAloneDoesNotAuthorizeThePersonalTargetResource()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(webSessions: true); var actor = await Seed(factory);
        using var cookie = factory.Client(); cookie.DefaultRequestHeaders.Add("Origin", "https://localhost");
        var csrf = await cookie.GetFromJsonAsync<JsonElement>("/api/v1/auth/csrf"); cookie.DefaultRequestHeaders.Add("X-CSRF-TOKEN", csrf.GetProperty("requestToken").GetString());
        await using (var db = factory.Database())
        {
            var user = await db.Users.SingleAsync(x => x.Id == actor.UserId);
            // Web sessions now require an expert profile; personal-target endpoints remain bearer-only.
            var profile = new DietitianProfile(user, "Synthetic target web expert", "Synthetic license");
            db.DietitianProfiles.Add(profile); db.Entry(profile).Property(x => x.IsVerified).CurrentValue = true;
            await db.SaveChangesAsync();
            using var login = await cookie.PostAsJsonAsync("/api/v1/auth/web-session", new { email = user.Email, password = Password }); Assert.Equal(HttpStatusCode.OK, login.StatusCode);
        }
        using var read = await cookie.GetAsync(Root); await Error(read, 401);
        using var write = await cookie.PatchAsJsonAsync(Root, new { dailyWaterTargetMl = 2000 }); await Error(write, 401);
    }

    [PostgresFact]
    public async Task EveryFieldRejectsZeroNegativeOverLimitAndWrongTypesWithoutCreatingAnyRow()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); using var client = await Client(factory, await Seed(factory));
        foreach (var field in Fields)
        {
            foreach (var value in new[] { 0m, -1m, field.Maximum + 0.001m })
            { using var invalid = await client.PatchAsJsonAsync(Root, new Dictionary<string, object?> { [field.Name] = value }); await Error(invalid, 422); }
            foreach (var value in new object[] { "100", true, new[] { 100 }, new { value = 100 } })
            { using var invalid = await client.PatchAsJsonAsync(Root, new Dictionary<string, object?> { [field.Name] = value }); await Error(invalid, 400); }
        }
        foreach (var raw in new[] { "{}", "null", "[]", "{", "{\"dailyWaterTargetMl\":1e100}", "{\"dailyWaterTargetMl\":NaN}", "{\"source\":\"assigned\"}", "{\"unknown\":null}" })
        { using var response = await client.PatchAsync(Root, new StringContent(raw, Encoding.UTF8, "application/json")); await Error(response, 400); }
        using var emptyJson = await client.PatchAsync(Root, new StringContent("", Encoding.UTF8, "application/json")); await Error(emptyJson, 400);
        using var absent = await client.PatchAsync(Root, null); await Error(absent, 415);
        using var text = await client.PatchAsync(Root, new StringContent("{}")); await Error(text, 415);
        using var readBody = await client.SendAsync(new HttpRequestMessage(HttpMethod.Get, Root) { Content = JsonContent.Create(new { }) }); await Error(readBody, 400);
        await using var db = factory.Database(); Assert.Empty(await db.PersonalNutritionTargets.ToListAsync());
    }

    [PostgresFact]
    public async Task ConcurrentFirstPartialUpdatesPreserveBothIndependentFieldsAndProduceOneRow()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var actor = await Seed(factory);
        using var one = await Client(factory, actor); using var two = await Client(factory, actor);
        var requests = await Task.WhenAll(one.PatchAsJsonAsync(Root, new { dailyProteinTargetGrams = 123.5m }),
            two.PatchAsJsonAsync(Root, new { dailyWaterTargetMl = 2345.75m }));
        foreach (var response in requests) { using (response) Assert.Equal(HttpStatusCode.OK, response.StatusCode); }
        var result = await one.GetFromJsonAsync<JsonElement>(Root);
        Assert.Equal(123.5m, result.GetProperty("dailyProteinTargetGrams").GetDecimal()); Assert.Equal(2345.75m, result.GetProperty("dailyWaterTargetMl").GetDecimal());
        await using var db = factory.Database(); Assert.Single(await db.PersonalNutritionTargets.ToListAsync());
    }

    [PostgresFact]
    public async Task DatabaseEnforcesBoundsFiniteNumbersUniqueOwnerAndRestrictForeignKey()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var actor = await Seed(factory); using var client = await Client(factory, actor);
        var maximums = await Patch(client, Fields.ToDictionary(x => x.Name, x => (object?)x.Maximum));
        foreach (var field in Fields) Assert.Equal(field.Maximum, maximums.GetProperty(field.Name).GetDecimal());
        await using var db = factory.Database();
        await db.Database.OpenConnectionAsync();
        foreach (var field in Fields)
            foreach (var invalid in new[] { "0", "-1", "'NaN'::numeric", "'Infinity'::numeric", "'-Infinity'::numeric", (field.Maximum + 1).ToString(System.Globalization.CultureInfo.InvariantCulture) })
            {
                // Identifiers and malformed numeric SQL literals come only from the fixed test cases above.
                await using var command = db.Database.GetDbConnection().CreateCommand();
                command.CommandText = $"UPDATE personal_nutrition_targets SET {field.Column} = {invalid}";
                var error = await Assert.ThrowsAsync<PostgresException>(() => command.ExecuteNonQueryAsync());
                Assert.Equal(PostgresErrorCodes.CheckViolation, error.SqlState);
            }
        var duplicate = await Assert.ThrowsAsync<PostgresException>(() => db.Database.ExecuteSqlRawAsync("INSERT INTO personal_nutrition_targets SELECT * FROM personal_nutrition_targets")); Assert.Equal(PostgresErrorCodes.UniqueViolation, duplicate.SqlState);
        var foreign = await Assert.ThrowsAsync<PostgresException>(() => db.Database.ExecuteSqlInterpolatedAsync($"UPDATE personal_nutrition_targets SET client_id = {Guid.NewGuid()}")); Assert.Equal(PostgresErrorCodes.ForeignKeyViolation, foreign.SqlState);
        var restricted = await Assert.ThrowsAsync<PostgresException>(() => db.Database.ExecuteSqlInterpolatedAsync($"DELETE FROM client_profiles WHERE id = {actor.ProfileId}")); Assert.Equal(PostgresErrorCodes.ForeignKeyViolation, restricted.SqlState);
    }

    [PostgresFact]
    public async Task FailedCreateOrUpdateRollsBackAndValuesAreNotLogged()
    {
        var failure = new TargetWriteFailure(); await using var factory = await RegistrationApiFactory.CreateAsync(interceptor: failure);
        using var client = await Client(factory, await Seed(factory)); failure.Armed = true;
        using var createFailure = await client.PatchAsJsonAsync(Root, new { dailyWaterTargetMl = 2345.625m }); await Error(createFailure, 500);
        Assert.Equal(JsonValueKind.Null, (await client.GetFromJsonAsync<JsonElement>(Root)).GetProperty("dailyWaterTargetMl").ValueKind);
        failure.Armed = false; var initial = await Patch(client, new { dailyWaterTargetMl = 2345.625m }); failure.Armed = true;
        using var updateFailure = await client.PatchAsJsonAsync(Root, new { dailyWaterTargetMl = 3456.875m }); await Error(updateFailure, 500);
        failure.Armed = false; Assert.Equal(initial.GetRawText(), (await client.GetFromJsonAsync<JsonElement>(Root)).GetRawText());
        Assert.DoesNotContain("2345.625", factory.Logs); Assert.DoesNotContain("3456.875", factory.Logs);
    }

    [PostgresFact]
    public async Task PersonalSettingsNeverReviseAssignedProgramOrItsSnapshotsOrConsumption()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var actor = await Seed(factory); var expert = await Seed(factory, expert: true);
        using var client = await Client(factory, actor); using var dietitian = await Client(factory, expert);
        await Assign(client, dietitian, actor.ProfileId, expert.ProfileId);
        var before = await client.GetFromJsonAsync<JsonElement>("/api/v1/nutrition-plans/active");
        var targets = await Patch(client, new { dailyCaloriesTargetKcal = 1700, dailyWaterTargetMl = 1800, dailyProteinTargetGrams = 80 });
        Assert.Equal("personal", targets.GetProperty("source").GetString()); Assert.Equal(1700, targets.GetProperty("dailyCaloriesTargetKcal").GetInt32());
        Assert.Equal(before.GetRawText(), (await client.GetFromJsonAsync<JsonElement>("/api/v1/nutrition-plans/active")).GetRawText());
        Assert.Equal(2400, before.GetProperty("dailyCaloriesTargetKcal").GetInt32());
        using var denied = await client.PatchAsJsonAsync("/api/v1/nutrition-plans/" + before.GetProperty("id").GetGuid(), new { dailyCaloriesTargetKcal = 1700 }); await Error(denied, 403);
        await using var db = factory.Database(); Assert.Single(await db.NutritionPlanVersions.ToListAsync());
        Assert.Empty(await db.MealLogs.ToListAsync()); Assert.Empty(await db.WaterLogs.ToListAsync());
    }

    [PostgresFact]
    public async Task MigrationPreservesAllExistingRowsSupportsEmptyRollbackAndBlocksPopulatedRollback()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(mealLogSharing: true); var actor = await Seed(factory); var expert = await Seed(factory, expert: true);
        using var client = await Client(factory, actor); using var dietitian = await Client(factory, expert);
        await Assign(client, dietitian, actor.ProfileId, expert.ProfileId);
        using var meal = await client.PostAsJsonAsync("/api/v1/meal-logs", new { mealType = "lunch", consumedAt = "2026-11-19T12:00:00Z", source = "manual", items = new[] { new { displayName = "Synthetic preserved target meal", isEstimated = true } } }); Assert.Equal(HttpStatusCode.Created, meal.StatusCode);
        using var water = await client.PostAsJsonAsync("/api/v1/water-logs", new { amountMl = 250.125m, consumedAt = "2026-11-19T12:00:00Z", source = "manual" }); Assert.Equal(HttpStatusCode.Created, water.StatusCode);
        await using var db = factory.Database(); var migrator = db.GetService<IMigrator>();
        var before = await ExistingRows(db);
        await migrator.MigrateAsync(PreviousMigration); Assert.Equal(before, await ExistingRows(db));
        await migrator.MigrateAsync(); Assert.Equal(before, await ExistingRows(db)); Assert.False(db.Database.HasPendingModelChanges());
        Assert.Empty(await db.PersonalNutritionTargets.ToListAsync());
        await Patch(client, new { dailyWaterTargetMl = (decimal?)null });
        var rollback = await Assert.ThrowsAsync<PostgresException>(() => migrator.MigrateAsync(PreviousMigration)); Assert.Equal(PostgresErrorCodes.RaiseException, rollback.SqlState);
        Assert.Equal(before, await ExistingRows(db)); Assert.Single(await db.PersonalNutritionTargets.ToListAsync());
        Assert.EndsWith("AddPersonalNutritionTargets", (await db.Database.GetAppliedMigrationsAsync()).Last());
    }

    private static async Task Assign(HttpClient client, HttpClient expert, Guid clientId, Guid expertId)
    {
        expert.DefaultRequestHeaders.Remove("X-Profile-Context"); expert.DefaultRequestHeaders.Add("X-Profile-Context", "dietitian");
        using var relationship = await client.PostAsJsonAsync("/api/v1/dietitian-relationships", new { dietitianId = expertId }); Assert.Equal(HttpStatusCode.Created, relationship.StatusCode);
        var id = (await relationship.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid();
        using var accept = await expert.PostAsync($"/api/v1/dietitian-relationships/{id}/accept", null); Assert.Equal(HttpStatusCode.OK, accept.StatusCode);
        using var permission = await client.PostAsJsonAsync("/api/v1/data-sharing-permissions", new { relationshipId = id, category = "nutrition_plans", isGranted = true }); Assert.Equal(HttpStatusCode.Created, permission.StatusCode);
        using var plan = await expert.PostAsJsonAsync("/api/v1/nutrition-plans", new { clientId, title = "Synthetic assigned target program", startDate = "2026-11-19", dailyCaloriesTargetKcal = 2400, dailyWaterTargetMl = 2500,
            items = new[] { new { mealType = "lunch", description = "Synthetic target recommendation", sortOrder = 0 } } }); Assert.Equal(HttpStatusCode.Created, plan.StatusCode);
        var planId = (await plan.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid();
        using var activated = await expert.PostAsync($"/api/v1/nutrition-plans/{planId}/activate", null); Assert.Equal(HttpStatusCode.OK, activated.StatusCode);
    }
    private static void AssertShape(JsonElement result)
    {
        Assert.Equal(Fields.Select(x => x.Name).Append("source").Order(), result.EnumerateObject().Select(x => x.Name).Order());
        Assert.Equal("personal", result.GetProperty("source").GetString());
    }
    private static async Task<JsonElement> Patch(HttpClient client, object body)
    { using var response = await client.PatchAsJsonAsync(Root, body); Assert.Equal(HttpStatusCode.OK, response.StatusCode); return await response.Content.ReadFromJsonAsync<JsonElement>(); }
    private static async Task<Actor> Seed(RegistrationApiFactory factory, bool expert = false)
    {
        await using var db = factory.Database(); var user = new User(Guid.NewGuid(), Guid.NewGuid().ToString("N") + "@EXAMPLE.TEST", expert ? UserRole.Dietitian : UserRole.Client,
            Password, DateTimeOffset.UtcNow, new PasswordHasher<User>()); Guid profileId;
        if (!expert) profileId = new ClientProfile(Guid.NewGuid(), user, "Synthetic personal target client").Id;
        else { var profile = new DietitianProfile(user, "Synthetic personal target expert", "Synthetic license"); profileId = profile.Id; db.Entry(profile).Property(x => x.IsVerified).CurrentValue = true; }
        db.Users.Add(user); db.Entry(user).Property(x => x.IsEmailVerified).CurrentValue = true; await db.SaveChangesAsync(); return new(user.Id, profileId);
    }
    private static async Task<HttpClient> Client(RegistrationApiFactory factory, Actor actor)
    {
        await using var db = factory.Database(); var jwt = new JwtAccessTokenService(Options.Create(factory.Jwt.Options), TimeProvider.System).Issue(await db.Users.SingleAsync(x => x.Id == actor.UserId));
        var client = factory.Client(false); client.DefaultRequestHeaders.Authorization = new("Bearer", jwt.AccessToken); client.DefaultRequestHeaders.Add("X-Profile-Context", "client"); return client;
    }
    private static async Task Error(HttpResponseMessage response, int status)
    {
        Assert.Equal((HttpStatusCode)status, response.StatusCode); var body = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal(status switch { 400 => "invalid_request", 401 => "unauthenticated", 403 => "forbidden", 404 => "not_found", 415 => "unsupported_media_type", 422 => "validation_failed", _ => "internal_error" }, body.GetProperty("error").GetProperty("code").GetString());
        Assert.False(string.IsNullOrWhiteSpace(body.GetProperty("requestId").GetString()));
    }
    private static async Task<string[]> ExistingRows(SmartNutrition.Api.Data.AppDbContext db)
    {
        var result = new List<string>(); var connection = db.Database.GetDbConnection(); await connection.OpenAsync();
        try
        {
            foreach (var table in new[] { "users", "client_profiles", "dietitian_profiles", "dietitian_client_relationships", "data_sharing_permissions", "nutrition_plans", "nutrition_plan_versions", "meal_logs", "meal_log_items", "water_logs", "auth_sessions", "refresh_tokens", "audit_events" })
            {
                await using var command = connection.CreateCommand();
                command.CommandText = $"SELECT count(*)::text || ':' || md5(coalesce(jsonb_agg(to_jsonb(t) ORDER BY id)::text, '[]')) FROM {table} t";
                result.Add((string)(await command.ExecuteScalarAsync())!);
            }
        }
        finally { await connection.CloseAsync(); }
        return result.ToArray();
    }
    private sealed class TargetWriteFailure : DbCommandInterceptor
    {
        internal bool Armed { get; set; }
        public override ValueTask<InterceptionResult<DbDataReader>> ReaderExecutingAsync(DbCommand command, CommandEventData eventData, InterceptionResult<DbDataReader> result, CancellationToken cancellationToken = default)
        {
            if (Armed && (command.CommandText.Contains("INSERT INTO personal_nutrition_targets", StringComparison.Ordinal) || command.CommandText.Contains("UPDATE personal_nutrition_targets", StringComparison.Ordinal)))
                throw new InvalidOperationException("Synthetic target storage failure");
            return base.ReaderExecutingAsync(command, eventData, result, cancellationToken);
        }
    }
}
