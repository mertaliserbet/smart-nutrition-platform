using System.Data;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using SmartNutrition.Api.Data;
using SmartNutrition.Api.Features.Dietitians;
using SmartNutrition.Api.Features.Relationships;

namespace SmartNutrition.Api.Features.MealLogs;

public sealed class MealLogService(AppDbContext database, TimeProvider clock)
{
    private IQueryable<MealLog> WithItems(IQueryable<MealLog> query) =>
        query.Include(x => x.Items.OrderBy(item => EF.Property<int>(item, "Position")));

    public async Task<MealLogResponse> CreateAsync(Guid clientId, CreateMealLogRequest request, CancellationToken token)
    {
        var log = MealLogValidation.Create(Guid.NewGuid(), clientId, RecordTime.Normalize(clock.GetUtcNow()), request);
        database.MealLogs.Add(log);
        SetPositions(log);
        await database.SaveChangesAsync(token);
        return MealLogResponse.From(log);
    }

    public async Task<PagedResponse<MealLogResponse>> ListAsync(Guid clientId, int page, int pageSize,
        DateTimeOffset? from, DateTimeOffset? to, CancellationToken token)
    {
        // Count and rows share one snapshot, including during concurrent writes/deletes.
        await using var transaction = await database.Database.BeginTransactionAsync(IsolationLevel.RepeatableRead, token);
        var query = database.MealLogs.AsNoTracking().Where(x => x.ClientId == clientId);
        if (from is not null) query = query.Where(x => x.ConsumedAt >= from.Value.ToUniversalTime());
        if (to is not null) query = query.Where(x => x.ConsumedAt < to.Value.ToUniversalTime());
        var count = await query.CountAsync(token);
        var rows = await WithItems(query.OrderByDescending(x => x.ConsumedAt).ThenBy(x => x.Id)
            .Skip((page - 1) * pageSize).Take(pageSize)).ToListAsync(token);
        await transaction.CommitAsync(token);
        return new(rows.Select(MealLogResponse.From).ToArray(), count);
    }

    public async Task<MealLogResponse> GetAsync(Guid clientId, Guid id, CancellationToken token) =>
        MealLogResponse.From(await WithItems(database.MealLogs.AsNoTracking()).SingleOrDefaultAsync(x => x.Id == id && x.ClientId == clientId, token)
            ?? throw new ResourceOperationException(404));

    public async Task<MealLogResponse> PatchAsync(Guid clientId, Guid id, PatchMealLogRequest request, CancellationToken token)
    {
        await using var transaction = await database.Database.BeginTransactionAsync(token);
        var log = await LockedAsync(clientId, id, token);
        var validated = MealLogValidation.Patch(log, request);
        var replaceItems = request.Items.ValueKind != JsonValueKind.Undefined;
        if (replaceItems) database.MealLogItems.RemoveRange(log.Items);
        log.Revise(validated, replaceItems);
        if (replaceItems) SetPositions(log);
        await database.SaveChangesAsync(token);
        await transaction.CommitAsync(token);
        return MealLogResponse.From(log);
    }

    public async Task DeleteAsync(Guid clientId, Guid id, CancellationToken token)
    {
        await using var transaction = await database.Database.BeginTransactionAsync(token);
        var log = await LockedAsync(clientId, id, token);
        // Remove from all normal reads without choosing a permanent retention/purge policy.
        log.Delete(RecordTime.Normalize(clock.GetUtcNow()));
        await database.SaveChangesAsync(token);
        await transaction.CommitAsync(token);
    }

    private async Task<MealLog> LockedAsync(Guid clientId, Guid id, CancellationToken token) =>
        await WithItems(database.MealLogs.FromSqlInterpolated(
            $"SELECT * FROM meal_logs WHERE id = {id} AND client_id = {clientId} AND deleted_at IS NULL FOR UPDATE"))
            .SingleOrDefaultAsync(token) ?? throw new ResourceOperationException(404);

    private void SetPositions(MealLog log)
    {
        for (var index = 0; index < log.Items.Count; index++)
            database.Entry(log.Items[index]).Property<int>("Position").CurrentValue = index;
    }
}
