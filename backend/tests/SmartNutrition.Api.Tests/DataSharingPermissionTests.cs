using System.Net;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
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

public sealed class DataSharingPermissionTests
{
    private const string Route = "/api/v1/data-sharing-permissions";
    private const string Password = "synthetic sharing password";
    private sealed record Pair(User Client, ClientProfile ClientProfile, User Expert, DietitianClientRelationship Relationship);

    [Theory]
    [InlineData("nutrition_plans")]
    [InlineData("meal_logs")]
    public void CategoriesKeepTheExistingResponseFields(string category)
    {
        var row = new DataSharingPermission(Guid.NewGuid(), false, DateTimeOffset.UtcNow, category);
        var json = JsonSerializer.SerializeToElement(row, JsonSerializerOptions.Web);
        Assert.Equal(new[] { "category", "consentRecordId", "createdAt", "id", "isGranted", "relationshipId", "updatedAt" },
            json.EnumerateObject().Select(property => property.Name).Order());
        Assert.Equal(category, json.GetProperty("category").GetString());
        Assert.False(json.GetProperty("isGranted").GetBoolean());
        Assert.Equal(JsonValueKind.Null, json.GetProperty("consentRecordId").ValueKind);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("all")]
    [InlineData("lab_reports")]
    [InlineData("Meal_Logs")]
    public void UnsupportedCategoriesCannotBecomePermissionModels(string? category) =>
        Assert.Throws<ArgumentException>(() => new DataSharingPermission(Guid.NewGuid(), true, DateTimeOffset.UtcNow, category!));

    [Fact]
    public void MigrationOnlyReplacesTheCategoryCheckWithoutChangingTablesOrRows()
    {
        var operations = new AddMealLogSharingCategory().UpOperations;
        Assert.Equal(2, operations.Count);
        Assert.Equal("ck_permissions_category", Assert.IsType<DropCheckConstraintOperation>(operations[0]).Name);
        var added = Assert.IsType<AddCheckConstraintOperation>(operations[1]);
        Assert.Equal("data_sharing_permissions", added.Table);
        Assert.Equal("category IN ('nutrition_plans','meal_logs') AND consent_record_id IS NULL", added.Sql);
    }

    [PostgresFact]
    public async Task DefaultRolloutRejectsBothGrantedAndDeniedNewMealRowsAndPreservesProgramSharing()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory);
        using var client = Bearer(factory, pair.Client);
        foreach (var granted in new[] { false, true })
        {
            using var meal = await Grant(client, pair.Relationship.Id, "meal_logs", granted);
            Assert.Equal(HttpStatusCode.UnprocessableEntity, meal.StatusCode);
        }
        using var program = await Grant(client, pair.Relationship.Id, "nutrition_plans");
        Assert.Equal(HttpStatusCode.Created, program.StatusCode);
        using var list = await client.GetAsync($"{Route}?relationshipId={pair.Relationship.Id}&page=1&pageSize=10");
        var body = await list.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal(1, body.GetProperty("totalCount").GetInt32());
        Assert.Equal("nutrition_plans", body.GetProperty("items")[0].GetProperty("category").GetString());
    }

    [PostgresFact]
    public async Task CategoriesAreIndependentAndOnlyTheClientsOwnActiveRelationshipCanWriteThem()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(mealLogSharing: true); var pair = await Seed(factory);
        using var client = Bearer(factory, pair.Client); using var expert = Bearer(factory, pair.Expert);
        using var meal = await Grant(client, pair.Relationship.Id, "meal_logs");
        Assert.Equal(HttpStatusCode.Created, meal.StatusCode);
        var row = await meal.Content.ReadFromJsonAsync<JsonElement>(); var id = row.GetProperty("id").GetGuid();
        Assert.EndsWith($"{Route}/{id}", meal.Headers.Location!.ToString());
        using var scope = factory.Services.CreateScope(); var access = scope.ServiceProvider.GetRequiredService<RelationshipAccessService>();
        var principal = new ClaimsPrincipal(new ClaimsIdentity([new("sub", pair.Expert.Id.ToString()), new("role", "dietitian")], "Bearer"));
        var actor = await access.RequireAsync(principal, default);
        Assert.False(await access.CanAccessNutritionPlansAsync(actor, pair.ClientProfile.Id));
        using var program = await Grant(client, pair.Relationship.Id, "nutrition_plans"); Assert.Equal(HttpStatusCode.Created, program.StatusCode);
        Assert.True(await access.CanAccessNutritionPlansAsync(actor, pair.ClientProfile.Id));
        using var duplicate = await Grant(client, pair.Relationship.Id, "meal_logs"); Assert.Equal(HttpStatusCode.Conflict, duplicate.StatusCode);
        using var expertWrite = await expert.PatchAsJsonAsync($"{Route}/{id}", new { isGranted = false }); Assert.Equal(HttpStatusCode.Forbidden, expertWrite.StatusCode);
        var other = await Seed(factory); using var stranger = Bearer(factory, other.Client);
        using var foreign = await stranger.PatchAsJsonAsync($"{Route}/{id}", new { isGranted = false }); Assert.Equal(HttpStatusCode.NotFound, foreign.StatusCode);
        using var foreignRead = await stranger.GetAsync($"{Route}/{id}"); Assert.Equal(HttpStatusCode.NotFound, foreignRead.StatusCode);
        using var revoked = await client.PatchAsJsonAsync($"{Route}/{id}", new { isGranted = false }); Assert.Equal(HttpStatusCode.OK, revoked.StatusCode);
        Assert.True(await access.CanAccessNutritionPlansAsync(actor, pair.ClientProfile.Id));
        using var list = await expert.GetAsync($"{Route}?relationshipId={pair.Relationship.Id}&page=1&pageSize=1");
        var firstPage = await list.Content.ReadFromJsonAsync<JsonElement>(); Assert.Equal(2, firstPage.GetProperty("totalCount").GetInt32()); Assert.Single(firstPage.GetProperty("items").EnumerateArray());
        using var second = await expert.GetAsync($"{Route}?relationshipId={pair.Relationship.Id}&page=2&pageSize=1");
        var secondPage = await second.Content.ReadFromJsonAsync<JsonElement>();
        Assert.NotEqual(firstPage.GetProperty("items")[0].GetProperty("id").GetGuid(), secondPage.GetProperty("items")[0].GetProperty("id").GetGuid());
    }

    [PostgresFact]
    public async Task DisablingRolloutNeverHidesExistingRowsAndStillAllowsWithdrawal()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory);
        // Represents an existing row from a previously enabled deployment, not an API bypass in production.
        await using var db = factory.Database(); var row = new DataSharingPermission(pair.Relationship.Id, true, DateTimeOffset.UtcNow, "meal_logs");
        db.DataSharingPermissions.Add(row); await db.SaveChangesAsync(); using var client = Bearer(factory, pair.Client);
        using var read = await client.GetAsync($"{Route}/{row.Id}"); Assert.Equal(HttpStatusCode.OK, read.StatusCode);
        using var grant = await client.PatchAsJsonAsync($"{Route}/{row.Id}", new { isGranted = true }); Assert.Equal(HttpStatusCode.UnprocessableEntity, grant.StatusCode);
        using var revoke = await client.PatchAsJsonAsync($"{Route}/{row.Id}", new { isGranted = false }); Assert.Equal(HttpStatusCode.OK, revoke.StatusCode);
        db.ChangeTracker.Clear(); Assert.False((await db.DataSharingPermissions.SingleAsync()).IsGranted);
    }

    [PostgresFact]
    public async Task PendingAndEndedRelationshipsConsentReferencesAndCategoryInjectionRemainRejected()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(mealLogSharing: true); var pair = await Seed(factory, active: false);
        using var client = Bearer(factory, pair.Client);
        using var pending = await Grant(client, pair.Relationship.Id, "meal_logs"); Assert.Equal(HttpStatusCode.Conflict, pending.StatusCode);
        await using var db = factory.Database(); await db.DietitianClientRelationships.Where(x => x.Id == pair.Relationship.Id)
            .ExecuteUpdateAsync(setters => setters.SetProperty(x => x.Status, RelationshipStatus.Ended).SetProperty(x => x.EndedAt, DateTimeOffset.UtcNow));
        using var ended = await Grant(client, pair.Relationship.Id, "meal_logs"); Assert.Equal(HttpStatusCode.Conflict, ended.StatusCode);
        using var consent = await client.PostAsJsonAsync(Route, new { relationshipId = pair.Relationship.Id, category = "meal_logs", isGranted = true, consentRecordId = Guid.NewGuid() });
        Assert.Equal(HttpStatusCode.UnprocessableEntity, consent.StatusCode);
        using var all = await Grant(client, pair.Relationship.Id, "all"); Assert.Equal(HttpStatusCode.UnprocessableEntity, all.StatusCode);
        using var injection = await client.PostAsJsonAsync(Route, new { relationshipId = pair.Relationship.Id, category = "meal_logs", isGranted = true, clientId = pair.ClientProfile.Id });
        Assert.Equal(HttpStatusCode.BadRequest, injection.StatusCode);
    }

    [PostgresFact]
    public async Task CookiePermissionWritesRequireOriginAndCsrfAndMfaAdminCannotGrant()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(webSessions: true, mealLogSharing: true); var pair = await Seed(factory);
        using var client = factory.Client(); await LoginCookie(client, pair.Client.Email, "/api/v1/auth/web-session");
        using var noOrigin = await Grant(client, pair.Relationship.Id, "meal_logs"); Assert.Equal(HttpStatusCode.Forbidden, noOrigin.StatusCode);
        using var noCsrfRequest = new HttpRequestMessage(HttpMethod.Post, Route) { Content = JsonContent.Create(new { relationshipId = pair.Relationship.Id, category = "meal_logs", isGranted = true }) };
        noCsrfRequest.Headers.Add("Origin", "https://localhost");
        using var noCsrf = await client.SendAsync(noCsrfRequest); Assert.Equal(HttpStatusCode.BadRequest, noCsrf.StatusCode);
        using var validRequest = new HttpRequestMessage(HttpMethod.Post, Route) { Content = JsonContent.Create(new { relationshipId = pair.Relationship.Id, category = "meal_logs", isGranted = true }) };
        validRequest.Headers.Add("Origin", "https://localhost"); validRequest.Headers.Add("X-CSRF-TOKEN", await Csrf(client));
        using var valid = await client.SendAsync(validRequest); Assert.Equal(HttpStatusCode.Created, valid.StatusCode);
        using var scope = factory.Services.CreateScope(); var adminUser = new User(Guid.NewGuid(), "SYNTHETIC-SHARING-ADMIN@EXAMPLE.TEST", UserRole.Admin, Password, DateTimeOffset.UtcNow, new PasswordHasher<User>());
        var setup = scope.ServiceProvider.GetRequiredService<AdminMfaService>().Initialize(adminUser, DateTimeOffset.UtcNow);
        await using var db = factory.Database(); db.Users.Add(adminUser); await db.SaveChangesAsync();
        using var admin = factory.Client(); await LoginCookie(admin, adminUser.Email, "/api/v1/auth/admin-web-session", setup.RecoveryCodes[0]);
        using var forbidden = await Grant(admin, pair.Relationship.Id, "meal_logs"); Assert.Equal(HttpStatusCode.Forbidden, forbidden.StatusCode);
    }

    [PostgresFact]
    public async Task MigrationPreservesProgramPermissionsAndRefusesRollbackWhileMealRowsExist()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory);
        await using var db = factory.Database(); var migrator = db.GetService<IMigrator>();
        await migrator.MigrateAsync("20261102032213_AddPasswordReset");
        var program = new DataSharingPermission(pair.Relationship.Id, true, DateTimeOffset.UtcNow); db.DataSharingPermissions.Add(program); await db.SaveChangesAsync();
        await db.Database.MigrateAsync(); db.ChangeTracker.Clear();
        var restored = await db.DataSharingPermissions.SingleAsync(); Assert.Equal(program.Id, restored.Id); Assert.True(restored.IsGranted); Assert.Equal(program.CreatedAt, restored.CreatedAt);
        Assert.Single(await db.DietitianClientRelationships.ToArrayAsync());
        Assert.False(db.Database.HasPendingModelChanges());
        var meal = new DataSharingPermission(pair.Relationship.Id, false, DateTimeOffset.UtcNow, "meal_logs"); db.DataSharingPermissions.Add(meal); await db.SaveChangesAsync();
        var error = await Assert.ThrowsAsync<PostgresException>(() => migrator.MigrateAsync("20261102032213_AddPasswordReset"));
        Assert.Equal(PostgresErrorCodes.CheckViolation, error.SqlState);
        db.ChangeTracker.Clear(); Assert.Equal(2, await db.DataSharingPermissions.CountAsync());
        Assert.Contains((await db.Database.GetAppliedMigrationsAsync()), x => x.EndsWith("_AddMealLogSharingCategory"));
    }

    [PostgresFact]
    public async Task ConcurrentDuplicateCategoryCreatesOnlyOneRowAndDatabaseRejectsUnknownCategory()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(mealLogSharing: true); var pair = await Seed(factory);
        using var first = Bearer(factory, pair.Client); using var second = Bearer(factory, pair.Client);
        var responses = await Task.WhenAll(Grant(first, pair.Relationship.Id, "meal_logs"), Grant(second, pair.Relationship.Id, "meal_logs"));
        try { Assert.Single(responses, x => x.StatusCode == HttpStatusCode.Created); Assert.Single(responses, x => x.StatusCode == HttpStatusCode.Conflict); }
        finally { foreach (var response in responses) response.Dispose(); }
        await using var db = factory.Database(); Assert.Single(await db.DataSharingPermissions.ToArrayAsync());
        var error = await Assert.ThrowsAsync<PostgresException>(() => db.Database.ExecuteSqlInterpolatedAsync(
            $"INSERT INTO data_sharing_permissions (id, relationship_id, category, is_granted, created_at, updated_at) VALUES ({Guid.NewGuid()}, {pair.Relationship.Id}, {"all"}, {true}, {DateTimeOffset.UtcNow}, {DateTimeOffset.UtcNow})"));
        Assert.Equal(PostgresErrorCodes.CheckViolation, error.SqlState);
    }

    private static async Task<Pair> Seed(RegistrationApiFactory factory, bool active = true)
    {
        var now = DateTimeOffset.UtcNow; var hasher = new PasswordHasher<User>();
        var client = new User(Guid.NewGuid(), $"SYNTHETIC-{Guid.NewGuid():N}@EXAMPLE.TEST", UserRole.Client, Password, now, hasher);
        var clientProfile = new ClientProfile(Guid.NewGuid(), client, "Synthetic client");
        var expert = new User(Guid.NewGuid(), $"SYNTHETIC-{Guid.NewGuid():N}@EXAMPLE.TEST", UserRole.Dietitian, Password, now, hasher);
        var expertProfile = new DietitianProfile(expert, "Synthetic expert", "Synthetic license");
        await using var db = factory.Database(); db.Users.AddRange(client, expert);
        db.Entry(client).Property(x => x.IsEmailVerified).CurrentValue = true; db.Entry(expert).Property(x => x.IsEmailVerified).CurrentValue = true;
        db.Entry(expertProfile).Property(x => x.IsVerified).CurrentValue = true;
        var relationship = new DietitianClientRelationship(clientProfile.Id, expertProfile.Id, now);
        if (active) relationship.Respond(RelationshipStatus.Active, now);
        db.DietitianClientRelationships.Add(relationship); await db.SaveChangesAsync(); return new(client, clientProfile, expert, relationship);
    }
    private static HttpClient Bearer(RegistrationApiFactory factory, User user)
    {
        var jwt = new JwtAccessTokenService(Options.Create(factory.Jwt.Options), TimeProvider.System).Issue(user);
        var client = factory.Client(false); client.DefaultRequestHeaders.Authorization = new("Bearer", jwt.AccessToken); return client;
    }
    private static Task<HttpResponseMessage> Grant(HttpClient client, Guid relationshipId, string category, bool isGranted = true) =>
        client.PostAsJsonAsync(Route, new { relationshipId, category, isGranted });
    private static async Task<string> Csrf(HttpClient client)
    {
        using var response = await client.GetAsync("/api/v1/auth/csrf"); Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        return (await response.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("requestToken").GetString()!;
    }
    private static async Task LoginCookie(HttpClient client, string email, string path, string? code = null)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, path) { Content = code is null
            ? JsonContent.Create(new { email, password = Password }) : JsonContent.Create(new { email, password = Password, mfaCode = code }) };
        request.Headers.Add("Origin", "https://localhost"); request.Headers.Add("X-CSRF-TOKEN", await Csrf(client));
        using var response = await client.SendAsync(request); Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }
}
