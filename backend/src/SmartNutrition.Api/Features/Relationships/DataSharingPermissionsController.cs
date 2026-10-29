using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.ModelBinding;
using Microsoft.EntityFrameworkCore;
using Npgsql;
using SmartNutrition.Api.Data;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Features.Dietitians;
using SmartNutrition.Api.Infrastructure;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Features.Relationships;

public sealed class CreateDataSharingPermissionRequest
{
    [JsonRequired] public Guid RelationshipId { get; init; }
    [JsonRequired] public string? Category { get; init; }
    [JsonRequired] public bool IsGranted { get; init; }
    public Guid? ConsentRecordId { get; init; }
}
public sealed class UpdateDataSharingPermissionRequest
{
    [JsonRequired] public bool IsGranted { get; init; }
    public Guid? ConsentRecordId { get; init; }
}

[ApiController, Route("api/v1/data-sharing-permissions")]
[Authorize(AuthenticationSchemes = WebSessionAuthentication.AccountScheme, Roles = "client,dietitian")]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public sealed class DataSharingPermissionsController(AppDbContext database, RelationshipAccessService access,
    RelationshipService relationships, TimeProvider clock) : ControllerBase
{
    private bool HasBody => HttpContext.Features.Get<IHttpRequestBodyDetectionFeature>()?.CanHaveBody == true;
    private async Task<DietitianClientRelationship> OwnRelationship(ProfileIdentity actor, Guid id, CancellationToken token) =>
        await relationships.Own(actor).SingleOrDefaultAsync(x => x.Id == id, token) ?? throw new ResourceOperationException(404);

    [HttpGet, ProducesResponseType<PagedResponse<DataSharingPermission>>(200)]
    public async Task<IActionResult> List([FromQuery, BindRequired] Guid relationshipId, [FromQuery, BindRequired] int page,
        [FromQuery, BindRequired] int pageSize, CancellationToken token)
    {
        if (relationshipId == Guid.Empty || !DietitiansController.ValidPage(page, pageSize) || HasBody ||
            Request.Query.Keys.Any(x => x is not ("relationshipId" or "page" or "pageSize"))) return BadRequest(ApiErrors.Create(HttpContext, 400));
        var actor = await access.RequireAsync(User, token); await OwnRelationship(actor, relationshipId, token);
        var query = database.DataSharingPermissions.AsNoTracking().Where(x => x.RelationshipId == relationshipId);
        return Ok(new PagedResponse<DataSharingPermission>(await query.OrderBy(x => x.Id).Skip((page - 1) * pageSize).Take(pageSize).ToListAsync(token), await query.CountAsync(token)));
    }

    [HttpGet("{dataSharingPermissionId:guid}"), ProducesResponseType<DataSharingPermission>(200)]
    public async Task<IActionResult> Get(Guid dataSharingPermissionId, CancellationToken token)
    {
        if (HasBody || Request.Query.Count != 0) return BadRequest(ApiErrors.Create(HttpContext, 400));
        var actor = await access.RequireAsync(User, token);
        var row = await database.DataSharingPermissions.AsNoTracking().SingleOrDefaultAsync(x => x.Id == dataSharingPermissionId, token)
            ?? throw new ResourceOperationException(404);
        await OwnRelationship(actor, row.RelationshipId, token); return Ok(row);
    }

    [HttpPost, Consumes("application/json"), RequestSizeLimit(4096), ProducesResponseType<DataSharingPermission>(201)]
    public async Task<IActionResult> Create(CreateDataSharingPermissionRequest request, CancellationToken token)
    {
        if (Request.Query.Count != 0 || request.RelationshipId == Guid.Empty || !await WebSessionAuthentication.ValidMutationAsync(HttpContext))
            return BadRequest(ApiErrors.Create(HttpContext, 400));
        if (request.Category != "nutrition_plans" || request.ConsentRecordId is not null) return StatusCode(422, ApiErrors.Create(HttpContext, 422));
        var actor = await access.RequireAsync(User, token);
        await using var transaction = await database.Database.BeginTransactionAsync(token);
        await WritableRelationship(actor, request.RelationshipId, token);
        if (await database.DataSharingPermissions.AnyAsync(x => x.RelationshipId == request.RelationshipId && x.Category == request.Category, token))
            throw new ResourceOperationException(409);
        var row = new DataSharingPermission(request.RelationshipId, request.IsGranted, clock.GetUtcNow()); database.DataSharingPermissions.Add(row);
        try { await database.SaveChangesAsync(token); }
        catch (DbUpdateException error) when (error.InnerException is PostgresException { SqlState: PostgresErrorCodes.UniqueViolation })
        { throw new ResourceOperationException(409); }
        await transaction.CommitAsync(token);
        return Created($"/api/v1/data-sharing-permissions/{row.Id}", row);
    }

    [HttpPatch("{dataSharingPermissionId:guid}"), Consumes("application/json"), RequestSizeLimit(4096), ProducesResponseType<DataSharingPermission>(200)]
    public async Task<IActionResult> Update(Guid dataSharingPermissionId, UpdateDataSharingPermissionRequest request, CancellationToken token)
    {
        if (Request.Query.Count != 0 || !await WebSessionAuthentication.ValidMutationAsync(HttpContext)) return BadRequest(ApiErrors.Create(HttpContext, 400));
        if (request.ConsentRecordId is not null) return StatusCode(422, ApiErrors.Create(HttpContext, 422));
        var actor = await access.RequireAsync(User, token);
        var candidate = await database.DataSharingPermissions.AsNoTracking().SingleOrDefaultAsync(x => x.Id == dataSharingPermissionId, token)
            ?? throw new ResourceOperationException(404);
        await using var transaction = await database.Database.BeginTransactionAsync(token);
        await WritableRelationship(actor, candidate.RelationshipId, token);
        var row = await database.DataSharingPermissions.SingleAsync(x => x.Id == dataSharingPermissionId, token);
        row.SetGranted(request.IsGranted, clock.GetUtcNow()); await database.SaveChangesAsync(token); await transaction.CommitAsync(token);
        return Ok(row);
    }

    private async Task WritableRelationship(ProfileIdentity actor, Guid relationshipId, CancellationToken token)
    {
        if (actor.Role != UserRole.Client || actor.ClientId is null) throw new ResourceOperationException(403);
        await access.LockActorAsync(actor, token); await access.LockClientAsync(actor.ClientId.Value, token);
        var row = await database.DietitianClientRelationships.FromSqlInterpolated($"SELECT * FROM dietitian_client_relationships WHERE id = {relationshipId} FOR UPDATE").AsNoTracking().SingleOrDefaultAsync(token);
        if (row is null || row.ClientId != actor.ClientId) throw new ResourceOperationException(404);
        if (row.Status != RelationshipStatus.Active) throw new ResourceOperationException(409);
    }
}
