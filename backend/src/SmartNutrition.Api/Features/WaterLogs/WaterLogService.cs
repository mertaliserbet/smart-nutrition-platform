using System.Data;
using Microsoft.EntityFrameworkCore;
using SmartNutrition.Api.Data;
using SmartNutrition.Api.Features.Dietitians;
using SmartNutrition.Api.Features.Relationships;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Features.WaterLogs;

public sealed class WaterLogService(AppDbContext database, TimeProvider clock)
{
    private IQueryable<WaterLog> Filter(Guid clientId, DateTimeOffset? from, DateTimeOffset? to)
    {
        var rows = database.WaterLogs.AsNoTracking().Where(x => x.ClientId == clientId);
        if (from is not null) rows = rows.Where(x => x.ConsumedAt >= from.Value.ToUniversalTime());
        if (to is not null) rows = rows.Where(x => x.ConsumedAt < to.Value.ToUniversalTime());
        return rows;
    }
    public async Task<WaterLogResponse> CreateAsync(Guid clientId, CreateWaterLogRequest request, CancellationToken token)
    {
        WaterLogValidation.Values(request.AmountMl, request.ConsumedAt);
        if (request.Source != RecordSource.Manual) throw new ResourceOperationException(422);
        var row = new WaterLog(Guid.NewGuid(), clientId, request.AmountMl, request.ConsumedAt, request.Source);
        database.WaterLogs.Add(row); await database.SaveChangesAsync(token);
        return WaterLogResponse.From(row);
    }
    public async Task<PagedResponse<WaterLogResponse>> ListAsync(Guid clientId, int page, int pageSize,
        DateTimeOffset? from, DateTimeOffset? to, CancellationToken token)
    {
        await using var transaction = await database.Database.BeginTransactionAsync(IsolationLevel.RepeatableRead, token);
        var query = Filter(clientId, from, to);
        var count = await query.CountAsync(token);
        var rows = await query.OrderByDescending(x => x.ConsumedAt).ThenBy(x => x.Id).Skip((page - 1) * pageSize).Take(pageSize).ToListAsync(token);
        await transaction.CommitAsync(token);
        return new(rows.Select(WaterLogResponse.From).ToArray(), count);
    }
    public async Task<WaterLogDailyTotalResponse> DailyTotalAsync(Guid clientId, DateTimeOffset from, DateTimeOffset to, CancellationToken token)
    {
        try
        {
            var total = await Filter(clientId, from, to).SumAsync(x => (decimal?)x.AmountMl, token) ?? 0m;
            return new(from.ToUniversalTime(), to.ToUniversalTime(), total);
        }
        catch (OverflowException) { throw new ResourceOperationException(422); }
    }
    public async Task<WaterLogResponse> GetAsync(Guid clientId, Guid id, CancellationToken token) => WaterLogResponse.From(
        await Filter(clientId, null, null).SingleOrDefaultAsync(x => x.Id == id, token) ?? throw new ResourceOperationException(404));
    public async Task<WaterLogResponse> PatchAsync(Guid clientId, Guid id, PatchWaterLogRequest request, CancellationToken token)
    {
        await using var transaction = await database.Database.BeginTransactionAsync(token);
        var row = await LockedAsync(clientId, id, token);
        var values = WaterLogValidation.Patch(row, request); row.Revise(values.AmountMl, values.ConsumedAt);
        await database.SaveChangesAsync(token); await transaction.CommitAsync(token);
        return WaterLogResponse.From(row);
    }
    public async Task DeleteAsync(Guid clientId, Guid id, CancellationToken token)
    {
        await using var transaction = await database.Database.BeginTransactionAsync(token);
        var row = await LockedAsync(clientId, id, token); row.Delete(clock.GetUtcNow());
        await database.SaveChangesAsync(token); await transaction.CommitAsync(token);
    }
    private async Task<WaterLog> LockedAsync(Guid clientId, Guid id, CancellationToken token) =>
        await database.WaterLogs.FromSqlInterpolated(
            $"SELECT * FROM water_logs WHERE id = {id} AND client_id = {clientId} AND deleted_at IS NULL FOR UPDATE")
            .SingleOrDefaultAsync(token) ?? throw new ResourceOperationException(404);
}
