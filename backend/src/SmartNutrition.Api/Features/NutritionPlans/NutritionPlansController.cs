using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.ModelBinding;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Features.Dietitians;
using SmartNutrition.Api.Features.Relationships;
using SmartNutrition.Api.Infrastructure;

namespace SmartNutrition.Api.Features.NutritionPlans;

[ApiController, Route("api/v1/nutrition-plans")]
[Authorize(AuthenticationSchemes = WebSessionAuthentication.AccountScheme, Roles = "client,dietitian")]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public sealed class NutritionPlansController(NutritionPlanService plans, RelationshipAccessService access) : ControllerBase
{
    private bool HasBody => HttpContext.Features.Get<IHttpRequestBodyDetectionFeature>()?.CanHaveBody == true;
    private bool NoInput => !HasBody && Request.Query.Count == 0;
    private Task<ProfileIdentity> Actor(CancellationToken token) => access.RequireAsync(User, token);
    [HttpPost, Consumes("application/json"), RequestSizeLimit(131072), ProducesResponseType<NutritionPlanResponse>(201)]
    public async Task<IActionResult> Create(CreateNutritionPlanRequest request, CancellationToken token)
    {
        if (Request.Query.Count != 0 || !await WebSessionAuthentication.ValidMutationAsync(HttpContext)) return BadRequest(ApiErrors.Create(HttpContext, 400));
        var result = await plans.CreateAsync(await Actor(token), request, token); return Created($"/api/v1/nutrition-plans/{result.Id}", result);
    }
    [HttpGet, ProducesResponseType<PagedResponse<NutritionPlanResponse>>(200)]
    public async Task<IActionResult> List([FromQuery, BindRequired] int page, [FromQuery, BindRequired] int pageSize, [FromQuery] Guid? clientId, CancellationToken token)
    {
        if (HasBody || !DietitiansController.ValidPage(page, pageSize) || Request.Query.Keys.Any(x => x is not ("page" or "pageSize" or "clientId"))) return BadRequest(ApiErrors.Create(HttpContext, 400));
        var actor = await Actor(token);
        if (actor.Role == SmartNutrition.Api.Models.UserRole.Client && Request.Query.ContainsKey("clientId")) return BadRequest(ApiErrors.Create(HttpContext, 400));
        return Ok(await plans.ListAsync(actor, clientId, page, pageSize, token));
    }
    [HttpGet("active"), Authorize(Roles = "client"), ProducesResponseType<NutritionPlanResponse>(200)]
    public async Task<IActionResult> Active(CancellationToken token) => !NoInput ? BadRequest(ApiErrors.Create(HttpContext, 400)) : Ok(await plans.ActiveAsync(await Actor(token), token));
    [HttpGet("{nutritionPlanId:guid}"), ProducesResponseType<NutritionPlanResponse>(200)]
    public async Task<IActionResult> Get(Guid nutritionPlanId, CancellationToken token) => !NoInput ? BadRequest(ApiErrors.Create(HttpContext, 400)) : Ok(await plans.GetAsync(await Actor(token), nutritionPlanId, token));
    [HttpPatch("{nutritionPlanId:guid}"), Consumes("application/json"), RequestSizeLimit(131072), ProducesResponseType<NutritionPlanResponse>(200)]
    public async Task<IActionResult> Patch(Guid nutritionPlanId, PatchNutritionPlanRequest request, CancellationToken token)
    {
        if (Request.Query.Count != 0 || !await WebSessionAuthentication.ValidMutationAsync(HttpContext)) return BadRequest(ApiErrors.Create(HttpContext, 400));
        return Ok(await plans.PatchAsync(await Actor(token), nutritionPlanId, request, token));
    }
    [HttpPost("{nutritionPlanId:guid}/activate"), ProducesResponseType<NutritionPlanResponse>(200)]
    public Task<IActionResult> Activate(Guid nutritionPlanId, CancellationToken token) => Change(nutritionPlanId, NutritionPlanStatus.Active, token);
    [HttpPost("{nutritionPlanId:guid}/archive"), ProducesResponseType<NutritionPlanResponse>(200)]
    public Task<IActionResult> Archive(Guid nutritionPlanId, CancellationToken token) => Change(nutritionPlanId, NutritionPlanStatus.Archived, token);
    private async Task<IActionResult> Change(Guid id, NutritionPlanStatus status, CancellationToken token)
    {
        if (!NoInput || !await WebSessionAuthentication.ValidMutationAsync(HttpContext)) return BadRequest(ApiErrors.Create(HttpContext, 400));
        return Ok(await plans.ChangeStatusAsync(await Actor(token), id, status, token));
    }
    [HttpGet("{nutritionPlanId:guid}/versions"), ProducesResponseType<PagedResponse<NutritionPlanVersionInfo>>(200)]
    public async Task<IActionResult> Versions(Guid nutritionPlanId, [FromQuery, BindRequired] int page, [FromQuery, BindRequired] int pageSize, CancellationToken token)
    {
        if (HasBody || !DietitiansController.ValidPage(page, pageSize) || Request.Query.Keys.Any(x => x is not ("page" or "pageSize"))) return BadRequest(ApiErrors.Create(HttpContext, 400));
        return Ok(await plans.VersionsAsync(await Actor(token), nutritionPlanId, page, pageSize, token));
    }
    [HttpGet("{nutritionPlanId:guid}/versions/{versionId:guid}"), ProducesResponseType<NutritionPlanVersionResponse>(200)]
    public async Task<IActionResult> Version(Guid nutritionPlanId, Guid versionId, CancellationToken token) => !NoInput ? BadRequest(ApiErrors.Create(HttpContext, 400)) : Ok(await plans.VersionAsync(await Actor(token), nutritionPlanId, versionId, token));
}
