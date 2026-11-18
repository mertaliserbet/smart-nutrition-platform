using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.AspNetCore.Mvc;
using SmartNutrition.Api.Features.Dietitians;
using SmartNutrition.Api.Features.Relationships;
using SmartNutrition.Api.Infrastructure;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Features.PersonalNutritionTargets;

[ApiController, Route("api/v1/personal-nutrition-targets")]
[Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme, Roles = "client,dietitian")]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public sealed class PersonalNutritionTargetsController(PersonalNutritionTargetService targets, RelationshipAccessService access) : ControllerBase
{
    private async Task<ProfileIdentity> Client(CancellationToken token)
    {
        var actor = await access.RequireAsync(User, token, Request);
        if (actor.Role != UserRole.Client || actor.ClientId is null) throw new ResourceOperationException(403);
        return actor;
    }
    [HttpGet, ProducesResponseType<PersonalNutritionTargetResponse>(200)]
    public async Task<IActionResult> Get(CancellationToken token)
    {
        if (Request.Query.Count != 0 || HttpContext.Features.Get<IHttpRequestBodyDetectionFeature>()?.CanHaveBody == true)
            return BadRequest(ApiErrors.Create(HttpContext, 400));
        return Ok(await targets.GetAsync((await Client(token)).ClientId!.Value, token));
    }
    [HttpPatch, Consumes("application/json"), RequestSizeLimit(4096), ProducesResponseType<PersonalNutritionTargetResponse>(200)]
    public async Task<IActionResult> Patch(PatchPersonalNutritionTargetRequest request, CancellationToken token) => Request.Query.Count != 0
        ? BadRequest(ApiErrors.Create(HttpContext, 400)) : Ok(await targets.PatchAsync(await Client(token), request, token));
}
