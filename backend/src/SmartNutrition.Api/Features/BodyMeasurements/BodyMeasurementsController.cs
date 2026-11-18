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

namespace SmartNutrition.Api.Features.BodyMeasurements;

[ApiController, Route("api/v1/body-measurements")]
[Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme, Roles = "client,dietitian")]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public sealed class BodyMeasurementsController(BodyMeasurementService measurements, RelationshipAccessService access) : ControllerBase
{
    private bool HasBody => HttpContext.Features.Get<IHttpRequestBodyDetectionFeature>()?.CanHaveBody == true;
    private bool NoInput => !HasBody && Request.Query.Count == 0;
    private async Task<Guid> ClientId(CancellationToken token)
    {
        var actor = await access.RequireAsync(User, token, Request);
        if (actor.Role != UserRole.Client || actor.ClientId is null) throw new ResourceOperationException(403);
        return actor.ClientId.Value;
    }
    [HttpPost, Consumes("application/json"), RequestSizeLimit(16384), ProducesResponseType<BodyMeasurementResponse>(201)]
    public async Task<IActionResult> Create(CreateBodyMeasurementRequest request, CancellationToken token)
    {
        if (Request.Query.Count != 0) return BadRequest(ApiErrors.Create(HttpContext, 400));
        var row = await measurements.CreateAsync(await ClientId(token), request, token);
        return Created($"/api/v1/body-measurements/{row.Id}", row);
    }
    [HttpGet, ProducesResponseType<PagedResponse<BodyMeasurementResponse>>(200)]
    public async Task<IActionResult> List([FromQuery, BindRequired] int page, [FromQuery, BindRequired] int pageSize,
        [FromQuery] string? from, [FromQuery] string? to, [FromQuery] string? sortOrder, CancellationToken token)
    {
        if (HasBody || page < 1 || pageSize is < 1 or > 100 || (long)(page - 1) * pageSize > int.MaxValue ||
            Request.Query.Keys.Any(x => x is not ("page" or "pageSize" or "from" or "to" or "sortOrder")) ||
            Request.Query.Any(x => x.Value.Count != 1) || sortOrder is not (null or "asc" or "desc") ||
            Request.Query.ContainsKey("sortOrder") && string.IsNullOrEmpty(sortOrder)) return BadRequest(ApiErrors.Create(HttpContext, 400));
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
        return Ok(await measurements.ListAsync(await ClientId(token), page, pageSize, start, end, sortOrder == "asc", token));
    }
    [HttpGet("{bodyMeasurementId}"), ProducesResponseType<BodyMeasurementResponse>(200)]
    public async Task<IActionResult> Get(Guid bodyMeasurementId, CancellationToken token) => !NoInput
        ? BadRequest(ApiErrors.Create(HttpContext, 400)) : Ok(await measurements.GetAsync(await ClientId(token), bodyMeasurementId, token));
    [HttpPatch("{bodyMeasurementId}"), Consumes("application/json"), RequestSizeLimit(16384), ProducesResponseType<BodyMeasurementResponse>(200)]
    public async Task<IActionResult> Patch(Guid bodyMeasurementId, PatchBodyMeasurementRequest request, CancellationToken token) => Request.Query.Count != 0
        ? BadRequest(ApiErrors.Create(HttpContext, 400)) : Ok(await measurements.PatchAsync(await ClientId(token), bodyMeasurementId, request, token));
    [HttpDelete("{bodyMeasurementId}"), ProducesResponseType(204)]
    public async Task<IActionResult> Delete(Guid bodyMeasurementId, CancellationToken token)
    {
        if (!NoInput) return BadRequest(ApiErrors.Create(HttpContext, 400));
        await measurements.DeleteAsync(await ClientId(token), bodyMeasurementId, token);
        return NoContent();
    }
}
