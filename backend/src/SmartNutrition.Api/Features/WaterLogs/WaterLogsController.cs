using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.ModelBinding;
using SmartNutrition.Api.Features.Dietitians;
using SmartNutrition.Api.Features.MealLogs;
using SmartNutrition.Api.Features.Relationships;
using SmartNutrition.Api.Infrastructure;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Features.WaterLogs;

[ApiController, Route("api/v1/water-logs")]
[Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme, Roles = "client,dietitian")]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public sealed class WaterLogsController(WaterLogService logs, RelationshipAccessService access) : ControllerBase
{
    private bool HasBody => HttpContext.Features.Get<IHttpRequestBodyDetectionFeature>()?.CanHaveBody == true;
    private bool NoInput => !HasBody && Request.Query.Count == 0;
    private bool QueryKeys(params string[] keys) => !HasBody && Request.Query.All(x => keys.Contains(x.Key) && x.Value.Count == 1);
    private async Task<Guid> ClientId(CancellationToken token)
    {
        var actor = await access.RequireAsync(User, token, Request);
        if (actor.Role != UserRole.Client || actor.ClientId is null) throw new ResourceOperationException(403);
        return actor.ClientId.Value;
    }
    private (DateTimeOffset? From, DateTimeOffset? To) Range(string? from, string? to)
    {
        DateTimeOffset? start = null, end = null;
        if (Request.Query.ContainsKey("from"))
        {
            if (!MealLogInstantJsonConverter.TryParse(from, out var value)) throw new ResourceOperationException(400);
            start = value;
        }
        if (Request.Query.ContainsKey("to"))
        {
            if (!MealLogInstantJsonConverter.TryParse(to, out var value)) throw new ResourceOperationException(400);
            end = value;
        }
        if (start is not null && end is not null && start >= end) throw new ResourceOperationException(400);
        return (start, end);
    }

    [HttpPost, Consumes("application/json"), RequestSizeLimit(4096), ProducesResponseType<WaterLogResponse>(201)]
    public async Task<IActionResult> Create(CreateWaterLogRequest request, CancellationToken token)
    {
        if (Request.Query.Count != 0) return BadRequest(ApiErrors.Create(HttpContext, 400));
        var result = await logs.CreateAsync(await ClientId(token), request, token);
        return Created($"/api/v1/water-logs/{result.Id}", result);
    }
    [HttpGet, ProducesResponseType<PagedResponse<WaterLogResponse>>(200)]
    public async Task<IActionResult> List([FromQuery, BindRequired] int page, [FromQuery, BindRequired] int pageSize,
        [FromQuery] string? from, [FromQuery] string? to, CancellationToken token)
    {
        if (!QueryKeys("page", "pageSize", "from", "to") || page < 1 || pageSize is < 1 or > 100 || (long)(page - 1) * pageSize > int.MaxValue)
            return BadRequest(ApiErrors.Create(HttpContext, 400));
        var range = Range(from, to);
        return Ok(await logs.ListAsync(await ClientId(token), page, pageSize, range.From, range.To, token));
    }
    [HttpGet("daily-total"), ProducesResponseType<WaterLogDailyTotalResponse>(200)]
    public async Task<IActionResult> DailyTotal([FromQuery] string? from, [FromQuery] string? to, CancellationToken token)
    {
        if (!QueryKeys("from", "to")) return BadRequest(ApiErrors.Create(HttpContext, 400));
        var range = Range(from, to);
        // Boundaries belong to the requested local calendar day. Distinct explicit
        // offsets allow DST days; neither the host nor UTC defines the user's day.
        if (range.From is not { } start || range.To is not { } end || start.TimeOfDay != TimeSpan.Zero ||
            end.TimeOfDay != TimeSpan.Zero || start.Date == DateTime.MaxValue.Date || end.Date != start.Date.AddDays(1))
            return BadRequest(ApiErrors.Create(HttpContext, 400));
        return Ok(await logs.DailyTotalAsync(await ClientId(token), start, end, token));
    }
    [HttpGet("{waterLogId}"), ProducesResponseType<WaterLogResponse>(200)]
    public async Task<IActionResult> Get(Guid waterLogId, CancellationToken token) => !NoInput
        ? BadRequest(ApiErrors.Create(HttpContext, 400)) : Ok(await logs.GetAsync(await ClientId(token), waterLogId, token));
    [HttpPatch("{waterLogId}"), Consumes("application/json"), RequestSizeLimit(4096), ProducesResponseType<WaterLogResponse>(200)]
    public async Task<IActionResult> Patch(Guid waterLogId, PatchWaterLogRequest request, CancellationToken token) => Request.Query.Count != 0
        ? BadRequest(ApiErrors.Create(HttpContext, 400)) : Ok(await logs.PatchAsync(await ClientId(token), waterLogId, request, token));
    [HttpDelete("{waterLogId}"), ProducesResponseType(204)]
    public async Task<IActionResult> Delete(Guid waterLogId, CancellationToken token)
    {
        if (!NoInput) return BadRequest(ApiErrors.Create(HttpContext, 400));
        await logs.DeleteAsync(await ClientId(token), waterLogId, token);
        return NoContent();
    }
}
