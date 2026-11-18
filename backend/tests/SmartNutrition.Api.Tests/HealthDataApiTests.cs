using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Security.Claims;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Microsoft.Extensions.Options;
using Npgsql;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Features.Dietitians;
using SmartNutrition.Api.Features.HealthData;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Tests;

public sealed partial class HealthDataApiTests
{
    private const string Connections = "/api/v1/wearable-connections";
    private const string Activities = "/api/v1/activity-logs";
    private const string Samples = "/api/v1/health-metric-samples?page=1&pageSize=100";
    private static readonly DateTimeOffset Day = new(2026, 10, 20, 0, 0, 0, TimeSpan.FromHours(3));
    private static string Records(Guid connection) => $"{Connections}/{connection}/records?page=1&pageSize=100";
    private static string Daily(DateTimeOffset? day = null, DateTimeOffset? end = null) => Activities + "/daily-summary?from=" +
        Uri.EscapeDataString((day ?? Day).ToString("O")) + "&to=" + Uri.EscapeDataString((end ?? (day ?? Day).AddDays(1)).ToString("O"));

    [PostgresFact]
    public async Task ImportRetryUpdateReadSummaryAndExplicitDeleteUseRealPostgres()
    {
        await using var f = await RegistrationApiFactory.CreateAsync(); var account = await Seed(f); using var client = Bearer(f, account.User);
        var connection = await Connect(client); var batch = Guid.NewGuid();
        var first = await Sync(client, connection.Id, [Change("steps", "steps-1", value: 123)], batch);
        var retry = await Sync(client, connection.Id, [Change("steps", "steps-1", value: 123)], batch);
        Assert.Equal(first.CommittedAt, retry.CommittedAt); Assert.Equal(first.Records[0].Id, retry.Records[0].Id);
        Assert.Equal(1, retry.Records[0].VersionNumber);
        var second = await Sync(client, connection.Id, [Change("steps", "steps-1", version: 1, value: 234)]);
        Assert.Equal(first.Records[0].Id, second.Records[0].Id); Assert.Equal(2, second.Records[0].VersionNumber);
        var samples = await client.GetFromJsonAsync<JsonElement>(Samples);
        Assert.Equal(1, samples.GetProperty("totalCount").GetInt32()); Assert.Equal(234, samples.GetProperty("items")[0].GetProperty("value").GetDecimal());
        var summary = await client.GetFromJsonAsync<ActivityDailySummaryResponse>(Daily()); Assert.Equal(234, summary!.Steps); Assert.Null(summary.DistanceKm);
        var deleted = await Sync(client, connection.Id, [Delete("steps", "steps-1", 2)]); Assert.True(deleted.Records[0].IsDeleted);
        Assert.Equal(3, deleted.Records[0].VersionNumber);
        Assert.Equal(0, (await client.GetFromJsonAsync<JsonElement>(Samples)).GetProperty("totalCount").GetInt32());
        var history = await client.GetFromJsonAsync<JsonElement>(Samples + "&includeDeleted=true"); Assert.True(history.GetProperty("items")[0].GetProperty("isDeleted").GetBoolean());
        using var stale = await client.PostAsJsonAsync(Connections + "/sync", Batch(connection.Id, [Change("steps", "steps-1", version: 2)]));
        await Error(stale, 409, "source_version_conflict");
        Assert.Null((await client.GetFromJsonAsync<ActivityDailySummaryResponse>(Daily()))!.Steps);
        var restored = await Sync(client, connection.Id, [Change("steps", "steps-1", version: 3, value: 456)]); Assert.Equal(4, restored.Records[0].VersionNumber);
        await using var db = f.Database(); Assert.Equal(1, await db.HealthMetricSamples.CountAsync()); Assert.Equal(1, await db.WearableRecords.CountAsync());
        Assert.Equal(4, await db.WearableSyncBatches.CountAsync());
    }

    [PostgresFact]
    public async Task OwnershipRolesProfileAndIdentityInjectionAreRejectedAcrossAllResources()
    {
        await using var f = await RegistrationApiFactory.CreateAsync(); var a = await Seed(f); var b = await Seed(f);
        using var owner = Bearer(f, a.User); using var other = Bearer(f, b.User); var connection = await Connect(owner);
        var imported = await Sync(owner, connection.Id, [Change("steps", "private-record")]);
        var activity = await Manual(owner);
        foreach (var route in new[] { $"{Connections}/{connection.Id}", Records(connection.Id), $"{Connections}/{connection.Id}/records/{imported.Records[0].Id}",
                     Samples + "&wearableRecordId=" + imported.Records[0].Id, Activities + "/" + activity.Id })
        { using var result = await other.GetAsync(route); await Error(result, 404, "not_found"); }
        using (var result = await other.PostAsJsonAsync(Connections + "/sync", Batch(connection.Id, [Change("steps", "injected")]))) await Error(result, 404, "not_found");
        using (var result = await other.PatchAsJsonAsync(Connections + "/" + connection.Id, new { expectedVersionNumber = 1, status = "revoked" })) await Error(result, 404, "not_found");
        using (var result = await owner.PostAsJsonAsync(Connections, new { provider = "health_connect", clientId = b.ClientId })) await Error(result, 400, "invalid_request");
        using (var result = await owner.PostAsJsonAsync(Connections + "/sync", new { wearableConnectionId = connection.Id, batchId = Guid.NewGuid(), changes = new[] { Change("steps", "injected") }, userId = b.User.Id })) await Error(result, 400, "invalid_request");
        Assert.Equal(0, (await other.GetFromJsonAsync<JsonElement>(Samples)).GetProperty("totalCount").GetInt32());
        foreach (var role in new[] { UserRole.Dietitian, UserRole.Admin })
        {
            var forbidden = await Seed(f, role); using var actor = Bearer(f, forbidden.User);
            var expectedStatus = role == UserRole.Admin ? 401 : 403;
            var expectedCode = role == UserRole.Admin ? "unauthenticated" : "forbidden";
            foreach (var route in new[] { Connections + "?page=1&pageSize=100", Samples, Activities + "?page=1&pageSize=100", Daily(), Activities + "/" + activity.Id })
            { using var result = await actor.GetAsync(route); await Error(result, expectedStatus, expectedCode); }
            using var write = await actor.PostAsJsonAsync(Connections + "/sync", Batch(connection.Id, [Change("steps", "injected")])); await Error(write, expectedStatus, expectedCode);
        }
        using var dietitianContext = Bearer(f, a.User, "dietitian");
        using var deniedContext = await dietitianContext.GetAsync(Samples); await Error(deniedContext, 403, "forbidden");
        var missing = await Seed(f, profile: false); using var noProfile = Bearer(f, missing.User);
        using var deniedProfile = await noProfile.GetAsync(Samples); await Error(deniedProfile, 403, "forbidden");
        var unverified = await Seed(f); using var unverifiedClient = Bearer(f, unverified.User);
        await using (var db = f.Database()) await db.Users.Where(x => x.Id == unverified.User.Id).ExecuteUpdateAsync(s => s.SetProperty(x => x.IsEmailVerified, false));
        using var invalid = await unverifiedClient.GetAsync(Samples); await Error(invalid, 401, "unauthenticated");
        using var anonymous = f.Client(); using var noAuth = await anonymous.GetAsync(Samples); await Error(noAuth, 401, "unauthenticated");
    }

    [PostgresFact]
    public async Task ValidationIsAtomicBoundedAndDoesNotPretendLastAttemptSucceeded()
    {
        await using var f = await RegistrationApiFactory.CreateAsync(); var a = await Seed(f); using var client = Bearer(f, a.User); var c = await Connect(client);
        var success = await Sync(client, c.Id, [Change("steps", "kept")]);
        var badCases = new (object Change, string Code)[]
        {
            (Change("sleep", "bad"), "unsupported_metric"), (Change("steps", "", value: 1), "invalid_source_identity"),
            (Change("steps", "bad", sourceId: ""), "invalid_source_identity"), (Change("steps", "bad", unit: "unknown"), "unsupported_unit"),
            (Change("steps", "bad", value: -1), "invalid_value"), (Change("steps", "bad", value: 1.2m), "invalid_value"),
            (Change("steps", "bad", end: Day), "invalid_interval"), (Change("steps", "bad", end: Day.AddDays(8)), "invalid_interval"),
            (Change("steps", "bad", start: DateTimeOffset.UtcNow.AddDays(1), end: DateTimeOffset.UtcNow.AddDays(1).AddHours(1)), "invalid_interval"),
            (Change("distance", "bad", rawType: "STEPS"), "unsupported_source_type"),
            (Change("heart_rate", "bad", value: 0), "invalid_value"), (Change("exercise", "bad", value: 19), "duration_mismatch")
        };
        foreach (var (change, code) in badCases)
        {
            using var response = await client.PostAsJsonAsync(Connections + "/sync", Batch(c.Id, [Change("steps", "would-be-partial"), change]));
            await Error(response, 422, code);
        }
        using (var empty = await client.PostAsJsonAsync(Connections + "/sync", Batch(c.Id, []))) await Error(empty, 422, "invalid_sync_batch");
        using (var duplicate = await client.PostAsJsonAsync(Connections + "/sync", Batch(c.Id, [Change("steps", "same"), Change("steps", "same")]))) await Error(duplicate, 422, "duplicate_source_record");
        using (var oversized = await client.PostAsJsonAsync(Connections + "/sync", Batch(c.Id, Enumerable.Range(0, 101).Select(n => Change("steps", n.ToString())).ToArray()))) await Error(oversized, 413, "sync_batch_limit");
        using (var unsupported = await client.PostAsJsonAsync(Connections, new { provider = "other" })) await Error(unsupported, 422, "unsupported_provider");
        var status = await client.GetFromJsonAsync<WearableConnectionResponse>(Connections + "/" + c.Id);
        Assert.Equal("failed", status!.LastSyncStatus); Assert.Equal(success.CommittedAt, status.LastSyncedAt); Assert.NotNull(status.LastErrorCode);
        await using var db = f.Database(); Assert.Equal(1, await db.WearableRecords.CountAsync()); Assert.Equal(1, await db.WearableSyncBatches.CountAsync());
    }

    [PostgresFact]
    public async Task ConcurrentRetryAndOptimisticCorrectionCannotDuplicateOrLoseUpdates()
    {
        await using var f = await RegistrationApiFactory.CreateAsync(); var a = await Seed(f); using var client = Bearer(f, a.User); var c = await Connect(client);
        var body = Batch(c.Id, [Change("steps", "concurrent")]);
        var retries = await Task.WhenAll(Enumerable.Range(0, 4).Select(_ => client.PostAsJsonAsync(Connections + "/sync", body)));
        foreach (var response in retries) { using (response) Assert.Equal(HttpStatusCode.OK, response.StatusCode); }
        var updates = await Task.WhenAll(new[] { 300m, 400m }.Select(v => client.PostAsJsonAsync(Connections + "/sync", Batch(c.Id, [Change("steps", "concurrent", version: 1, value: v)]))));
        Assert.Single(updates, r => r.StatusCode == HttpStatusCode.OK); Assert.Single(updates, r => r.StatusCode == HttpStatusCode.Conflict);
        foreach (var response in updates) response.Dispose();
        await using var db = f.Database(); Assert.Equal(1, await db.WearableRecords.CountAsync()); Assert.Equal(1, await db.HealthMetricSamples.CountAsync());
        Assert.Equal(2, (await db.WearableRecords.SingleAsync()).VersionNumber); Assert.Equal(2, await db.WearableSyncBatches.CountAsync());
    }

    [PostgresFact]
    public async Task BatchIdCannotBeReusedAndAConflictRollsBackOtherChanges()
    {
        await using var f = await RegistrationApiFactory.CreateAsync(); var a = await Seed(f); using var client = Bearer(f, a.User); var c = await Connect(client);
        var batch = Guid.NewGuid(); await Sync(client, c.Id, [Change("steps", "existing")], batch);
        using (var conflict = await client.PostAsJsonAsync(Connections + "/sync", Batch(c.Id, [Change("steps", "existing", value: 9)], batch))) await Error(conflict, 409, "sync_batch_conflict");
        using (var conflict = await client.PostAsJsonAsync(Connections + "/sync", Batch(c.Id, [Change("steps", "aaa-new"), Change("steps", "existing", version: 0, value: 9)]))) await Error(conflict, 409, "source_version_conflict");
        await using var db = f.Database(); Assert.Equal(1, await db.WearableRecords.CountAsync()); Assert.Equal(1, await db.HealthMetricSamples.CountAsync());
    }

    [PostgresFact]
    public async Task HeartRateNativeRecordRetainsPointsAcrossPartialWindowsAndUsesExplicitRemoval()
    {
        await using var f = await RegistrationApiFactory.CreateAsync(); var a = await Seed(f); using var client = Bearer(f, a.User); var c = await Connect(client);
        var t1 = Day.AddHours(10); var t2 = t1.AddMinutes(1); var t3 = t2.AddMinutes(1);
        await Sync(client, c.Id, [Heart("hr-record", 0, [(t1, 60m), (t2, 80m)])]);
        await Sync(client, c.Id, [Heart("hr-record", 1, [(t3, 100m)])]);
        Assert.Equal(3, (await client.GetFromJsonAsync<JsonElement>(Samples)).GetProperty("totalCount").GetInt32());
        var summary = await client.GetFromJsonAsync<ActivityDailySummaryResponse>(Daily()); Assert.Equal(3, summary!.HeartRateSampleCount); Assert.Equal(80, summary.HeartRateMeanBpm);
        await Sync(client, c.Id, [Heart("hr-record", 2, [(t2, 90m)], [t1.ToString("O")])]);
        var remaining = await client.GetFromJsonAsync<JsonElement>(Samples); Assert.Equal(2, remaining.GetProperty("totalCount").GetInt32());
        Assert.Equal(95, (await client.GetFromJsonAsync<ActivityDailySummaryResponse>(Daily()))!.HeartRateMeanBpm);
        Assert.Equal(3, (await client.GetFromJsonAsync<JsonElement>(Samples + "&includeDeleted=true")).GetProperty("totalCount").GetInt32());
    }

    [PostgresFact]
    public async Task RawUnitsOffsetsAndExerciseDurationAreNormalizedWithoutInventingEnergy()
    {
        await using var f = await RegistrationApiFactory.CreateAsync(); var a = await Seed(f); using var client = Bearer(f, a.User); var c = await Connect(client, "health_kit");
        await Sync(client, c.Id, [Change("distance", "distance", value: 1250, rawType: "DISTANCE_WALKING_RUNNING"),
            Change("active_energy", "energy", value: 42.5m), Change("exercise", "workout", value: 30)]);
        var samples = (await client.GetFromJsonAsync<JsonElement>(Samples)).GetProperty("items").EnumerateArray().ToArray();
        var distance = samples.Single(s => s.GetProperty("metric").GetString() == "distance");
        Assert.Equal(1250, distance.GetProperty("rawValue").GetDecimal()); Assert.Equal(1.25m, distance.GetProperty("value").GetDecimal());
        Assert.Equal("METER", distance.GetProperty("rawUnit").GetString()); Assert.Equal("km", distance.GetProperty("unit").GetString());
        Assert.Equal(TimeSpan.Zero, distance.GetProperty("startedAt").GetDateTimeOffset().Offset);
        var activities = (await client.GetFromJsonAsync<JsonElement>(Activities + "?page=1&pageSize=100")).GetProperty("items");
        Assert.Equal(1, activities.GetArrayLength()); Assert.Equal(30, activities[0].GetProperty("durationMinutes").GetDecimal());
        Assert.Equal(JsonValueKind.Null, activities[0].GetProperty("caloriesKcal").ValueKind);
        var summary = await client.GetFromJsonAsync<ActivityDailySummaryResponse>(Daily()); Assert.Equal(1.25m, summary!.DistanceKm); Assert.Equal(42.5m, summary.ActiveEnergyKcal); Assert.Equal(30, summary.ExerciseMinutes);
        using var readOnly = await client.DeleteAsync(Activities + "/" + activities[0].GetProperty("id").GetGuid() + "?expectedVersionNumber=1"); await Error(readOnly, 409, "source_record_read_only");
    }

    [PostgresFact]
    public async Task RevocationStopsImportAndReconnectDoesNotReactivateOrDeleteHistory()
    {
        await using var f = await RegistrationApiFactory.CreateAsync(); var a = await Seed(f); using var client = Bearer(f, a.User); var c = await Connect(client);
        await Sync(client, c.Id, [Change("steps", "kept")]);
        using var revoke = await client.PatchAsJsonAsync(Connections + "/" + c.Id, new { expectedVersionNumber = 1, status = "revoked" }); Assert.Equal(HttpStatusCode.OK, revoke.StatusCode);
        var reconnected = await Connect(client); Assert.Equal(c.Id, reconnected.Id); Assert.Equal("revoked", reconnected.Status); Assert.Equal(2, reconnected.VersionNumber);
        using var denied = await client.PostAsJsonAsync(Connections + "/sync", Batch(c.Id, [Change("steps", "new")])); await Error(denied, 403, "sync_disabled");
        Assert.Equal(1, (await client.GetFromJsonAsync<JsonElement>(Samples)).GetProperty("totalCount").GetInt32()); Assert.Equal(100, (await client.GetFromJsonAsync<ActivityDailySummaryResponse>(Daily()))!.Steps);
        using var staleEnable = await client.PatchAsJsonAsync(Connections + "/" + c.Id, new { expectedVersionNumber = 1, status = "active" }); await Error(staleEnable, 409, "source_version_conflict");
        using var enable = await client.PatchAsJsonAsync(Connections + "/" + c.Id, new { expectedVersionNumber = 2, status = "active" }); Assert.Equal(HttpStatusCode.OK, enable.StatusCode);
        await Sync(client, c.Id, [Change("steps", "new", start: Day.AddHours(12), end: Day.AddHours(13))]);
        await using var db = f.Database(); Assert.Equal(0, await db.DataSharingPermissions.CountAsync());
    }

    [PostgresFact]
    public async Task OverlappingSourcesAndManualEnergyAreConservativeAndDeterministic()
    {
        await using var f = await RegistrationApiFactory.CreateAsync(); var a = await Seed(f); using var client = Bearer(f, a.User);
        var android = await Connect(client); var ios = await Connect(client, "health_kit");
        await Sync(client, ios.Id, [Change("steps", "ios", value: 900), Change("active_energy", "ios-energy", value: 900), Change("exercise", "ios-ex", value: 30)]);
        await Sync(client, android.Id, [Change("steps", "android", value: 120), Change("steps", "other-app", value: 800, sourceId: "z.synthetic.app"),
            Change("steps", "adjacent", value: 20, start: Day.AddHours(11), end: Day.AddHours(12)), Change("active_energy", "android-energy", value: 50), Change("exercise", "android-ex", value: 30)]);
        await Manual(client, duration: 30, kcal: 25);
        var result = await client.GetFromJsonAsync<ActivityDailySummaryResponse>(Daily());
        Assert.Equal(140, result!.Steps); Assert.Equal(25, result.ActiveEnergyKcal); Assert.Equal(30, result.ExerciseMinutes); Assert.Equal(1, result.ExerciseCount);
        Assert.Equal(6, result.ExcludedOverlapCount); Assert.True(result.IsPartial);
        Assert.Equal(result, await client.GetFromJsonAsync<ActivityDailySummaryResponse>(Daily()));
        Assert.Equal(6, (await client.GetFromJsonAsync<JsonElement>(Samples)).GetProperty("totalCount").GetInt32());
    }

    [PostgresFact]
    public async Task MidnightAndDstBoundariesDoNotProrateUnknownScalarAllocation()
    {
        await using var f = await RegistrationApiFactory.CreateAsync(); var a = await Seed(f); using var client = Bearer(f, a.User); var c = await Connect(client);
        await Sync(client, c.Id, [Change("steps", "cross-midnight", start: Day.AddMinutes(-30), end: Day.AddMinutes(30), value: 80),
            Change("exercise", "cross-exercise", start: Day.AddMinutes(-30), end: Day.AddMinutes(30), value: 60)]);
        await Manual(client, duration: null, kcal: 10);
        var result = await client.GetFromJsonAsync<ActivityDailySummaryResponse>(Daily()); Assert.Null(result!.Steps); Assert.Equal(30, result.ExerciseMinutes);
        Assert.Null(result.ActiveEnergyKcal); Assert.Equal(2, result.UnallocatedCount);
        var before = await client.GetFromJsonAsync<ActivityDailySummaryResponse>(Daily(Day.AddDays(-1))); Assert.Null(before!.Steps); Assert.Equal(30, before.ExerciseMinutes);
        var spring = new DateTimeOffset(2026, 3, 29, 0, 0, 0, TimeSpan.FromHours(1)); var springEnd = new DateTimeOffset(2026, 3, 30, 0, 0, 0, TimeSpan.FromHours(2));
        var dst = await client.GetFromJsonAsync<ActivityDailySummaryResponse>(Daily(spring, springEnd)); Assert.Equal(23, (dst!.To - dst.From).TotalHours);
        var fall = new DateTimeOffset(2026, 10, 25, 0, 0, 0, TimeSpan.FromHours(2)); var fallEnd = new DateTimeOffset(2026, 10, 26, 0, 0, 0, TimeSpan.FromHours(1));
        Assert.Equal(25, ((await client.GetFromJsonAsync<ActivityDailySummaryResponse>(Daily(fall, fallEnd)))!.To - fall.ToUniversalTime()).TotalHours);
        using var bad = await client.GetAsync(Daily(Day.AddHours(1))); await Error(bad, 400, "invalid_request");
    }

    [PostgresFact]
    public async Task ManualActivityEditingUsesVersionsAndNeverAllowsWearableSpoofing()
    {
        await using var f = await RegistrationApiFactory.CreateAsync(); var a = await Seed(f); using var client = Bearer(f, a.User); var row = await Manual(client);
        var patch = new { expectedVersionNumber = 1, activityType = "synthetic walk edited", startedAt = Day.AddHours(10), durationMinutes = 40, distanceKm = 2, caloriesKcal = (decimal?)null };
        using var edit = await client.PatchAsJsonAsync(Activities + "/" + row.Id, patch); Assert.Equal(HttpStatusCode.OK, edit.StatusCode);
        var updated = (await edit.Content.ReadFromJsonAsync<ActivityLogResponse>())!; Assert.Equal(2, updated.VersionNumber); Assert.Equal(40, updated.DurationMinutes);
        using var stale = await client.PatchAsJsonAsync(Activities + "/" + row.Id, patch); await Error(stale, 409, "source_version_conflict");
        using var forged = await client.PostAsJsonAsync(Activities, new { activityType = "synthetic", startedAt = Day, durationMinutes = 1, distanceKm = (decimal?)null, caloriesKcal = (decimal?)null, source = "wearable" }); await Error(forged, 422, "invalid_value");
        using var deleted = await client.DeleteAsync(Activities + "/" + row.Id + "?expectedVersionNumber=2"); Assert.Equal(HttpStatusCode.NoContent, deleted.StatusCode);
        using var missing = await client.GetAsync(Activities + "/" + row.Id); await Error(missing, 404, "not_found");
    }

    [PostgresFact]
    public async Task QueryPaginationStrictJsonAndExplicitOffsetsAreEnforced()
    {
        await using var f = await RegistrationApiFactory.CreateAsync(); var a = await Seed(f); using var client = Bearer(f, a.User); var c = await Connect(client);
        await Sync(client, c.Id, [Change("steps", "a"), Change("steps", "b", start: Day.AddHours(12), end: Day.AddHours(13))]);
        var first = await client.GetFromJsonAsync<JsonElement>(Samples.Replace("pageSize=100", "pageSize=1")); var second = await client.GetFromJsonAsync<JsonElement>(Samples.Replace("page=1", "page=2").Replace("pageSize=100", "pageSize=1"));
        Assert.Equal(2, first.GetProperty("totalCount").GetInt32()); Assert.NotEqual(first.GetProperty("items")[0].GetProperty("id").GetGuid(), second.GetProperty("items")[0].GetProperty("id").GetGuid());
        foreach (var query in new[] { "?page=0&pageSize=10", "?page=1&pageSize=101", "?page=1&pageSize=1&page=2", "?page=1&pageSize=1&clientId=" + a.ClientId,
                     "?page=1&pageSize=1&from=2026-10-20T00:00:00", "?page=2147483647&pageSize=100", "?pageSize=1" })
        { using var response = await client.GetAsync(Activities + query); await Error(response, 400, "invalid_request"); }
        using var invalidJson = await client.PostAsJsonAsync(Connections + "/sync", new { wearableConnectionId = c.Id, batchId = Guid.NewGuid(), changes = new[] { new { operation = "upsert", metric = "steps", sourceId = "synthetic.app", externalRecordId = "x", rawType = "STEPS", expectedVersionNumber = 0, sourceName = "Synthetic", recordingMethod = "0", rawUnit = "COUNT", samples = new[] { new { startedAt = "2026-10-20T10:00:00", endedAt = "2026-10-20T11:00:00Z", rawValue = 1 } } } } });
        await Error(invalidJson, 400, "invalid_request");
    }

    [PostgresFact]
    public async Task DatabaseConstraintsAndMigrationRollbackProtectHealthAndExistingData()
    {
        await using var f = await RegistrationApiFactory.CreateAsync(); var a = await Seed(f); var b = await Seed(f); using var client = Bearer(f, a.User); var c = await Connect(client);
        await Sync(client, c.Id, [Change("steps", "constraint")]);
        await using var db = f.Database();
        async Task Rejected(FormattableString sql, string state)
        { var error = await Assert.ThrowsAsync<PostgresException>(() => db.Database.ExecuteSqlInterpolatedAsync(sql)); Assert.Equal(state, error.SqlState); }
        await Rejected($"INSERT INTO health_metric_samples (id,client_id,wearable_record_id,sample_key,started_at,ended_at,raw_value,value,unit,is_deleted) SELECT {Guid.NewGuid()},client_id,wearable_record_id,sample_key,started_at,ended_at,raw_value,value,unit,is_deleted FROM health_metric_samples LIMIT 1", PostgresErrorCodes.UniqueViolation);
        await Rejected($"INSERT INTO health_metric_samples (id,client_id,wearable_record_id,sample_key,started_at,ended_at,raw_value,value,unit,is_deleted) SELECT {Guid.NewGuid()},{b.ClientId},wearable_record_id,'foreign',started_at,ended_at,raw_value,value,unit,is_deleted FROM health_metric_samples LIMIT 1", PostgresErrorCodes.ForeignKeyViolation);
        await Rejected($"UPDATE health_metric_samples SET value = {-1m}", PostgresErrorCodes.CheckViolation);
        var migrator = db.GetService<IMigrator>();
        var rollback = await Assert.ThrowsAsync<PostgresException>(() => migrator.MigrateAsync("20261118204842_AddClientTasks")); Assert.Contains("Cannot remove health", rollback.MessageText);
        Assert.Equal(1, await db.HealthMetricSamples.CountAsync()); Assert.True(await db.Users.AnyAsync(x => x.Id == a.User.Id));
        Assert.Equal("20261118222117_AddHealthDataSync", (await db.Database.GetAppliedMigrationsAsync()).Last());
    }

    private static object Batch(Guid connection, object[] changes, Guid? batchId = null) => new { wearableConnectionId = connection, batchId = batchId ?? Guid.NewGuid(), changes };
    private static object Change(string metric, string id, int version = 0, decimal value = 100, string sourceId = "a.synthetic.app",
        string? unit = null, string? rawType = null, DateTimeOffset? start = null, DateTimeOffset? end = null)
    {
        var begin = start ?? Day.AddHours(10); var finish = end ?? (metric == "heart_rate" ? begin : metric == "exercise" ? begin.AddMinutes(30) : begin.AddHours(1));
        return new { operation = "upsert", metric, sourceId, externalRecordId = id, rawType = rawType ?? metric switch { "steps" => "STEPS", "distance" => "DISTANCE_DELTA", "exercise" => "WORKOUT", "active_energy" => "ACTIVE_ENERGY_BURNED", _ => "HEART_RATE" },
            expectedVersionNumber = version, sourceName = "Synthetic source", recordingMethod = "0", exerciseType = metric == "exercise" ? "synthetic_walk" : null,
            rawUnit = unit ?? metric switch { "steps" => "COUNT", "distance" => "METER", "exercise" => "MINUTE", "active_energy" => "KILOCALORIE", _ => "BEATS_PER_MINUTE" },
            samples = new[] { new { startedAt = begin, endedAt = finish, rawValue = value } } };
    }
    private static object Heart(string id, int version, (DateTimeOffset Time, decimal Value)[] points, string[]? deleted = null) => new
    {
        operation = "upsert", metric = "heart_rate", sourceId = "a.synthetic.app", externalRecordId = id, rawType = "HEART_RATE", expectedVersionNumber = version,
        sourceName = "Synthetic source", recordingMethod = "0", rawUnit = "BEATS_PER_MINUTE",
        samples = points.Select(p => new { startedAt = p.Time, endedAt = p.Time, rawValue = p.Value }), deletedSampleStarts = deleted
    };
    private static object Delete(string metric, string id, int version) => new { operation = "delete", metric, sourceId = "a.synthetic.app", externalRecordId = id, rawType = metric == "steps" ? "STEPS" : "HEART_RATE", expectedVersionNumber = version };
    private static async Task<WearableSyncResult> Sync(HttpClient client, Guid connection, object[] changes, Guid? batchId = null)
    {
        using var response = await client.PostAsJsonAsync(Connections + "/sync", Batch(connection, changes, batchId));
        Assert.True(response.StatusCode == HttpStatusCode.OK, $"{response.StatusCode}: {await response.Content.ReadAsStringAsync()}");
        return (await response.Content.ReadFromJsonAsync<WearableSyncResult>())!;
    }
    private static async Task<WearableConnectionResponse> Connect(HttpClient client, string provider = "health_connect")
    { using var response = await client.PostAsJsonAsync(Connections, new { provider }); response.EnsureSuccessStatusCode(); return (await response.Content.ReadFromJsonAsync<WearableConnectionResponse>())!; }
    private static async Task<ActivityLogResponse> Manual(HttpClient client, decimal? duration = 30, decimal? kcal = null)
    {
        using var response = await client.PostAsJsonAsync(Activities, new { activityType = "Synthetic walk", startedAt = Day.AddHours(10), durationMinutes = duration, distanceKm = (decimal?)null, caloriesKcal = kcal, source = "manual" });
        response.EnsureSuccessStatusCode(); return (await response.Content.ReadFromJsonAsync<ActivityLogResponse>())!;
    }
    private sealed record Account(User User, Guid ClientId);
    private static async Task<Account> Seed(RegistrationApiFactory factory, UserRole role = UserRole.Client, bool verified = true, bool profile = true)
    {
        await using var db = factory.Database(); var user = new User(Guid.NewGuid(), Guid.NewGuid().ToString("N") + "@EXAMPLE.TEST", role, "Synthetic health password", DateTimeOffset.UtcNow, new PasswordHasher<User>());
        var client = profile && role == UserRole.Client ? new ClientProfile(Guid.NewGuid(), user, "Synthetic health client") : null;
        if (role == UserRole.Dietitian) _ = new DietitianProfile(user, "Synthetic expert", "Synthetic license");
        db.Users.Add(user); db.Entry(user).Property(u => u.IsEmailVerified).CurrentValue = verified; await db.SaveChangesAsync();
        return new(user, client?.Id ?? Guid.Empty);
    }
    private static HttpClient Bearer(RegistrationApiFactory factory, User user, string context = "client")
    {
        var client = factory.Client(false); var settings = factory.Jwt.Options;
        // Deliberately sign a test-only Admin claim: the real issuer never issues it,
        // and the production validator must reject it before resource authorization.
        var token = user.Role != UserRole.Admin ? new JwtAccessTokenService(Options.Create(settings), TimeProvider.System).Issue(user).AccessToken :
            new JsonWebTokenHandler().CreateToken(new SecurityTokenDescriptor
            {
                Issuer = settings.Issuer, Audience = settings.Audience, TokenType = "at+jwt",
                Subject = new ClaimsIdentity([new Claim("sub", user.Id.ToString("D")), new Claim("role", "admin"), new Claim("credentialsVersion", "0")]),
                NotBefore = DateTime.UtcNow.AddSeconds(-1), Expires = DateTime.UtcNow.AddMinutes(5),
                SigningCredentials = new SigningCredentials(settings.CreateSigningKey(), SecurityAlgorithms.HmacSha256)
            });
        client.DefaultRequestHeaders.Authorization = new("Bearer", token); client.DefaultRequestHeaders.Add("X-Profile-Context", context); return client;
    }
    private static async Task Error(HttpResponseMessage response, int status, string code)
    {
        var text = await response.Content.ReadAsStringAsync(); Assert.True((int)response.StatusCode == status, $"Expected {status}, got {response.StatusCode}: {text}");
        var json = JsonSerializer.Deserialize<JsonElement>(text); Assert.Equal(code, json.GetProperty("error").GetProperty("code").GetString());
        Assert.False(string.IsNullOrWhiteSpace(json.GetProperty("requestId").GetString())); Assert.Contains("no-store", response.Headers.CacheControl!.ToString());
        Assert.DoesNotContain("private-record", text);
    }
}
