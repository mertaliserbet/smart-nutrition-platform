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
using Microsoft.Extensions.Options;
using Npgsql;
using SmartNutrition.Api.Data.Migrations;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Features.BodyMeasurements;
using SmartNutrition.Api.Features.Dietitians;
using SmartNutrition.Api.Features.Relationships;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Tests;

public sealed class BodyMeasurementApiTests
{
    private const string Root = "/api/v1/body-measurements";
    private const string Time = "2026-11-18T12:00:00+03:00";
    private const string PrivateNote = "Synthetic private body measurement note";
    private sealed record Actor(Guid UserId, Guid ProfileId);

    [Fact]
    public void MigrationOnlyAddsMeasurementTableAndIndexAndGuardsRollback()
    {
        var migration = new AddBodyMeasurements();
        Assert.Equal(2, migration.UpOperations.Count);
        var table = Assert.IsType<CreateTableOperation>(migration.UpOperations[0]); Assert.Equal("body_measurements", table.Name);
        var foreignKey = Assert.Single(table.ForeignKeys); Assert.Equal("client_profiles", foreignKey.PrincipalTable); Assert.Equal(ReferentialAction.Restrict, foreignKey.OnDelete);
        Assert.IsType<CreateIndexOperation>(migration.UpOperations[1]);
        Assert.Contains("IF EXISTS", Assert.IsType<SqlOperation>(migration.DownOperations[0]).Sql);
    }

    [Fact]
    public void DomainKeepsDecimalsAndUtcAndRejectsInvalidIdentityTimeAndEmptyMeasurements()
    {
        var at = DateTimeOffset.Parse(Time);
        var row = new BodyMeasurement(Guid.NewGuid(), Guid.NewGuid(), at, RecordSource.Manual, weightKg: 73.123456789m);
        Assert.Equal(73.123456789m, row.WeightKg); Assert.Null(row.WaistCm); Assert.Equal(TimeSpan.Zero, row.MeasuredAt.Offset);
        Assert.Equal(at, row.MeasuredAt);
        Assert.Throws<ArgumentException>(() => new BodyMeasurement(Guid.Empty, row.ClientId, at, RecordSource.Manual, weightKg: 73));
        Assert.Throws<ArgumentException>(() => new BodyMeasurement(row.Id, Guid.Empty, at, RecordSource.Manual, weightKg: 73));
        Assert.Throws<ArgumentException>(() => new BodyMeasurement(row.Id, row.ClientId, default, RecordSource.Manual, weightKg: 73));
        Assert.Throws<ArgumentException>(() => new BodyMeasurement(row.Id, row.ClientId, at, (RecordSource)99, weightKg: 73));
        Assert.Throws<ArgumentException>(() => new BodyMeasurement(row.Id, row.ClientId, at, RecordSource.Manual));
    }

    [PostgresFact]
    public async Task CreateAndDetailUseJwtProfileAndPreserveNullsDecimalsAndUtc()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var actor = await Seed(factory); using var client = await Client(factory, actor);
        var body = Body(); body["measuredAt"] = "2026-11-18T12:00:00.1234567+03:00";
        body["waistCm"] = 83.125m; body["hipCm"] = 98.5m; body["chestCm"] = 90.75m;
        using var response = await client.PostAsJsonAsync(Root, body); Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var row = await response.Content.ReadFromJsonAsync<JsonElement>(); var id = row.GetProperty("id").GetGuid();
        Assert.Equal($"{Root}/{id}", response.Headers.Location?.OriginalString); Assert.Contains("no-store", response.Headers.CacheControl!.ToString());
        Assert.Equal(new[] { "bodyFatPercent", "chestCm", "clientId", "hipCm", "id", "measuredAt", "note", "source", "waistCm", "weightKg" }, row.EnumerateObject().Select(x => x.Name).Order());
        Assert.Equal(actor.ProfileId, row.GetProperty("clientId").GetGuid()); Assert.NotEqual(actor.UserId, actor.ProfileId);
        Assert.Equal(73.123456789m, row.GetProperty("weightKg").GetDecimal()); Assert.Equal(98.5m, row.GetProperty("hipCm").GetDecimal());
        Assert.Equal(90.75m, row.GetProperty("chestCm").GetDecimal()); Assert.Equal(83.125m, row.GetProperty("waistCm").GetDecimal());
        Assert.Equal(JsonValueKind.Null, row.GetProperty("bodyFatPercent").ValueKind); Assert.Equal("manual", row.GetProperty("source").GetString());
        Assert.Equal(new DateTimeOffset(2026, 11, 18, 9, 0, 0, TimeSpan.Zero).AddTicks(1234560), row.GetProperty("measuredAt").GetDateTimeOffset());
        Assert.Equal(row.GetRawText(), (await client.GetFromJsonAsync<JsonElement>($"{Root}/{id}")).GetRawText());
        Assert.DoesNotContain(PrivateNote, factory.Logs);
    }

    [PostgresFact]
    public async Task EveryMeasurementCanBeProvidedIndependentlyWithoutFakeZeros()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); using var client = await Client(factory, await Seed(factory));
        foreach (var field in new[] { "weightKg", "waistCm", "hipCm", "chestCm", "bodyFatPercent" })
        {
            var body = new Dictionary<string, object?> { ["measuredAt"] = Time, ["source"] = "manual", [field] = 42.125m };
            var row = await Create(client, body);
            foreach (var other in new[] { "weightKg", "waistCm", "hipCm", "chestCm", "bodyFatPercent" })
                if (other == field) Assert.Equal(42.125m, row.GetProperty(other).GetDecimal()); else Assert.Equal(JsonValueKind.Null, row.GetProperty(other).ValueKind);
            Assert.Equal(JsonValueKind.Null, row.GetProperty("note").ValueKind);
        }
    }

    [PostgresFact]
    public async Task PatchPreservesOmittedFieldsClearsNullsAndValidatesFinalStateAtomically()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); using var client = await Client(factory, await Seed(factory));
        var row = await Create(client); var id = row.GetProperty("id").GetGuid();
        using var added = await client.PatchAsJsonAsync($"{Root}/{id}", new { hipCm = 95.125m }); Assert.Equal(HttpStatusCode.OK, added.StatusCode);
        var value = await added.Content.ReadFromJsonAsync<JsonElement>(); Assert.Equal(row.GetProperty("weightKg").GetDecimal(), value.GetProperty("weightKg").GetDecimal());
        Assert.Equal(PrivateNote, value.GetProperty("note").GetString()); Assert.Equal(row.GetProperty("measuredAt").GetString(), value.GetProperty("measuredAt").GetString());
        using var cleared = await client.PatchAsJsonAsync($"{Root}/{id}", new { weightKg = (decimal?)null, note = (string?)null }); Assert.Equal(HttpStatusCode.OK, cleared.StatusCode);
        var final = await cleared.Content.ReadFromJsonAsync<JsonElement>(); Assert.Equal(JsonValueKind.Null, final.GetProperty("weightKg").ValueKind);
        Assert.Equal(JsonValueKind.Null, final.GetProperty("note").ValueKind); Assert.Equal(95.125m, final.GetProperty("hipCm").GetDecimal());
        using var empty = await client.PatchAsJsonAsync($"{Root}/{id}", new { hipCm = (decimal?)null, measuredAt = "2026-11-20T00:00:00Z" }); await Error(empty, 422);
        Assert.Equal(final.GetRawText(), (await client.GetFromJsonAsync<JsonElement>($"{Root}/{id}")).GetRawText());
        using var moved = await client.PatchAsJsonAsync($"{Root}/{id}", new { hipCm = (decimal?)null, chestCm = 91.75m, measuredAt = "2026-11-19T02:00:00+02:00" });
        Assert.Equal(HttpStatusCode.OK, moved.StatusCode); var updated = await moved.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal(DateTimeOffset.Parse("2026-11-19T00:00:00Z"), updated.GetProperty("measuredAt").GetDateTimeOffset());
        Assert.Equal(JsonValueKind.Null, updated.GetProperty("hipCm").ValueKind);
    }

    [PostgresFact]
    public async Task SoftDeleteHidesListDetailPatchAndDeleteButRetainsInternalHistory()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); using var client = await Client(factory, await Seed(factory));
        var id = (await Create(client)).GetProperty("id").GetGuid(); using var deleted = await client.DeleteAsync($"{Root}/{id}");
        Assert.Equal(HttpStatusCode.NoContent, deleted.StatusCode); Assert.Equal("", await deleted.Content.ReadAsStringAsync());
        using var get = await client.GetAsync($"{Root}/{id}"); await Error(get, 404);
        using var patch = await client.PatchAsJsonAsync($"{Root}/{id}", new { weightKg = 75 }); await Error(patch, 404);
        using var repeat = await client.DeleteAsync($"{Root}/{id}"); await Error(repeat, 404);
        var list = await client.GetFromJsonAsync<JsonElement>($"{Root}?page=1&pageSize=10"); Assert.Equal(0, list.GetProperty("totalCount").GetInt32());
        Assert.Empty(list.GetProperty("items").EnumerateArray()); await using var db = factory.Database(); Assert.Empty(await db.BodyMeasurements.ToListAsync());
        Assert.NotNull((await db.BodyMeasurements.IgnoreQueryFilters().SingleAsync()).DeletedAt);
    }

    [PostgresFact]
    public async Task OtherOwnersCannotReadChangeDeleteCountOrSpoofOwnership()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); using var owner = await Client(factory, await Seed(factory));
        using var other = await Client(factory, await Seed(factory)); var row = await Create(owner); var id = row.GetProperty("id").GetGuid();
        using var get = await other.GetAsync($"{Root}/{id}"); await Error(get, 404);
        using var patch = await other.PatchAsJsonAsync($"{Root}/{id}", new { weightKg = 1 }); await Error(patch, 404);
        using var delete = await other.DeleteAsync($"{Root}/{id}"); await Error(delete, 404);
        var list = await other.GetFromJsonAsync<JsonElement>($"{Root}?page=1&pageSize=10"); Assert.Equal(0, list.GetProperty("totalCount").GetInt32());
        var spoof = Body(); spoof["clientId"] = row.GetProperty("clientId").GetGuid(); using var create = await other.PostAsJsonAsync(Root, spoof); await Error(create, 400);
        using var spoofPatch = await other.PatchAsJsonAsync($"{Root}/{id}", new { clientId = row.GetProperty("clientId").GetGuid(), weightKg = 1 }); await Error(spoofPatch, 400);
        using var query = await other.GetAsync($"{Root}?page=1&pageSize=10&clientId={id}"); await Error(query, 400);
        using var missing = await other.GetAsync($"{Root}/{Guid.NewGuid()}"); await Error(missing, 404);
        Assert.Equal(row.GetRawText(), (await owner.GetFromJsonAsync<JsonElement>($"{Root}/{id}")).GetRawText());
    }

    [PostgresFact]
    public async Task AnonymousExpertContextsAndRevokedJwtAreRejectedWhileDualClientStillOwnsItsData()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(webSessions: true); var actor = await Seed(factory); using var owner = await Client(factory, actor);
        var id = (await Create(owner)).GetProperty("id").GetGuid(); using var anonymous = factory.Client(false);
        foreach (var method in new[] { HttpMethod.Get, HttpMethod.Post, HttpMethod.Patch, HttpMethod.Delete })
        {
            using var request = new HttpRequestMessage(method, method == HttpMethod.Post ? Root : $"{Root}/{id}");
            if (method == HttpMethod.Post || method == HttpMethod.Patch) request.Content = JsonContent.Create(Body());
            using var response = await anonymous.SendAsync(request); await Error(response, 401);
        }
        using var anonymousList = await anonymous.GetAsync($"{Root}?page=1&pageSize=10"); await Error(anonymousList, 401);
        owner.DefaultRequestHeaders.Remove("X-Profile-Context"); owner.DefaultRequestHeaders.Add("X-Profile-Context", "dietitian");
        using var wrong = await owner.GetAsync($"{Root}/{id}"); await Error(wrong, 403);
        await using (var db = factory.Database())
        {
            var profile = new DietitianProfile(await db.Users.SingleAsync(x => x.Id == actor.UserId), "Synthetic dual expert", "Synthetic license");
            db.DietitianProfiles.Add(profile); db.Entry(profile).Property(x => x.IsVerified).CurrentValue = true; await db.SaveChangesAsync();
        }
        using var dualExpert = await owner.GetAsync($"{Root}/{id}"); await Error(dualExpert, 403);
        owner.DefaultRequestHeaders.Remove("X-Profile-Context"); owner.DefaultRequestHeaders.Add("X-Profile-Context", "client");
        using var dualClient = await owner.GetAsync($"{Root}/{id}"); Assert.Equal(HttpStatusCode.OK, dualClient.StatusCode);
        using var cookie = factory.Client(); var csrf = await cookie.GetFromJsonAsync<JsonElement>("/api/v1/auth/csrf");
        string email; await using (var db = factory.Database()) email = (await db.Users.SingleAsync(x => x.Id == actor.UserId)).Email;
        using var login = new HttpRequestMessage(HttpMethod.Post, "/api/v1/auth/web-session")
        { Content = JsonContent.Create(new { email, password = "synthetic measurement password" }) };
        login.Headers.Add("Origin", "https://localhost"); login.Headers.Add("X-CSRF-TOKEN", csrf.GetProperty("requestToken").GetString());
        using var signed = await cookie.SendAsync(login); Assert.Equal(HttpStatusCode.OK, signed.StatusCode);
        using var cookieRead = await cookie.GetAsync($"{Root}/{id}"); await Error(cookieRead, 401);
        using var expert = await Client(factory, await Seed(factory, expert: true));
        using var expertRead = await expert.GetAsync($"{Root}?page=1&pageSize=10"); await Error(expertRead, 403);
        using var expertRoute = await expert.GetAsync($"/api/v1/dietitian/clients/{actor.ProfileId}/body-measurements?page=1&pageSize=10"); Assert.Equal(HttpStatusCode.NotFound, expertRoute.StatusCode);
        await using (var db = factory.Database()) await db.Users.Where(x => x.Id == actor.UserId).ExecuteUpdateAsync(x => x.SetProperty(p => p.CredentialsVersion, p => p.CredentialsVersion + 1));
        using var revoked = await owner.GetAsync($"{Root}/{id}"); await Error(revoked, 401);
    }

    [PostgresFact]
    public async Task DateRangeAndPagingHaveStableOrderForHistoryAndGraphs()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); using var client = await Client(factory, await Seed(factory));
        var first = await Create(client, Body("2026-11-17T21:00:00Z"));
        var same = await Create(client, Body("2026-11-18T00:00:00+03:00"));
        var latest = await Create(client, Body("2026-11-18T20:59:59.999999Z"));
        await Create(client, Body("2026-11-18T21:00:00Z")); await Create(client, Body("2026-11-17T20:59:59.999999Z"));
        using var other = await Client(factory, await Seed(factory)); await Create(other);
        var filter = "&from=" + Uri.EscapeDataString("2026-11-18T00:00:00+03:00") + "&to=" + Uri.EscapeDataString("2026-11-19T00:00:00+03:00");
        var ties = new[] { first.GetProperty("id").GetGuid(), same.GetProperty("id").GetGuid() }.Order().ToArray();
        foreach (var order in new[] { "asc", "desc" })
        {
            var ids = new List<Guid>();
            for (var page = 1; page <= 4; page++)
            {
                var result = await client.GetFromJsonAsync<JsonElement>($"{Root}?page={page}&pageSize=1&sortOrder={order}{filter}");
                Assert.Equal(3, result.GetProperty("totalCount").GetInt32()); ids.AddRange(result.GetProperty("items").EnumerateArray().Select(x => x.GetProperty("id").GetGuid()));
            }
            Assert.Equal(order == "asc" ? [ties[0], ties[1], latest.GetProperty("id").GetGuid()] : new[] { latest.GetProperty("id").GetGuid(), ties[0], ties[1] }, ids);
        }
        var unfiltered = await client.GetFromJsonAsync<JsonElement>($"{Root}?page=1&pageSize=100"); Assert.Equal(5, unfiltered.GetProperty("totalCount").GetInt32());
        var dates = unfiltered.GetProperty("items").EnumerateArray().Select(x => x.GetProperty("measuredAt").GetDateTimeOffset()).ToArray(); Assert.Equal(dates.OrderDescending(), dates);
    }

    [PostgresFact]
    public async Task InvalidValuesAndMalformedPatchesDoNotChangeStoredData()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); using var client = await Client(factory, await Seed(factory)); var row = await Create(client); var id = row.GetProperty("id").GetGuid();
        foreach (var field in new[] { "weightKg", "waistCm", "hipCm", "chestCm" })
        foreach (var value in new[] { -1m, 0m })
        { var input = Body(); input[field] = value; using var post = await client.PostAsJsonAsync(Root, input); await Error(post, 422); using var patch = await client.PatchAsJsonAsync($"{Root}/{id}", new Dictionary<string, object?> { [field] = value }); await Error(patch, 422); }
        foreach (var value in new[] { -0.001m, 100.001m })
        { var input = Body(); input["bodyFatPercent"] = value; using var post = await client.PostAsJsonAsync(Root, input); await Error(post, 422); }
        foreach (var note in new[] { new string('a', 2001), "bad\0note" })
        { var input = Body(); input["note"] = note; using var post = await client.PostAsJsonAsync(Root, input); await Error(post, 422); }
        foreach (var source in new[] { "wearable", "ai_assisted" })
        { var input = Body(); input["source"] = source; using var post = await client.PostAsJsonAsync(Root, input); await Error(post, 422); }
        using var empty = await client.PostAsJsonAsync(Root, new { measuredAt = Time, source = "manual", note = "Synthetic note without measurements" }); await Error(empty, 422);
        foreach (var input in new object[] { new { }, new { source = "manual" }, new { id }, new { weightKg = "70" }, new { weightKg = true }, new { measuredAt = "2026-11-18T12:00:00" } })
        { using var patch = await client.PatchAsJsonAsync($"{Root}/{id}", input); await Error(patch, 400); }
        using var nullDate = await client.PatchAsJsonAsync($"{Root}/{id}", new { measuredAt = (string?)null }); await Error(nullDate, 422);
        foreach (var input in new object[] { new { weightKg = 70 }, new { measuredAt = Time, weightKg = 70 }, new { measuredAt = "2026-11-18T12:00:00", source = "manual", weightKg = 70 } })
        { using var post = await client.PostAsJsonAsync(Root, input); await Error(post, 400); }
        Assert.Equal(row.GetRawText(), (await client.GetFromJsonAsync<JsonElement>($"{Root}/{id}")).GetRawText());
        var boundary = Body(); boundary["note"] = string.Concat(Enumerable.Repeat("🌿", 2000)); boundary["bodyFatPercent"] = 0m;
        var valid = await Create(client, boundary); Assert.Equal(0, valid.GetProperty("bodyFatPercent").GetDecimal());
    }

    [PostgresFact]
    public async Task StrictQueriesRejectBadRangesPagingAndUnexpectedBodies()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); using var client = await Client(factory, await Seed(factory));
        foreach (var query in new[] { "", "page=1", "pageSize=10", "page=0&pageSize=10", "page=1&pageSize=0", "page=1&pageSize=101", "page=2147483647&pageSize=100", "page=x&pageSize=10",
            "page=1&pageSize=10&page=2", "page=1&pageSize=10&from=", "page=1&pageSize=10&sortOrder=", "page=1&pageSize=10&sortOrder=random", "page=1&pageSize=10&from=2026-11-18T00:00:00",
            "page=1&pageSize=10&to=bad", "page=1&pageSize=10&from=2026-11-18T00:00:00Z&to=2026-11-18T00:00:00Z", "page=1&pageSize=10&from=2026-11-19T00:00:00Z&to=2026-11-18T00:00:00Z" })
        { using var response = await client.GetAsync($"{Root}?{query}"); await Error(response, 400); }
        using var request = new HttpRequestMessage(HttpMethod.Get, $"{Root}?page=1&pageSize=10") { Content = JsonContent.Create(new { }) };
        using var getBody = await client.SendAsync(request); await Error(getBody, 400);
        var id = (await Create(client)).GetProperty("id").GetGuid();
        using var extraGet = await client.GetAsync($"{Root}/{id}?page=1"); await Error(extraGet, 400);
        using var extraPatch = await client.PatchAsJsonAsync($"{Root}/{id}?extra=true", new { weightKg = 70 }); await Error(extraPatch, 400);
        using var deleteBody = new HttpRequestMessage(HttpMethod.Delete, $"{Root}/{id}") { Content = JsonContent.Create(new { }) };
        using var deleted = await client.SendAsync(deleteBody); await Error(deleted, 400);
    }

    [PostgresFact]
    public async Task ConcurrentPartialUpdatesPreserveBothChangesAndDeleteCannotBeUndone()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var actor = await Seed(factory); using var first = await Client(factory, actor); using var second = await Client(factory, actor);
        var id = (await Create(first)).GetProperty("id").GetGuid();
        var responses = await Task.WhenAll(first.PatchAsJsonAsync($"{Root}/{id}", new { waistCm = 84.5m }), second.PatchAsJsonAsync($"{Root}/{id}", new { hipCm = 95.5m }));
        foreach (var response in responses) { using (response) Assert.Equal(HttpStatusCode.OK, response.StatusCode); }
        var row = await first.GetFromJsonAsync<JsonElement>($"{Root}/{id}"); Assert.Equal(84.5m, row.GetProperty("waistCm").GetDecimal()); Assert.Equal(95.5m, row.GetProperty("hipCm").GetDecimal());
        var competing = await Task.WhenAll(first.PatchAsJsonAsync($"{Root}/{id}", new { chestCm = 90m }), second.DeleteAsync($"{Root}/{id}"));
        using var patched = competing[0]; using var deleted = competing[1]; Assert.Contains(patched.StatusCode, new[] { HttpStatusCode.OK, HttpStatusCode.NotFound }); Assert.Equal(HttpStatusCode.NoContent, deleted.StatusCode);
        using var missing = await first.GetAsync($"{Root}/{id}"); await Error(missing, 404);
    }

    [PostgresFact]
    public async Task DatabaseEnforcesNonemptyPositiveFiniteMeasurementsAndOwnershipForeignKey()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); using var client = await Client(factory, await Seed(factory)); var id = (await Create(client)).GetProperty("id").GetGuid();
        await using var db = factory.Database();
        foreach (var expression in new[] { "NULL", "0", "-1", "'NaN'::numeric", "'Infinity'::numeric", "'-Infinity'::numeric" })
        {
            var sql = "UPDATE body_measurements SET weight_kg=" + expression + " WHERE id={0}";
            var error = await Assert.ThrowsAsync<PostgresException>(() => db.Database.ExecuteSqlRawAsync(sql, id));
            Assert.Equal(PostgresErrorCodes.CheckViolation, error.SqlState);
        }
        var foreign = Guid.NewGuid(); var fk = await Assert.ThrowsAsync<PostgresException>(() => db.Database.ExecuteSqlInterpolatedAsync($"UPDATE body_measurements SET client_id={foreign} WHERE id={id}")); Assert.Equal(PostgresErrorCodes.ForeignKeyViolation, fk.SqlState);
        var value = await db.BodyMeasurements.SingleAsync(); Assert.Equal(73.123456789m, value.WeightKg);
    }

    [PostgresFact]
    public async Task StorageFailureRollsBackPartialUpdateWithoutLoggingHealthValues()
    {
        var failure = new WriteFailure(); await using var factory = await RegistrationApiFactory.CreateAsync(interceptor: failure);
        using var client = await Client(factory, await Seed(factory)); var original = await Create(client); var id = original.GetProperty("id").GetGuid();
        failure.Armed = true; using var response = await client.PatchAsJsonAsync($"{Root}/{id}", new { weightKg = 80.987m, note = "Synthetic failed private note" }); await Error(response, 500);
        failure.Armed = false; Assert.Equal(original.GetRawText(), (await client.GetFromJsonAsync<JsonElement>($"{Root}/{id}")).GetRawText());
        Assert.DoesNotContain(PrivateNote, factory.Logs); Assert.DoesNotContain("Synthetic failed private note", factory.Logs);
    }

    [PostgresFact]
    public async Task MigrationPreservesUsersMealsWaterTargetsAndPlansAndBlocksDataLosingRollback()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); using var client = await Client(factory, await Seed(factory));
        using var meal = await client.PostAsJsonAsync("/api/v1/meal-logs", new { mealType = "lunch", consumedAt = Time, source = "manual", items = new[] { new { displayName = "Synthetic preserved food", isEstimated = true } } }); Assert.Equal(HttpStatusCode.Created, meal.StatusCode);
        using var water = await client.PostAsJsonAsync("/api/v1/water-logs", new { amountMl = 250.125m, consumedAt = Time, source = "manual" }); Assert.Equal(HttpStatusCode.Created, water.StatusCode);
        using var targets = await client.PatchAsJsonAsync("/api/v1/personal-nutrition-targets", new { dailyCaloriesTargetKcal = 1900m, dailyWaterTargetMl = 2100m }); Assert.Equal(HttpStatusCode.OK, targets.StatusCode);
        using var plan = await client.PostAsJsonAsync("/api/v1/nutrition-plans", new { title = "Synthetic preserved body test plan", startDate = "2026-11-18", items = new[] { new { mealType = "lunch", description = "Synthetic recommendation", sortOrder = 0 } } }); Assert.Equal(HttpStatusCode.Created, plan.StatusCode);
        await using var db = factory.Database(); var migrator = db.GetService<IMigrator>();
        await migrator.MigrateAsync("20261116222048_AddPersonalNutritionTargets"); var before = await ExistingRows(db);
        await migrator.MigrateAsync(); Assert.Equal(before, await ExistingRows(db)); Assert.False(db.Database.HasPendingModelChanges());
        await Create(client); var error = await Assert.ThrowsAsync<PostgresException>(() => migrator.MigrateAsync("20261116222048_AddPersonalNutritionTargets"));
        Assert.Equal(PostgresErrorCodes.RaiseException, error.SqlState); Assert.Single(await db.BodyMeasurements.ToListAsync()); Assert.Equal(before, await ExistingRows(db));
    }

    private static async Task<string[]> ExistingRows(SmartNutrition.Api.Data.AppDbContext db)
    {
        var values = new List<string>(); var connection = db.Database.GetDbConnection(); await connection.OpenAsync();
        try
        {
            foreach (var table in new[] { "users", "client_profiles", "dietitian_profiles", "dietitian_client_relationships", "data_sharing_permissions", "meal_logs", "meal_log_items", "water_logs", "personal_nutrition_targets", "nutrition_plans", "nutrition_plan_versions", "auth_sessions", "refresh_tokens", "audit_events" })
            {
                await using var command = connection.CreateCommand(); command.CommandText = $"SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text), '[]'::jsonb)::text FROM {table} t";
                values.Add((string)(await command.ExecuteScalarAsync())!);
            }
        }
        finally { await connection.CloseAsync(); }
        return values.ToArray();
    }
    private static Dictionary<string, object?> Body(string time = Time) => new() { ["measuredAt"] = time, ["source"] = "manual", ["weightKg"] = 73.123456789m, ["note"] = PrivateNote };
    private static async Task<JsonElement> Create(HttpClient client, Dictionary<string, object?>? body = null)
    { using var response = await client.PostAsJsonAsync(Root, body ?? Body()); Assert.Equal(HttpStatusCode.Created, response.StatusCode); return await response.Content.ReadFromJsonAsync<JsonElement>(); }
    private static async Task<Actor> Seed(RegistrationApiFactory factory, bool expert = false)
    {
        await using var db = factory.Database(); var user = new User(Guid.NewGuid(), Guid.NewGuid().ToString("N") + "@EXAMPLE.TEST", expert ? UserRole.Dietitian : UserRole.Client, "synthetic measurement password", DateTimeOffset.UtcNow, new PasswordHasher<User>());
        Guid id;
        if (!expert) id = new ClientProfile(Guid.NewGuid(), user, "Synthetic measurement client").Id;
        else { var profile = new DietitianProfile(user, "Synthetic measurement expert", "Synthetic license"); id = profile.Id; db.Entry(profile).Property(x => x.IsVerified).CurrentValue = true; }
        db.Users.Add(user); db.Entry(user).Property(x => x.IsEmailVerified).CurrentValue = true; await db.SaveChangesAsync(); return new(user.Id, id);
    }
    private static async Task<HttpClient> Client(RegistrationApiFactory factory, Actor actor)
    {
        await using var db = factory.Database(); var jwt = new JwtAccessTokenService(Options.Create(factory.Jwt.Options), TimeProvider.System).Issue(await db.Users.SingleAsync(x => x.Id == actor.UserId));
        var client = factory.Client(false); client.DefaultRequestHeaders.Authorization = new("Bearer", jwt.AccessToken); client.DefaultRequestHeaders.Add("X-Profile-Context", "client"); return client;
    }
    private static async Task Error(HttpResponseMessage response, int status)
    {
        Assert.Equal((HttpStatusCode)status, response.StatusCode); var body = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal(status switch { 400 => "invalid_request", 401 => "unauthenticated", 403 => "forbidden", 404 => "not_found", 422 => "validation_failed", _ => "internal_error" }, body.GetProperty("error").GetProperty("code").GetString());
        Assert.False(string.IsNullOrWhiteSpace(body.GetProperty("requestId").GetString())); Assert.DoesNotContain(PrivateNote, body.GetRawText());
    }
    private sealed class WriteFailure : DbCommandInterceptor
    {
        public bool Armed { get; set; }
        public override ValueTask<InterceptionResult<DbDataReader>> ReaderExecutingAsync(DbCommand command, CommandEventData eventData, InterceptionResult<DbDataReader> result, CancellationToken cancellationToken = default)
        {
            if (Armed && command.CommandText.Contains("UPDATE body_measurements", StringComparison.Ordinal)) throw new InvalidOperationException("Synthetic measurement storage failure");
            return base.ReaderExecutingAsync(command, eventData, result, cancellationToken);
        }
    }
}
