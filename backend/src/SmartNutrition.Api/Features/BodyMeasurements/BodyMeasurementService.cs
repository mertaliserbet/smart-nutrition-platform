using System.Data;
using Microsoft.EntityFrameworkCore;
using SmartNutrition.Api.Data;
using SmartNutrition.Api.Features.Dietitians;
using SmartNutrition.Api.Features.Relationships;

namespace SmartNutrition.Api.Features.BodyMeasurements;

public sealed class BodyMeasurementService(AppDbContext database, TimeProvider clock)
{
    public async Task<BodyMeasurementResponse> CreateAsync(Guid clientId, CreateBodyMeasurementRequest request, CancellationToken token)
    {
        var row = BodyMeasurementValidation.Create(Guid.NewGuid(), clientId, request);
        database.BodyMeasurements.Add(row); await database.SaveChangesAsync(token);
        return BodyMeasurementResponse.From(row);
    }
    public async Task<PagedResponse<BodyMeasurementResponse>> ListAsync(Guid clientId, int page, int pageSize,
        DateTimeOffset? from, DateTimeOffset? to, bool ascending, CancellationToken token)
    {
        await using var transaction = await database.Database.BeginTransactionAsync(IsolationLevel.RepeatableRead, token);
        var query = database.BodyMeasurements.AsNoTracking().Where(x => x.ClientId == clientId);
        if (from is not null) query = query.Where(x => x.MeasuredAt >= from.Value.ToUniversalTime());
        if (to is not null) query = query.Where(x => x.MeasuredAt < to.Value.ToUniversalTime());
        var count = await query.CountAsync(token);
        var ordered = ascending ? query.OrderBy(x => x.MeasuredAt).ThenBy(x => x.Id) : query.OrderByDescending(x => x.MeasuredAt).ThenBy(x => x.Id);
        var rows = await ordered.Skip((page - 1) * pageSize).Take(pageSize).ToListAsync(token);
        await transaction.CommitAsync(token);
        return new(rows.Select(BodyMeasurementResponse.From).ToArray(), count);
    }
    public async Task<BodyMeasurementResponse> GetAsync(Guid clientId, Guid id, CancellationToken token) => BodyMeasurementResponse.From(
        await database.BodyMeasurements.AsNoTracking().SingleOrDefaultAsync(x => x.ClientId == clientId && x.Id == id, token)
            ?? throw new ResourceOperationException(404));
    public async Task<BodyMeasurementResponse> PatchAsync(Guid clientId, Guid id, PatchBodyMeasurementRequest request, CancellationToken token)
    {
        await using var transaction = await database.Database.BeginTransactionAsync(token);
        var row = await LockedAsync(clientId, id, token); var value = BodyMeasurementValidation.Patch(row, request);
        row.Revise(value.MeasuredAt, value.WeightKg, value.WaistCm, value.HipCm, value.ChestCm, value.BodyFatPercent, value.Note);
        await database.SaveChangesAsync(token); await transaction.CommitAsync(token);
        return BodyMeasurementResponse.From(row);
    }
    public async Task DeleteAsync(Guid clientId, Guid id, CancellationToken token)
    {
        await using var transaction = await database.Database.BeginTransactionAsync(token);
        var row = await LockedAsync(clientId, id, token); row.Delete(clock.GetUtcNow());
        await database.SaveChangesAsync(token); await transaction.CommitAsync(token);
    }
    private async Task<BodyMeasurement> LockedAsync(Guid clientId, Guid id, CancellationToken token) =>
        await database.BodyMeasurements.FromSqlInterpolated(
            $"SELECT * FROM body_measurements WHERE id = {id} AND client_id = {clientId} AND deleted_at IS NULL FOR UPDATE")
            .SingleOrDefaultAsync(token) ?? throw new ResourceOperationException(404);
}
