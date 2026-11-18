using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.AspNetCore.Mvc;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Features.MealLogs;
using SmartNutrition.Api.Infrastructure;

namespace SmartNutrition.Api.Features.NutritionPlans;

[ApiController, Route("api/v1/nutrition-plans/{nutritionPlanId:guid}/versions/{versionId:guid}/meal-comparison")]
[Authorize(AuthenticationSchemes = WebSessionAuthentication.AccountScheme, Roles = "client,dietitian")]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public sealed class NutritionPlanMealComparisonController(NutritionPlanMealComparisonService comparisons) : ControllerBase
{
    [HttpGet, ProducesResponseType<NutritionPlanMealComparisonResponse>(200)]
    public async Task<IActionResult> Compare(Guid nutritionPlanId, Guid versionId,
        [FromQuery] string? from, [FromQuery] string? to, CancellationToken token)
    {
        if (HttpContext.Features.Get<IHttpRequestBodyDetectionFeature>()?.CanHaveBody == true ||
            Request.Query.Any(x => x.Key is not ("from" or "to") || x.Value.Count != 1) ||
            !MealLogInstantJsonConverter.TryParse(from, out var start) || !MealLogInstantJsonConverter.TryParse(to, out var end) ||
            start.TimeOfDay != TimeSpan.Zero || end.TimeOfDay != TimeSpan.Zero ||
            start.Date == DateTime.MaxValue.Date || end.Date != start.Date.AddDays(1) || start >= end)
            return BadRequest(ApiErrors.Create(HttpContext, 400));
        return Ok(await comparisons.CompareAsync(Request, User, nutritionPlanId, versionId, start, end, token));
    }
}
