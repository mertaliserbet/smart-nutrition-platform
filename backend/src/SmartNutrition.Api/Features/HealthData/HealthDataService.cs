using System.Data;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using SmartNutrition.Api.Data;
using SmartNutrition.Api.Features.Dietitians;
using SmartNutrition.Api.Features.Relationships;

namespace SmartNutrition.Api.Features.HealthData;

public sealed class HealthDataService(AppDbContext db, RelationshipAccessService access, TimeProvider clock)
{
    internal async Task LockAsync(ProfileIdentity actor, CancellationToken token)
    {
        await access.LockActorAsync(actor, token);
        await access.LockClientAsync(actor.ClientId!.Value, token);
    }
    public async Task<WearableConnectionResponse> ConnectAsync(ProfileIdentity actor, string provider, CancellationToken token)
    {
        HealthDataValidation.Provider(provider);
        await using var tx = await db.Database.BeginTransactionAsync(token);
        await LockAsync(actor, token);
        var client = actor.ClientId!.Value;
        var row = await db.WearableConnections.SingleOrDefaultAsync(x => x.ClientId == client && x.Provider == provider, token);
        if (row is null)
        {
            row = new() { Id = Guid.NewGuid(), ClientId = client, Provider = provider };
            db.WearableConnections.Add(row);
            await db.SaveChangesAsync(token);
        }
        await tx.CommitAsync(token);
        return WearableConnectionResponse.From(row);
    }
    public async Task<PagedResponse<WearableConnectionResponse>> ConnectionsAsync(Guid client, int page, int size, CancellationToken token)
    {
        await using var tx = await db.Database.BeginTransactionAsync(IsolationLevel.RepeatableRead, token);
        var query = db.WearableConnections.AsNoTracking().Where(x => x.ClientId == client);
        var count = await query.CountAsync(token);
        var rows = await query.OrderBy(x => x.Provider).Skip((page - 1) * size).Take(size).ToListAsync(token);
        await tx.CommitAsync(token);
        return new(rows.Select(WearableConnectionResponse.From).ToArray(), count);
    }
    internal async Task<WearableConnection> ConnectionAsync(Guid client, Guid id, CancellationToken token) =>
        await db.WearableConnections.SingleOrDefaultAsync(x => x.ClientId == client && x.Id == id, token) ?? throw new ResourceOperationException(404);
    public async Task<WearableConnectionResponse> GetConnectionAsync(Guid client, Guid id, CancellationToken token) =>
        WearableConnectionResponse.From(await ConnectionAsync(client, id, token));
    public async Task<WearableConnectionResponse> PatchConnectionAsync(ProfileIdentity actor, Guid id, PatchWearableConnectionRequest input, CancellationToken token)
    {
        if (input.Status is not ("active" or "revoked") || input.ExpectedVersionNumber < 1) throw new ResourceOperationException(422, "invalid_value");
        await using var tx = await db.Database.BeginTransactionAsync(token);
        await LockAsync(actor, token);
        var row = await ConnectionAsync(actor.ClientId!.Value, id, token);
        if (row.VersionNumber != input.ExpectedVersionNumber) throw new ResourceOperationException(409, "source_version_conflict");
        if (row.Status != input.Status) { row.Status = input.Status; row.VersionNumber++; }
        await db.SaveChangesAsync(token); await tx.CommitAsync(token);
        return WearableConnectionResponse.From(row);
    }

    public async Task<WearableSyncResult> SyncAsync(ProfileIdentity actor, WearableSyncRequest input, CancellationToken token)
    {
        await using var tx = await db.Database.BeginTransactionAsync(token);
        // Serializes this client's writes, reconnect/revoke and retries across API instances.
        await LockAsync(actor, token);
        var connection = await ConnectionAsync(actor.ClientId!.Value, input.WearableConnectionId, token);
        if (connection.Status != "active") throw new ResourceOperationException(403, "sync_disabled");
        var now = RecordTime.Normalize(clock.GetUtcNow());
        NormalizedChange[] changes;
        string hash;
        List<ChangePlan> plans = [];
        try
        {
            changes = HealthDataValidation.Normalize(input, connection.Provider, now)
                .OrderBy(c => c.SourceId, StringComparer.Ordinal).ThenBy(c => c.RawType, StringComparer.Ordinal)
                .ThenBy(c => c.ExternalRecordId, StringComparer.Ordinal).ToArray();
            hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(JsonSerializer.Serialize(changes, HealthJson.Options))));
            var receipt = await db.WearableSyncBatches.AsNoTracking().SingleOrDefaultAsync(x => x.WearableConnectionId == connection.Id && x.BatchId == input.BatchId, token);
            if (receipt is not null)
            {
                if (receipt.RequestHash != hash) throw new ResourceOperationException(409, "sync_batch_conflict");
                await tx.CommitAsync(token);
                return JsonSerializer.Deserialize<WearableSyncResult>(receipt.ResponseJson, HealthJson.Options)!;
            }
            foreach (var change in changes) plans.Add(await PlanAsync(connection, change, token));
        }
        catch (ResourceOperationException error) when (error.StatusCode is 409 or 413 or 422)
        {
            // Plans have not mutated health rows. Commit only safe attempt metadata.
            connection.LastAttemptAt = now; connection.LastSyncStatus = "failed"; connection.LastErrorCode = error.Code;
            await db.SaveChangesAsync(token); await tx.CommitAsync(token);
            throw;
        }
        foreach (var plan in plans) await ApplyAsync(connection, plan, now, token);
        var result = new WearableSyncResult(input.BatchId, connection.Id, now,
            plans.Select(p => WearableRecordResponse.From(p.Record, connection.Provider)).ToArray());
        db.WearableSyncBatches.Add(new()
        {
            Id = Guid.NewGuid(), ClientId = connection.ClientId, WearableConnectionId = connection.Id, BatchId = input.BatchId,
            RequestHash = hash, ResponseJson = JsonSerializer.Serialize(result, HealthJson.Options), CommittedAt = now
        });
        connection.LastSyncedAt = now; connection.LastAttemptAt = now; connection.LastSyncStatus = "succeeded"; connection.LastErrorCode = null;
        await db.SaveChangesAsync(token); await tx.CommitAsync(token);
        return result;
    }
    private sealed record ChangePlan(NormalizedChange Change, WearableRecord Record, bool IsNew, bool Changed,
        List<HealthMetricSample> Samples, ActivityLog? Activity);
    private async Task<ChangePlan> PlanAsync(WearableConnection connection, NormalizedChange c, CancellationToken token)
    {
        var row = await db.WearableRecords.SingleOrDefaultAsync(x => x.WearableConnectionId == connection.Id && x.SourceId == c.SourceId &&
            x.RawType == c.RawType && x.ExternalRecordId == c.ExternalRecordId, token);
        var isNew = row is null;
        row ??= new() { Id = Guid.NewGuid(), ClientId = connection.ClientId, WearableConnectionId = connection.Id,
            SourceId = c.SourceId, ExternalRecordId = c.ExternalRecordId, RawType = c.RawType, Metric = c.Metric, RawUnit = c.RawUnit };
        if (row.Metric != c.Metric) throw new ResourceOperationException(409, "source_version_conflict");
        List<HealthMetricSample> samples = [];
        ActivityLog? activity = null;
        if (c.Metric == "exercise") activity = await db.ActivityLogs.SingleOrDefaultAsync(x => x.WearableRecordId == row.Id, token);
        else if (c.Operation == "upsert")
        {
            var keys = c.Samples.Select(s => s.Key).Concat(c.DeletedKeys).ToArray();
            samples = await db.HealthMetricSamples.Where(x => x.WearableRecordId == row.Id && keys.Contains(x.SampleKey)).ToListAsync(token);
        }
        var changed = isNew || (c.Operation == "delete" ? !row.IsDeleted : row.IsDeleted || row.SourceName != c.SourceName ||
            row.RecordingMethod != c.RecordingMethod || row.ExerciseType != c.ExerciseType ||
            (c.Metric == "exercise" ? ActivityChanged(activity, c) : c.Samples.Any(s => !samples.Any(old => Same(old, s))) ||
                samples.Any(s => !s.IsDeleted && c.DeletedKeys.Contains(s.SampleKey))));
        // Exact desired-state retries are harmless. A stale mutation must never overwrite a newer value or tombstone.
        if (changed && c.ExpectedVersionNumber != row.VersionNumber) throw new ResourceOperationException(409, "source_version_conflict");
        return new(c, row, isNew, changed, samples, activity);
    }
    private static bool Same(HealthMetricSample old, NormalizedSample s) => !old.IsDeleted && old.StartedAt == s.StartedAt &&
        old.EndedAt == s.EndedAt && old.RawValue == s.RawValue && old.Value == s.Value && old.Unit == s.Unit;
    private static bool ActivityChanged(ActivityLog? old, NormalizedChange c) => old is null || old.IsDeleted || old.ActivityType != c.ExerciseType ||
        old.StartedAt != c.Samples[0].StartedAt || old.EndedAt != c.Samples[0].EndedAt || old.DurationMinutes != c.Samples[0].Value || old.RawDurationMinutes != c.Samples[0].RawValue;
    private async Task ApplyAsync(WearableConnection connection, ChangePlan plan, DateTimeOffset now, CancellationToken token)
    {
        if (!plan.Changed) return;
        var (c, row, isNew, _, samples, activity) = plan;
        if (isNew) db.WearableRecords.Add(row);
        row.VersionNumber++; row.UpdatedAt = now; row.IsDeleted = c.Operation == "delete";
        if (row.IsDeleted)
        {
            await db.HealthMetricSamples.Where(x => x.WearableRecordId == row.Id).ExecuteUpdateAsync(s => s.SetProperty(x => x.IsDeleted, true), token);
            if (activity is not null) { activity.IsDeleted = true; activity.UpdatedAt = now; activity.VersionNumber = row.VersionNumber; }
            return;
        }
        row.SourceName = c.SourceName; row.RecordingMethod = c.RecordingMethod; row.ExerciseType = c.ExerciseType;
        if (c.Metric == "exercise")
        {
            if (activity is null)
            {
                activity = new() { Id = Guid.NewGuid(), ClientId = row.ClientId, Source = "wearable", WearableConnectionId = connection.Id,
                    WearableRecordId = row.Id, ExternalRecordId = row.ExternalRecordId, CreatedAt = now };
                db.ActivityLogs.Add(activity);
            }
            activity.ActivityType = c.ExerciseType!; activity.StartedAt = c.Samples[0].StartedAt; activity.EndedAt = c.Samples[0].EndedAt;
            activity.DurationMinutes = c.Samples[0].Value; activity.RawDurationMinutes = c.Samples[0].RawValue;
            activity.IsDeleted = false; activity.UpdatedAt = now; activity.VersionNumber = row.VersionNumber;
        }
        else
        {
            foreach (var s in c.Samples)
            {
                var target = samples.SingleOrDefault(x => x.SampleKey == s.Key);
                if (target is null)
                {
                    target = new() { Id = Guid.NewGuid(), ClientId = row.ClientId, WearableRecordId = row.Id, SampleKey = s.Key };
                    db.HealthMetricSamples.Add(target);
                }
                target.StartedAt = s.StartedAt; target.EndedAt = s.EndedAt; target.RawValue = s.RawValue;
                target.Value = s.Value; target.Unit = s.Unit; target.IsDeleted = false;
            }
            foreach (var sample in samples.Where(s => c.DeletedKeys.Contains(s.SampleKey))) sample.IsDeleted = true;
        }
    }

    public async Task<PagedResponse<WearableRecordResponse>> RecordsAsync(Guid client, Guid id, int page, int size,
        string? sourceId, string? rawType, string? externalId, CancellationToken token)
    {
        await using var tx = await db.Database.BeginTransactionAsync(IsolationLevel.RepeatableRead, token);
        var connection = await ConnectionAsync(client, id, token);
        var query = db.WearableRecords.AsNoTracking().Where(x => x.WearableConnectionId == id && x.ClientId == client);
        if (sourceId is not null) query = query.Where(x => x.SourceId == sourceId);
        if (rawType is not null) query = query.Where(x => x.RawType == rawType);
        if (externalId is not null) query = query.Where(x => x.ExternalRecordId == externalId);
        var count = await query.CountAsync(token);
        var rows = await query.OrderByDescending(x => x.UpdatedAt).ThenBy(x => x.Id).Skip((page - 1) * size).Take(size).ToListAsync(token);
        await tx.CommitAsync(token);
        return new(rows.Select(x => WearableRecordResponse.From(x, connection.Provider)).ToArray(), count);
    }
    public async Task<WearableRecordResponse> RecordAsync(Guid client, Guid connectionId, Guid id, CancellationToken token)
    {
        var connection = await ConnectionAsync(client, connectionId, token);
        return WearableRecordResponse.From(await db.WearableRecords.AsNoTracking().SingleOrDefaultAsync(x => x.ClientId == client && x.WearableConnectionId == connectionId && x.Id == id, token)
            ?? throw new ResourceOperationException(404), connection.Provider);
    }
    public async Task<PagedResponse<HealthMetricSampleResponse>> SamplesAsync(Guid client, int page, int size,
        string? metric, Guid? recordId, DateTimeOffset? from, DateTimeOffset? to, bool includeDeleted, CancellationToken token)
    {
        if (metric is not null && metric is not ("steps" or "distance" or "active_energy" or "heart_rate")) throw new ResourceOperationException(422, "unsupported_metric");
        await using var tx = await db.Database.BeginTransactionAsync(IsolationLevel.RepeatableRead, token);
        if (recordId is not null && !await db.WearableRecords.AnyAsync(x => x.Id == recordId && x.ClientId == client, token)) throw new ResourceOperationException(404);
        var query = from s in db.HealthMetricSamples.AsNoTracking()
                    join r in db.WearableRecords on s.WearableRecordId equals r.Id
                    where s.ClientId == client && r.ClientId == client && (includeDeleted || !s.IsDeleted && !r.IsDeleted)
                    select new { Sample = s, Record = r };
        if (metric is not null) query = query.Where(x => x.Record.Metric == metric);
        if (recordId is not null) query = query.Where(x => x.Record.Id == recordId);
        if (from is not null) query = query.Where(x => x.Sample.StartedAt >= from.Value.ToUniversalTime());
        if (to is not null) query = query.Where(x => x.Sample.StartedAt < to.Value.ToUniversalTime());
        var count = await query.CountAsync(token);
        var rows = await query.OrderByDescending(x => x.Sample.StartedAt).ThenBy(x => x.Sample.Id).Skip((page - 1) * size).Take(size)
            .Select(x => new HealthMetricSampleResponse(x.Sample.Id, x.Record.Id, x.Record.Metric, x.Sample.StartedAt, x.Sample.EndedAt,
                x.Sample.RawValue, x.Record.RawUnit, x.Sample.Value, x.Sample.Unit, x.Sample.IsDeleted)).ToListAsync(token);
        await tx.CommitAsync(token);
        return new(rows, count);
    }
}
