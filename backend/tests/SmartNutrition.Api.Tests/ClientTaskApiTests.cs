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
using SmartNutrition.Api.Features.ClientTasks;
using SmartNutrition.Api.Features.Dietitians;
using SmartNutrition.Api.Features.Relationships;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Tests;

public sealed class ClientTaskApiTests
{
    private const string Route = "/api/v1/client-tasks";
    private const string Password = "Synthetic task password";
    private const string Description = "Synthetic private task description";
    private const string PreviousMigration = "20261118180743_AddMealLogComments";
    private sealed record Pair(User Owner, ClientProfile Client, User Expert, DietitianProfile Profile, DietitianClientRelationship Relationship, DataSharingPermission Permission);
    private static string Detail(Guid id) => $"{Route}/{id}";
    private static string History(Guid id) => Detail(id) + "/versions?page=1&pageSize=100";
    private static string List(Guid? client = null) => Route + "?page=1&pageSize=100" + (client is null ? "" : "&clientId=" + client);

    [PostgresFact]
    public async Task CreateListDetailAndImmutableHistoryUseExactContractAndServerOwnership()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory);
        using var owner = Bearer(factory, pair.Owner, "client"); using var expert = Bearer(factory, pair.Expert);
        Assert.Equal(0, (await owner.GetFromJsonAsync<JsonElement>(List())).GetProperty("totalCount").GetInt32());
        var due = DateTimeOffset.UtcNow.AddDays(3).ToOffset(TimeSpan.FromHours(3));
        var task = await Create(expert, pair, "  " + Description + "  ", due);
        Assert.Equal(pair.Client.Id, task.ClientId); Assert.Equal(pair.Profile.Id, task.DietitianId); Assert.Equal(pair.Relationship.Id, task.RelationshipId);
        Assert.Equal(Description, task.Description); Assert.Equal(ClientTaskStatus.Pending, task.Status); Assert.Equal(1, task.VersionNumber);
        Assert.False(task.IsReminderEnabled); Assert.Equal(task.CreatedAt, task.UpdatedAt); Assert.Equal(TimeSpan.Zero, task.DueAt!.Value.Offset);
        using var read = await owner.GetAsync(Detail(task.Id)); Assert.Equal(HttpStatusCode.OK, read.StatusCode); Assert.Contains("no-store", read.Headers.CacheControl!.ToString());
        var body = await read.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal(new[] { "clientId", "createdAt", "description", "dietitianId", "dueAt", "id", "isReminderEnabled", "relationshipId", "status", "updatedAt", "versionNumber" }, body.EnumerateObject().Select(x => x.Name).Order());
        var second = await Create(expert, pair); Assert.Null(second.DueAt);
        var all = await expert.GetFromJsonAsync<JsonElement>(List(pair.Client.Id)); Assert.Equal(2, all.GetProperty("totalCount").GetInt32());
        var page = await owner.GetFromJsonAsync<JsonElement>(Route + "?page=3&pageSize=1"); Assert.Equal(2, page.GetProperty("totalCount").GetInt32()); Assert.Empty(page.GetProperty("items").EnumerateArray());
        var updated = await Patch(expert, task, new { expectedVersionNumber = 1, description = "Synthetic edited task" });
        Assert.Equal(2, updated.VersionNumber);
        var history = await owner.GetFromJsonAsync<JsonElement>(History(task.Id)); Assert.Equal(2, history.GetProperty("totalCount").GetInt32());
        Assert.Equal(Description, history.GetProperty("items")[1].GetProperty("snapshot").GetProperty("description").GetString());
        Assert.False(history.GetProperty("items")[0].TryGetProperty("recordedByUserId", out _));
        await using var db = factory.Database(); var version = await db.ClientTaskVersions.FirstAsync(x => x.ClientTaskId == task.Id);
        db.Entry(version).Property(x => x.SnapshotJson).CurrentValue = "{}";
        await Assert.ThrowsAsync<InvalidOperationException>(() => db.SaveChangesAsync());
        Assert.DoesNotContain(Description, factory.Logs);
    }

    [PostgresFact]
    public async Task ClientTransitionsReminderAndCompletionTimeAreRecordedWithoutDeliveryClaims()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory);
        using var owner = Bearer(factory, pair.Owner, "client"); using var expert = Bearer(factory, pair.Expert);
        var task = await Create(expert, pair, due: DateTimeOffset.UtcNow.AddDays(1));
        task = await Patch(owner, task, new { expectedVersionNumber = 1, status = "in_progress", isReminderEnabled = true });
        Assert.True(task.IsReminderEnabled); Assert.Equal(ClientTaskStatus.InProgress, task.Status);
        using var backwards = await owner.PatchAsJsonAsync(Detail(task.Id), new { expectedVersionNumber = 2, status = "pending" }); await Error(backwards, HttpStatusCode.Conflict);
        task = await Patch(expert, task, new { expectedVersionNumber = 2, dueAt = (string?)null }); Assert.False(task.IsReminderEnabled); Assert.Null(task.DueAt);
        using var noDeadline = await owner.PatchAsJsonAsync(Detail(task.Id), new { expectedVersionNumber = 3, isReminderEnabled = true }); await Error(noDeadline, HttpStatusCode.UnprocessableEntity);
        task = await Patch(owner, task, new { expectedVersionNumber = 3, status = "completed" });
        Assert.Equal(ClientTaskStatus.Completed, task.Status);
        foreach (var actor in new[] { owner, expert })
        { using var closed = await actor.PatchAsJsonAsync(Detail(task.Id), new { expectedVersionNumber = 4, status = "pending" }); await Error(closed, HttpStatusCode.Conflict); }
        var history = await owner.GetFromJsonAsync<JsonElement>(History(task.Id));
        Assert.Equal(4, history.GetProperty("totalCount").GetInt32());
        Assert.Equal(task.UpdatedAt, history.GetProperty("items")[0].GetProperty("createdAt").GetDateTimeOffset());
        Assert.Equal("completed", history.GetProperty("items")[0].GetProperty("snapshot").GetProperty("status").GetString());
        using var noDelete = await owner.DeleteAsync(Detail(task.Id)); Assert.Equal(HttpStatusCode.MethodNotAllowed, noDelete.StatusCode);
    }

    [PostgresFact]
    public async Task RoleSpecificFieldsAndStatusAuthorityCannotBeOverridden()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory);
        using var owner = Bearer(factory, pair.Owner, "client"); using var expert = Bearer(factory, pair.Expert); var task = await Create(expert, pair);
        foreach (var body in new object[] { new { expectedVersionNumber = 1, description = Description }, new { expectedVersionNumber = 1, dueAt = (string?)null }, new { expectedVersionNumber = 1, status = "cancelled" } })
        { using var denied = await owner.PatchAsJsonAsync(Detail(task.Id), body); await Error(denied, HttpStatusCode.Forbidden); }
        foreach (var body in new object[] { new { expectedVersionNumber = 1, isReminderEnabled = false }, new { expectedVersionNumber = 1, status = "completed" }, new { expectedVersionNumber = 1, status = "in_progress" } })
        { using var denied = await expert.PatchAsJsonAsync(Detail(task.Id), body); await Error(denied, HttpStatusCode.Forbidden); }
        using var noCreate = await owner.PostAsJsonAsync(Route, new { clientId = pair.Client.Id, description = Description }); await Error(noCreate, HttpStatusCode.Forbidden);
        task = await Patch(expert, task, new { expectedVersionNumber = 1, status = "cancelled" }); Assert.Equal(ClientTaskStatus.Cancelled, task.Status);
        var direct = await Create(expert, pair); direct = await Patch(owner, direct, new { expectedVersionNumber = 1, status = "completed" }); Assert.Equal(ClientTaskStatus.Completed, direct.Status);
    }

    [PostgresFact]
    public async Task WithdrawalStopsEveryExpertOperationButClientCanCompleteAndOtherGrantsRemain()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory);
        using var owner = Bearer(factory, pair.Owner, "client"); using var expert = Bearer(factory, pair.Expert); var task = await Create(expert, pair);
        using var revoke = await owner.PatchAsJsonAsync($"/api/v1/data-sharing-permissions/{pair.Permission.Id}", new { isGranted = false }); Assert.Equal(HttpStatusCode.OK, revoke.StatusCode);
        foreach (var path in new[] { List(pair.Client.Id), Detail(task.Id), History(task.Id) })
        { using var denied = await expert.GetAsync(path); await Error(denied, HttpStatusCode.Forbidden); }
        using var create = await expert.PostAsJsonAsync(Route, new { clientId = pair.Client.Id, description = Description }); await Error(create, HttpStatusCode.Forbidden);
        using var edit = await expert.PatchAsJsonAsync(Detail(task.Id), new { expectedVersionNumber = 1, description = "Synthetic change" }); await Error(edit, HttpStatusCode.Forbidden);
        await Patch(owner, task, new { expectedVersionNumber = 1, status = "completed" });
        await using var db = factory.Database(); Assert.True(await db.DataSharingPermissions.AnyAsync(x => x.RelationshipId == pair.Relationship.Id && x.Category == "nutrition_plans" && x.IsGranted));
        Assert.Equal(2, (await owner.GetFromJsonAsync<JsonElement>(History(task.Id))).GetProperty("totalCount").GetInt32());
    }

    [PostgresFact]
    public async Task RelationshipEndCancelsOnlyOpenTasksAtomicallyAndNewRelationshipCannotReopenOldHistory()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory);
        using var owner = Bearer(factory, pair.Owner, "client"); using var expert = Bearer(factory, pair.Expert);
        var open = await Create(expert, pair); var complete = await Create(expert, pair); await Patch(owner, complete, new { expectedVersionNumber = 1, status = "completed" });
        using var end = await owner.PostAsync($"/api/v1/dietitian-relationships/{pair.Relationship.Id}/end", null); Assert.Equal(HttpStatusCode.OK, end.StatusCode);
        var cancelled = await owner.GetFromJsonAsync<ClientTaskResponse>(Detail(open.Id)); Assert.Equal(ClientTaskStatus.Cancelled, cancelled!.Status); Assert.Equal(2, cancelled.VersionNumber);
        Assert.Equal(ClientTaskStatus.Completed, (await owner.GetFromJsonAsync<ClientTaskResponse>(Detail(complete.Id)))!.Status);
        foreach (var path in new[] { Detail(open.Id), History(open.Id), List(pair.Client.Id) })
        { using var denied = await expert.GetAsync(path); await Error(denied, HttpStatusCode.NotFound); }
        var now = DateTimeOffset.UtcNow; var next = new DietitianClientRelationship(pair.Client.Id, pair.Profile.Id, now); next.Respond(RelationshipStatus.Active, now);
        await using (var db = factory.Database()) { db.DietitianClientRelationships.Add(next); db.DataSharingPermissions.Add(new DataSharingPermission(next.Id, true, now, "client_tasks")); await db.SaveChangesAsync(); }
        using var stillHidden = await expert.GetAsync(Detail(open.Id)); await Error(stillHidden, HttpStatusCode.NotFound);
        Assert.Equal(0, (await expert.GetFromJsonAsync<JsonElement>(List(pair.Client.Id))).GetProperty("totalCount").GetInt32());
        Assert.Equal(2, (await owner.GetFromJsonAsync<JsonElement>(List())).GetProperty("totalCount").GetInt32());
        Assert.Equal(2, (await owner.GetFromJsonAsync<JsonElement>(History(open.Id))).GetProperty("totalCount").GetInt32());
    }

    [PostgresFact]
    public async Task UnrelatedProfilesMissingGrantAndUnverifiedExpertsCannotAccessTasks()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory); var stranger = await Seed(factory);
        using var expert = Bearer(factory, pair.Expert); var task = await Create(expert, pair);
        foreach (var actor in new[] { Bearer(factory, stranger.Owner, "client"), Bearer(factory, stranger.Expert) })
        {
            using (actor)
            {
                foreach (var path in new[] { Detail(task.Id), History(task.Id) }) { using var denied = await actor.GetAsync(path); await Error(denied, HttpStatusCode.NotFound); }
                using var edit = await actor.PatchAsJsonAsync(Detail(task.Id), new { expectedVersionNumber = 1, status = "completed" }); await Error(edit, HttpStatusCode.NotFound);
            }
        }
        await using (var db = factory.Database()) await db.DataSharingPermissions.Where(x => x.Id == pair.Permission.Id).ExecuteDeleteAsync();
        using var missing = await expert.GetAsync(Detail(task.Id)); await Error(missing, HttpStatusCode.Forbidden);
        using var missingCreate = await expert.PostAsJsonAsync(Route, new { clientId = pair.Client.Id, description = Description }); await Error(missingCreate, HttpStatusCode.Forbidden);
        await using (var db = factory.Database()) await db.DietitianProfiles.Where(x => x.Id == pair.Profile.Id).ExecuteUpdateAsync(x => x.SetProperty(p => p.IsVerified, false));
        using var unapproved = await expert.GetAsync(Detail(task.Id)); await Error(unapproved, HttpStatusCode.Forbidden);
        using var forged = Bearer(factory, pair.Owner); using var spoof = await forged.GetAsync(Detail(task.Id)); await Error(spoof, HttpStatusCode.Forbidden);
        using var anonymous = factory.Client(false); using var noIdentity = await anonymous.GetAsync(List()); await Error(noIdentity, HttpStatusCode.Unauthorized);
        await using (var db = factory.Database()) await db.Users.Where(x => x.Id == pair.Expert.Id).ExecuteUpdateAsync(x => x.SetProperty(p => p.IsEmailVerified, false));
        using var stale = await expert.GetAsync(Detail(task.Id)); await Error(stale, HttpStatusCode.Unauthorized);
    }

    [PostgresFact]
    public async Task DefaultClosedCategoryCanOnlyBeGrantedByClientAfterRolloutAndAlwaysRevoked()
    {
        foreach (var enabled in new[] { false, true })
        {
            await using var factory = await RegistrationApiFactory.CreateAsync(clientTaskSharing: enabled); var pair = await Seed(factory, grant: false);
            using var owner = Bearer(factory, pair.Owner, "client"); using var expert = Bearer(factory, pair.Expert);
            using var permission = await owner.PostAsJsonAsync("/api/v1/data-sharing-permissions", new { relationshipId = pair.Relationship.Id, category = "client_tasks", isGranted = true });
            Assert.Equal(enabled ? HttpStatusCode.Created : HttpStatusCode.UnprocessableEntity, permission.StatusCode);
            if (enabled)
            {
                var id = (await permission.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid();
                await Create(expert, pair);
                using var forbidden = await expert.PatchAsJsonAsync($"/api/v1/data-sharing-permissions/{id}", new { isGranted = false }); await Error(forbidden, HttpStatusCode.Forbidden);
            }
            else
            {
                await using (var db = factory.Database()) { db.DataSharingPermissions.Add(pair.Permission); await db.SaveChangesAsync(); }
                using var grant = await owner.PatchAsJsonAsync($"/api/v1/data-sharing-permissions/{pair.Permission.Id}", new { isGranted = true }); await Error(grant, HttpStatusCode.UnprocessableEntity);
                using var revoke = await owner.PatchAsJsonAsync($"/api/v1/data-sharing-permissions/{pair.Permission.Id}", new { isGranted = false }); Assert.Equal(HttpStatusCode.OK, revoke.StatusCode);
                using var read = await owner.GetAsync($"/api/v1/data-sharing-permissions?relationshipId={pair.Relationship.Id}&page=1&pageSize=100"); Assert.Equal(HttpStatusCode.OK, read.StatusCode);
            }
        }
    }

    [PostgresFact]
    public async Task ValidationRejectsUnknownFieldsInvalidDatesTextNullsAndUnsupportedStatuses()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory); using var expert = Bearer(factory, pair.Expert);
        foreach (var body in new object[] { new { }, new { clientId = pair.Client.Id }, new { clientId = pair.Client.Id, description = Description, dietitianId = pair.Profile.Id },
            new { clientId = pair.Client.Id, description = Description, dueAt = "2026-11-18" }, new { clientId = pair.Client.Id, description = Description, dueAt = 12 } })
        { using var invalid = await expert.PostAsJsonAsync(Route, body); await Error(invalid, HttpStatusCode.BadRequest); }
        foreach (var text in new string?[] { null, "", " \t\n\u00a0", new('x', 2001), "invalid\0text" })
        { using var invalid = await expert.PostAsJsonAsync(Route, new { clientId = pair.Client.Id, description = text }); await Error(invalid, HttpStatusCode.UnprocessableEntity); }
        using var past = await expert.PostAsJsonAsync(Route, new { clientId = pair.Client.Id, description = Description, dueAt = DateTimeOffset.UtcNow.AddMinutes(-1) }); await Error(past, HttpStatusCode.UnprocessableEntity);
        var emoji = string.Concat(Enumerable.Repeat("🥣", 2000)); Assert.Equal(emoji, (await Create(expert, pair, emoji)).Description);
        var task = await Create(expert, pair);
        foreach (var body in new object[] { new { description = Description }, new { expectedVersionNumber = 1 }, new { expectedVersionNumber = 1, versionNumber = 2, description = Description }, new { expectedVersionNumber = 1, description = 42 } })
        { using var invalid = await expert.PatchAsJsonAsync(Detail(task.Id), body); await Error(invalid, HttpStatusCode.BadRequest); }
        foreach (var body in new object[] { new { expectedVersionNumber = 0, description = Description }, new { expectedVersionNumber = 1, description = (string?)null }, new { expectedVersionNumber = 1, status = "overdue" }, new { expectedVersionNumber = 1, status = (string?)null } })
        { using var invalid = await expert.PatchAsJsonAsync(Detail(task.Id), body); await Error(invalid, HttpStatusCode.UnprocessableEntity); }
        var same = await Patch(expert, task, new { expectedVersionNumber = 1, description = Description }); Assert.Equal(1, same.VersionNumber);
        Assert.Equal(1, (await expert.GetFromJsonAsync<JsonElement>(History(task.Id))).GetProperty("totalCount").GetInt32());
    }

    [PostgresFact]
    public async Task PaginationBodiesQueryAndTargetSelectionAreStrict()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory);
        using var owner = Bearer(factory, pair.Owner, "client"); using var expert = Bearer(factory, pair.Expert); var task = await Create(expert, pair);
        foreach (var query in new[] { "", "?page=1", "?page=0&pageSize=10", "?page=1&pageSize=101", "?page=2147483647&pageSize=100", "?page=1&page=2&pageSize=10", "?page=1&pageSize=10&status=pending" })
        { using var invalid = await owner.GetAsync(Route + query); await Error(invalid, HttpStatusCode.BadRequest); using var invalidHistory = await owner.GetAsync(Detail(task.Id) + "/versions" + query); await Error(invalidHistory, HttpStatusCode.BadRequest); }
        using var selfId = await owner.GetAsync(List(pair.Client.Id)); await Error(selfId, HttpStatusCode.BadRequest);
        using var missingTarget = await expert.GetAsync(List()); await Error(missingTarget, HttpStatusCode.BadRequest);
        using var unknown = await expert.PostAsJsonAsync(Route, new { clientId = Guid.NewGuid(), description = Description }); await Error(unknown, HttpStatusCode.NotFound);
        using var zero = await expert.PostAsJsonAsync(Route, new { clientId = Guid.Empty, description = Description }); await Error(zero, HttpStatusCode.UnprocessableEntity);
        using var body = new HttpRequestMessage(HttpMethod.Get, List()) { Content = JsonContent.Create(new { }) }; using var withBody = await owner.SendAsync(body); await Error(withBody, HttpStatusCode.BadRequest);
        using var detailQuery = await owner.GetAsync(Detail(task.Id) + "?page=1"); await Error(detailQuery, HttpStatusCode.BadRequest);
        using var writeQuery = await expert.PostAsJsonAsync(Route + "?page=1", new { clientId = pair.Client.Id, description = Description }); await Error(writeQuery, HttpStatusCode.BadRequest);
    }

    [PostgresFact]
    public async Task TwoConcurrentUpdatesWithSameVersionHaveOneWinnerAndOneHistoryEntry()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory); using var expert = Bearer(factory, pair.Expert); var task = await Create(expert, pair);
        var responses = await Task.WhenAll(expert.PatchAsJsonAsync(Detail(task.Id), new { expectedVersionNumber = 1, description = "Synthetic first edit" }),
            expert.PatchAsJsonAsync(Detail(task.Id), new { expectedVersionNumber = 1, description = "Synthetic second edit" }));
        try { Assert.Equal(new[] { HttpStatusCode.OK, HttpStatusCode.Conflict }, responses.Select(x => x.StatusCode).Order()); }
        finally { foreach (var response in responses) response.Dispose(); }
        Assert.Equal(2, (await expert.GetFromJsonAsync<ClientTaskResponse>(Detail(task.Id)))!.VersionNumber);
        Assert.Equal(2, (await expert.GetFromJsonAsync<JsonElement>(History(task.Id))).GetProperty("totalCount").GetInt32());
    }

    [PostgresFact]
    public async Task WaitingWritesRecheckPermissionAndRelationshipAfterClientLock()
    {
        foreach (var endRelationship in new[] { false, true })
        {
            var pause = new ClientLockPause(); await using var factory = await RegistrationApiFactory.CreateAsync(interceptor: pause); var pair = await Seed(factory);
            using var expert = Bearer(factory, pair.Expert); using var owner = Bearer(factory, pair.Owner, "client"); var task = await Create(expert, pair);
            pause.Armed = true;
            var pending = expert.PatchAsJsonAsync(Detail(task.Id), new { expectedVersionNumber = 1, description = "Synthetic raced edit" });
            try
            {
                await pause.Entered.Task.WaitAsync(TimeSpan.FromSeconds(15));
                using var changed = endRelationship ? await owner.PostAsync($"/api/v1/dietitian-relationships/{pair.Relationship.Id}/end", null)
                    : await owner.PatchAsJsonAsync($"/api/v1/data-sharing-permissions/{pair.Permission.Id}", new { isGranted = false });
                Assert.Equal(HttpStatusCode.OK, changed.StatusCode);
            }
            finally { pause.Release.TrySetResult(); }
            using var denied = await pending; await Error(denied, endRelationship ? HttpStatusCode.NotFound : HttpStatusCode.Forbidden);
            Assert.Equal(Description, (await owner.GetFromJsonAsync<ClientTaskResponse>(Detail(task.Id)))!.Description);
        }
    }

    [PostgresFact]
    public async Task HistoryFailureRollsBackTaskPatchAndRelationshipCancellation()
    {
        var failure = new HistoryFailure(); await using var factory = await RegistrationApiFactory.CreateAsync(interceptor: failure); var pair = await Seed(factory);
        using var expert = Bearer(factory, pair.Expert); using var owner = Bearer(factory, pair.Owner, "client"); var task = await Create(expert, pair);
        failure.Armed = true; using var failed = await expert.PatchAsJsonAsync(Detail(task.Id), new { expectedVersionNumber = 1, description = "Synthetic rolled back edit" }); await Error(failed, HttpStatusCode.InternalServerError);
        failure.Armed = true; using var failedEnd = await owner.PostAsync($"/api/v1/dietitian-relationships/{pair.Relationship.Id}/end", null); await Error(failedEnd, HttpStatusCode.InternalServerError);
        await using var db = factory.Database(); Assert.Equal(RelationshipStatus.Active, (await db.DietitianClientRelationships.SingleAsync()).Status);
        var unchanged = await db.ClientTasks.SingleAsync(); Assert.Equal(Description, unchanged.Description); Assert.Equal(ClientTaskStatus.Pending, unchanged.Status); Assert.Equal(1, unchanged.VersionNumber); Assert.Equal(1, await db.ClientTaskVersions.CountAsync());
    }

    [PostgresFact]
    public async Task MigrationPreservesAllOldDataAndRejectsLossyRollbackAndCrossPairForeignKeys()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync();
        await using (var db = factory.Database()) await db.GetService<IMigrator>().MigrateAsync(PreviousMigration);
        var pair = await Seed(factory, grant: false); var other = await Seed(factory, grant: false);
        await using (var db = factory.Database())
        {
            var before = await Fingerprint(db); await db.Database.MigrateAsync(); Assert.Equal(before, await Fingerprint(db));
            // Even an ungranted task permission is data and must prevent downgrade.
            db.DataSharingPermissions.Add(new DataSharingPermission(pair.Relationship.Id, false, DateTimeOffset.UtcNow, "client_tasks")); await db.SaveChangesAsync();
            await Assert.ThrowsAsync<PostgresException>(() => db.GetService<IMigrator>().MigrateAsync(PreviousMigration));
        }
        using var expert = Bearer(factory, pair.Expert);
        await using (var db = factory.Database()) await db.DataSharingPermissions.Where(x => x.Category == "client_tasks").ExecuteUpdateAsync(x => x.SetProperty(p => p.IsGranted, true));
        var task = await Create(expert, pair);
        await using (var db = factory.Database())
        {
            await Assert.ThrowsAsync<PostgresException>(() => db.GetService<IMigrator>().MigrateAsync(PreviousMigration));
            Assert.Equal(task.Id, (await db.ClientTasks.SingleAsync()).Id);
            var invalid = new ClientTask(other.Client.Id, pair.Profile.Id, pair.Relationship.Id, Description, null, DateTimeOffset.UtcNow); db.ClientTasks.Add(invalid);
            var error = await Assert.ThrowsAsync<DbUpdateException>(() => db.SaveChangesAsync()); Assert.Equal(PostgresErrorCodes.ForeignKeyViolation, Assert.IsType<PostgresException>(error.InnerException).SqlState);
        }
        await using (var db = factory.Database())
        {
            var version = await db.ClientTaskVersions.SingleAsync();
            db.ClientTaskVersions.Add(new ClientTaskVersion(await db.ClientTasks.SingleAsync(), pair.Expert.Id));
            var duplicate = await Assert.ThrowsAsync<DbUpdateException>(() => db.SaveChangesAsync()); Assert.Equal(PostgresErrorCodes.UniqueViolation, Assert.IsType<PostgresException>(duplicate.InnerException).SqlState);
            Assert.NotEqual(Guid.Empty, version.RecordedByUserId);
        }
    }

    [PostgresFact]
    public async Task WebDualProfileRequiresCsrfOriginAndRejectsMixedAuthentication()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(webSessions: true); var pair = await Seed(factory, dual: true); using var web = factory.Client();
        await LoginWeb(web, pair.Expert.Email, "/api/v1/auth/web-session");
        web.DefaultRequestHeaders.Add("X-Profile-Context", "dietitian");
        using var noOrigin = await web.PostAsJsonAsync(Route, new { clientId = pair.Client.Id, description = Description }); await Error(noOrigin, HttpStatusCode.Forbidden);
        web.DefaultRequestHeaders.Add("Origin", "https://localhost");
        using var noCsrf = await web.PostAsJsonAsync(Route, new { clientId = pair.Client.Id, description = Description }); await Error(noCsrf, HttpStatusCode.BadRequest);
        var csrf = await web.GetFromJsonAsync<JsonElement>("/api/v1/auth/csrf"); web.DefaultRequestHeaders.Add("X-CSRF-TOKEN", csrf.GetProperty("requestToken").GetString());
        var task = await Create(web, pair);
        using var read = await web.GetAsync(Detail(task.Id)); Assert.Equal(HttpStatusCode.OK, read.StatusCode);
        web.DefaultRequestHeaders.Remove("Origin"); web.DefaultRequestHeaders.Add("Origin", "https://foreign.example.test");
        using var foreign = await web.GetAsync(History(task.Id)); await Error(foreign, HttpStatusCode.Forbidden);
        web.DefaultRequestHeaders.Remove("Origin"); web.DefaultRequestHeaders.Add("Origin", "https://localhost"); web.DefaultRequestHeaders.Authorization = new("Bearer", "synthetic.ambiguous.credentials");
        using var mixed = await web.GetAsync(Detail(task.Id)); await Error(mixed, HttpStatusCode.BadRequest);
        web.DefaultRequestHeaders.Authorization = null; web.DefaultRequestHeaders.Remove("X-Profile-Context"); web.DefaultRequestHeaders.Add("X-Profile-Context", "client");
        using var switchToClient = await web.GetAsync(List()); await Error(switchToClient, HttpStatusCode.Forbidden);
        using var bearerClient = Bearer(factory, pair.Expert, "client"); Assert.Equal(0, (await bearerClient.GetFromJsonAsync<JsonElement>(List())).GetProperty("totalCount").GetInt32());
    }

    [PostgresFact]
    public async Task MfaAdminHasNoTaskAccess()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(webSessions: true); var pair = await Seed(factory);
        using var expert = Bearer(factory, pair.Expert); var task = await Create(expert, pair);
        var admin = new User(Guid.NewGuid(), Guid.NewGuid().ToString("N") + "@EXAMPLE.TEST", UserRole.Admin, Password, DateTimeOffset.UtcNow, new PasswordHasher<User>());
        using var scope = factory.Services.CreateScope(); var setup = scope.ServiceProvider.GetRequiredService<AdminMfaService>().Initialize(admin, DateTimeOffset.UtcNow);
        await using (var db = factory.Database()) { db.Users.Add(admin); db.Entry(admin).Property(x => x.IsEmailVerified).CurrentValue = true; await db.SaveChangesAsync(); }
        using var web = factory.Client(); await LoginWeb(web, admin.Email, "/api/v1/auth/admin-web-session", setup.RecoveryCodes[0]);
        foreach (var path in new[] { List(pair.Client.Id), Detail(task.Id), History(task.Id) }) { using var denied = await web.GetAsync(path); await Error(denied, HttpStatusCode.Forbidden); }
    }

    [PostgresFact]
    public async Task PendingRelationshipCannotAuthorizeAssignmentOrReading()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory);
        using var expert = Bearer(factory, pair.Expert); using var owner = Bearer(factory, pair.Owner, "client"); var task = await Create(expert, pair);
        await using (var db = factory.Database()) await db.DietitianClientRelationships.Where(x => x.Id == pair.Relationship.Id).ExecuteUpdateAsync(x => x.SetProperty(p => p.Status, RelationshipStatus.Pending));
        using var create = await expert.PostAsJsonAsync(Route, new { clientId = pair.Client.Id, description = Description }); await Error(create, HttpStatusCode.NotFound);
        foreach (var path in new[] { List(pair.Client.Id), Detail(task.Id), History(task.Id) })
        { using var denied = await expert.GetAsync(path); await Error(denied, HttpStatusCode.NotFound); }
        using var own = await owner.GetAsync(Detail(task.Id)); Assert.Equal(HttpStatusCode.OK, own.StatusCode);
    }

    [PostgresFact]
    public async Task OverdueTaskStillCompletesAndUnchangedPastDueAtDoesNotBlockDescriptionEdit()
    {
        var clock = new TaskClock(DateTimeOffset.UtcNow); await using var factory = await RegistrationApiFactory.CreateAsync(clock: clock); var pair = await Seed(factory);
        using var expert = Bearer(factory, pair.Expert); using var owner = Bearer(factory, pair.Owner, "client");
        var task = await Create(expert, pair, due: clock.GetUtcNow().AddMinutes(1)); clock.Now = clock.Now.AddMinutes(2);
        task = await Patch(expert, task, new { expectedVersionNumber = 1, description = "Synthetic late edit", dueAt = task.DueAt });
        Assert.Equal(ClientTaskStatus.Pending, task.Status);
        using var pastChange = await expert.PatchAsJsonAsync(Detail(task.Id), new { expectedVersionNumber = 2, dueAt = clock.Now.AddSeconds(-1) }); await Error(pastChange, HttpStatusCode.UnprocessableEntity);
        task = await Patch(owner, task, new { expectedVersionNumber = 2, status = "completed" }); Assert.Equal(ClientTaskStatus.Completed, task.Status);
        Assert.True(task.UpdatedAt > task.DueAt);
    }

    [PostgresFact]
    public async Task PostgreSqlRejectsInvalidStatusReminderTimesAndMissingSnapshotIdentity()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory); using var expert = Bearer(factory, pair.Expert); var task = await Create(expert, pair);
        foreach (var sql in new[]
        {
            "UPDATE client_tasks SET status='unknown'", "UPDATE client_tasks SET version_number=0",
            "UPDATE client_tasks SET is_reminder_enabled=true", "UPDATE client_tasks SET due_at=created_at",
            "UPDATE client_tasks SET updated_at=created_at - interval '1 second'", "UPDATE client_tasks SET description=''",
            "UPDATE client_task_versions SET snapshot=jsonb_build_object()"
        })
        {
            await using var db = factory.Database();
            var error = await Assert.ThrowsAsync<PostgresException>(() => db.Database.ExecuteSqlRawAsync(sql));
            Assert.Equal(PostgresErrorCodes.CheckViolation, error.SqlState);
        }
        Assert.Equal(1, (await expert.GetFromJsonAsync<ClientTaskResponse>(Detail(task.Id)))!.VersionNumber);
    }

    [PostgresFact]
    public async Task ListCountAndRowsShareSnapshotWhileGrantIsWithdrawnAndAnotherTaskArrives()
    {
        var pause = new ListPagePause(); await using var factory = await RegistrationApiFactory.CreateAsync(interceptor: pause); var pair = await Seed(factory);
        using var expert = Bearer(factory, pair.Expert); using var owner = Bearer(factory, pair.Owner, "client"); var task = await Create(expert, pair);
        pause.Armed = true; var pending = expert.GetAsync(List(pair.Client.Id));
        try
        {
            await pause.Entered.Task.WaitAsync(TimeSpan.FromSeconds(15));
            using var revoke = await owner.PatchAsJsonAsync($"/api/v1/data-sharing-permissions/{pair.Permission.Id}", new { isGranted = false }); Assert.Equal(HttpStatusCode.OK, revoke.StatusCode);
            await using var db = factory.Database(); var other = new ClientTask(pair.Client.Id, pair.Profile.Id, pair.Relationship.Id, Description, null, DateTimeOffset.UtcNow);
            db.ClientTasks.Add(other); db.ClientTaskVersions.Add(new ClientTaskVersion(other, pair.Expert.Id)); await db.SaveChangesAsync();
        }
        finally { pause.Release.TrySetResult(); }
        using var response = await pending; Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(); Assert.Equal(1, body.GetProperty("totalCount").GetInt32()); Assert.Single(body.GetProperty("items").EnumerateArray());
        Assert.Equal(task.Id, body.GetProperty("items")[0].GetProperty("id").GetGuid());
        using var next = await expert.GetAsync(List(pair.Client.Id)); await Error(next, HttpStatusCode.Forbidden);
    }

    private sealed class TaskClock(DateTimeOffset now) : TimeProvider
    { public DateTimeOffset Now { get; set; } = now; public override DateTimeOffset GetUtcNow() => Now; }

    private sealed class ListPagePause : DbCommandInterceptor
    {
        public bool Armed { get; set; }
        public TaskCompletionSource Entered { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public TaskCompletionSource Release { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public override async ValueTask<InterceptionResult<DbDataReader>> ReaderExecutingAsync(DbCommand command, CommandEventData eventData, InterceptionResult<DbDataReader> result, CancellationToken cancellationToken = default)
        {
            if (Armed && command.CommandText.Contains("FROM client_tasks", StringComparison.Ordinal) && command.CommandText.Contains("ORDER BY", StringComparison.Ordinal))
            { Armed = false; Entered.TrySetResult(); await Release.Task.WaitAsync(TimeSpan.FromSeconds(15), cancellationToken); }
            return result;
        }
    }

    private static async Task<Pair> Seed(RegistrationApiFactory factory, bool grant = true, bool dual = false)
    {
        await using var db = factory.Database(); var now = DateTimeOffset.UtcNow;
        var owner = new User(Guid.NewGuid(), Guid.NewGuid().ToString("N") + "@EXAMPLE.TEST", UserRole.Client, Password, now, new PasswordHasher<User>());
        var client = new ClientProfile(Guid.NewGuid(), owner, "Synthetic task client");
        var expert = new User(Guid.NewGuid(), Guid.NewGuid().ToString("N") + "@EXAMPLE.TEST", dual ? UserRole.Client : UserRole.Dietitian, Password, now, new PasswordHasher<User>());
        var profile = new DietitianProfile(expert, "Synthetic task expert", "Synthetic license"); if (dual) _ = new ClientProfile(Guid.NewGuid(), expert, "Synthetic dual profile");
        db.Users.AddRange(owner, expert); db.Entry(owner).Property(x => x.IsEmailVerified).CurrentValue = true; db.Entry(expert).Property(x => x.IsEmailVerified).CurrentValue = true; db.Entry(profile).Property(x => x.IsVerified).CurrentValue = true;
        var relationship = new DietitianClientRelationship(client.Id, profile.Id, now); relationship.Respond(RelationshipStatus.Active, now);
        var permission = new DataSharingPermission(relationship.Id, true, now, "client_tasks");
        db.DietitianClientRelationships.Add(relationship); db.DataSharingPermissions.Add(new DataSharingPermission(relationship.Id, true, now));
        if (grant) db.DataSharingPermissions.Add(permission); await db.SaveChangesAsync(); return new(owner, client, expert, profile, relationship, permission);
    }
    private static HttpClient Bearer(RegistrationApiFactory factory, User user, string context = "dietitian")
    {
        var client = factory.Client(false); var jwt = new JwtAccessTokenService(Options.Create(factory.Jwt.Options), TimeProvider.System).Issue(user);
        client.DefaultRequestHeaders.Authorization = new("Bearer", jwt.AccessToken); client.DefaultRequestHeaders.Add("X-Profile-Context", context); return client;
    }
    private static async Task<ClientTaskResponse> Create(HttpClient expert, Pair pair, string description = Description, DateTimeOffset? due = null)
    {
        using var response = await expert.PostAsJsonAsync(Route, new { clientId = pair.Client.Id, description, dueAt = due });
        Assert.Equal(HttpStatusCode.Created, response.StatusCode); var row = (await response.Content.ReadFromJsonAsync<ClientTaskResponse>())!;
        Assert.Equal(Detail(row.Id), response.Headers.Location!.ToString()); return row;
    }
    private static async Task<ClientTaskResponse> Patch(HttpClient actor, ClientTaskResponse task, object request)
    { using var response = await actor.PatchAsJsonAsync(Detail(task.Id), request); Assert.Equal(HttpStatusCode.OK, response.StatusCode); return (await response.Content.ReadFromJsonAsync<ClientTaskResponse>())!; }
    private static async Task Error(HttpResponseMessage response, HttpStatusCode status)
    {
        Assert.Equal(status, response.StatusCode); var text = await response.Content.ReadAsStringAsync(); var body = JsonSerializer.Deserialize<JsonElement>(text);
        Assert.True(body.TryGetProperty("error", out _)); Assert.False(string.IsNullOrWhiteSpace(body.GetProperty("requestId").GetString())); Assert.DoesNotContain(Description, text);
        Assert.Contains("no-store", response.Headers.CacheControl!.ToString());
    }
    private static async Task LoginWeb(HttpClient web, string email, string route, string? mfa = null)
    {
        var csrf = await web.GetFromJsonAsync<JsonElement>("/api/v1/auth/csrf");
        using var login = new HttpRequestMessage(HttpMethod.Post, route) { Content = mfa is null ? JsonContent.Create(new { email, password = Password }) : JsonContent.Create(new { email, password = Password, mfaCode = mfa }) };
        login.Headers.Add("Origin", "https://localhost"); login.Headers.Add("X-CSRF-TOKEN", csrf.GetProperty("requestToken").GetString());
        using var response = await web.SendAsync(login); Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }
    private static async Task<string> Fingerprint(SmartNutrition.Api.Data.AppDbContext db)
    {
        await db.Database.OpenConnectionAsync(); await using var command = db.Database.GetDbConnection().CreateCommand();
        command.CommandText = """
            CREATE TEMP TABLE task_data_snapshot (name text, digest text);
            DO $$ DECLARE r record; h text; BEGIN
              FOR r IN SELECT tablename FROM pg_tables WHERE schemaname=current_schema() AND tablename NOT IN ('__ef_migrations_history','client_tasks','client_task_versions') ORDER BY tablename LOOP
                EXECUTE format('SELECT md5(coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text)::text,''[]'')) FROM %I t',r.tablename) INTO h;
                INSERT INTO task_data_snapshot VALUES(r.tablename,h);
              END LOOP;
            END $$;
            SELECT jsonb_agg(jsonb_build_object('table',name,'hash',digest) ORDER BY name)::text FROM task_data_snapshot;
            DROP TABLE task_data_snapshot;
            """;
        return (string)(await command.ExecuteScalarAsync())!;
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
    private sealed class HistoryFailure : DbCommandInterceptor
    {
        public bool Armed { get; set; }
        public override ValueTask<InterceptionResult<DbDataReader>> ReaderExecutingAsync(DbCommand command, CommandEventData eventData, InterceptionResult<DbDataReader> result, CancellationToken cancellationToken = default)
        {
            if (Armed && command.CommandText.Contains("INSERT INTO client_task_versions", StringComparison.Ordinal))
            { Armed = false; throw new InvalidOperationException("Synthetic history write failure."); }
            return ValueTask.FromResult(result);
        }
    }
}
