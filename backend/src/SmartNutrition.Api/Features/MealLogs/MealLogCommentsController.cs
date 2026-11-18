using System.Data;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.ModelBinding;
using Microsoft.EntityFrameworkCore;
using SmartNutrition.Api.Data;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Features.Dietitians;
using SmartNutrition.Api.Features.Relationships;
using SmartNutrition.Api.Infrastructure;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Features.MealLogs;

[ApiController, Route("api/v1/meal-logs/{mealLogId:guid}/comments")]
[Authorize(AuthenticationSchemes = WebSessionAuthentication.AccountScheme, Roles = "client,dietitian")]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public sealed class MealLogCommentsController(AppDbContext database, RelationshipAccessService access, TimeProvider clock) : ControllerBase
{
    [HttpGet, ProducesResponseType<PagedResponse<MealLogCommentResponse>>(200)]
    public async Task<IActionResult> List(Guid mealLogId, [FromQuery, BindRequired] int page, [FromQuery, BindRequired] int pageSize, CancellationToken token)
    {
        if (HttpContext.Features.Get<IHttpRequestBodyDetectionFeature>()?.CanHaveBody == true || page < 1 || pageSize is < 1 or > 100 ||
            (long)(page - 1) * pageSize > int.MaxValue || Request.Query.Any(x => x.Key is not ("page" or "pageSize") || x.Value.Count != 1))
            return BadRequest(ApiErrors.Create(HttpContext, 400));
        await using var transaction = await database.Database.BeginTransactionAsync(IsolationLevel.RepeatableRead, token);
        await RequireMealAsync(await access.RequireAsync(User, token, Request), mealLogId, token);
        var query = database.MealLogComments.AsNoTracking().Where(x => x.MealLogId == mealLogId);
        var total = await query.CountAsync(token);
        var rows = await query.OrderBy(x => x.CreatedAt).ThenBy(x => x.Id).Skip((page - 1) * pageSize).Take(pageSize).ToListAsync(token);
        await transaction.CommitAsync(token);
        return Ok(new PagedResponse<MealLogCommentResponse>(rows.Select(MealLogCommentResponse.From).ToArray(), total));
    }

    [HttpPost, Consumes("application/json"), RequestSizeLimit(32768), ProducesResponseType<MealLogCommentResponse>(201)]
    public async Task<IActionResult> Create(Guid mealLogId, CreateMealLogCommentRequest request, CancellationToken token)
    {
        if (Request.Query.Count != 0 || !await WebSessionAuthentication.ValidMutationAsync(HttpContext)) return BadRequest(ApiErrors.Create(HttpContext, 400));
        await using var transaction = await database.Database.BeginTransactionAsync(token);
        var actor = await access.RequireAsync(User, token, Request);
        var clientId = await RequireMealAsync(actor, mealLogId, token);
        // Same lock order as permission withdrawal/relationship termination. Recheck AFTER waiting.
        await access.LockActorAsync(actor, token);
        await access.LockClientAsync(clientId, token);
        actor = await access.RequireAsync(User, token, Request);
        await RequireMealAsync(actor, mealLogId, token);
        _ = await database.MealLogs.FromSqlInterpolated($"SELECT * FROM meal_logs WHERE id = {mealLogId} AND deleted_at IS NULL FOR UPDATE")
            .AsNoTracking().SingleOrDefaultAsync(token) ?? throw new ResourceOperationException(404);
        if (actor.Role == UserRole.Dietitian ? request.ParentCommentId is not null : request.ParentCommentId is null)
            throw new ResourceOperationException(403);
        if (request.ParentCommentId == Guid.Empty || !MealLogComment.ValidText(request.Text?.Trim())) throw new ResourceOperationException(422);
        if (request.ParentCommentId is { } parentId)
        {
            var parent = await database.MealLogComments.AsNoTracking().SingleOrDefaultAsync(x => x.Id == parentId && x.MealLogId == mealLogId, token)
                ?? throw new ResourceOperationException(404);
            if (parent.ParentCommentId is not null) throw new ResourceOperationException(422);
        }
        var row = new MealLogComment(mealLogId, actor.UserId, request.Text!, clock.GetUtcNow(), request.ParentCommentId);
        database.MealLogComments.Add(row); await database.SaveChangesAsync(token); await transaction.CommitAsync(token);
        // No unsupported detail route is advertised by a Location header.
        return StatusCode(201, MealLogCommentResponse.From(row));
    }

    private async Task<Guid> RequireMealAsync(ProfileIdentity actor, Guid mealLogId, CancellationToken token)
    {
        var clientId = await database.MealLogs.AsNoTracking().Where(x => x.Id == mealLogId).Select(x => (Guid?)x.ClientId).SingleOrDefaultAsync(token)
            ?? throw new ResourceOperationException(404);
        if (actor.Role == UserRole.Client)
        {
            if (actor.ClientId != clientId) throw new ResourceOperationException(404);
        }
        else
        {
            var granted = await database.DietitianClientRelationships.AsNoTracking()
                .Where(x => x.ClientId == clientId && x.DietitianId == actor.DietitianId && x.Status == RelationshipStatus.Active)
                .Select(x => (bool?)database.DataSharingPermissions.Any(p => p.RelationshipId == x.Id && p.Category == "meal_logs" && p.IsGranted))
                .SingleOrDefaultAsync(token) ?? throw new ResourceOperationException(404);
            if (!granted) throw new ResourceOperationException(403);
        }
        return clientId;
    }
}
