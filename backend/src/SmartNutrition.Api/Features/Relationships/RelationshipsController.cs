using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.ModelBinding;
using Microsoft.EntityFrameworkCore;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Features.Dietitians;
using SmartNutrition.Api.Infrastructure;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Features.Relationships;

[ApiController, Route("api/v1/dietitian-relationships")]
[Authorize(AuthenticationSchemes = WebSessionAuthentication.AccountScheme, Roles = "client,dietitian")]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public sealed class RelationshipsController(RelationshipAccessService access, RelationshipService relationships) : ControllerBase
{
    [HttpPost, Consumes("application/json"), RequestSizeLimit(4096)]
    [ProducesResponseType<RelationshipResponse>(201)]
    public async Task<IActionResult> Create(RelationshipRequest request, CancellationToken token)
    {
        if (base.Request.Query.Count != 0 || !await WebSessionAuthentication.ValidMutationAsync(HttpContext)) return BadRequest(ApiErrors.Create(HttpContext, 400));
        var actor = await access.RequireAsync(User, token);
        var result = await relationships.RequestAsync(actor, request, HttpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown", token);
        return StatusCode(201, result);
    }

    [HttpGet, ProducesResponseType<PagedResponse<RelationshipResponse>>(200)]
    public async Task<IActionResult> List([FromQuery, BindRequired] int page, [FromQuery, BindRequired] int pageSize,
        [FromQuery] string? status, CancellationToken token)
    {
        if (!DietitiansController.ValidPage(page, pageSize) || HttpContext.Features.Get<IHttpRequestBodyDetectionFeature>()?.CanHaveBody == true ||
            base.Request.Query.Keys.Any(x => x is not ("page" or "pageSize" or "status")) ||
            (status is not null && status is not ("pending" or "active" or "rejected" or "ended"))) return BadRequest(ApiErrors.Create(HttpContext, 400));
        var actor = await access.RequireAsync(User, token); var query = relationships.Own(actor);
        if (status is not null) { var selected = Enum.Parse<RelationshipStatus>(status, true); query = query.Where(x => x.Status == selected); }
        var total = await query.CountAsync(token);
        var rows = await query.OrderByDescending(x => x.RequestedAt).ThenBy(x => x.Id).Skip((page - 1) * pageSize).Take(pageSize).ToListAsync(token);
        return Ok(new PagedResponse<RelationshipResponse>(rows.Select(RelationshipResponse.From).ToList(), total));
    }

    [HttpPost("{relationshipId:guid}/accept"), ProducesResponseType<RelationshipResponse>(200)]
    public Task<IActionResult> Accept(Guid relationshipId, CancellationToken token) => Change(relationshipId, "accept", token);
    [HttpPost("{relationshipId:guid}/reject"), ProducesResponseType<RelationshipResponse>(200)]
    public Task<IActionResult> Reject(Guid relationshipId, CancellationToken token) => Change(relationshipId, "reject", token);
    [HttpPost("{relationshipId:guid}/end"), ProducesResponseType<RelationshipResponse>(200)]
    public Task<IActionResult> End(Guid relationshipId, CancellationToken token) => Change(relationshipId, "end", token);
    private async Task<IActionResult> Change(Guid id, string action, CancellationToken token)
    {
        if (base.Request.Query.Count != 0 || HttpContext.Features.Get<IHttpRequestBodyDetectionFeature>()?.CanHaveBody == true ||
            !await WebSessionAuthentication.ValidMutationAsync(HttpContext)) return BadRequest(ApiErrors.Create(HttpContext, 400));
        return Ok(await relationships.TransitionAsync(await access.RequireAsync(User, token), id, action, token));
    }
}

[ApiController, Route("api/v1/dietitians/me/invitation-code")]
[Authorize(AuthenticationSchemes = WebSessionAuthentication.AccountScheme, Roles = "dietitian")]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public sealed class InvitationCodesController(RelationshipAccessService access, RelationshipService relationships) : ControllerBase
{
    [HttpPost, ProducesResponseType<InvitationCodeResponse>(200)]
    public async Task<IActionResult> Create(CancellationToken token)
    {
        if (Request.Query.Count != 0 || HttpContext.Features.Get<IHttpRequestBodyDetectionFeature>()?.CanHaveBody == true ||
            !await WebSessionAuthentication.ValidMutationAsync(HttpContext)) return BadRequest(ApiErrors.Create(HttpContext, 400));
        return Ok(await relationships.CreateInvitationAsync(await access.RequireAsync(User, token), HttpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown", token));
    }
}
