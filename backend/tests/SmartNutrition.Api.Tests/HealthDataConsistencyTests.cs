using System.Data.Common;
using System.Net;
using System.Net.Http.Json;
using System.Text;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using SmartNutrition.Api.Data;
using SmartNutrition.Api.Features.HealthData;

namespace SmartNutrition.Api.Tests;

public sealed partial class HealthDataApiTests
{
    [PostgresFact]
    public async Task KestrelRejectsOversizedSyncBeforeBindingAndDoesNotWriteHealthRows()
    {
        await using var f = await RegistrationApiFactory.CreateAsync(); var account = await Seed(f);
        using var bearer = Bearer(f, account.User); await using var db = f.Database();
        var settings = new Dictionary<string, string?>(f.Jwt.Configuration)
        { ["ConnectionStrings:DefaultConnection"] = db.Database.GetConnectionString() };
        await using var host = new WebApplicationFactory<Program>().WithWebHostBuilder(builder => builder
            .UseEnvironment("Production").ConfigureAppConfiguration((_, c) => c.AddInMemoryCollection(settings)));
        host.UseKestrel(0); using var client = host.CreateClient(); client.DefaultRequestHeaders.Authorization = bearer.DefaultRequestHeaders.Authorization;
        using var content = new StringContent("{\"padding\":\"" + new string('x', 524288) + "\"}", Encoding.UTF8, "application/json");
        using var response = await client.PostAsync(Connections + "/sync", content); await Error(response, 413, "payload_too_large");
        Assert.Equal(0, await db.WearableRecords.CountAsync());
    }

    [PostgresFact]
    public async Task ExerciseCorrectionAndDeletionPreserveOneCanonicalActivityAndItsRawDuration()
    {
        await using var f = await RegistrationApiFactory.CreateAsync(); var account = await Seed(f); using var client = Bearer(f, account.User);
        var connection = await Connect(client); await Sync(client, connection.Id, [Change("exercise", "native-exercise", value: 30)]);
        var before = await client.GetFromJsonAsync<System.Text.Json.JsonElement>(Activities + "?page=1&pageSize=100");
        var id = before.GetProperty("items")[0].GetProperty("id").GetGuid();
        await Sync(client, connection.Id, [Change("exercise", "native-exercise", version: 1, value: 40.000001m, end: Day.AddHours(10).AddMinutes(40))]);
        var changed = await client.GetFromJsonAsync<ActivityLogResponse>(Activities + "/" + id);
        Assert.Equal(40, changed!.DurationMinutes); Assert.Equal(40.000001m, changed.RawDurationMinutes); Assert.Equal(2, changed.VersionNumber);
        await Sync(client, connection.Id, [new { operation = "delete", metric = "exercise", sourceId = "a.synthetic.app", externalRecordId = "native-exercise", rawType = "WORKOUT", expectedVersionNumber = 2 }]);
        using var missing = await client.GetAsync(Activities + "/" + id); await Error(missing, 404, "not_found");
        await using var db = f.Database(); Assert.Equal(1, await db.ActivityLogs.CountAsync()); Assert.True((await db.ActivityLogs.SingleAsync()).IsDeleted);
        Assert.DoesNotContain("native-exercise", f.Logs);
    }

    [PostgresFact]
    public async Task MigrationCreatesTheActualColumnsKeysAndIndexesExpectedByTheModel()
    {
        await using var f = await RegistrationApiFactory.CreateAsync(); await using var db = f.Database();
        await db.Database.OpenConnectionAsync();
        var names = new[] { "wearable_connections", "wearable_records", "health_metric_samples", "activity_logs", "wearable_sync_batches" };
        foreach (var table in db.Model.GetRelationalModel().Tables.Where(t => names.Contains(t.Name)))
        {
            await using var command = db.Database.GetDbConnection().CreateCommand();
            command.CommandText = $"SELECT attname FROM pg_attribute WHERE attrelid = '{table.Name}'::regclass AND attnum > 0 AND NOT attisdropped";
            await using (var reader = await command.ExecuteReaderAsync())
            {
                List<string> columns = []; while (await reader.ReadAsync()) columns.Add(reader.GetString(0));
                Assert.Equal(table.Columns.Select(c => c.Name).Order(), columns.Order());
            }
            command.CommandText = $"SELECT conname FROM pg_constraint WHERE conrelid = '{table.Name}'::regclass UNION ALL SELECT indexname FROM pg_indexes WHERE schemaname=current_schema() AND tablename='{table.Name}'";
            await using var constraints = await command.ExecuteReaderAsync(); List<string> actual = [];
            while (await constraints.ReadAsync()) actual.Add(constraints.GetString(0));
            foreach (var name in table.ForeignKeyConstraints.Select(c => c.Name).Concat(table.UniqueConstraints.Select(c => c.Name)).Concat(table.Indexes.Select(c => c.Name)))
                Assert.Contains(name, actual);
        }
    }

    [PostgresFact]
    public async Task U3MigrationPreservesEveryPreexistingTableAndCanRollbackOnlyWhileEmpty()
    {
        await using var f = await RegistrationApiFactory.CreateAsync();
        await using (var db = f.Database()) await db.GetService<IMigrator>().MigrateAsync("20261118204842_AddClientTasks");
        var account = await Seed(f);
        await using var database = f.Database();
        var before = await OldTableFingerprint(database);
        await database.Database.MigrateAsync();
        Assert.Equal(before, await OldTableFingerprint(database));
        Assert.True(await database.Users.AnyAsync(x => x.Id == account.User.Id));
        await database.GetService<IMigrator>().MigrateAsync("20261118204842_AddClientTasks");
        Assert.Equal(before, await OldTableFingerprint(database));
        await database.Database.MigrateAsync();
        Assert.False(database.Database.HasPendingModelChanges());
    }

    [PostgresFact]
    public async Task DatabaseFailureRollsBackBulkTombstonesReceiptAndSuccessMetadata()
    {
        var failure = new ReceiptFailure(); await using var f = await RegistrationApiFactory.CreateAsync(interceptor: failure);
        var account = await Seed(f); using var client = Bearer(f, account.User); var connection = await Connect(client);
        var original = await Sync(client, connection.Id, [Change("steps", "preserved")]);
        failure.Armed = true;
        using var result = await client.PostAsJsonAsync(Connections + "/sync", Batch(connection.Id, [Delete("steps", "preserved", 1)]));
        await Error(result, 500, "internal_error");
        await using var db = f.Database(); Assert.False((await db.HealthMetricSamples.SingleAsync()).IsDeleted);
        var record = await db.WearableRecords.SingleAsync(); Assert.False(record.IsDeleted); Assert.Equal(1, record.VersionNumber);
        Assert.Equal(1, await db.WearableSyncBatches.CountAsync());
        var status = await client.GetFromJsonAsync<WearableConnectionResponse>(Connections + "/" + connection.Id);
        Assert.Equal(original.CommittedAt, status!.LastSyncedAt);
    }

    [PostgresFact]
    public async Task RevocationCompletingBeforeAWaitingImportIsRecheckedUnderTheClientLock()
    {
        var pause = new ClientWritePause(); await using var f = await RegistrationApiFactory.CreateAsync(interceptor: pause);
        var account = await Seed(f); using var client = Bearer(f, account.User); var connection = await Connect(client);
        await Sync(client, connection.Id, [Change("steps", "existing")]);
        pause.Armed = true;
        var revoke = client.PatchAsJsonAsync(Connections + "/" + connection.Id, new { expectedVersionNumber = 1, status = "revoked" });
        await pause.Entered.Task.WaitAsync(TimeSpan.FromSeconds(10));
        var import = client.PostAsJsonAsync(Connections + "/sync", Batch(connection.Id, [Change("steps", "waiting")]));
        pause.Release.TrySetResult();
        using var revoked = await revoke; Assert.Equal(HttpStatusCode.OK, revoked.StatusCode);
        using var denied = await import; await Error(denied, 403, "sync_disabled");
        await using var db = f.Database(); Assert.Equal(1, await db.WearableRecords.CountAsync());
    }

    [PostgresFact]
    public async Task ZeroIsKnownAndMicrosecondEquivalentPointKeysCannotDuplicate()
    {
        await using var f = await RegistrationApiFactory.CreateAsync(); var a = await Seed(f); using var client = Bearer(f, a.User); var c = await Connect(client);
        await Sync(client, c.Id, [Change("steps", "zero", value: 0)]);
        Assert.Equal(0, (await client.GetFromJsonAsync<ActivityDailySummaryResponse>(Daily()))!.Steps);
        var now = Day.AddHours(10); var sameUtc = now.ToOffset(TimeSpan.FromHours(-4));
        using var duplicate = await client.PostAsJsonAsync(Connections + "/sync", Batch(c.Id, [Heart("same-point", 0, [(now, 60m), (sameUtc.AddTicks(1), 70m)])]));
        await Error(duplicate, 422, "invalid_sync_batch");
        using var tooMany = await client.PostAsJsonAsync(Connections + "/sync", Batch(c.Id, [Heart("too-many", 0,
            Enumerable.Range(0, 1001).Select(i => (now.AddSeconds(i), 60m)).ToArray())]));
        await Error(tooMany, 413, "sync_batch_limit");
    }

    private static async Task<string> OldTableFingerprint(AppDbContext db)
    {
        await db.Database.OpenConnectionAsync(); await using var command = db.Database.GetDbConnection().CreateCommand();
        command.CommandText = """
            CREATE TEMP TABLE health_old_snapshot (name text, digest text);
            DO $$ DECLARE r record; h text; BEGIN
              FOR r IN SELECT tablename FROM pg_tables WHERE schemaname=current_schema() AND tablename NOT IN
                ('__ef_migrations_history','activity_logs','wearable_connections','wearable_records','health_metric_samples','wearable_sync_batches') ORDER BY tablename LOOP
                EXECUTE format('SELECT md5(coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text)::text,''[]'')) FROM %I t',r.tablename) INTO h;
                INSERT INTO health_old_snapshot VALUES(r.tablename,h);
              END LOOP;
            END $$;
            SELECT jsonb_agg(jsonb_build_object('table',name,'hash',digest) ORDER BY name)::text FROM health_old_snapshot;
            DROP TABLE health_old_snapshot;
            """;
        return (string)(await command.ExecuteScalarAsync())!;
    }
    private sealed class ReceiptFailure : DbCommandInterceptor
    {
        internal bool Armed;
        public override ValueTask<InterceptionResult<DbDataReader>> ReaderExecutingAsync(DbCommand command, CommandEventData eventData,
            InterceptionResult<DbDataReader> result, CancellationToken cancellationToken = default)
        {
            if (Armed && command.CommandText.Contains("INSERT INTO wearable_sync_batches", StringComparison.Ordinal))
            { Armed = false; throw new InvalidOperationException("Synthetic receipt persistence failure"); }
            return ValueTask.FromResult(result);
        }
    }
    private sealed class ClientWritePause : DbCommandInterceptor
    {
        internal bool Armed;
        internal TaskCompletionSource Entered { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal TaskCompletionSource Release { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public override async ValueTask<InterceptionResult<DbDataReader>> ReaderExecutingAsync(DbCommand command, CommandEventData eventData,
            InterceptionResult<DbDataReader> result, CancellationToken cancellationToken = default)
        {
            if (Armed && command.CommandText.Contains("FROM client_profiles", StringComparison.Ordinal) && command.CommandText.Contains("FOR UPDATE", StringComparison.Ordinal))
            { Armed = false; Entered.TrySetResult(); await Release.Task.WaitAsync(TimeSpan.FromSeconds(10), cancellationToken); }
            return result;
        }
    }
}
