using System.Data;
using Microsoft.EntityFrameworkCore;
using SmartNutrition.Api.Data;
using SmartNutrition.Api.Features.Dietitians;
using SmartNutrition.Api.Features.Relationships;

namespace SmartNutrition.Api.Features.HealthData;

public sealed class ActivityLogService(AppDbContext db, HealthDataService health, TimeProvider clock)
{
    private IQueryable<ActivityLog> Query(Guid client) => db.ActivityLogs.AsNoTracking().Where(x => x.ClientId == client && !x.IsDeleted);
    public async Task<ActivityLogResponse> CreateAsync(ProfileIdentity actor, CreateActivityLogRequest input, CancellationToken token)
    {
        if (input.Source != "manual") throw new ResourceOperationException(422, "invalid_value");
        var now = RecordTime.Normalize(clock.GetUtcNow()); var times = HealthDataValidation.Activity(input, now);
        await using var tx = await db.Database.BeginTransactionAsync(token);
        await health.LockAsync(actor, token);
        var row = new ActivityLog { Id = Guid.NewGuid(), ClientId = actor.ClientId!.Value, CreatedAt = now, UpdatedAt = now };
        Set(row, input, times); db.ActivityLogs.Add(row);
        await db.SaveChangesAsync(token); await tx.CommitAsync(token);
        return ActivityLogResponse.From(row);
    }
    private static void Set(ActivityLog row, ActivityInput input, (DateTimeOffset Start, DateTimeOffset? End) times)
    {
        row.ActivityType = input.ActivityType; row.StartedAt = times.Start; row.EndedAt = times.End;
        row.DurationMinutes = times.End is null ? null : (times.End.Value - times.Start).Ticks / (decimal)TimeSpan.TicksPerMinute;
        row.DistanceKm = input.DistanceKm; row.CaloriesKcal = input.CaloriesKcal;
    }
    public async Task<PagedResponse<ActivityLogResponse>> ListAsync(Guid client, int page, int size, DateTimeOffset? from, DateTimeOffset? to, CancellationToken token)
    {
        await using var tx = await db.Database.BeginTransactionAsync(IsolationLevel.RepeatableRead, token);
        var query = Query(client);
        if (from is not null) query = query.Where(x => x.StartedAt >= from.Value.ToUniversalTime());
        if (to is not null) query = query.Where(x => x.StartedAt < to.Value.ToUniversalTime());
        var count = await query.CountAsync(token);
        var rows = await query.OrderByDescending(x => x.StartedAt).ThenBy(x => x.Id).Skip((page - 1) * size).Take(size).ToListAsync(token);
        await tx.CommitAsync(token);
        return new(rows.Select(ActivityLogResponse.From).ToArray(), count);
    }
    public async Task<ActivityLogResponse> GetAsync(Guid client, Guid id, CancellationToken token) => ActivityLogResponse.From(
        await Query(client).SingleOrDefaultAsync(x => x.Id == id, token) ?? throw new ResourceOperationException(404));
    private async Task<ActivityLog> EditableAsync(Guid client, Guid id, int version, CancellationToken token)
    {
        var row = await db.ActivityLogs.SingleOrDefaultAsync(x => x.ClientId == client && x.Id == id && !x.IsDeleted, token) ?? throw new ResourceOperationException(404);
        if (row.Source != "manual") throw new ResourceOperationException(409, "source_record_read_only");
        if (version < 1) throw new ResourceOperationException(422, "invalid_value");
        if (row.VersionNumber != version) throw new ResourceOperationException(409, "source_version_conflict");
        return row;
    }
    public async Task<ActivityLogResponse> PatchAsync(ProfileIdentity actor, Guid id, PatchActivityLogRequest input, CancellationToken token)
    {
        var now = RecordTime.Normalize(clock.GetUtcNow()); var times = HealthDataValidation.Activity(input, now);
        await using var tx = await db.Database.BeginTransactionAsync(token);
        await health.LockAsync(actor, token);
        var row = await EditableAsync(actor.ClientId!.Value, id, input.ExpectedVersionNumber, token);
        Set(row, input, times); row.VersionNumber++; row.UpdatedAt = now;
        await db.SaveChangesAsync(token); await tx.CommitAsync(token);
        return ActivityLogResponse.From(row);
    }
    public async Task DeleteAsync(ProfileIdentity actor, Guid id, int version, CancellationToken token)
    {
        await using var tx = await db.Database.BeginTransactionAsync(token);
        await health.LockAsync(actor, token);
        var row = await EditableAsync(actor.ClientId!.Value, id, version, token);
        row.IsDeleted = true; row.VersionNumber++; row.UpdatedAt = RecordTime.Normalize(clock.GetUtcNow());
        await db.SaveChangesAsync(token); await tx.CommitAsync(token);
    }
}
