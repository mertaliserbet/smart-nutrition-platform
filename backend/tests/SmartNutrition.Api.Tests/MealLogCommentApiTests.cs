using System.Data.Common;
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Microsoft.Extensions.Options;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Features.Dietitians;
using SmartNutrition.Api.Features.MealLogs;
using SmartNutrition.Api.Features.Relationships;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Tests;

public sealed class MealLogCommentApiTests
{
    private const string Password = "Synthetic comment password";
    private const string Text = "Synthetic private meal comment";
    private const string Migration = "20261118180743_AddMealLogComments";
    private sealed record Pair(User Owner, ClientProfile Client, User Expert, DietitianProfile Profile, DietitianClientRelationship Relationship, DataSharingPermission Permission);
    private static string Route(Guid meal) => $"/api/v1/meal-logs/{meal}/comments";
    private static string List(Guid meal) => Route(meal) + "?page=1&pageSize=10";

    [PostgresFact]
    public async Task ExpertRootAndMultipleClientRepliesRoundTripWithServerIdentityAndPaging()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory);
        using var owner = Bearer(factory, pair.Owner, "client"); using var expert = Bearer(factory, pair.Expert);
        var meal = await Meal(owner);
        var empty = await owner.GetFromJsonAsync<JsonElement>(List(meal)); Assert.Equal(0, empty.GetProperty("totalCount").GetInt32());
        var root = await Create(expert, meal, "  " + Text + "  ");
        Assert.Equal(Text, root.Text); Assert.Equal(pair.Expert.Id, root.AuthorUserId); Assert.Null(root.ParentCommentId);
        Assert.Equal(TimeSpan.Zero, root.CreatedAt.Offset);
        var first = await Create(owner, meal, Text, root.Id); var second = await Create(owner, meal, Text, root.Id);
        Assert.Equal(pair.Owner.Id, first.AuthorUserId); Assert.Equal(root.Id, second.ParentCommentId);
        var all = await owner.GetFromJsonAsync<JsonElement>(List(meal)); Assert.Equal(3, all.GetProperty("totalCount").GetInt32());
        Assert.Equal(new[] { "authorUserId", "createdAt", "id", "mealLogId", "parentCommentId", "text" }, all.GetProperty("items")[0].EnumerateObject().Select(x => x.Name).Order());
        await using (var db = factory.Database())
            await db.MealLogComments.Where(x => x.MealLogId == meal).ExecuteUpdateAsync(x => x.SetProperty(p => p.CreatedAt, DateTimeOffset.Parse("2026-11-18T00:00:00Z")));
        var expected = new[] { root.Id, first.Id, second.Id }.Order().ToArray();
        for (var page = 1; page <= 4; page++)
        {
            using var response = await expert.GetAsync(Route(meal) + $"?page={page}&pageSize=1"); Assert.Equal(HttpStatusCode.OK, response.StatusCode);
            Assert.Contains("no-store", response.Headers.CacheControl!.ToString());
            var body = await response.Content.ReadFromJsonAsync<JsonElement>(); Assert.Equal(3, body.GetProperty("totalCount").GetInt32());
            var ids = body.GetProperty("items").EnumerateArray().Select(x => x.GetProperty("id").GetGuid()).ToArray();
            Assert.Equal(page <= 3 ? [expected[page - 1]] : Array.Empty<Guid>(), ids);
        }
        Assert.DoesNotContain(Text, factory.Logs);
    }

    [PostgresFact]
    public async Task OnlyExpertRootsAndOwnerRepliesToSameMealRootsAreAccepted()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory);
        using var owner = Bearer(factory, pair.Owner, "client"); using var expert = Bearer(factory, pair.Expert);
        var meal = await Meal(owner); var otherMeal = await Meal(owner); var root = await Create(expert, meal, Text);
        using var ownerRoot = await owner.PostAsJsonAsync(Route(meal), new { text = Text }); await Error(ownerRoot, HttpStatusCode.Forbidden);
        using var expertReply = await expert.PostAsJsonAsync(Route(meal), new { text = Text, parentCommentId = root.Id }); await Error(expertReply, HttpStatusCode.Forbidden);
        var reply = await Create(owner, meal, Text, root.Id);
        using var deep = await owner.PostAsJsonAsync(Route(meal), new { text = Text, parentCommentId = reply.Id }); await Error(deep, HttpStatusCode.UnprocessableEntity);
        foreach (var parent in new[] { root.Id, Guid.NewGuid() })
        { using var foreignParent = await owner.PostAsJsonAsync(Route(otherMeal), new { text = Text, parentCommentId = parent }); await Error(foreignParent, HttpStatusCode.NotFound); }
    }

    [PostgresFact]
    public async Task TextUsesUnicodeScalarLimitTrimAndSharedValidationErrors()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory);
        using var owner = Bearer(factory, pair.Owner, "client"); using var expert = Bearer(factory, pair.Expert); var meal = await Meal(owner);
        var emojis = string.Concat(Enumerable.Repeat("🥣", 2000)); Assert.Equal(emojis, (await Create(expert, meal, "\t" + emojis + "\n")).Text);
        foreach (var text in new string?[] { null, "", " \t\n\u00a0", new('x', 2001), emojis + "x", "bad\0text" })
        { using var invalid = await expert.PostAsJsonAsync(Route(meal), new { text }); await Error(invalid, HttpStatusCode.UnprocessableEntity); }
        foreach (var body in new object[] { new { }, new { text = Text, authorUserId = pair.Owner.Id }, new { text = Text, clientId = pair.Client.Id } })
        { using var invalid = await expert.PostAsJsonAsync(Route(meal), body); await Error(invalid, HttpStatusCode.BadRequest); }
        using var emptyParent = await owner.PostAsJsonAsync(Route(meal), new { text = Text, parentCommentId = Guid.Empty }); await Error(emptyParent, HttpStatusCode.UnprocessableEntity);
    }

    [PostgresFact]
    public async Task WithdrawalAndEndedRelationshipBlockExpertButKeepOwnerHistoryAndReplies()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory);
        using var owner = Bearer(factory, pair.Owner, "client"); using var expert = Bearer(factory, pair.Expert); var meal = await Meal(owner);
        var root = await Create(expert, meal, Text);
        using var revoke = await owner.PatchAsJsonAsync($"/api/v1/data-sharing-permissions/{pair.Permission.Id}", new { isGranted = false }); Assert.Equal(HttpStatusCode.OK, revoke.StatusCode);
        using var read = await expert.GetAsync(List(meal)); await Error(read, HttpStatusCode.Forbidden);
        using var write = await expert.PostAsJsonAsync(Route(meal), new { text = Text }); await Error(write, HttpStatusCode.Forbidden);
        await Create(owner, meal, Text, root.Id);
        using var end = await owner.PostAsync($"/api/v1/dietitian-relationships/{pair.Relationship.Id}/end", null); Assert.Equal(HttpStatusCode.OK, end.StatusCode);
        using var after = await expert.GetAsync(List(meal)); await Error(after, HttpStatusCode.NotFound);
        using var afterWrite = await expert.PostAsJsonAsync(Route(meal), new { text = Text }); await Error(afterWrite, HttpStatusCode.NotFound);
        await Create(owner, meal, Text, root.Id);
        var history = await owner.GetFromJsonAsync<JsonElement>(List(meal)); Assert.Equal(3, history.GetProperty("totalCount").GetInt32());
    }

    [PostgresFact]
    public async Task UnrelatedClientsExpertsAndHeaderSpoofingCannotReadOrWrite()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory); var stranger = await Seed(factory);
        using var owner = Bearer(factory, pair.Owner, "client"); var meal = await Meal(owner);
        foreach (var client in new[] { Bearer(factory, stranger.Owner, "client"), Bearer(factory, stranger.Expert) })
        { using (client) { using var read = await client.GetAsync(List(meal)); await Error(read, HttpStatusCode.NotFound); using var write = await client.PostAsJsonAsync(Route(meal), new { text = Text }); await Error(write, HttpStatusCode.NotFound); } }
        using var forged = Bearer(factory, pair.Owner); using var spoofed = await forged.GetAsync(List(meal)); await Error(spoofed, HttpStatusCode.Forbidden);
        using var expert = Bearer(factory, pair.Expert);
        await using (var db = factory.Database()) await db.DietitianProfiles.Where(x => x.Id == pair.Profile.Id).ExecuteUpdateAsync(x => x.SetProperty(p => p.IsVerified, false));
        using var unapproved = await expert.PostAsJsonAsync(Route(meal), new { text = Text }); await Error(unapproved, HttpStatusCode.Forbidden);
        using var anonymous = factory.Client(false); using var unauthenticated = await anonymous.GetAsync(List(meal)); await Error(unauthenticated, HttpStatusCode.Unauthorized);
        await using (var db = factory.Database()) await db.Users.Where(x => x.Id == pair.Expert.Id).ExecuteUpdateAsync(x => x.SetProperty(p => p.IsEmailVerified, false));
        using var stale = await expert.GetAsync(List(meal)); await Error(stale, HttpStatusCode.Unauthorized);
    }

    [PostgresFact]
    public async Task NewExpertNeedsTheirOwnGrantToSeePriorCommentHistory()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory); var next = await Seed(factory);
        using var owner = Bearer(factory, pair.Owner, "client"); using var first = Bearer(factory, pair.Expert); using var expert = Bearer(factory, next.Expert);
        var meal = await Meal(owner); var root = await Create(first, meal, Text); await Create(owner, meal, Text, root.Id);
        using var ended = await owner.PostAsync($"/api/v1/dietitian-relationships/{pair.Relationship.Id}/end", null); Assert.Equal(HttpStatusCode.OK, ended.StatusCode);
        var now = DateTimeOffset.UtcNow; var relation = new DietitianClientRelationship(pair.Client.Id, next.Profile.Id, now); relation.Respond(RelationshipStatus.Active, now);
        await using (var db = factory.Database()) { db.DietitianClientRelationships.Add(relation); db.DataSharingPermissions.Add(new DataSharingPermission(relation.Id, true, now)); await db.SaveChangesAsync(); }
        using var noMealGrant = await expert.GetAsync(List(meal)); await Error(noMealGrant, HttpStatusCode.Forbidden);
        await using (var db = factory.Database()) { db.DataSharingPermissions.Add(new DataSharingPermission(relation.Id, true, now, "meal_logs")); await db.SaveChangesAsync(); }
        var page = await expert.GetFromJsonAsync<JsonElement>(List(meal)); Assert.Equal(2, page.GetProperty("totalCount").GetInt32());
        Assert.Contains(page.GetProperty("items").EnumerateArray(), item => item.GetProperty("id").GetGuid() == root.Id);
        using var oldExpert = await first.GetAsync(List(meal)); await Error(oldExpert, HttpStatusCode.NotFound);
    }

    [PostgresFact]
    public async Task MissingPermissionPendingRelationshipAndAdminCannotAccessComments()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(webSessions: true); var pair = await Seed(factory);
        using var owner = Bearer(factory, pair.Owner, "client"); using var expert = Bearer(factory, pair.Expert); var meal = await Meal(owner);
        await using (var db = factory.Database()) await db.DataSharingPermissions.Where(x => x.Id == pair.Permission.Id).ExecuteDeleteAsync();
        using var missing = await expert.GetAsync(List(meal)); await Error(missing, HttpStatusCode.Forbidden);
        await using (var db = factory.Database()) await db.DietitianClientRelationships.Where(x => x.Id == pair.Relationship.Id).ExecuteUpdateAsync(x => x.SetProperty(p => p.Status, RelationshipStatus.Pending));
        using var pending = await expert.PostAsJsonAsync(Route(meal), new { text = Text }); await Error(pending, HttpStatusCode.NotFound);
        var admin = new User(Guid.NewGuid(), Guid.NewGuid().ToString("N") + "@EXAMPLE.TEST", UserRole.Admin, Password, DateTimeOffset.UtcNow, new PasswordHasher<User>());
        using var scope = factory.Services.CreateScope(); var setup = scope.ServiceProvider.GetRequiredService<AdminMfaService>().Initialize(admin, DateTimeOffset.UtcNow);
        await using (var db = factory.Database()) { db.Users.Add(admin); db.Entry(admin).Property(x => x.IsEmailVerified).CurrentValue = true; await db.SaveChangesAsync(); }
        using var administrator = factory.Client(); var csrf = await administrator.GetFromJsonAsync<JsonElement>("/api/v1/auth/csrf");
        using var login = new HttpRequestMessage(HttpMethod.Post, "/api/v1/auth/admin-web-session") { Content = JsonContent.Create(new { email = admin.Email, password = Password, mfaCode = setup.RecoveryCodes[0] }) };
        login.Headers.Add("Origin", "https://localhost"); login.Headers.Add("X-CSRF-TOKEN", csrf.GetProperty("requestToken").GetString());
        using var signedIn = await administrator.SendAsync(login); Assert.Equal(HttpStatusCode.OK, signedIn.StatusCode);
        administrator.DefaultRequestHeaders.Add("Origin", "https://localhost");
        using var adminRead = await administrator.GetAsync(List(meal)); await Error(adminRead, HttpStatusCode.Forbidden);
        using var adminWrite = await administrator.PostAsJsonAsync(Route(meal), new { text = Text }); await Error(adminWrite, HttpStatusCode.Forbidden);
    }

    [PostgresFact]
    public async Task DeletedMealsHideCommentsAndUnsupportedMethodsRemainUnavailable()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory);
        using var owner = Bearer(factory, pair.Owner, "client"); using var expert = Bearer(factory, pair.Expert); var meal = await Meal(owner); var root = await Create(expert, meal, Text);
        foreach (var method in new[] { HttpMethod.Patch, HttpMethod.Delete })
        { using var request = new HttpRequestMessage(method, Route(meal)); using var response = await expert.SendAsync(request); Assert.Equal(HttpStatusCode.MethodNotAllowed, response.StatusCode); }
        using var deleted = await owner.DeleteAsync($"/api/v1/meal-logs/{meal}"); Assert.Equal(HttpStatusCode.NoContent, deleted.StatusCode);
        foreach (var actor in new[] { owner, expert })
        { using var read = await actor.GetAsync(List(meal)); await Error(read, HttpStatusCode.NotFound); using var write = await actor.PostAsJsonAsync(Route(meal), new { text = Text, parentCommentId = actor == owner ? root.Id : (Guid?)null }); await Error(write, HttpStatusCode.NotFound); }
        await using var db = factory.Database(); Assert.Equal(1, await db.MealLogComments.CountAsync());
    }

    [PostgresFact]
    public async Task StrictPaginationAndQueryBodiesAreValidated()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory);
        using var owner = Bearer(factory, pair.Owner, "client"); var meal = await Meal(owner);
        foreach (var query in new[] { "", "?page=1", "?page=0&pageSize=10", "?page=1&pageSize=101", "?page=2147483647&pageSize=100", "?page=1&page=2&pageSize=10", "?page=1&pageSize=10&clientId=" + pair.Client.Id })
        { using var invalid = await owner.GetAsync(Route(meal) + query); await Error(invalid, HttpStatusCode.BadRequest); }
        using var body = new HttpRequestMessage(HttpMethod.Get, List(meal)) { Content = JsonContent.Create(new { }) };
        using var withBody = await owner.SendAsync(body); await Error(withBody, HttpStatusCode.BadRequest);
        using var queryWrite = await owner.PostAsJsonAsync(Route(meal) + "?page=1", new { text = Text }); await Error(queryWrite, HttpStatusCode.BadRequest);
    }

    [PostgresFact]
    public async Task DualProfileWebCookieRequiresOriginAndSessionBoundCsrf()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(webSessions: true); var pair = await Seed(factory, dual: true);
        using var owner = Bearer(factory, pair.Owner, "client"); var meal = await Meal(owner); using var web = factory.Client();
        var csrf = await web.GetFromJsonAsync<JsonElement>("/api/v1/auth/csrf");
        using var login = new HttpRequestMessage(HttpMethod.Post, "/api/v1/auth/web-session") { Content = JsonContent.Create(new { email = pair.Expert.Email, password = Password }) };
        login.Headers.Add("Origin", "https://localhost"); login.Headers.Add("X-CSRF-TOKEN", csrf.GetProperty("requestToken").GetString());
        using var signedIn = await web.SendAsync(login); Assert.Equal(HttpStatusCode.OK, signedIn.StatusCode);
        web.DefaultRequestHeaders.Add("X-Profile-Context", "dietitian");
        using var noOrigin = await web.PostAsJsonAsync(Route(meal), new { text = Text }); await Error(noOrigin, HttpStatusCode.Forbidden);
        web.DefaultRequestHeaders.Add("Origin", "https://localhost");
        using var noCsrf = await web.PostAsJsonAsync(Route(meal), new { text = Text }); await Error(noCsrf, HttpStatusCode.BadRequest);
        csrf = await web.GetFromJsonAsync<JsonElement>("/api/v1/auth/csrf"); web.DefaultRequestHeaders.Add("X-CSRF-TOKEN", csrf.GetProperty("requestToken").GetString());
        var root = await Create(web, meal, Text); Assert.Equal(pair.Expert.Id, root.AuthorUserId);
        using var read = await web.GetAsync(List(meal)); Assert.Equal(HttpStatusCode.OK, read.StatusCode);
        web.DefaultRequestHeaders.Remove("Origin"); web.DefaultRequestHeaders.Add("Origin", "https://foreign.example.test");
        using var foreignOrigin = await web.GetAsync(List(meal)); await Error(foreignOrigin, HttpStatusCode.Forbidden);
        web.DefaultRequestHeaders.Remove("Origin"); web.DefaultRequestHeaders.Add("Origin", "https://localhost"); web.DefaultRequestHeaders.Authorization = new("Bearer", "synthetic.ambiguous.credentials");
        using var mixed = await web.GetAsync(List(meal)); await Error(mixed, HttpStatusCode.BadRequest);
    }

    [PostgresFact]
    public async Task WriteWaitingOnClientLockRechecksRevokedPermission()
    {
        var pause = new ClientLockPause(); await using var factory = await RegistrationApiFactory.CreateAsync(interceptor: pause);
        var pair = await Seed(factory); using var owner = Bearer(factory, pair.Owner, "client"); using var expert = Bearer(factory, pair.Expert); var meal = await Meal(owner);
        pause.Armed = true; var pending = expert.PostAsJsonAsync(Route(meal), new { text = Text });
        try { await pause.Entered.Task.WaitAsync(TimeSpan.FromSeconds(15)); using var revoke = await owner.PatchAsJsonAsync($"/api/v1/data-sharing-permissions/{pair.Permission.Id}", new { isGranted = false }); Assert.Equal(HttpStatusCode.OK, revoke.StatusCode); }
        finally { pause.Release.TrySetResult(); }
        using var denied = await pending; await Error(denied, HttpStatusCode.Forbidden);
        await using var db = factory.Database(); Assert.Empty(await db.MealLogComments.ToListAsync());
    }

    [PostgresFact]
    public async Task MigrationPreservesExistingRowsAndRefusesToDropNonemptyComments()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory);
        using var owner = Bearer(factory, pair.Owner, "client"); using var expert = Bearer(factory, pair.Expert); var meal = await Meal(owner);
        await using (var db = factory.Database())
        {
            var migrator = db.GetService<IMigrator>();
            await migrator.MigrateAsync("20261118122704_AddBodyMeasurementSharingCategory");
            var before = await Fingerprint(db);
            await migrator.MigrateAsync(Migration);
            Assert.Equal(before, await Fingerprint(db));
        }
        var root = await Create(expert, meal, Text);
        await using (var db = factory.Database())
        {
            await Assert.ThrowsAsync<PostgresException>(() => db.GetService<IMigrator>().MigrateAsync("20261118122704_AddBodyMeasurementSharingCategory"));
            Assert.Equal(root.Id, (await db.MealLogComments.SingleAsync()).Id);
        }
        var otherMeal = await Meal(owner);
        await using (var db = factory.Database())
        {
            db.MealLogComments.Add(new MealLogComment(otherMeal, pair.Owner.Id, Text, DateTimeOffset.UtcNow, root.Id));
            var error = await Assert.ThrowsAsync<DbUpdateException>(() => db.SaveChangesAsync());
            Assert.Equal(PostgresErrorCodes.ForeignKeyViolation, Assert.IsType<PostgresException>(error.InnerException).SqlState);
        }
    }

    private static async Task<string> Fingerprint(SmartNutrition.Api.Data.AppDbContext db)
    {
        await db.Database.OpenConnectionAsync(); await using var command = db.Database.GetDbConnection().CreateCommand();
        command.CommandText = """
            CREATE TEMP TABLE comment_snapshot (name text, digest text);
            DO $$ DECLARE r record; h text; BEGIN
              FOR r IN SELECT tablename FROM pg_tables WHERE schemaname=current_schema() AND tablename NOT IN ('__ef_migrations_history','meal_log_comments') ORDER BY tablename LOOP
                EXECUTE format('SELECT md5(coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text)::text,''[]'')) FROM %I t',r.tablename) INTO h;
                INSERT INTO comment_snapshot VALUES(r.tablename,h);
              END LOOP;
            END $$;
            SELECT jsonb_agg(jsonb_build_object('table',name,'hash',digest) ORDER BY name)::text FROM comment_snapshot;
            DROP TABLE comment_snapshot;
            """;
        return (string)(await command.ExecuteScalarAsync())!;
    }
    private static async Task<Pair> Seed(RegistrationApiFactory factory, bool dual = false)
    {
        await using var db = factory.Database(); var now = DateTimeOffset.UtcNow;
        var owner = new User(Guid.NewGuid(), Guid.NewGuid().ToString("N") + "@EXAMPLE.TEST", UserRole.Client, Password, now, new PasswordHasher<User>());
        var client = new ClientProfile(Guid.NewGuid(), owner, "Synthetic comment client");
        var expert = new User(Guid.NewGuid(), Guid.NewGuid().ToString("N") + "@EXAMPLE.TEST", dual ? UserRole.Client : UserRole.Dietitian, Password, now, new PasswordHasher<User>());
        var profile = new DietitianProfile(expert, "Synthetic comment expert", "Synthetic license"); if (dual) _ = new ClientProfile(Guid.NewGuid(), expert, "Synthetic dual account");
        db.Users.AddRange(owner, expert); db.Entry(owner).Property(x => x.IsEmailVerified).CurrentValue = true; db.Entry(expert).Property(x => x.IsEmailVerified).CurrentValue = true; db.Entry(profile).Property(x => x.IsVerified).CurrentValue = true;
        var relationship = new DietitianClientRelationship(client.Id, profile.Id, now); relationship.Respond(RelationshipStatus.Active, now);
        var permission = new DataSharingPermission(relationship.Id, true, now, "meal_logs");
        db.DietitianClientRelationships.Add(relationship); db.DataSharingPermissions.Add(permission); await db.SaveChangesAsync(); return new(owner, client, expert, profile, relationship, permission);
    }
    private static HttpClient Bearer(RegistrationApiFactory factory, User user, string context = "dietitian")
    {
        var client = factory.Client(false); var jwt = new JwtAccessTokenService(Options.Create(factory.Jwt.Options), TimeProvider.System).Issue(user);
        client.DefaultRequestHeaders.Authorization = new("Bearer", jwt.AccessToken); client.DefaultRequestHeaders.Add("X-Profile-Context", context); return client;
    }
    private static async Task<Guid> Meal(HttpClient owner)
    {
        using var response = await owner.PostAsJsonAsync("/api/v1/meal-logs", new { mealType = "lunch", consumedAt = "2026-11-18T12:00:00Z", source = "manual", items = new[] { new { displayName = "Synthetic meal", isEstimated = false } } });
        Assert.Equal(HttpStatusCode.Created, response.StatusCode); return (await response.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid();
    }
    private static async Task<MealLogCommentResponse> Create(HttpClient actor, Guid meal, string text, Guid? parent = null)
    {
        using var response = await actor.PostAsJsonAsync(Route(meal), new { text, parentCommentId = parent });
        Assert.Equal(HttpStatusCode.Created, response.StatusCode); return (await response.Content.ReadFromJsonAsync<MealLogCommentResponse>())!;
    }
    private static async Task Error(HttpResponseMessage response, HttpStatusCode status)
    {
        Assert.Equal(status, response.StatusCode); var content = await response.Content.ReadAsStringAsync(); var body = JsonSerializer.Deserialize<JsonElement>(content);
        Assert.True(body.TryGetProperty("error", out _)); Assert.False(string.IsNullOrWhiteSpace(body.GetProperty("requestId").GetString())); Assert.DoesNotContain(Text, content);
        Assert.False(body.TryGetProperty("items", out _)); Assert.False(body.TryGetProperty("text", out _));
    }
    private sealed class ClientLockPause : DbCommandInterceptor
    {
        public bool Armed { get; set; }
        public TaskCompletionSource Entered { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public TaskCompletionSource Release { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public override async ValueTask<InterceptionResult<DbDataReader>> ReaderExecutingAsync(DbCommand command, CommandEventData eventData, InterceptionResult<DbDataReader> result, CancellationToken cancellationToken = default)
        {
            if (Armed && command.CommandText.Contains("FROM client_profiles", StringComparison.Ordinal) && command.CommandText.Contains("FOR UPDATE", StringComparison.Ordinal))
            { Armed = false; Entered.TrySetResult(); await Release.Task.WaitAsync(TimeSpan.FromSeconds(15), cancellationToken); }
            return result;
        }
    }
}
