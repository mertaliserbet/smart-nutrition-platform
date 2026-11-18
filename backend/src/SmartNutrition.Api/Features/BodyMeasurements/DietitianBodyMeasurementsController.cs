using System.Data;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.ModelBinding;
using Microsoft.EntityFrameworkCore;
using SmartNutrition.Api.Data;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Features.Dietitians;
using SmartNutrition.Api.Features.MealLogs;
using SmartNutrition.Api.Features.Relationships;
using SmartNutrition.Api.Infrastructure;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Features.BodyMeasurements;

[ApiController, Route("api/v1/dietitian/clients/{clientId}/body-measurements")]
[Authorize(AuthenticationSchemes = WebSessionAuthentication.AccountScheme, Roles = "client,dietitian")]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public sealed class DietitianBodyMeasurementsController(AppDbContext database, RelationshipAccessService access) : ControllerBase
{
    [HttpGet, ProducesResponseType<PagedResponse<BodyMeasurementResponse>>(200)]
    public async Task<IActionResult> List(Guid clientId, [FromQuery, BindRequired] int page,
        [FromQuery, BindRequired] int pageSize, [FromQuery] string? from, [FromQuery] string? to, [FromQuery] string? sortOrder,
        CancellationToken token)
    {
        if (HttpContext.Features.Get<IHttpRequestBodyDetectionFeature>()?.CanHaveBody == true ||
            page < 1 || pageSize is < 1 or > 100 || (long)(page - 1) * pageSize > int.MaxValue ||
            Request.Query.Keys.Any(x => x is not ("page" or "pageSize" or "from" or "to" or "sortOrder")) ||
            Request.Query.Any(x => x.Value.Count != 1) || sortOrder is not (null or "asc" or "desc") ||
            (Request.Query.ContainsKey("sortOrder") && string.IsNullOrEmpty(sortOrder)))
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
                    permission.Category == "body_measurements" && permission.IsGranted)
            }).SingleOrDefaultAsync(token) ?? throw new ResourceOperationException(404);
        if (!relationship.Granted) throw new ResourceOperationException(403);

        var query = database.BodyMeasurements.AsNoTracking().Where(x => x.ClientId == clientId);
        if (start is not null) query = query.Where(x => x.MeasuredAt >= start.Value.ToUniversalTime());
        if (end is not null) query = query.Where(x => x.MeasuredAt < end.Value.ToUniversalTime());
        var total = await query.CountAsync(token);
        var ordered = sortOrder == "asc" ? query.OrderBy(x => x.MeasuredAt).ThenBy(x => x.Id) : query.OrderByDescending(x => x.MeasuredAt).ThenBy(x => x.Id);
        var rows = await ordered.Skip((page - 1) * pageSize).Take(pageSize).ToListAsync(token);
        await transaction.CommitAsync(token);
        return Ok(new PagedResponse<BodyMeasurementResponse>(rows.Select(BodyMeasurementResponse.From).ToArray(), total));
    }
}
