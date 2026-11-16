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
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Tests;

public sealed class MealLogApiTests
{
    private const string Root = "/api/v1/meal-logs";
    private const string PrivateName = "Synthetic private meal item";
    private sealed record Actor(Guid UserId, Guid ProfileId);

    [PostgresFact]
    public async Task OwnManualMealRoundTripsUtcDecimalsNullsAndItemOrderWithoutRelationship()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync();
        var actor = await Seed(factory); using var client = await Client(factory, actor);
        var input = Content(); input["consumedAt"] = "2026-11-16T15:30:00.1234567+03:00";
        input["items"] = new[] { Item(), Item("Synthetic second item", quantity: null, calories: 0m) };
        using var created = await client.PostAsJsonAsync(Root, input);
        Assert.Equal(HttpStatusCode.Created, created.StatusCode);
        var row = await created.Content.ReadFromJsonAsync<JsonElement>(); var id = row.GetProperty("id").GetGuid();
        Assert.Equal($"{Root}/{id}", created.Headers.Location?.OriginalString);
        Assert.Contains("no-store", created.Headers.CacheControl!.ToString());
        Assert.Equal(actor.ProfileId, row.GetProperty("clientId").GetGuid());
        Assert.NotEqual(actor.UserId, row.GetProperty("clientId").GetGuid());
        Assert.Equal(new DateTimeOffset(2026, 11, 16, 12, 30, 0, TimeSpan.Zero).AddTicks(1234560), row.GetProperty("consumedAt").GetDateTimeOffset());
        Assert.Equal(TimeSpan.Zero, row.GetProperty("consumedAt").GetDateTimeOffset().Offset);
        Assert.Equal("manual", row.GetProperty("source").GetString());
        Assert.Equal(JsonValueKind.Null, row.GetProperty("foodAnalysisId").ValueKind);
        var items = row.GetProperty("items"); Assert.Equal(2, items.GetArrayLength());
        Assert.Equal(PrivateName, items[0].GetProperty("displayName").GetString());
        Assert.Equal(125.125m, items[0].GetProperty("quantityGrams").GetDecimal());
        Assert.Equal(12.3456789m, items[0].GetProperty("proteinGrams").GetDecimal());
        Assert.Equal(JsonValueKind.Null, items[1].GetProperty("quantityGrams").ValueKind);
        Assert.Equal(0, items[1].GetProperty("caloriesKcal").GetDecimal());
        Assert.All(items.EnumerateArray(), item => Assert.Equal(id, item.GetProperty("mealLogId").GetGuid()));
        using var loaded = await client.GetAsync($"{Root}/{id}");
        Assert.Equal(row.GetRawText(), (await loaded.Content.ReadFromJsonAsync<JsonElement>()).GetRawText());
        Assert.DoesNotContain("deletedAt", row.GetRawText()); Assert.DoesNotContain("position", row.GetRawText());
        Assert.DoesNotContain(PrivateName, factory.Logs);
    }

    [PostgresFact]
    public async Task PatchPreservesOmittedFieldsClearsNullableNoteAndReplacesItemsAtomically()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); using var client = await Client(factory, await Seed(factory));
        var initial = await Create(client); var id = initial.GetProperty("id").GetGuid();
        var oldItem = initial.GetProperty("items")[0].GetProperty("id").GetGuid();
        using var partial = await client.PatchAsJsonAsync($"{Root}/{id}", new { note = (string?)null, mealType = "dinner" });
        Assert.Equal(HttpStatusCode.OK, partial.StatusCode);
        var row = await partial.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal(JsonValueKind.Null, row.GetProperty("note").ValueKind);
        Assert.Equal("dinner", row.GetProperty("mealType").GetString());
        Assert.Equal(initial.GetProperty("createdAt").GetString(), row.GetProperty("createdAt").GetString());
        Assert.Equal(initial.GetProperty("consumedAt").GetString(), row.GetProperty("consumedAt").GetString());
        Assert.Equal(oldItem, row.GetProperty("items")[0].GetProperty("id").GetGuid());
        using var replaced = await client.PatchAsJsonAsync($"{Root}/{id}", new { items = new[] { Item("Synthetic replacement") } });
        Assert.Equal(HttpStatusCode.OK, replaced.StatusCode);
        await using var db = factory.Database();
        Assert.False(await db.MealLogItems.AnyAsync(x => x.Id == oldItem));
        Assert.Equal("Synthetic replacement", (await db.MealLogItems.SingleAsync()).DisplayName);
        Assert.Equal(1, await db.MealLogs.CountAsync());
    }

    [PostgresFact]
    public async Task DeleteRemovesAllNormalAccessAndRetainsInternalRowsWithoutInventingPurgePolicy()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); using var client = await Client(factory, await Seed(factory));
        var row = await Create(client); var id = row.GetProperty("id").GetGuid();
        using var deleted = await client.DeleteAsync($"{Root}/{id}"); Assert.Equal(HttpStatusCode.NoContent, deleted.StatusCode);
        Assert.Equal("", await deleted.Content.ReadAsStringAsync());
        using var get = await client.GetAsync($"{Root}/{id}"); await Error(get, HttpStatusCode.NotFound, "not_found");
        using var patch = await client.PatchAsJsonAsync($"{Root}/{id}", new { note = "Synthetic change" }); await Error(patch, HttpStatusCode.NotFound, "not_found");
        using var repeat = await client.DeleteAsync($"{Root}/{id}"); await Error(repeat, HttpStatusCode.NotFound, "not_found");
        var list = await client.GetFromJsonAsync<JsonElement>($"{Root}?page=1&pageSize=10");
        Assert.Equal(0, list.GetProperty("totalCount").GetInt32()); Assert.Empty(list.GetProperty("items").EnumerateArray());
        await using var db = factory.Database(); Assert.Empty(await db.MealLogs.ToListAsync());
        Assert.NotNull((await db.MealLogs.IgnoreQueryFilters().SingleAsync()).DeletedAt);
        Assert.Single(await db.MealLogItems.ToListAsync());
    }

    [PostgresFact]
    public async Task OtherClientCannotReadPatchDeleteOrCountOwnersRecords()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync();
        using var owner = await Client(factory, await Seed(factory)); using var stranger = await Client(factory, await Seed(factory));
        var row = await Create(owner); var id = row.GetProperty("id").GetGuid();
        using var get = await stranger.GetAsync($"{Root}/{id}"); await Error(get, HttpStatusCode.NotFound, "not_found");
        using var patch = await stranger.PatchAsJsonAsync($"{Root}/{id}", new { note = "Synthetic hijack" }); await Error(patch, HttpStatusCode.NotFound, "not_found");
        using var delete = await stranger.DeleteAsync($"{Root}/{id}"); await Error(delete, HttpStatusCode.NotFound, "not_found");
        var list = await stranger.GetFromJsonAsync<JsonElement>($"{Root}?page=1&pageSize=10"); Assert.Equal(0, list.GetProperty("totalCount").GetInt32());
        using var missing = await stranger.GetAsync($"{Root}/{Guid.NewGuid()}");
        Assert.Equal((await get.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("error").GetRawText(),
            (await missing.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("error").GetRawText());
    }

    [PostgresFact]
    public async Task AllEndpointsRequireJwtAndRespectRevocationAndProfileContext()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync();
        var actor = await Seed(factory); using var signed = await Client(factory, actor);
        var id = (await Create(signed)).GetProperty("id").GetGuid();
        using var anonymous = factory.Client(false);
        using var anonymousList = await anonymous.GetAsync($"{Root}?page=1&pageSize=10");
        await Error(anonymousList, HttpStatusCode.Unauthorized, "unauthenticated");
        foreach (var method in new[] { HttpMethod.Get, HttpMethod.Post, HttpMethod.Patch, HttpMethod.Delete })
        {
            using var request = new HttpRequestMessage(method, method == HttpMethod.Post ? Root : $"{Root}/{id}");
            if (method == HttpMethod.Post || method == HttpMethod.Patch) request.Content = JsonContent.Create(Content());
            using var response = await anonymous.SendAsync(request); await Error(response, HttpStatusCode.Unauthorized, "unauthenticated");
        }
        signed.DefaultRequestHeaders.Remove("X-Profile-Context"); signed.DefaultRequestHeaders.Add("X-Profile-Context", "dietitian");
        using var wrongContext = await signed.GetAsync($"{Root}?page=1&pageSize=10"); await Error(wrongContext, HttpStatusCode.Forbidden, "forbidden");
        signed.DefaultRequestHeaders.Remove("X-Profile-Context"); signed.DefaultRequestHeaders.Add("X-Profile-Context", "admin");
        using var malformed = await signed.GetAsync($"{Root}?page=1&pageSize=10"); await Error(malformed, HttpStatusCode.BadRequest, "invalid_request");
        signed.DefaultRequestHeaders.Remove("X-Profile-Context"); signed.DefaultRequestHeaders.Add("X-Profile-Context", "client");
        await using (var db = factory.Database())
        { var user = await db.Users.SingleAsync(x => x.Id == actor.UserId); db.Entry(user).Property(x => x.CredentialsVersion).CurrentValue++; await db.SaveChangesAsync(); }
        using var revoked = await signed.GetAsync($"{Root}/{id}"); await Error(revoked, HttpStatusCode.Unauthorized, "unauthenticated");
        using var expert = await Client(factory, await Seed(factory, expert: true));
        using var deniedExpert = await expert.PostAsJsonAsync(Root, Content()); await Error(deniedExpert, HttpStatusCode.Forbidden, "forbidden");
    }

    [PostgresFact]
    public async Task VerifiedDualProfileOnlyUsesItsOwnClientContextAndCookiesDoNotAuthorizeMeals()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(webSessions: true);
        var actor = await Seed(factory);
        await using (var db = factory.Database())
        {
            var user = await db.Users.SingleAsync(x => x.Id == actor.UserId);
            var expert = new DietitianProfile(user, "Synthetic dual expert", "Synthetic license");
            db.DietitianProfiles.Add(expert); db.Entry(expert).Property(x => x.IsVerified).CurrentValue = true; await db.SaveChangesAsync();
        }
        using var client = await Client(factory, actor); await Create(client);
        client.DefaultRequestHeaders.Remove("X-Profile-Context"); client.DefaultRequestHeaders.Add("X-Profile-Context", "dietitian");
        using var denied = await client.GetAsync($"{Root}?page=1&pageSize=10"); await Error(denied, HttpStatusCode.Forbidden, "forbidden");
        using var cookie = factory.Client(); cookie.DefaultRequestHeaders.Add("Origin", "https://localhost");
        var csrf = await cookie.GetFromJsonAsync<JsonElement>("/api/v1/auth/csrf"); cookie.DefaultRequestHeaders.Add("X-CSRF-TOKEN", csrf.GetProperty("requestToken").GetString());
        await using (var db = factory.Database())
        {
            var user = await db.Users.SingleAsync(x => x.Id == actor.UserId);
            using var login = await cookie.PostAsJsonAsync("/api/v1/auth/web-session", new { email = user.Email, password = "synthetic meal test password" });
            Assert.Equal(HttpStatusCode.OK, login.StatusCode);
        }
        using var cookieRead = await cookie.GetAsync($"{Root}?page=1&pageSize=10"); await Error(cookieRead, HttpStatusCode.Unauthorized, "unauthenticated");
    }

    [PostgresFact]
    public async Task ListAppliesOwnerUtcHalfOpenRangeStableOrderingAndPaginationBeforeReturningCount()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); using var client = await Client(factory, await Seed(factory));
        var ids = new List<Guid>();
        foreach (var date in new[] { "2026-11-15T12:00:00Z", "2026-11-16T12:00:00Z", "2026-11-16T12:00:00Z", "2026-11-17T12:00:00Z" })
        { var body = Content(); body["consumedAt"] = date; ids.Add((await Create(client, body)).GetProperty("id").GetGuid()); }
        var range = "from=2026-11-16T15%3A00%3A00%2B03%3A00&to=2026-11-17T12%3A00%3A00Z";
        var first = await client.GetFromJsonAsync<JsonElement>($"{Root}?page=1&pageSize=1&{range}");
        var second = await client.GetFromJsonAsync<JsonElement>($"{Root}?page=2&pageSize=1&{range}");
        Assert.Equal(2, first.GetProperty("totalCount").GetInt32()); Assert.Equal(2, second.GetProperty("totalCount").GetInt32());
        // PostgreSQL orders UUIDs by their canonical hexadecimal representation.
        var expected = ids.Skip(1).Take(2).OrderBy(x => x.ToString("D"), StringComparer.Ordinal).ToArray();
        Assert.Equal(expected[0], first.GetProperty("items")[0].GetProperty("id").GetGuid());
        Assert.Equal(expected[1], second.GetProperty("items")[0].GetProperty("id").GetGuid());
        var empty = await client.GetFromJsonAsync<JsonElement>($"{Root}?page=3&pageSize=1&{range}");
        Assert.Equal(2, empty.GetProperty("totalCount").GetInt32()); Assert.Empty(empty.GetProperty("items").EnumerateArray());
        var all = await client.GetFromJsonAsync<JsonElement>($"{Root}?page=1&pageSize=100");
        Assert.Equal(ids[3], all.GetProperty("items")[0].GetProperty("id").GetGuid());
    }

    [PostgresFact]
    public async Task InvalidQueriesAndGetDeleteBodiesReturnShared400()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); using var client = await Client(factory, await Seed(factory));
        foreach (var query in new[] { "", "?page=1", "?page=0&pageSize=10", "?page=1&pageSize=101", "?page=2147483647&pageSize=100",
            "?page=1&page=2&pageSize=10", "?page=1&pageSize=10&clientId=" + Guid.NewGuid(), "?page=1&pageSize=10&from=2026-11-16T12:00:00",
            "?page=1&pageSize=10&from=", "?page=1&pageSize=10&from=2026-11-17T12:00:00Z&to=2026-11-16T12:00:00Z" })
        { using var response = await client.GetAsync(Root + query); await Error(response, HttpStatusCode.BadRequest, "invalid_request"); }
        using var invalidId = await client.GetAsync(Root + "/invalid-uuid"); await Error(invalidId, HttpStatusCode.BadRequest, "invalid_request");
        var id = (await Create(client)).GetProperty("id").GetGuid();
        foreach (var method in new[] { HttpMethod.Get, HttpMethod.Delete })
        {
            using var request = new HttpRequestMessage(method, $"{Root}/{id}") { Content = JsonContent.Create(new { }) };
            using var response = await client.SendAsync(request); await Error(response, HttpStatusCode.BadRequest, "invalid_request");
        }
    }

    [PostgresFact]
    public async Task ServerFieldsMissingRequiredFieldsAndMalformedJsonAreRejected()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); using var client = await Client(factory, await Seed(factory));
        foreach (var field in new[] { "clientId", "id", "createdAt", "deletedAt", "dietitianId" })
        { var body = Content(); body[field] = Guid.NewGuid(); using var response = await client.PostAsJsonAsync(Root, body); await Error(response, HttpStatusCode.BadRequest, "invalid_request"); }
        foreach (var field in new[] { "mealType", "consumedAt", "source", "items" })
        { var body = Content(); body.Remove(field); using var response = await client.PostAsJsonAsync(Root, body); await Error(response, HttpStatusCode.BadRequest, "invalid_request"); }
        var timestamp = Content(); timestamp["consumedAt"] = "2026-11-16T12:00:00";
        using var noOffset = await client.PostAsJsonAsync(Root, timestamp); await Error(noOffset, HttpStatusCode.BadRequest, "invalid_request");
        var invalidItem = Content(); var item = Item(); item["id"] = Guid.NewGuid(); invalidItem["items"] = new[] { item };
        using var itemIdentity = await client.PostAsJsonAsync(Root, invalidItem); await Error(itemIdentity, HttpStatusCode.BadRequest, "invalid_request");
        item.Remove("id"); item["quantityGrams"] = "125";
        using var numericString = await client.PostAsJsonAsync(Root, invalidItem); await Error(numericString, HttpStatusCode.BadRequest, "invalid_request");
        using var malformed = await client.PostAsync(Root, new StringContent("{", Encoding.UTF8, "application/json")); await Error(malformed, HttpStatusCode.BadRequest, "invalid_request");
        using var media = await client.PostAsync(Root, new StringContent("{}")); await Error(media, HttpStatusCode.UnsupportedMediaType, "unsupported_media_type");
    }

    [PostgresFact]
    public async Task InvalidQuantitiesAndUnverifiedReferencesCannotCreateOrPartiallyChangeAMeal()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); using var client = await Client(factory, await Seed(factory));
        foreach (var field in new[] { "quantityGrams", "caloriesKcal", "proteinGrams", "carbsGrams", "fatGrams", "displayName", "foodItemId", "recipeId" })
        {
            var item = Item(); item[field] = field switch { "displayName" => "  ", "foodItemId" or "recipeId" => Guid.NewGuid(), _ => -1m };
            var body = Content(); body["items"] = new[] { item }; using var response = await client.PostAsJsonAsync(Root, body);
            await Error(response, HttpStatusCode.UnprocessableEntity, "validation_failed");
        }
        foreach (var source in new[] { "wearable", "ai_assisted" })
        { var body = Content(); body["source"] = source; using var response = await client.PostAsJsonAsync(Root, body); await Error(response, HttpStatusCode.UnprocessableEntity, "validation_failed"); }
        var analysis = Content(); analysis["foodAnalysisId"] = Guid.NewGuid();
        using var unverified = await client.PostAsJsonAsync(Root, analysis); await Error(unverified, HttpStatusCode.UnprocessableEntity, "validation_failed");
        foreach (var items in new object?[] { null, Array.Empty<object>(), new object?[] { null }, Enumerable.Range(0, 101).Select(_ => Item()).ToArray() })
        { var body = Content(); body["items"] = items; using var response = await client.PostAsJsonAsync(Root, body); await Error(response, HttpStatusCode.UnprocessableEntity, "validation_failed"); }
        var initial = await Create(client); var id = initial.GetProperty("id").GetGuid();
        using var emptyPatch = await client.PatchAsJsonAsync($"{Root}/{id}", new { }); await Error(emptyPatch, HttpStatusCode.BadRequest, "invalid_request");
        using var sourcePatch = await client.PatchAsJsonAsync($"{Root}/{id}", new { source = "manual" }); await Error(sourcePatch, HttpStatusCode.BadRequest, "invalid_request");
        foreach (var field in new[] { "mealType", "consumedAt", "items" })
        { using var response = await client.PatchAsJsonAsync($"{Root}/{id}", new Dictionary<string, object?> { [field] = null }); await Error(response, HttpStatusCode.UnprocessableEntity, "validation_failed"); }
        using var invalidPatch = await client.PatchAsJsonAsync($"{Root}/{id}", new { note = "Synthetic should roll back", items = new object[0] });
        await Error(invalidPatch, HttpStatusCode.UnprocessableEntity, "validation_failed");
        var loaded = await client.GetFromJsonAsync<JsonElement>($"{Root}/{id}"); Assert.Equal(initial.GetRawText(), loaded.GetRawText());
        Assert.DoesNotContain(PrivateName, factory.Logs);
    }

    [PostgresFact]
    public async Task DatabaseFailureRollsBackHeaderAndReplacementItemsWithoutLeakingFoodValues()
    {
        var failure = new MealWriteFailure(); await using var factory = await RegistrationApiFactory.CreateAsync(interceptor: failure);
        using var client = await Client(factory, await Seed(factory)); var initial = await Create(client); var id = initial.GetProperty("id").GetGuid();
        failure.Armed = true;
        using var response = await client.PatchAsJsonAsync($"{Root}/{id}", new { note = "Synthetic changed note", items = new[] { Item("Synthetic failed item") } });
        await Error(response, HttpStatusCode.InternalServerError, "internal_error");
        failure.Armed = false;
        Assert.Equal(initial.GetRawText(), (await client.GetFromJsonAsync<JsonElement>($"{Root}/{id}")).GetRawText());
        Assert.DoesNotContain("Synthetic failed item", factory.Logs); Assert.DoesNotContain(PrivateName, factory.Logs);
    }

    [PostgresFact]
    public async Task ConcurrentPatchAndDeleteCannotResurrectOrOrphanAMeal()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var actor = await Seed(factory);
        using var client = await Client(factory, actor); using var second = await Client(factory, actor);
        var id = (await Create(client)).GetProperty("id").GetGuid();
        var patch = client.PatchAsJsonAsync($"{Root}/{id}", new { items = new[] { Item("Synthetic concurrent item") } });
        var delete = second.DeleteAsync($"{Root}/{id}"); await Task.WhenAll(patch, delete);
        using var patched = await patch; using var deleted = await delete;
        Assert.Contains(patched.StatusCode, new[] { HttpStatusCode.OK, HttpStatusCode.NotFound }); Assert.Equal(HttpStatusCode.NoContent, deleted.StatusCode);
        using var loaded = await client.GetAsync($"{Root}/{id}"); Assert.Equal(HttpStatusCode.NotFound, loaded.StatusCode);
        await using var db = factory.Database(); Assert.Single(await db.MealLogs.IgnoreQueryFilters().ToListAsync());
        Assert.Single(await db.MealLogItems.ToListAsync());
    }

    [PostgresFact]
    public async Task AdditiveMigrationPreservesExistingAuthRelationshipsPermissionsAndProgramVersions()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var actor = await Seed(factory); var expert = await Seed(factory, expert: true);
        using var client = await Client(factory, actor); using var expertClient = await Client(factory, expert);
        expertClient.DefaultRequestHeaders.Remove("X-Profile-Context"); expertClient.DefaultRequestHeaders.Add("X-Profile-Context", "dietitian");
        using var relation = await client.PostAsJsonAsync("/api/v1/dietitian-relationships", new { dietitianId = expert.ProfileId });
        Assert.Equal(HttpStatusCode.Created, relation.StatusCode);
        var relationshipId = (await relation.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid();
        using var accepted = await expertClient.PostAsync($"/api/v1/dietitian-relationships/{relationshipId}/accept", null); Assert.Equal(HttpStatusCode.OK, accepted.StatusCode);
        using var permission = await client.PostAsJsonAsync("/api/v1/data-sharing-permissions", new { relationshipId, category = "nutrition_plans", isGranted = true }); Assert.Equal(HttpStatusCode.Created, permission.StatusCode);
        using var program = await client.PostAsJsonAsync("/api/v1/nutrition-plans", new { title = "Synthetic preserved program", startDate = "2026-11-16", items = new[] { new { mealType = "lunch", description = "Synthetic recommendation", sortOrder = 0 } } });
        Assert.Equal(HttpStatusCode.Created, program.StatusCode);
        await using var db = factory.Database(); var migrator = db.GetService<IMigrator>();
        await migrator.MigrateAsync("20261107104433_AddMealLogSharingCategory");
        var before = await ExistingRows(db);
        await migrator.MigrateAsync(); Assert.Equal(before, await ExistingRows(db));
        Assert.False(db.Database.HasPendingModelChanges());
        await Create(client); Assert.Single(await db.MealLogs.AsNoTracking().ToListAsync());
        var rollback = await Assert.ThrowsAsync<PostgresException>(() => migrator.MigrateAsync("20261107104433_AddMealLogSharingCategory"));
        Assert.Equal(PostgresErrorCodes.RaiseException, rollback.SqlState);
        Assert.Single(await db.MealLogs.AsNoTracking().ToListAsync()); Assert.Equal(before, await ExistingRows(db));
        // Existing default-off G1 behavior remains intact after applying the new migration.
        using var mealPermission = await client.PostAsJsonAsync("/api/v1/data-sharing-permissions", new { relationshipId, category = "meal_logs", isGranted = true });
        await Error(mealPermission, HttpStatusCode.UnprocessableEntity, "validation_failed");
    }

    [PostgresFact]
    public async Task PostgresConstraintsRejectInvalidNumbersAndForeignKeys()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); using var client = await Client(factory, await Seed(factory));
        var row = await Create(client); var id = row.GetProperty("id").GetGuid();
        await using var db = factory.Database();
        var negative = await Assert.ThrowsAsync<PostgresException>(() => db.Database.ExecuteSqlInterpolatedAsync($"UPDATE meal_log_items SET quantity_grams = -1 WHERE meal_log_id = {id}"));
        Assert.Equal(PostgresErrorCodes.CheckViolation, negative.SqlState);
        var nonFinite = await Assert.ThrowsAsync<PostgresException>(() => db.Database.ExecuteSqlInterpolatedAsync($"UPDATE meal_log_items SET calories_kcal = 'NaN'::numeric WHERE meal_log_id = {id}"));
        Assert.Equal(PostgresErrorCodes.CheckViolation, nonFinite.SqlState);
        var foreign = await Assert.ThrowsAsync<PostgresException>(() => db.Database.ExecuteSqlInterpolatedAsync($"UPDATE meal_logs SET client_id = {Guid.NewGuid()} WHERE id = {id}"));
        Assert.Equal(PostgresErrorCodes.ForeignKeyViolation, foreign.SqlState);
    }

    private static async Task<string[]> ExistingRows(SmartNutrition.Api.Data.AppDbContext db)
    {
        var rows = new List<string>(); var connection = db.Database.GetDbConnection(); await connection.OpenAsync();
        try
        {
            foreach (var table in new[] { "users", "client_profiles", "dietitian_profiles", "dietitian_client_relationships", "data_sharing_permissions", "nutrition_plans", "nutrition_plan_versions", "auth_sessions", "refresh_tokens", "audit_events" })
            {
                await using var command = connection.CreateCommand();
                command.CommandText = $"SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text), '[]'::jsonb)::text FROM {table} t";
                rows.Add((string)(await command.ExecuteScalarAsync())!);
            }
        }
        finally { await connection.CloseAsync(); }
        return rows.ToArray();
    }

    private static Dictionary<string, object?> Content() => new()
    { ["mealType"] = "lunch", ["consumedAt"] = "2026-11-16T12:00:00Z", ["source"] = "manual", ["note"] = "Synthetic private note", ["items"] = new[] { Item() } };
    private static Dictionary<string, object?> Item(string name = PrivateName, decimal? quantity = 125.125m, decimal? calories = null) => new()
    { ["displayName"] = name, ["isEstimated"] = true, ["quantityGrams"] = quantity, ["caloriesKcal"] = calories, ["proteinGrams"] = 12.3456789m, ["carbsGrams"] = null, ["fatGrams"] = 0m };
    private static async Task<JsonElement> Create(HttpClient client, Dictionary<string, object?>? body = null)
    {
        using var response = await client.PostAsJsonAsync(Root, body ?? Content()); Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        return await response.Content.ReadFromJsonAsync<JsonElement>();
    }
    private static async Task<Actor> Seed(RegistrationApiFactory factory, bool expert = false)
    {
        await using var db = factory.Database(); var user = new User(Guid.NewGuid(), Guid.NewGuid().ToString("N") + "@EXAMPLE.TEST",
            expert ? UserRole.Dietitian : UserRole.Client, "synthetic meal test password", DateTimeOffset.UtcNow, new PasswordHasher<User>());
        Guid profileId;
        if (!expert) profileId = new ClientProfile(Guid.NewGuid(), user, "Synthetic meal client").Id;
        else { var profile = new DietitianProfile(user, "Synthetic meal expert", "Synthetic license"); profileId = profile.Id; db.Entry(profile).Property(x => x.IsVerified).CurrentValue = true; }
        db.Users.Add(user); db.Entry(user).Property(x => x.IsEmailVerified).CurrentValue = true; await db.SaveChangesAsync(); return new(user.Id, profileId);
    }
    private static async Task<HttpClient> Client(RegistrationApiFactory factory, Actor actor)
    {
        await using var db = factory.Database(); var user = await db.Users.SingleAsync(x => x.Id == actor.UserId);
        var pair = new JwtAccessTokenService(Options.Create(factory.Jwt.Options), TimeProvider.System).Issue(user);
        var client = factory.Client(false); client.DefaultRequestHeaders.Authorization = new("Bearer", pair.AccessToken);
        client.DefaultRequestHeaders.Add("X-Profile-Context", "client"); return client;
    }
    private static async Task Error(HttpResponseMessage response, HttpStatusCode status, string code)
    {
        Assert.Equal(status, response.StatusCode); var body = JsonSerializer.Deserialize<JsonElement>(await response.Content.ReadAsStringAsync());
        Assert.Equal(code, body.GetProperty("error").GetProperty("code").GetString()); Assert.False(string.IsNullOrWhiteSpace(body.GetProperty("requestId").GetString()));
        Assert.DoesNotContain(PrivateName, body.GetRawText());
    }
    private sealed class MealWriteFailure : DbCommandInterceptor
    {
        internal bool Armed { get; set; }
        public override ValueTask<InterceptionResult<DbDataReader>> ReaderExecutingAsync(DbCommand command, CommandEventData eventData,
            InterceptionResult<DbDataReader> result, CancellationToken cancellationToken = default)
        {
            if (Armed && command.CommandText.Contains("INSERT INTO meal_log_items", StringComparison.Ordinal)) throw new InvalidOperationException("Synthetic storage failure");
            return base.ReaderExecutingAsync(command, eventData, result, cancellationToken);
        }
    }
}
