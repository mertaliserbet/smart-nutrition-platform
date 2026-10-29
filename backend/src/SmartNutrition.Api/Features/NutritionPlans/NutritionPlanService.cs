using Microsoft.EntityFrameworkCore;
using Npgsql;
using SmartNutrition.Api.Data;
using SmartNutrition.Api.Features.Dietitians;
using SmartNutrition.Api.Features.Relationships;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Features.NutritionPlans;

public sealed class NutritionPlanService(AppDbContext database, RelationshipAccessService access, TimeProvider clock)
{
    private sealed record Reference(Guid Id, Guid ClientId, Guid? DietitianId);
    private async Task<Reference> ReferenceAsync(Guid id, CancellationToken token) =>
        await database.NutritionPlans.AsNoTracking().Where(x => x.Id == id).Select(x => new Reference(x.Id, x.ClientId, x.DietitianId)).SingleOrDefaultAsync(token)
        ?? throw new ResourceOperationException(404);

    internal async Task RequireReadAsync(ProfileIdentity actor, Guid clientId, CancellationToken token)
    {
        if (actor.Role == UserRole.Client)
        { if (actor.ClientId != clientId) throw new ResourceOperationException(404); return; }
        if (actor.Role != UserRole.Dietitian || actor.DietitianId is null || !actor.IsDietitianVerified ||
            !await database.DietitianProfiles.AnyAsync(x => x.Id == actor.DietitianId && x.IsVerified && x.User.IsEmailVerified && x.User.Role == UserRole.Dietitian, token))
            throw new ResourceOperationException(403);
        if (!await database.DietitianClientRelationships.AnyAsync(x => x.ClientId == clientId && x.DietitianId == actor.DietitianId && x.Status == RelationshipStatus.Active, token))
            throw new ResourceOperationException(404);
        if (!await access.CanAccessNutritionPlansAsync(actor, clientId, token)) throw new ResourceOperationException(403);
    }
    private static void RequireEdit(ProfileIdentity actor, Guid? owner)
    {
        if (actor.Role == UserRole.Client ? owner is not null : owner != actor.DietitianId)
            throw new ResourceOperationException(403);
    }
    private static Guid Target(ProfileIdentity actor, Guid? supplied)
    {
        if (actor.Role == UserRole.Client)
        { if (supplied is not null) throw new ResourceOperationException(400); return actor.ClientId ?? throw new ResourceOperationException(403); }
        return supplied is null || supplied == Guid.Empty ? throw new ResourceOperationException(400) : supplied.Value;
    }
    private async Task<NutritionPlanResponse> ResponseAsync(NutritionPlan plan, CancellationToken token)
    {
        var versionId = await database.NutritionPlanVersions.Where(x => x.NutritionPlanId == plan.Id && x.VersionNumber == plan.VersionNumber).Select(x => x.Id).SingleAsync(token);
        return NutritionPlanResponse.From(plan, versionId);
    }

    public async Task<NutritionPlanResponse> CreateAsync(ProfileIdentity actor, CreateNutritionPlanRequest request, CancellationToken token)
    {
        if (actor.Role == UserRole.Client && request.ClientIdSpecified) throw new ResourceOperationException(400);
        var id = Guid.NewGuid(); var content = NutritionPlanValidation.Create(id, request); var clientId = Target(actor, request.ClientId);
        await RequireReadAsync(actor, clientId, token);
        await using var transaction = await database.Database.BeginTransactionAsync(token);
        await access.LockActorAsync(actor, token); await access.LockClientAsync(clientId, token); await RequireReadAsync(actor, clientId, token);
        var plan = new NutritionPlan(id, clientId, actor.Role == UserRole.Client ? null : actor.DietitianId, content, clock.GetUtcNow());
        var version = new NutritionPlanVersion(plan, actor.UserId, clock.GetUtcNow());
        database.NutritionPlans.Add(plan); database.NutritionPlanVersions.Add(version);
        await database.SaveChangesAsync(token); await transaction.CommitAsync(token); return NutritionPlanResponse.From(plan, version.Id);
    }

    public async Task<PagedResponse<NutritionPlanResponse>> ListAsync(ProfileIdentity actor, Guid? clientId, int page, int size, CancellationToken token)
    {
        var target = Target(actor, clientId); await RequireReadAsync(actor, target, token);
        var query = database.NutritionPlans.AsNoTracking().Where(x => x.ClientId == target);
        var count = await query.CountAsync(token);
        var rows = await (from plan in query
            join version in database.NutritionPlanVersions.AsNoTracking() on new { Id = plan.Id, plan.VersionNumber } equals new { Id = version.NutritionPlanId, version.VersionNumber }
            orderby plan.CreatedAt descending, plan.Id
            select new { Plan = plan, VersionId = version.Id }).Skip((page - 1) * size).Take(size).ToListAsync(token);
        return new(rows.Select(row => NutritionPlanResponse.From(row.Plan, row.VersionId)).ToList(), count);
    }
    public async Task<NutritionPlanResponse> GetAsync(ProfileIdentity actor, Guid id, CancellationToken token)
    {
        var reference = await ReferenceAsync(id, token); await RequireReadAsync(actor, reference.ClientId, token);
        return await ResponseAsync(await database.NutritionPlans.AsNoTracking().SingleAsync(x => x.Id == id, token), token);
    }
    public async Task<NutritionPlanResponse> ActiveAsync(ProfileIdentity actor, CancellationToken token)
    {
        if (actor.Role != UserRole.Client || actor.ClientId is null) throw new ResourceOperationException(403);
        var plan = await database.NutritionPlans.AsNoTracking().SingleOrDefaultAsync(x => x.ClientId == actor.ClientId && x.Status == NutritionPlanStatus.Active, token)
            ?? throw new ResourceOperationException(404);
        return await ResponseAsync(plan, token);
    }
    public async Task<NutritionPlanResponse> PatchAsync(ProfileIdentity actor, Guid id, PatchNutritionPlanRequest request, CancellationToken token)
    {
        var reference = await ReferenceAsync(id, token); await RequireReadAsync(actor, reference.ClientId, token); RequireEdit(actor, reference.DietitianId);
        await using var transaction = await database.Database.BeginTransactionAsync(token);
        await access.LockActorAsync(actor, token); await access.LockClientAsync(reference.ClientId, token); await RequireReadAsync(actor, reference.ClientId, token);
        var plan = await database.NutritionPlans.FromSqlInterpolated($"SELECT * FROM nutrition_plans WHERE id = {id} FOR UPDATE").SingleAsync(token);
        RequireEdit(actor, plan.DietitianId); plan.Revise(NutritionPlanValidation.Patch(plan, request));
        var version = new NutritionPlanVersion(plan, actor.UserId, clock.GetUtcNow()); database.NutritionPlanVersions.Add(version);
        await database.SaveChangesAsync(token); await transaction.CommitAsync(token); return NutritionPlanResponse.From(plan, version.Id);
    }
    public async Task<NutritionPlanResponse> ChangeStatusAsync(ProfileIdentity actor, Guid id, NutritionPlanStatus status, CancellationToken token)
    {
        var reference = await ReferenceAsync(id, token); await RequireReadAsync(actor, reference.ClientId, token); RequireEdit(actor, reference.DietitianId);
        await using var transaction = await database.Database.BeginTransactionAsync(token);
        await access.LockActorAsync(actor, token); await access.LockClientAsync(reference.ClientId, token); await RequireReadAsync(actor, reference.ClientId, token);
        var plan = await database.NutritionPlans.FromSqlInterpolated($"SELECT * FROM nutrition_plans WHERE id = {id} FOR UPDATE").SingleAsync(token);
        RequireEdit(actor, plan.DietitianId);
        if (status == NutritionPlanStatus.Active && await database.NutritionPlans.AnyAsync(x => x.ClientId == plan.ClientId && x.Id != id && x.Status == NutritionPlanStatus.Active, token))
            throw new ResourceOperationException(409, "active_nutrition_plan_conflict");
        plan.SetStatus(status);
        try { await database.SaveChangesAsync(token); }
        catch (DbUpdateException error) when (error.InnerException is PostgresException { SqlState: PostgresErrorCodes.UniqueViolation, ConstraintName: "ux_nutrition_plans_active_client" })
        { throw new ResourceOperationException(409, "active_nutrition_plan_conflict"); }
        var response = await ResponseAsync(plan, token); await transaction.CommitAsync(token); return response;
    }
    public async Task<PagedResponse<NutritionPlanVersionInfo>> VersionsAsync(ProfileIdentity actor, Guid id, int page, int size, CancellationToken token)
    {
        var reference = await ReferenceAsync(id, token); await RequireReadAsync(actor, reference.ClientId, token);
        var query = database.NutritionPlanVersions.AsNoTracking().Where(x => x.NutritionPlanId == id);
        return new(await query.OrderByDescending(x => x.VersionNumber).Skip((page - 1) * size).Take(size)
            .Select(x => new NutritionPlanVersionInfo(x.Id, x.NutritionPlanId, x.VersionNumber, x.CreatedAt)).ToListAsync(token), await query.CountAsync(token));
    }
    public async Task<NutritionPlanVersionResponse> VersionAsync(ProfileIdentity actor, Guid id, Guid versionId, CancellationToken token)
    {
        var reference = await ReferenceAsync(id, token); await RequireReadAsync(actor, reference.ClientId, token);
        var row = await database.NutritionPlanVersions.AsNoTracking().SingleOrDefaultAsync(x => x.Id == versionId && x.NutritionPlanId == id, token) ?? throw new ResourceOperationException(404);
        return new(row.Id, row.NutritionPlanId, row.VersionNumber, row.CreatedAt,
            System.Text.Json.JsonSerializer.Deserialize<NutritionPlanSnapshot>(row.SnapshotJson, NutritionPlan.Json) ?? throw new InvalidOperationException("Program version is unavailable."));
    }
}
