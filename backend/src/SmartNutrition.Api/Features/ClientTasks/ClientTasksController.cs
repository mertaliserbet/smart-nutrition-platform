using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.ModelBinding;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Features.Dietitians;
using SmartNutrition.Api.Features.Relationships;
using SmartNutrition.Api.Infrastructure;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Features.ClientTasks;

[ApiController, Route("api/v1/client-tasks")]
[Authorize(AuthenticationSchemes = WebSessionAuthentication.AccountScheme, Roles = "client,dietitian")]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public sealed class ClientTasksController(ClientTaskService tasks, RelationshipAccessService access) : ControllerBase
{
    private bool HasBody => HttpContext.Features.Get<IHttpRequestBodyDetectionFeature>()?.CanHaveBody == true;
    private Task<ProfileIdentity> Actor(CancellationToken token) => access.RequireAsync(User, token, Request);
    private bool ValidPage(int page, int size, bool allowClientId) => !HasBody && page >= 1 && size is >= 1 and <= 100 &&
        (long)(page - 1) * size <= int.MaxValue && Request.Query.All(x => x.Value.Count == 1 &&
            (x.Key is "page" or "pageSize" || allowClientId && x.Key == "clientId"));

    [HttpGet, ProducesResponseType<PagedResponse<ClientTaskResponse>>(200)]
    public async Task<IActionResult> List([FromQuery, BindRequired] int page, [FromQuery, BindRequired] int pageSize,
        [FromQuery] Guid? clientId, CancellationToken token)
    {
        if (!ValidPage(page, pageSize, true)) return BadRequest(ApiErrors.Create(HttpContext, 400));
        var actor = await Actor(token);
        if (actor.Role == UserRole.Client && Request.Query.ContainsKey("clientId")) return BadRequest(ApiErrors.Create(HttpContext, 400));
        return Ok(await tasks.ListAsync(actor, clientId, page, pageSize, token));
    }
    [HttpGet("{clientTaskId:guid}"), ProducesResponseType<ClientTaskResponse>(200)]
    public async Task<IActionResult> Get(Guid clientTaskId, CancellationToken token) =>
        HasBody || Request.Query.Count != 0 ? BadRequest(ApiErrors.Create(HttpContext, 400)) : Ok(await tasks.GetAsync(await Actor(token), clientTaskId, token));

    [HttpGet("{clientTaskId:guid}/versions"), ProducesResponseType<PagedResponse<ClientTaskVersionResponse>>(200)]
    public async Task<IActionResult> Versions(Guid clientTaskId, [FromQuery, BindRequired] int page, [FromQuery, BindRequired] int pageSize, CancellationToken token) =>
        !ValidPage(page, pageSize, false) ? BadRequest(ApiErrors.Create(HttpContext, 400)) : Ok(await tasks.VersionsAsync(await Actor(token), clientTaskId, page, pageSize, token));

    [HttpPost, Consumes("application/json"), RequestSizeLimit(32768), ProducesResponseType<ClientTaskResponse>(201)]
    public async Task<IActionResult> Create(CreateClientTaskRequest request, CancellationToken token)
    {
        if (Request.Query.Count != 0 || !await WebSessionAuthentication.ValidMutationAsync(HttpContext)) return BadRequest(ApiErrors.Create(HttpContext, 400));
        var result = await tasks.CreateAsync(await Actor(token), request, token);
        return Created($"/api/v1/client-tasks/{result.Id}", result);
    }
    [HttpPatch("{clientTaskId:guid}"), Consumes("application/json"), RequestSizeLimit(32768), ProducesResponseType<ClientTaskResponse>(200)]
    public async Task<IActionResult> Patch(Guid clientTaskId, PatchClientTaskRequest request, CancellationToken token)
    {
        if (Request.Query.Count != 0 || !await WebSessionAuthentication.ValidMutationAsync(HttpContext)) return BadRequest(ApiErrors.Create(HttpContext, 400));
        return Ok(await tasks.PatchAsync(await Actor(token), clientTaskId, request, token));
    }
}
