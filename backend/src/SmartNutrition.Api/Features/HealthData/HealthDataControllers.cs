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

namespace SmartNutrition.Api.Features.HealthData;

[ApiController]
[Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme, Roles = "client")]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public abstract class OwnHealthController(RelationshipAccessService access) : ControllerBase
{
    protected async Task<ProfileIdentity> Actor(CancellationToken token)
    {
        var actor = await access.RequireAsync(User, token, Request);
        if (actor.Role != UserRole.Client || actor.ClientId is null) throw new ResourceOperationException(403);
        return actor;
    }
    protected void Query(params string[] keys)
    {
        if (HttpContext.Features.Get<IHttpRequestBodyDetectionFeature>()?.CanHaveBody == true ||
            Request.Query.Any(x => !keys.Contains(x.Key) || x.Value.Count != 1)) throw new ResourceOperationException(400);
    }
    protected void BodyQuery() { if (Request.Query.Count != 0) throw new ResourceOperationException(400); }
    protected static void Page(int page, int size)
    {
        if (page < 1 || size is < 1 or > 100 || (long)(page - 1) * size > int.MaxValue) throw new ResourceOperationException(400);
    }
    protected (DateTimeOffset? From, DateTimeOffset? To) Range(string? from, string? to)
    {
        DateTimeOffset? start = null, end = null;
        if (Request.Query.ContainsKey("from"))
        {
            if (!MealLogInstantJsonConverter.TryParse(from, out var instant)) throw new ResourceOperationException(400);
            start = instant;
        }
        if (Request.Query.ContainsKey("to"))
        {
            if (!MealLogInstantJsonConverter.TryParse(to, out var instant)) throw new ResourceOperationException(400);
            end = instant;
        }
        if (start is not null && end is not null && start >= end) throw new ResourceOperationException(400);
        return (start, end);
    }
}

[Route("api/v1/wearable-connections")]
public sealed class WearableConnectionsController(HealthDataService health, RelationshipAccessService access) : OwnHealthController(access)
{
    [HttpPost, Consumes("application/json"), RequestSizeLimit(4096), ProducesResponseType<WearableConnectionResponse>(200)]
    public async Task<IActionResult> Connect(CreateWearableConnectionRequest input, CancellationToken token)
    {
        BodyQuery(); return Ok(await health.ConnectAsync(await Actor(token), input.Provider, token));
    }
    [HttpGet, ProducesResponseType<PagedResponse<WearableConnectionResponse>>(200)]
    public async Task<IActionResult> List([FromQuery, BindRequired] int page, [FromQuery, BindRequired] int pageSize, CancellationToken token)
    {
        Query("page", "pageSize"); Page(page, pageSize);
        return Ok(await health.ConnectionsAsync((await Actor(token)).ClientId!.Value, page, pageSize, token));
    }
    [HttpGet("{wearableConnectionId}"), ProducesResponseType<WearableConnectionResponse>(200)]
    public async Task<IActionResult> Get(Guid wearableConnectionId, CancellationToken token)
    {
        Query(); return Ok(await health.GetConnectionAsync((await Actor(token)).ClientId!.Value, wearableConnectionId, token));
    }
    [HttpPatch("{wearableConnectionId}"), Consumes("application/json"), RequestSizeLimit(4096), ProducesResponseType<WearableConnectionResponse>(200)]
    public async Task<IActionResult> Patch(Guid wearableConnectionId, PatchWearableConnectionRequest input, CancellationToken token)
    {
        BodyQuery(); return Ok(await health.PatchConnectionAsync(await Actor(token), wearableConnectionId, input, token));
    }
    [HttpPost("sync"), Consumes("application/json"), RequestSizeLimit(524288), ProducesResponseType<WearableSyncResult>(200)]
    public async Task<IActionResult> Sync(WearableSyncRequest input, CancellationToken token)
    {
        BodyQuery(); return Ok(await health.SyncAsync(await Actor(token), input, token));
    }
    [HttpGet("{wearableConnectionId}/records"), ProducesResponseType<PagedResponse<WearableRecordResponse>>(200)]
    public async Task<IActionResult> Records(Guid wearableConnectionId, [FromQuery, BindRequired] int page, [FromQuery, BindRequired] int pageSize,
        [FromQuery] string? sourceId, [FromQuery] string? rawType, [FromQuery] string? externalRecordId, CancellationToken token)
    {
        Query("page", "pageSize", "sourceId", "rawType", "externalRecordId"); Page(page, pageSize);
        if (!HealthDataValidation.OptionalText(sourceId) || !HealthDataValidation.OptionalText(rawType, 64) || !HealthDataValidation.OptionalText(externalRecordId)) throw new ResourceOperationException(400);
        return Ok(await health.RecordsAsync((await Actor(token)).ClientId!.Value, wearableConnectionId, page, pageSize, sourceId, rawType, externalRecordId, token));
    }
    [HttpGet("{wearableConnectionId}/records/{wearableRecordId}"), ProducesResponseType<WearableRecordResponse>(200)]
    public async Task<IActionResult> Record(Guid wearableConnectionId, Guid wearableRecordId, CancellationToken token)
    {
        Query(); return Ok(await health.RecordAsync((await Actor(token)).ClientId!.Value, wearableConnectionId, wearableRecordId, token));
    }
}

[Route("api/v1/health-metric-samples")]
public sealed class HealthMetricSamplesController(HealthDataService health, RelationshipAccessService access) : OwnHealthController(access)
{
    [HttpGet, ProducesResponseType<PagedResponse<HealthMetricSampleResponse>>(200)]
    public async Task<IActionResult> List([FromQuery, BindRequired] int page, [FromQuery, BindRequired] int pageSize, [FromQuery] string? metric,
        [FromQuery] Guid? wearableRecordId, [FromQuery] string? from, [FromQuery] string? to, [FromQuery] bool includeDeleted, CancellationToken token)
    {
        Query("page", "pageSize", "metric", "wearableRecordId", "from", "to", "includeDeleted"); Page(page, pageSize);
        var range = Range(from, to);
        return Ok(await health.SamplesAsync((await Actor(token)).ClientId!.Value, page, pageSize, metric, wearableRecordId, range.From, range.To, includeDeleted, token));
    }
}

[Route("api/v1/activity-logs")]
public sealed class ActivityLogsController(ActivityLogService logs, ActivitySummaryService summary, RelationshipAccessService access) : OwnHealthController(access)
{
    [HttpPost, Consumes("application/json"), RequestSizeLimit(4096), ProducesResponseType<ActivityLogResponse>(201)]
    public async Task<IActionResult> Create(CreateActivityLogRequest input, CancellationToken token)
    {
        BodyQuery(); var row = await logs.CreateAsync(await Actor(token), input, token);
        return Created($"/api/v1/activity-logs/{row.Id}", row);
    }
    [HttpGet, ProducesResponseType<PagedResponse<ActivityLogResponse>>(200)]
    public async Task<IActionResult> List([FromQuery, BindRequired] int page, [FromQuery, BindRequired] int pageSize,
        [FromQuery] string? from, [FromQuery] string? to, CancellationToken token)
    {
        Query("page", "pageSize", "from", "to"); Page(page, pageSize); var range = Range(from, to);
        return Ok(await logs.ListAsync((await Actor(token)).ClientId!.Value, page, pageSize, range.From, range.To, token));
    }
    [HttpGet("daily-summary"), ProducesResponseType<ActivityDailySummaryResponse>(200)]
    public async Task<IActionResult> Daily([FromQuery] string? from, [FromQuery] string? to, CancellationToken token)
    {
        Query("from", "to"); var range = Range(from, to);
        if (range.From is not { } start || range.To is not { } end || start.TimeOfDay != TimeSpan.Zero || end.TimeOfDay != TimeSpan.Zero ||
            start.Date == DateTime.MaxValue.Date || end.Date != start.Date.AddDays(1) || (end - start).TotalHours is < 22 or > 26)
            throw new ResourceOperationException(400);
        return Ok(await summary.DailyAsync((await Actor(token)).ClientId!.Value, start, end, token));
    }
    [HttpGet("{activityLogId}"), ProducesResponseType<ActivityLogResponse>(200)]
    public async Task<IActionResult> Get(Guid activityLogId, CancellationToken token)
    {
        Query(); return Ok(await logs.GetAsync((await Actor(token)).ClientId!.Value, activityLogId, token));
    }
    [HttpPatch("{activityLogId}"), Consumes("application/json"), RequestSizeLimit(4096), ProducesResponseType<ActivityLogResponse>(200)]
    public async Task<IActionResult> Patch(Guid activityLogId, PatchActivityLogRequest input, CancellationToken token)
    {
        BodyQuery(); return Ok(await logs.PatchAsync(await Actor(token), activityLogId, input, token));
    }
    [HttpDelete("{activityLogId}"), ProducesResponseType(204)]
    public async Task<IActionResult> Delete(Guid activityLogId, [FromQuery, BindRequired] int expectedVersionNumber, CancellationToken token)
    {
        Query("expectedVersionNumber"); await logs.DeleteAsync(await Actor(token), activityLogId, expectedVersionNumber, token); return NoContent();
    }
}
