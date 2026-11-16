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
using SmartNutrition.Api.Features.MealLogs;
using SmartNutrition.Api.Features.NutritionPlans;
using SmartNutrition.Api.Features.Relationships;
using SmartNutrition.Api.Features.WaterLogs;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Tests;

public sealed class WaterLogApiTests
{
    private const string Root = "/api/v1/water-logs";
    private const string Start = "2026-11-19T00:00:00+03:00", End = "2026-11-20T00:00:00+03:00";
    private sealed record Actor(Guid UserId, Guid ProfileId);

    [Fact]
    public void DomainPreservesDecimalAndUtcAndRejectsInvalidRequiredFields()
    {
        var time = DateTimeOffset.Parse("2026-11-19T12:00:00+03:00");
        var row = new WaterLog(Guid.NewGuid(), Guid.NewGuid(), 250.123456789m, time, RecordSource.Manual);
        Assert.Equal(250.123456789m, row.AmountMl); Assert.Equal(TimeSpan.Zero, row.ConsumedAt.Offset); Assert.Equal(time, row.ConsumedAt);
        Assert.Throws<ArgumentException>(() => new WaterLog(Guid.Empty, row.ClientId, 1, time, RecordSource.Manual));
        Assert.Throws<ArgumentException>(() => new WaterLog(row.Id, Guid.Empty, 1, time, RecordSource.Manual));
        Assert.Throws<ArgumentOutOfRangeException>(() => new WaterLog(row.Id, row.ClientId, 0, time, RecordSource.Manual));
        Assert.Throws<ArgumentException>(() => new WaterLog(row.Id, row.ClientId, 1, default, RecordSource.Manual));
        Assert.Throws<ArgumentException>(() => new WaterLog(row.Id, row.ClientId, 1, time, (RecordSource)99));
    }

    [PostgresFact]
    public async Task CreateAndDetailUseServerIdentityAndCanonicalFieldsWithoutDietitianOrTarget()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var actor = await Seed(factory);
        using var client = await Client(factory, actor);
        using var response = await client.PostAsJsonAsync(Root, Body(250.123456789m, "2026-11-19T12:00:00.1234567+03:00"));
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var row = await response.Content.ReadFromJsonAsync<JsonElement>(); var id = row.GetProperty("id").GetGuid();
        Assert.Equal($"{Root}/{id}", response.Headers.Location?.OriginalString); Assert.Contains("no-store", response.Headers.CacheControl!.ToString());
        Assert.Equal(new[] { "amountMl", "clientId", "consumedAt", "id", "source" }, row.EnumerateObject().Select(x => x.Name).Order());
        Assert.Equal(actor.ProfileId, row.GetProperty("clientId").GetGuid()); Assert.NotEqual(actor.UserId, row.GetProperty("clientId").GetGuid());
        Assert.Equal(250.123456789m, row.GetProperty("amountMl").GetDecimal()); Assert.Equal("manual", row.GetProperty("source").GetString());
        Assert.Equal(new DateTimeOffset(2026, 11, 19, 9, 0, 0, TimeSpan.Zero).AddTicks(1234560), row.GetProperty("consumedAt").GetDateTimeOffset());
        var loaded = await client.GetFromJsonAsync<JsonElement>($"{Root}/{id}"); Assert.Equal(row.GetRawText(), loaded.GetRawText());
        await using var db = factory.Database(); Assert.Single(await db.WaterLogs.ToListAsync()); Assert.Empty(await db.NutritionPlans.ToListAsync());
    }

    [PostgresFact]
    public async Task DailyTotalUsesHalfOpenSelectedLocalDayAndExcludesOtherOwners()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync();
        using var client = await Client(factory, await Seed(factory)); using var other = await Client(factory, await Seed(factory));
        await Create(client, 11, "2026-11-18T20:59:59.999999Z");
        await Create(client, 250.5m, "2026-11-18T21:00:00Z");
        await Create(client, 125.25m, "2026-11-19T20:59:59.999999Z");
        await Create(client, 22, "2026-11-19T21:00:00Z"); await Create(other, 999, "2026-11-19T10:00:00Z");
        var total = await client.GetFromJsonAsync<JsonElement>(Daily());
        Assert.Equal(new[] { "from", "to", "totalAmountMl" }, total.EnumerateObject().Select(x => x.Name).Order());
        Assert.Equal(375.75m, total.GetProperty("totalAmountMl").GetDecimal());
        Assert.Equal(DateTimeOffset.Parse("2026-11-18T21:00:00Z"), total.GetProperty("from").GetDateTimeOffset());
        Assert.Equal(TimeSpan.Zero, total.GetProperty("to").GetDateTimeOffset().Offset);
        var filtered = await client.GetFromJsonAsync<JsonElement>($"{Root}?page=1&pageSize=1&from={Uri.EscapeDataString(Start)}&to={Uri.EscapeDataString(End)}");
        Assert.Equal(2, filtered.GetProperty("totalCount").GetInt32()); Assert.Single(filtered.GetProperty("items").EnumerateArray());
        Assert.Equal(125.25m, filtered.GetProperty("items")[0].GetProperty("amountMl").GetDecimal());
        var empty = await client.GetFromJsonAsync<JsonElement>(Daily("2026-11-21T00:00:00Z", "2026-11-22T00:00:00Z"));
        Assert.Equal(0m, empty.GetProperty("totalAmountMl").GetDecimal());
    }

    [PostgresFact]
    public async Task ExplicitBoundaryOffsetsHandleSpring23HoursAndAutumn25Hours()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); using var client = await Client(factory, await Seed(factory));
        await Create(client, 100.25m, "2026-03-08T01:30:00-05:00"); await Create(client, 200.5m, "2026-03-08T03:30:00-04:00");
        await Create(client, 999, "2026-03-09T00:00:00-04:00");
        var spring = await client.GetFromJsonAsync<JsonElement>(Daily("2026-03-08T00:00:00-05:00", "2026-03-09T00:00:00-04:00"));
        Assert.Equal(300.75m, spring.GetProperty("totalAmountMl").GetDecimal());
        Assert.Equal(TimeSpan.FromHours(23), spring.GetProperty("to").GetDateTimeOffset() - spring.GetProperty("from").GetDateTimeOffset());
        await Create(client, 99.25m, "2026-11-01T01:30:00-04:00"); await Create(client, 99.25m, "2026-11-01T01:30:00-05:00");
        var autumn = await client.GetFromJsonAsync<JsonElement>(Daily("2026-11-01T00:00:00-04:00", "2026-11-02T00:00:00-05:00"));
        Assert.Equal(198.5m, autumn.GetProperty("totalAmountMl").GetDecimal());
        Assert.Equal(TimeSpan.FromHours(25), autumn.GetProperty("to").GetDateTimeOffset() - autumn.GetProperty("from").GetDateTimeOffset());
    }

    [PostgresFact]
    public async Task PatchAndSoftDeleteImmediatelyChangeTotalsAndPreserveOtherDaysAndOmittedValues()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); using var client = await Client(factory, await Seed(factory));
        var row = await Create(client, 200); var id = row.GetProperty("id").GetGuid();
        using var patch = await client.PatchAsJsonAsync($"{Root}/{id}", new { amountMl = 310.125m }); Assert.Equal(HttpStatusCode.OK, patch.StatusCode);
        var changed = await patch.Content.ReadFromJsonAsync<JsonElement>(); Assert.Equal(row.GetProperty("consumedAt").GetString(), changed.GetProperty("consumedAt").GetString());
        Assert.Equal(310.125m, (await client.GetFromJsonAsync<JsonElement>(Daily())).GetProperty("totalAmountMl").GetDecimal());
        using var move = await client.PatchAsJsonAsync($"{Root}/{id}", new { consumedAt = "2026-11-20T12:00:00+03:00" }); Assert.Equal(HttpStatusCode.OK, move.StatusCode);
        Assert.Equal(0m, (await client.GetFromJsonAsync<JsonElement>(Daily())).GetProperty("totalAmountMl").GetDecimal());
        Assert.Equal(310.125m, (await move.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("amountMl").GetDecimal());
        var tomorrow = Daily("2026-11-20T00:00:00+03:00", "2026-11-21T00:00:00+03:00");
        Assert.Equal(310.125m, (await client.GetFromJsonAsync<JsonElement>(tomorrow)).GetProperty("totalAmountMl").GetDecimal());
        using var deleted = await client.DeleteAsync($"{Root}/{id}"); Assert.Equal(HttpStatusCode.NoContent, deleted.StatusCode); Assert.Equal("", await deleted.Content.ReadAsStringAsync());
        Assert.Equal(0m, (await client.GetFromJsonAsync<JsonElement>(tomorrow)).GetProperty("totalAmountMl").GetDecimal());
        using var get = await client.GetAsync($"{Root}/{id}"); await Error(get, 404);
        using var repeated = await client.DeleteAsync($"{Root}/{id}"); await Error(repeated, 404);
        using var patchDeleted = await client.PatchAsJsonAsync($"{Root}/{id}", new { amountMl = 10 }); await Error(patchDeleted, 404);
        Assert.Equal(0, (await client.GetFromJsonAsync<JsonElement>($"{Root}?page=1&pageSize=10")).GetProperty("totalCount").GetInt32());
        await using var db = factory.Database(); Assert.Empty(await db.WaterLogs.ToListAsync()); Assert.NotNull((await db.WaterLogs.IgnoreQueryFilters().SingleAsync()).DeletedAt);
    }

    [PostgresFact]
    public async Task OwnershipProtectsDetailPatchDeleteCountAndTotalsAndRejectsClientIdInputs()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); using var owner = await Client(factory, await Seed(factory)); using var other = await Client(factory, await Seed(factory));
        var row = await Create(owner, 777.625m); var id = row.GetProperty("id").GetGuid();
        using var get = await other.GetAsync($"{Root}/{id}"); await Error(get, 404);
        using var patch = await other.PatchAsJsonAsync($"{Root}/{id}", new { amountMl = 1 }); await Error(patch, 404);
        using var delete = await other.DeleteAsync($"{Root}/{id}"); await Error(delete, 404);
        Assert.Equal(0, (await other.GetFromJsonAsync<JsonElement>($"{Root}?page=1&pageSize=10")).GetProperty("totalCount").GetInt32());
        Assert.Equal(0m, (await other.GetFromJsonAsync<JsonElement>(Daily())).GetProperty("totalAmountMl").GetDecimal());
        var spoof = Body(1); spoof["clientId"] = row.GetProperty("clientId").GetGuid(); using var create = await other.PostAsJsonAsync(Root, spoof); await Error(create, 400);
        using var query = await other.GetAsync($"{Root}?page=1&pageSize=10&clientId={row.GetProperty("clientId").GetGuid()}"); await Error(query, 400);
        using var sum = await other.GetAsync(Daily() + "&clientId=" + row.GetProperty("clientId").GetGuid()); await Error(sum, 400);
    }

    [PostgresFact]
    public async Task AllEndpointsRequireJwtAndRespectProfileContextAndCredentialRevocation()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var actor = await Seed(factory); using var client = await Client(factory, actor);
        var id = (await Create(client)).GetProperty("id").GetGuid(); using var anonymous = factory.Client(false);
        foreach (var path in new[] { $"{Root}?page=1&pageSize=10", Daily(), $"{Root}/{id}" })
        { using var response = await anonymous.GetAsync(path); await Error(response, 401); }
        foreach (var method in new[] { HttpMethod.Post, HttpMethod.Patch, HttpMethod.Delete })
        {
            using var request = new HttpRequestMessage(method, method == HttpMethod.Post ? Root : $"{Root}/{id}");
            if (method != HttpMethod.Delete) request.Content = JsonContent.Create(Body(1));
            using var response = await anonymous.SendAsync(request); await Error(response, 401);
        }
        client.DefaultRequestHeaders.Remove("X-Profile-Context"); client.DefaultRequestHeaders.Add("X-Profile-Context", "dietitian");
        using var wrong = await client.GetAsync(Daily()); await Error(wrong, 403);
        client.DefaultRequestHeaders.Remove("X-Profile-Context"); client.DefaultRequestHeaders.Add("X-Profile-Context", "admin");
        using var malformed = await client.GetAsync(Daily()); await Error(malformed, 400);
        client.DefaultRequestHeaders.Remove("X-Profile-Context"); client.DefaultRequestHeaders.Add("X-Profile-Context", "client");
        await using (var db = factory.Database())
        { var user = await db.Users.SingleAsync(x => x.Id == actor.UserId); db.Entry(user).Property(x => x.CredentialsVersion).CurrentValue++; await db.SaveChangesAsync(); }
        using var revoked = await client.GetAsync(Daily()); await Error(revoked, 401);
        using var expert = await Client(factory, await Seed(factory, expert: true)); using var denied = await expert.GetAsync(Daily()); await Error(denied, 403);
    }

    [PostgresFact]
    public async Task VerifiedDualProfileNeedsClientContextAndCookieAloneDoesNotAuthorize()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(webSessions: true); var actor = await Seed(factory);
        await using (var db = factory.Database())
        {
            var user = await db.Users.SingleAsync(x => x.Id == actor.UserId); var profile = new DietitianProfile(user, "Synthetic water expert", "Synthetic license");
            db.DietitianProfiles.Add(profile); db.Entry(profile).Property(x => x.IsVerified).CurrentValue = true; await db.SaveChangesAsync();
        }
        using var client = await Client(factory, actor); await Create(client);
        client.DefaultRequestHeaders.Remove("X-Profile-Context"); client.DefaultRequestHeaders.Add("X-Profile-Context", "dietitian");
        using var denied = await client.GetAsync(Daily()); await Error(denied, 403);
        using var cookie = factory.Client(); cookie.DefaultRequestHeaders.Add("Origin", "https://localhost");
        var csrf = await cookie.GetFromJsonAsync<JsonElement>("/api/v1/auth/csrf"); cookie.DefaultRequestHeaders.Add("X-CSRF-TOKEN", csrf.GetProperty("requestToken").GetString());
        await using (var db = factory.Database())
        { var user = await db.Users.SingleAsync(x => x.Id == actor.UserId); using var login = await cookie.PostAsJsonAsync("/api/v1/auth/web-session", new { email = user.Email, password = "synthetic water test password" }); Assert.Equal(HttpStatusCode.OK, login.StatusCode); }
        using var cookieOnly = await cookie.GetAsync(Daily()); await Error(cookieOnly, 401);
    }

    [PostgresFact]
    public async Task ListOrdersBeforePagingAndTotalDoesNotSumOnlyOnePage()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); using var client = await Client(factory, await Seed(factory));
        var ids = new List<Guid>(); for (var i = 0; i < 12; i++) ids.Add((await Create(client, 10.25m)).GetProperty("id").GetGuid());
        var expected = ids.OrderBy(x => x.ToString("D"), StringComparer.Ordinal).ToArray();
        var first = await client.GetFromJsonAsync<JsonElement>($"{Root}?page=1&pageSize=10"); var second = await client.GetFromJsonAsync<JsonElement>($"{Root}?page=2&pageSize=10");
        Assert.Equal(12, first.GetProperty("totalCount").GetInt32()); Assert.Equal(10, first.GetProperty("items").GetArrayLength());
        Assert.Equal(expected.Take(10), first.GetProperty("items").EnumerateArray().Select(x => x.GetProperty("id").GetGuid()));
        Assert.Equal(expected.Skip(10), second.GetProperty("items").EnumerateArray().Select(x => x.GetProperty("id").GetGuid()));
        Assert.Equal(123m, (await client.GetFromJsonAsync<JsonElement>(Daily())).GetProperty("totalAmountMl").GetDecimal());
        await Create(client, 1, "2026-11-19T13:00:00+03:00");
        var latest = await client.GetFromJsonAsync<JsonElement>($"{Root}?page=1&pageSize=1"); Assert.Equal(1m, latest.GetProperty("items")[0].GetProperty("amountMl").GetDecimal());
    }

    [PostgresFact]
    public async Task InvalidAmountsSourcesShapesAndPatchNullsUseSharedErrorsWithoutPartialWrites()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); using var client = await Client(factory, await Seed(factory));
        foreach (var amount in new[] { 0m, -0.01m }) { using var response = await client.PostAsJsonAsync(Root, Body(amount)); await Error(response, 422); }
        foreach (var field in new[] { "amountMl", "source", "consumedAt" })
        { var body = Body(1); body.Remove(field); using var response = await client.PostAsJsonAsync(Root, body); await Error(response, 400); }
        foreach (var source in new[] { "wearable", "ai_assisted" })
        { var body = Body(1); body["source"] = source; using var response = await client.PostAsJsonAsync(Root, body); await Error(response, 422); }
        foreach (var value in new object?[] { null, "125", "NaN" })
        {
            var body = Body(1); body["amountMl"] = value; using var response = await client.PostAsJsonAsync(Root, body); await Error(response, 400);
        }
        using var raw = await client.PostAsync(Root, new StringContent("{\"amountMl\":NaN}", Encoding.UTF8, "application/json")); await Error(raw, 400);
        using var media = await client.PostAsync(Root, new StringContent("{}")); await Error(media, 415);
        var noOffset = Body(1, "2026-11-19T12:00:00"); using var date = await client.PostAsJsonAsync(Root, noOffset); await Error(date, 400);
        var row = await Create(client); var id = row.GetProperty("id").GetGuid();
        foreach (var field in new[] { "amountMl", "consumedAt" })
        { using var response = await client.PatchAsJsonAsync($"{Root}/{id}", new Dictionary<string, object?> { [field] = null }); await Error(response, 422); }
        foreach (var body in new object[] { new { }, new { source = "manual" }, new { id }, new { amountMl = "100" } })
        { using var response = await client.PatchAsJsonAsync($"{Root}/{id}", body); await Error(response, 400); }
        using var partial = await client.PatchAsJsonAsync($"{Root}/{id}", new { amountMl = -1, consumedAt = "2026-11-20T12:00:00Z" }); await Error(partial, 422);
        Assert.Equal(row.GetRawText(), (await client.GetFromJsonAsync<JsonElement>($"{Root}/{id}")).GetRawText());
    }

    [PostgresFact]
    public async Task InvalidPaginationDayBoundariesQueriesIdsAndBodiesAreRejected()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); using var client = await Client(factory, await Seed(factory));
        foreach (var query in new[] { "", "?page=1", "?page=0&pageSize=10", "?page=1&pageSize=101", "?page=2147483647&pageSize=100", "?page=1&page=2&pageSize=10", "?page=1&pageSize=10&from=", "?page=1&pageSize=10&to=2026-11-19" })
        { using var response = await client.GetAsync(Root + query); await Error(response, 400); }
        foreach (var pair in new[] { (Start, Start), (End, Start), ("2026-11-19T01:00:00+03:00", End), (Start, "2026-11-21T00:00:00+03:00"), ("2026-11-19T00:00:00", End) })
        { using var response = await client.GetAsync(Daily(pair.Item1, pair.Item2)); await Error(response, 400); }
        foreach (var path in new[] { Root + "/daily-total", Root + "/daily-total?from=" + Uri.EscapeDataString(Start), Daily() + "&unexpected=1", Daily() + "&from=" + Uri.EscapeDataString(Start), Root + "/invalid-uuid" })
        { using var response = await client.GetAsync(path); await Error(response, 400); }
        var id = (await Create(client)).GetProperty("id").GetGuid();
        foreach (var method in new[] { HttpMethod.Get, HttpMethod.Delete })
        { using var request = new HttpRequestMessage(method, $"{Root}/{id}") { Content = JsonContent.Create(new { }) }; using var response = await client.SendAsync(request); await Error(response, 400); }
    }

    [PostgresFact]
    public async Task DatabaseConstraintsAndUnrepresentableTotalFailWithoutSilentRounding()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); using var client = await Client(factory, await Seed(factory));
        var id = (await Create(client, decimal.MaxValue)).GetProperty("id").GetGuid(); await Create(client, decimal.MaxValue);
        using var overflow = await client.GetAsync(Daily()); await Error(overflow, 422);
        await using var db = factory.Database();
        foreach (var sql in new[] { "UPDATE water_logs SET amount_ml = 0", "UPDATE water_logs SET amount_ml = 'NaN'::numeric", "UPDATE water_logs SET amount_ml = 'Infinity'::numeric", "UPDATE water_logs SET source = 'unknown'" })
        { var error = await Assert.ThrowsAsync<PostgresException>(() => db.Database.ExecuteSqlRawAsync(sql)); Assert.Equal(PostgresErrorCodes.CheckViolation, error.SqlState); }
        var foreign = await Assert.ThrowsAsync<PostgresException>(() => db.Database.ExecuteSqlInterpolatedAsync($"UPDATE water_logs SET client_id = {Guid.NewGuid()} WHERE id = {id}")); Assert.Equal(PostgresErrorCodes.ForeignKeyViolation, foreign.SqlState);
    }

    [PostgresFact]
    public async Task FailedWriteRollsBackValuesAndDailyTotal()
    {
        var failure = new WaterWriteFailure(); await using var factory = await RegistrationApiFactory.CreateAsync(interceptor: failure);
        using var client = await Client(factory, await Seed(factory)); var row = await Create(client, 731.625m); var id = row.GetProperty("id").GetGuid();
        failure.Armed = true; using var response = await client.PatchAsJsonAsync($"{Root}/{id}", new { amountMl = 999.125m }); await Error(response, 500);
        failure.Armed = false; Assert.Equal(row.GetRawText(), (await client.GetFromJsonAsync<JsonElement>($"{Root}/{id}")).GetRawText());
        Assert.Equal(731.625m, (await client.GetFromJsonAsync<JsonElement>(Daily())).GetProperty("totalAmountMl").GetDecimal());
        Assert.DoesNotContain("731.625", factory.Logs); Assert.DoesNotContain("999.125", factory.Logs);
    }

    [PostgresFact]
    public async Task ConcurrentPatchAndDeleteNeverResurrectsADeletedWaterRecord()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var actor = await Seed(factory); using var client = await Client(factory, actor); using var other = await Client(factory, actor);
        var id = (await Create(client)).GetProperty("id").GetGuid();
        var patch = client.PatchAsJsonAsync($"{Root}/{id}", new { amountMl = 900 }); var delete = other.DeleteAsync($"{Root}/{id}"); await Task.WhenAll(patch, delete);
        using var patched = await patch; using var deleted = await delete; Assert.Contains(patched.StatusCode, new[] { HttpStatusCode.OK, HttpStatusCode.NotFound }); Assert.Equal(HttpStatusCode.NoContent, deleted.StatusCode);
        Assert.Equal(0m, (await client.GetFromJsonAsync<JsonElement>(Daily())).GetProperty("totalAmountMl").GetDecimal());
    }

    [PostgresFact]
    public async Task MigrationPreservesExistingAuthMealPlanAndSharingRowsAndBlocksDestructiveRollback()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(mealLogSharing: true);
        var actor = await Seed(factory); var expert = await Seed(factory, expert: true);
        using var client = await Client(factory, actor); using var specialist = await Client(factory, expert);
        specialist.DefaultRequestHeaders.Remove("X-Profile-Context"); specialist.DefaultRequestHeaders.Add("X-Profile-Context", "dietitian");
        using var relation = await client.PostAsJsonAsync("/api/v1/dietitian-relationships", new { dietitianId = expert.ProfileId }); Assert.Equal(HttpStatusCode.Created, relation.StatusCode);
        var relationshipId = (await relation.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid();
        using var accepted = await specialist.PostAsync($"/api/v1/dietitian-relationships/{relationshipId}/accept", null); Assert.Equal(HttpStatusCode.OK, accepted.StatusCode);
        foreach (var category in new[] { "nutrition_plans", "meal_logs" })
        { using var permission = await client.PostAsJsonAsync("/api/v1/data-sharing-permissions", new { relationshipId, category, isGranted = true }); Assert.Equal(HttpStatusCode.Created, permission.StatusCode); }
        using var plan = await client.PostAsJsonAsync("/api/v1/nutrition-plans", new { title = "Synthetic preserved water test program", startDate = "2026-11-19", items = new[] { new { mealType = "lunch", description = "Synthetic recommendation", sortOrder = 0 } } }); Assert.Equal(HttpStatusCode.Created, plan.StatusCode);
        using var meal = await client.PostAsJsonAsync("/api/v1/meal-logs", new { mealType = "lunch", consumedAt = "2026-11-19T12:00:00Z", source = "manual", items = new[] { new { displayName = "Synthetic preserved meal", isEstimated = true } } }); Assert.Equal(HttpStatusCode.Created, meal.StatusCode);
        await using var db = factory.Database(); var migrator = db.GetService<IMigrator>();
        await migrator.MigrateAsync("20261116065951_AddMealLogs");
        var before = await ExistingRows(db); await migrator.MigrateAsync(); Assert.Equal(before, await ExistingRows(db));
        Assert.False(db.Database.HasPendingModelChanges());
        var water = await Create(client); var id = water.GetProperty("id").GetGuid(); using var removed = await client.DeleteAsync($"{Root}/{id}"); Assert.Equal(HttpStatusCode.NoContent, removed.StatusCode);
        var rollback = await Assert.ThrowsAsync<PostgresException>(() => migrator.MigrateAsync("20261116065951_AddMealLogs")); Assert.Equal(PostgresErrorCodes.RaiseException, rollback.SqlState);
        Assert.Equal(before, await ExistingRows(db)); Assert.Single(await db.WaterLogs.IgnoreQueryFilters().ToListAsync());
    }

    private static async Task<string[]> ExistingRows(SmartNutrition.Api.Data.AppDbContext db)
    {
        var result = new List<string>(); var connection = db.Database.GetDbConnection(); await connection.OpenAsync();
        try
        {
            foreach (var table in new[] { "users", "client_profiles", "dietitian_profiles", "dietitian_client_relationships", "data_sharing_permissions", "nutrition_plans", "nutrition_plan_versions", "meal_logs", "meal_log_items", "auth_sessions", "refresh_tokens", "audit_events" })
            {
                await using var command = connection.CreateCommand();
                command.CommandText = $"SELECT count(*)::text || ':' || md5(coalesce(jsonb_agg(to_jsonb(t) ORDER BY id)::text, '[]')) FROM {table} t";
                result.Add((string)(await command.ExecuteScalarAsync())!);
            }
        }
        finally { await connection.CloseAsync(); }
        return result.ToArray();
    }

    private static Dictionary<string, object?> Body(decimal amount, string consumedAt = "2026-11-19T12:00:00+03:00") => new() { ["amountMl"] = amount, ["consumedAt"] = consumedAt, ["source"] = "manual" };
    private static string Daily(string from = Start, string to = End) => $"{Root}/daily-total?from={Uri.EscapeDataString(from)}&to={Uri.EscapeDataString(to)}";
    private static async Task<JsonElement> Create(HttpClient client, decimal amount = 250, string consumedAt = "2026-11-19T12:00:00+03:00")
    { using var response = await client.PostAsJsonAsync(Root, Body(amount, consumedAt)); Assert.Equal(HttpStatusCode.Created, response.StatusCode); return await response.Content.ReadFromJsonAsync<JsonElement>(); }
    private static async Task<Actor> Seed(RegistrationApiFactory factory, bool expert = false)
    {
        await using var db = factory.Database(); var user = new User(Guid.NewGuid(), Guid.NewGuid().ToString("N") + "@EXAMPLE.TEST", expert ? UserRole.Dietitian : UserRole.Client,
            "synthetic water test password", DateTimeOffset.UtcNow, new PasswordHasher<User>()); Guid profileId;
        if (!expert) profileId = new ClientProfile(Guid.NewGuid(), user, "Synthetic water client").Id;
        else { var profile = new DietitianProfile(user, "Synthetic water expert", "Synthetic license"); profileId = profile.Id; db.Entry(profile).Property(x => x.IsVerified).CurrentValue = true; }
        db.Users.Add(user); db.Entry(user).Property(x => x.IsEmailVerified).CurrentValue = true; await db.SaveChangesAsync(); return new(user.Id, profileId);
    }
    private static async Task<HttpClient> Client(RegistrationApiFactory factory, Actor actor)
    {
        await using var db = factory.Database(); var jwt = new JwtAccessTokenService(Options.Create(factory.Jwt.Options), TimeProvider.System).Issue(await db.Users.SingleAsync(x => x.Id == actor.UserId));
        var client = factory.Client(false); client.DefaultRequestHeaders.Authorization = new("Bearer", jwt.AccessToken); client.DefaultRequestHeaders.Add("X-Profile-Context", "client"); return client;
    }
    private static async Task Error(HttpResponseMessage response, int status)
    {
        Assert.Equal((HttpStatusCode)status, response.StatusCode); var body = JsonSerializer.Deserialize<JsonElement>(await response.Content.ReadAsStringAsync());
        Assert.Equal(status switch { 400 => "invalid_request", 401 => "unauthenticated", 403 => "forbidden", 404 => "not_found", 415 => "unsupported_media_type", 422 => "validation_failed", _ => "internal_error" }, body.GetProperty("error").GetProperty("code").GetString());
        Assert.False(string.IsNullOrWhiteSpace(body.GetProperty("requestId").GetString()));
    }
    private sealed class WaterWriteFailure : DbCommandInterceptor
    {
        internal bool Armed { get; set; }
        public override ValueTask<InterceptionResult<DbDataReader>> ReaderExecutingAsync(DbCommand command, CommandEventData eventData, InterceptionResult<DbDataReader> result, CancellationToken cancellationToken = default)
        {
            if (Armed && command.CommandText.Contains("UPDATE water_logs", StringComparison.Ordinal)) throw new InvalidOperationException("Synthetic water storage failure");
            return base.ReaderExecutingAsync(command, eventData, result, cancellationToken);
        }
    }
}
