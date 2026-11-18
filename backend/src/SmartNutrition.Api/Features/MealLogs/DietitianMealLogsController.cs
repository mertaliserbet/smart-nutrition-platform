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

[ApiController, Route("api/v1/dietitian/clients/{clientId}/meal-logs")]
[Authorize(AuthenticationSchemes = WebSessionAuthentication.AccountScheme, Roles = "client,dietitian")]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public sealed class DietitianMealLogsController(AppDbContext database, RelationshipAccessService access) : ControllerBase
{
    [HttpGet, ProducesResponseType<PagedResponse<MealLogResponse>>(200)]
    public async Task<IActionResult> List(Guid clientId, [FromQuery, BindRequired] int page,
        [FromQuery, BindRequired] int pageSize, [FromQuery] string? from, [FromQuery] string? to,
        CancellationToken token)
    {
        if (HttpContext.Features.Get<IHttpRequestBodyDetectionFeature>()?.CanHaveBody == true ||
            page < 1 || pageSize is < 1 or > 100 || (long)(page - 1) * pageSize > int.MaxValue ||
            Request.Query.Keys.Any(x => x is not ("page" or "pageSize" or "from" or "to")) ||
            Request.Query.Any(x => x.Value.Count != 1))
            return BadRequest(ApiErrors.Create(HttpContext, 400));
        DateTimeOffset? start = null, end = null;
        if (Request.Query.ContainsKey("from"))
        {
            if (!MealLogInstantJsonConverter.TryParse(from, out var value)) return BadRequest(ApiErrors.Create(HttpContext, 400));
            start = value;
        }
        if (Request.Query.ContainsKey("to"))
        {
            if (!MealLogInstantJsonConverter.TryParse(to, out var value)) return BadRequest(ApiErrors.Create(HttpContext, 400));
            end = value;
        }
        if (start is not null && end is not null && start >= end) return BadRequest(ApiErrors.Create(HttpContext, 400));

        // Current identity, relationship, consent, count and rows share one snapshot.
        // No cached authorization: a read starting after a committed withdrawal is denied.
        await using var transaction = await database.Database.BeginTransactionAsync(IsolationLevel.RepeatableRead, token);
        var actor = await access.RequireAsync(User, token, Request, asDietitian: true);
        var relationship = await database.DietitianClientRelationships.AsNoTracking()
            .Where(x => x.ClientId == clientId && x.DietitianId == actor.DietitianId && x.Status == RelationshipStatus.Active)
            .Select(x => new
            {
                Granted = database.DataSharingPermissions.Any(permission => permission.RelationshipId == x.Id &&
                    permission.Category == "meal_logs" && permission.IsGranted)
            }).SingleOrDefaultAsync(token) ?? throw new ResourceOperationException(404);
        if (!relationship.Granted) throw new ResourceOperationException(403);

        var query = database.MealLogs.AsNoTracking().Where(x => x.ClientId == clientId);
        if (start is not null) query = query.Where(x => x.ConsumedAt >= start.Value.ToUniversalTime());
        if (end is not null) query = query.Where(x => x.ConsumedAt < end.Value.ToUniversalTime());
        var total = await query.CountAsync(token);
        var rows = await query.OrderByDescending(x => x.ConsumedAt).ThenBy(x => x.Id)
            .Skip((page - 1) * pageSize).Take(pageSize)
            .Include(x => x.Items.OrderBy(item => EF.Property<int>(item, "Position"))).ToListAsync(token);
        await transaction.CommitAsync(token);
        return Ok(new PagedResponse<MealLogResponse>(rows.Select(MealLogResponse.From).ToArray(), total));
    }
}
