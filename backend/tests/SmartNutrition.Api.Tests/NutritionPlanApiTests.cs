using System.Data.Common;
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.Extensions.Options;
using Npgsql;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Features.Dietitians;
using SmartNutrition.Api.Features.NutritionPlans;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Tests;

public sealed class NutritionPlanApiTests
{
    private const string Root = "/api/v1/nutrition-plans";
    private const string Password = "synthetic program test password";
    private sealed record Actor(Guid UserId, Guid ProfileId, string Email, UserRole Role);

    [PostgresFact]
    public async Task PersonalProgramNeedsNoDietitianAndReturnsTheApprovedNullableFieldsAndServerItems()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var actor = await Seed(factory, UserRole.Client);
        using var client = await Client(factory, actor); using var created = await client.PostAsJsonAsync(Root, Content());
        Assert.Equal(HttpStatusCode.Created, created.StatusCode); var row = await created.Content.ReadFromJsonAsync<JsonElement>();
        var id = row.GetProperty("id").GetGuid(); Assert.Equal(actor.ProfileId, row.GetProperty("clientId").GetGuid());
        Assert.Equal(JsonValueKind.Null, row.GetProperty("dietitianId").ValueKind); Assert.Equal(JsonValueKind.Null, row.GetProperty("dailyCaloriesTargetKcal").ValueKind);
        Assert.Equal("draft", row.GetProperty("status").GetString()); Assert.Equal(1, row.GetProperty("versionNumber").GetInt32());
        var item = row.GetProperty("items")[0]; Assert.Equal(id, item.GetProperty("nutritionPlanId").GetGuid()); Assert.NotEqual(Guid.Empty, item.GetProperty("id").GetGuid());
        Assert.Equal(JsonValueKind.Null, item.GetProperty("dayOfWeek").ValueKind); Assert.Equal(JsonValueKind.Null, item.GetProperty("recipeId").ValueKind);
        Assert.Equal(new[] { "clientId", "createdAt", "dailyCaloriesTargetKcal", "dailyWaterTargetMl", "dietitianId", "endDate", "id", "items", "startDate", "status", "title", "versionId", "versionNumber" }, row.EnumerateObject().Select(x => x.Name).Order());
        using var activate = await client.PostAsync($"{Root}/{id}/activate", null); Assert.Equal(HttpStatusCode.OK, activate.StatusCode);
        using var active = await client.GetAsync(Root + "/active"); Assert.Equal(HttpStatusCode.OK, active.StatusCode);
        Assert.Equal(id, (await active.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid());
        using var list = await client.GetAsync(Root + "?page=1&pageSize=10"); Assert.Equal(1, (await list.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("totalCount").GetInt32());
        using var ownIdentity = await client.GetAsync(Root + $"?page=1&pageSize=10&clientId={actor.ProfileId}"); Assert.Equal(HttpStatusCode.BadRequest, ownIdentity.StatusCode);
        using var emptyIdentity = await client.GetAsync(Root + "?page=1&pageSize=10&clientId="); Assert.Equal(HttpStatusCode.BadRequest, emptyIdentity.StatusCode);
        using var injected = await client.PostAsJsonAsync(Root, Content(actor.ProfileId)); Assert.Equal(HttpStatusCode.BadRequest, injected.StatusCode);
        var nullIdentity = Content(); nullIdentity["clientId"] = null;
        using var alsoInjected = await client.PostAsJsonAsync(Root, nullIdentity); Assert.Equal(HttpStatusCode.BadRequest, alsoInjected.StatusCode);
    }

    [PostgresFact]
    public async Task AssignedProgramsAreClientReadOnlyAndDietitiansCannotEditPersonalOrAnotherExpertsPlan()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var c = await Seed(factory, UserRole.Client); var d = await Seed(factory, UserRole.Dietitian);
        using var client = await Client(factory, c); using var expert = await Client(factory, d); await Connect(client, expert, d.ProfileId);
        var personal = await Create(client); var assigned = await Create(expert, c.ProfileId);
        using var clientEdit = await client.PatchAsJsonAsync($"{Root}/{assigned}", new { title = "Synthetic forbidden edit" }); Assert.Equal(HttpStatusCode.Forbidden, clientEdit.StatusCode);
        using var clientActivate = await client.PostAsync($"{Root}/{assigned}/activate", null); Assert.Equal(HttpStatusCode.Forbidden, clientActivate.StatusCode);
        using var personalEdit = await expert.PatchAsJsonAsync($"{Root}/{personal}", new { title = "Synthetic forbidden edit" }); Assert.Equal(HttpStatusCode.Forbidden, personalEdit.StatusCode);
        using var activated = await expert.PostAsync($"{Root}/{assigned}/activate", null); Assert.Equal(HttpStatusCode.OK, activated.StatusCode);
        using var read = await client.GetAsync(Root + "/active"); Assert.Equal(assigned, (await read.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid());
        using var stranger = await Client(factory, await Seed(factory, UserRole.Client)); using var foreign = await stranger.GetAsync($"{Root}/{assigned}"); Assert.Equal(HttpStatusCode.NotFound, foreign.StatusCode);
        using var noRelation = await Client(factory, await Seed(factory, UserRole.Dietitian)); using var denied = await noRelation.GetAsync($"{Root}/{assigned}"); Assert.Equal(HttpStatusCode.NotFound, denied.StatusCode);
        using var dietitianActive = await expert.GetAsync(Root + "/active"); Assert.Equal(HttpStatusCode.Forbidden, dietitianActive.StatusCode);
    }

    [PostgresFact]
    public async Task RevisionsAreAtomicPreserveSnapshotsAndNullablePatchSemantics()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); using var client = await Client(factory, await Seed(factory, UserRole.Client));
        var content = Content(); content["endDate"] = "2026-11-15"; content["dailyWaterTargetMl"] = 1800.125m;
        using var created = await client.PostAsJsonAsync(Root, content); var first = await created.Content.ReadFromJsonAsync<JsonElement>(); var id = first.GetProperty("id").GetGuid(); var versionId = first.GetProperty("versionId").GetGuid();
        using var changed = await client.PatchAsJsonAsync($"{Root}/{id}", new { title = "Synthetic revised program", endDate = (string?)null, dailyWaterTargetMl = (decimal?)null });
        Assert.Equal(HttpStatusCode.OK, changed.StatusCode); var current = await changed.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal(2, current.GetProperty("versionNumber").GetInt32()); Assert.Equal(JsonValueKind.Null, current.GetProperty("endDate").ValueKind);
        Assert.Equal(first.GetProperty("startDate").GetString(), current.GetProperty("startDate").GetString());
        Assert.NotEqual(first.GetProperty("items")[0].GetProperty("id").GetGuid(), current.GetProperty("items")[0].GetProperty("id").GetGuid());
        using var old = await client.GetAsync($"{Root}/{id}/versions/{versionId}"); Assert.Equal(HttpStatusCode.OK, old.StatusCode);
        var snapshot = (await old.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("snapshot"); Assert.Equal("Synthetic program", snapshot.GetProperty("title").GetString());
        Assert.Equal(1800.125m, snapshot.GetProperty("dailyWaterTargetMl").GetDecimal()); Assert.Equal(first.GetProperty("items").GetRawText(), snapshot.GetProperty("items").GetRawText());
        using var versions = await client.GetAsync($"{Root}/{id}/versions?page=1&pageSize=10"); Assert.Equal(2, (await versions.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("totalCount").GetInt32());
        using var empty = await client.PatchAsJsonAsync($"{Root}/{id}", new { }); Assert.Equal(HttpStatusCode.BadRequest, empty.StatusCode);
        using var nullItems = await client.PatchAsJsonAsync($"{Root}/{id}", new { items = (object?)null }); Assert.Equal(HttpStatusCode.UnprocessableEntity, nullItems.StatusCode);
        var other = await Create(client); using var wrongParent = await client.GetAsync($"{Root}/{other}/versions/{versionId}"); Assert.Equal(HttpStatusCode.NotFound, wrongParent.StatusCode);
    }

    [PostgresFact]
    public async Task ConcurrentActivationAndRawDatabaseWritesCannotCreateTwoActivePrograms()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var actor = await Seed(factory, UserRole.Client);
        using var first = await Client(factory, actor); using var second = await Client(factory, actor);
        var a = await Create(first); var b = await Create(first);
        var responses = await Task.WhenAll(first.PostAsync($"{Root}/{a}/activate", null), second.PostAsync($"{Root}/{b}/activate", null));
        try
        {
            Assert.Single(responses, x => x.StatusCode == HttpStatusCode.OK); var conflict = Assert.Single(responses, x => x.StatusCode == HttpStatusCode.Conflict);
            Assert.Equal("active_nutrition_plan_conflict", (await conflict.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("error").GetProperty("code").GetString());
        }
        finally { foreach (var response in responses) response.Dispose(); }
        await using var db = factory.Database(); var active = await db.NutritionPlans.SingleAsync(x => x.Status == NutritionPlanStatus.Active);
        var draft = await db.NutritionPlans.SingleAsync(x => x.Status == NutritionPlanStatus.Draft);
        var error = await Assert.ThrowsAsync<PostgresException>(() => db.NutritionPlans.Where(x => x.Id == draft.Id).ExecuteUpdateAsync(setters => setters.SetProperty(x => x.Status, NutritionPlanStatus.Active)));
        Assert.Equal(PostgresErrorCodes.UniqueViolation, error.SqlState);
        using var repeated = await first.PostAsync($"{Root}/{active.Id}/activate", null); Assert.Equal(HttpStatusCode.OK, repeated.StatusCode);
        using var archived = await first.PostAsync($"{Root}/{active.Id}/archive", null); using var archiveAgain = await first.PostAsync($"{Root}/{active.Id}/archive", null);
        Assert.Equal(await archived.Content.ReadAsStringAsync(), await archiveAgain.Content.ReadAsStringAsync());
        using var none = await first.GetAsync(Root + "/active"); Assert.Equal(HttpStatusCode.NotFound, none.StatusCode);
    }

    [PostgresFact]
    public async Task RelationshipEndArchivesOnlyTheAssignedActiveProgramAndKeepsClientHistoryReadable()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var c = await Seed(factory, UserRole.Client); var d = await Seed(factory, UserRole.Dietitian);
        using var client = await Client(factory, c); using var expert = await Client(factory, d); var relation = await Connect(client, expert, d.ProfileId);
        var personal = await Create(client); var assigned = await Create(expert, c.ProfileId);
        using var activation = await expert.PostAsync($"{Root}/{assigned}/activate", null); Assert.Equal(HttpStatusCode.OK, activation.StatusCode);
        using var end = await client.PostAsync($"/api/v1/dietitian-relationships/{relation.RelationshipId}/end", null); Assert.Equal(HttpStatusCode.OK, end.StatusCode);
        using var retained = await client.GetAsync($"{Root}/{assigned}"); var row = await retained.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal("archived", row.GetProperty("status").GetString()); Assert.Equal(d.ProfileId, row.GetProperty("dietitianId").GetGuid()); Assert.Equal(1, row.GetProperty("versionNumber").GetInt32());
        using var history = await client.GetAsync($"{Root}/{assigned}/versions?page=1&pageSize=10"); Assert.Equal(HttpStatusCode.OK, history.StatusCode);
        using var oldExpert = await expert.GetAsync($"{Root}/{assigned}"); Assert.Equal(HttpStatusCode.NotFound, oldExpert.StatusCode);
        using var personalRead = await client.GetAsync($"{Root}/{personal}"); Assert.Equal("draft", (await personalRead.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("status").GetString());
        using var personalActive = await client.PostAsync($"{Root}/{personal}/activate", null); Assert.Equal(HttpStatusCode.OK, personalActive.StatusCode);
    }

    [PostgresFact]
    public async Task RevokedPermissionBlocksReadsAndAWriteThatWasWaitingOnTheClientLock()
    {
        var pause = new PauseClientLock(); await using var factory = await RegistrationApiFactory.CreateAsync(interceptor: pause);
        var c = await Seed(factory, UserRole.Client); var d = await Seed(factory, UserRole.Dietitian);
        using var client = await Client(factory, c); using var expert = await Client(factory, d); var relation = await Connect(client, expert, d.ProfileId);
        var id = await Create(expert, c.ProfileId); pause.Armed = true;
        var writing = expert.PatchAsJsonAsync($"{Root}/{id}", new { title = "Synthetic stale edit" });
        await pause.Entered.Task.WaitAsync(TimeSpan.FromSeconds(10));
        using var revoked = await client.PatchAsJsonAsync($"/api/v1/data-sharing-permissions/{relation.PermissionId}", new { isGranted = false }); Assert.Equal(HttpStatusCode.OK, revoked.StatusCode);
        pause.Release.TrySetResult(); using var denied = await writing; Assert.Equal(HttpStatusCode.Forbidden, denied.StatusCode);
        using var blockedRead = await expert.GetAsync($"{Root}/{id}"); Assert.Equal(HttpStatusCode.Forbidden, blockedRead.StatusCode);
        using var own = await client.GetAsync($"{Root}/{id}"); Assert.Equal(HttpStatusCode.OK, own.StatusCode);
        Assert.Equal(1, (await own.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("versionNumber").GetInt32());
    }

    [PostgresFact]
    public async Task VersionInsertFailureRollsBackBothNewProgramAndCurrentRevision()
    {
        var failure = new WriteFailure(); await using var factory = await RegistrationApiFactory.CreateAsync(interceptor: failure);
        using var client = await Client(factory, await Seed(factory, UserRole.Client)); failure.Armed = true;
        using var failed = await client.PostAsJsonAsync(Root, Content()); Assert.Equal(HttpStatusCode.InternalServerError, failed.StatusCode);
        await using var db = factory.Database(); Assert.Empty(await db.NutritionPlans.ToListAsync()); Assert.Empty(await db.NutritionPlanVersions.ToListAsync());
        failure.Armed = false; var id = await Create(client); failure.Armed = true;
        using var revision = await client.PatchAsJsonAsync($"{Root}/{id}", new { title = "Synthetic rolled back revision" }); Assert.Equal(HttpStatusCode.InternalServerError, revision.StatusCode);
        var row = await db.NutritionPlans.AsNoTracking().SingleAsync(); Assert.Equal("Synthetic program", row.Title); Assert.Equal(1, row.VersionNumber); Assert.Single(await db.NutritionPlanVersions.ToListAsync());
    }

    [PostgresFact]
    public async Task EndingRelationshipAndArchivingItsProgramRollBackTogether()
    {
        var failure = new WriteFailure(); await using var factory = await RegistrationApiFactory.CreateAsync(interceptor: failure);
        var c = await Seed(factory, UserRole.Client); var d = await Seed(factory, UserRole.Dietitian);
        using var client = await Client(factory, c); using var expert = await Client(factory, d); var relation = await Connect(client, expert, d.ProfileId); var id = await Create(expert, c.ProfileId);
        using var activated = await expert.PostAsync($"{Root}/{id}/activate", null); Assert.Equal(HttpStatusCode.OK, activated.StatusCode);
        failure.Relationship = true; failure.Armed = true;
        using var ended = await client.PostAsync($"/api/v1/dietitian-relationships/{relation.RelationshipId}/end", null); Assert.Equal(HttpStatusCode.InternalServerError, ended.StatusCode);
        await using var db = factory.Database(); Assert.Equal(NutritionPlanStatus.Active, (await db.NutritionPlans.SingleAsync()).Status);
        Assert.Equal(RelationshipStatus.Active, (await db.DietitianClientRelationships.SingleAsync()).Status);
    }

    [PostgresFact]
    public async Task ItemsAlternativesAndServerOnlyFieldsAreValidatedWithoutExposingProgramContentInLogs()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); using var client = await Client(factory, await Seed(factory, UserRole.Client));
        var group = Guid.NewGuid(); var body = Content(); body["items"] = new[] { Item(0, group), Item(1, group) };
        using var valid = await client.PostAsJsonAsync(Root, body); Assert.Equal(HttpStatusCode.Created, valid.StatusCode);
        body["items"] = new[] { Item(0, group) }; using var single = await client.PostAsJsonAsync(Root, body); Assert.Equal(HttpStatusCode.UnprocessableEntity, single.StatusCode);
        body["items"] = new[] { Item(0, group), Item(1, group, 1) }; using var crossDay = await client.PostAsJsonAsync(Root, body); Assert.Equal(HttpStatusCode.UnprocessableEntity, crossDay.StatusCode);
        body["items"] = new[] { new { id = Guid.NewGuid(), mealType = "breakfast", description = "Synthetic private recommendation", sortOrder = 0 } };
        using var foreignItem = await client.PostAsJsonAsync(Root, body); Assert.Equal(HttpStatusCode.BadRequest, foreignItem.StatusCode);
        body["items"] = new[] { new { mealType = "breakfast", description = "Synthetic private recommendation", sortOrder = 0, recipeId = Guid.NewGuid() } };
        using var recipe = await client.PostAsJsonAsync(Root, body); Assert.Equal(HttpStatusCode.UnprocessableEntity, recipe.StatusCode);
        body = Content(); body["dailyWaterTargetMl"] = 0; using var zero = await client.PostAsJsonAsync(Root, body); Assert.Equal(HttpStatusCode.UnprocessableEntity, zero.StatusCode);
        body = Content(); body["dietitianId"] = Guid.NewGuid(); using var owner = await client.PostAsJsonAsync(Root, body); Assert.Equal(HttpStatusCode.BadRequest, owner.StatusCode);
        Assert.DoesNotContain("Synthetic private recommendation", factory.Logs);
    }

    [PostgresFact]
    public async Task CookieProgramMutationsCannotBypassCsrfOrExactOrigin()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(webSessions: true); var c = await Seed(factory, UserRole.Client);
        using var client = factory.Client(); var csrf = await Csrf(client);
        using var login = new HttpRequestMessage(HttpMethod.Post, "/api/v1/auth/web-session") { Content = JsonContent.Create(new { email = c.Email, password = Password }) };
        login.Headers.Add("Origin", "https://localhost"); login.Headers.Add("X-CSRF-TOKEN", csrf);
        using var signedIn = await client.SendAsync(login); Assert.Equal(HttpStatusCode.OK, signedIn.StatusCode);
        using var noOrigin = await client.PostAsJsonAsync(Root, Content()); Assert.Equal(HttpStatusCode.Forbidden, noOrigin.StatusCode);
        using var missing = new HttpRequestMessage(HttpMethod.Post, Root) { Content = JsonContent.Create(Content()) }; missing.Headers.Add("Origin", "https://localhost");
        using var noCsrf = await client.SendAsync(missing); Assert.Equal(HttpStatusCode.BadRequest, noCsrf.StatusCode);
        using var good = new HttpRequestMessage(HttpMethod.Post, Root) { Content = JsonContent.Create(Content()) }; good.Headers.Add("Origin", "https://localhost"); good.Headers.Add("X-CSRF-TOKEN", await Csrf(client));
        using var created = await client.SendAsync(good); Assert.Equal(HttpStatusCode.Created, created.StatusCode);
    }

    private static object Item(int order, Guid? group = null, int? day = null) => new { dayOfWeek = day, mealType = "breakfast", description = "Synthetic private recommendation", recommendedQuantity = " 1 synthetic portion ", sortOrder = order, recipeId = (Guid?)null, alternativeGroupId = group };
    private static Dictionary<string, object?> Content(Guid? clientId = null)
    {
        var body = new Dictionary<string, object?> { ["title"] = "Synthetic program", ["startDate"] = "2026-10-29", ["endDate"] = null,
            ["dailyCaloriesTargetKcal"] = null, ["dailyWaterTargetMl"] = null, ["items"] = new[] { Item(0) } };
        if (clientId is not null) body["clientId"] = clientId; return body;
    }
    private static async Task<Guid> Create(HttpClient client, Guid? target = null)
    { using var response = await client.PostAsJsonAsync(Root, Content(target)); Assert.Equal(HttpStatusCode.Created, response.StatusCode); return (await response.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid(); }
    private static async Task<(Guid RelationshipId, Guid PermissionId)> Connect(HttpClient client, HttpClient expert, Guid expertId)
    {
        using var request = await client.PostAsJsonAsync("/api/v1/dietitian-relationships", new { dietitianId = expertId }); Assert.Equal(HttpStatusCode.Created, request.StatusCode);
        var id = (await request.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid();
        using var accepted = await expert.PostAsync($"/api/v1/dietitian-relationships/{id}/accept", null); Assert.Equal(HttpStatusCode.OK, accepted.StatusCode);
        using var permission = await client.PostAsJsonAsync("/api/v1/data-sharing-permissions", new { relationshipId = id, category = "nutrition_plans", isGranted = true }); Assert.Equal(HttpStatusCode.Created, permission.StatusCode);
        return (id, (await permission.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid());
    }
    private static async Task<Actor> Seed(RegistrationApiFactory factory, UserRole role)
    {
        await using var db = factory.Database(); var email = Guid.NewGuid().ToString("N") + "@example.test";
        var user = new User(Guid.NewGuid(), email.ToUpperInvariant(), role, Password, DateTimeOffset.UtcNow, new PasswordHasher<User>()); Guid profileId;
        if (role == UserRole.Client) profileId = new ClientProfile(Guid.NewGuid(), user, "Synthetic client").Id;
        else { var profile = new DietitianProfile(user, "Synthetic expert", "Synthetic license"); profileId = profile.Id; db.Entry(profile).Property(x => x.IsVerified).CurrentValue = true; }
        db.Users.Add(user); db.Entry(user).Property(x => x.IsEmailVerified).CurrentValue = true; await db.SaveChangesAsync(); return new(user.Id, profileId, email, role);
    }
    private static async Task<HttpClient> Client(RegistrationApiFactory factory, Actor actor)
    {
        await using var db = factory.Database(); var user = await db.Users.SingleAsync(x => x.Id == actor.UserId);
        var jwt = new JwtAccessTokenService(Options.Create(factory.Jwt.Options), TimeProvider.System).Issue(user); var client = factory.Client(false);
        client.DefaultRequestHeaders.Authorization = new("Bearer", jwt.AccessToken); return client;
    }
    private static async Task<string> Csrf(HttpClient client)
    { using var response = await client.GetAsync("/api/v1/auth/csrf"); return (await response.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("requestToken").GetString()!; }
    private sealed class WriteFailure : DbCommandInterceptor
    {
        public bool Armed { get; set; } public bool Relationship { get; set; }
        public override ValueTask<InterceptionResult<DbDataReader>> ReaderExecutingAsync(DbCommand command, CommandEventData eventData, InterceptionResult<DbDataReader> result, CancellationToken cancellationToken = default)
        {
            if (Armed && command.CommandText.Contains(Relationship ? "UPDATE dietitian_client_relationships" : "INSERT INTO nutrition_plan_versions")) throw new InvalidOperationException("Synthetic program write failure");
            return base.ReaderExecutingAsync(command, eventData, result, cancellationToken);
        }
    }
    private sealed class PauseClientLock : DbCommandInterceptor
    {
        public bool Armed { get; set; } private int _paused;
        public TaskCompletionSource Entered { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public TaskCompletionSource Release { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public override async ValueTask<InterceptionResult<DbDataReader>> ReaderExecutingAsync(DbCommand command, CommandEventData eventData, InterceptionResult<DbDataReader> result, CancellationToken cancellationToken = default)
        {
            if (Armed && command.CommandText.Contains("client_profiles") && command.CommandText.Contains("FOR UPDATE") && Interlocked.Exchange(ref _paused, 1) == 0)
            { Entered.TrySetResult(); await Release.Task.WaitAsync(TimeSpan.FromSeconds(15), cancellationToken); }
            return result;
        }
    }
}
