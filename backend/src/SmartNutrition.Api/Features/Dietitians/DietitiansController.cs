using System.ComponentModel.DataAnnotations;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.ModelBinding;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using SmartNutrition.Api.Data;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Infrastructure;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Features.Dietitians;

public sealed record DietitianStatusResponse(Guid Id, string DisplayName, bool IsVerified);
public sealed record DietitianListItem(Guid Id, string DisplayName);
public sealed record DietitianReviewItem(Guid Id, string DisplayName, string LicenseInfo, bool IsVerified);
public sealed record PagedResponse<T>(IReadOnlyList<T> Items, int TotalCount);

[ApiController, Route("api/v1/dietitians")]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public sealed class DietitiansController(AppDbContext database, DietitianApplicationService applications,
    VerificationEmailQueue emailQueue) : ControllerBase
{
    [HttpPost("apply"), AllowAnonymous, Consumes("application/json"), RequestSizeLimit(16384), EnableRateLimiting("dietitian-application")]
    [ProducesResponseType<RegisterUserResponse>(201)]
    public async Task<IActionResult> Apply(DietitianApplicationRequest request, CancellationToken cancellationToken)
    {
        if (Request.Query.Count != 0) return BadRequest(ApiErrors.Create(HttpContext, 400));
        try
        {
            var user = await applications.ApplyAsync(request, cancellationToken);
            emailQueue.Enqueue(user.Email);
            return StatusCode(201, new RegisterUserResponse(user.Id));
        }
        catch (ValidationException) { return StatusCode(422, ApiErrors.Create(HttpContext, 422)); }
        catch (RegistrationEmailConflictException) { return Conflict(ApiErrors.Create(HttpContext, 409)); }
    }

    [HttpGet("me"), Authorize(AuthenticationSchemes = WebSessionAuthentication.AccountScheme, Roles = "dietitian")]
    [ProducesResponseType<DietitianStatusResponse>(200)]
    public async Task<IActionResult> Me(CancellationToken cancellationToken)
    {
        if (Request.Query.Count != 0 || HasBody) return BadRequest(ApiErrors.Create(HttpContext, 400));
        if (!Guid.TryParse(User.FindFirst("sub")?.Value, out var userId)) return Unauthorized(ApiErrors.Create(HttpContext, 401));
        var profile = await database.DietitianProfiles.AsNoTracking()
            .Where(x => x.UserId == userId && x.User.Role == UserRole.Dietitian && x.User.IsEmailVerified)
            .Select(x => new DietitianStatusResponse(x.Id, x.DisplayName, x.IsVerified)).SingleOrDefaultAsync(cancellationToken);
        return profile is null ? NotFound(ApiErrors.Create(HttpContext, 404)) : Ok(profile);
    }

    [HttpGet, AllowAnonymous]
    [ProducesResponseType<PagedResponse<DietitianListItem>>(200)]
    public async Task<IActionResult> Search([FromQuery, BindRequired] int page, [FromQuery, BindRequired] int pageSize,
        [FromQuery] string? query, CancellationToken cancellationToken)
    {
        if (HasBody || Request.Query.Keys.Any(key => key is not ("page" or "pageSize" or "query")) ||
            !ValidPage(page, pageSize)) return BadRequest(ApiErrors.Create(HttpContext, 400));
        var profiles = database.DietitianProfiles.AsNoTracking().Where(x => x.IsVerified &&
            x.User.Role == UserRole.Dietitian && x.User.IsEmailVerified);
        if (!string.IsNullOrWhiteSpace(query))
        {
            var pattern = "%" + query.Trim().Replace("\\", "\\\\").Replace("%", "\\%").Replace("_", "\\_") + "%";
            profiles = profiles.Where(x => EF.Functions.ILike(x.DisplayName, pattern, "\\"));
        }
        var total = await profiles.CountAsync(cancellationToken);
        var items = await profiles.OrderBy(x => x.DisplayName).ThenBy(x => x.Id).Skip((page - 1) * pageSize).Take(pageSize)
            .Select(x => new DietitianListItem(x.Id, x.DisplayName)).ToListAsync(cancellationToken);
        return Ok(new PagedResponse<DietitianListItem>(items, total));
    }

    private bool HasBody => HttpContext.Features.Get<IHttpRequestBodyDetectionFeature>()?.CanHaveBody == true;
    internal static bool ValidPage(int page, int size) => page > 0 && size > 0 && (long)(page - 1) * size <= int.MaxValue;
}
