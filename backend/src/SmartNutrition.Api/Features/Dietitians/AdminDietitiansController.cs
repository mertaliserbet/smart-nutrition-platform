using Microsoft.AspNetCore.Antiforgery;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.ModelBinding;
using Microsoft.EntityFrameworkCore;
using SmartNutrition.Api.Data;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Infrastructure;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Features.Dietitians;

[ApiController, Route("api/v1/admin/dietitians")]
[Authorize(AuthenticationSchemes = WebSessionAuthentication.Scheme, Roles = "admin")]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public sealed class AdminDietitiansController(AppDbContext database, IAntiforgery antiforgery,
    WebSessionService sessions, TimeProvider clock) : ControllerBase
{
    private bool HasBody => HttpContext.Features.Get<IHttpRequestBodyDetectionFeature>()?.CanHaveBody == true;

    [HttpGet]
    [ProducesResponseType<PagedResponse<DietitianReviewItem>>(200)]
    public async Task<IActionResult> List([FromQuery, BindRequired] bool isVerified, [FromQuery, BindRequired] int page,
        [FromQuery, BindRequired] int pageSize, CancellationToken cancellationToken)
    {
        if (HasBody || Request.Query.Keys.Any(key => key is not ("isVerified" or "page" or "pageSize")) ||
            !DietitiansController.ValidPage(page, pageSize)) return BadRequest(ApiErrors.Create(HttpContext, 400));
        var query = database.DietitianProfiles.AsNoTracking().Where(x => x.IsVerified == isVerified && x.User.Role == UserRole.Dietitian);
        var total = await query.CountAsync(cancellationToken);
        var items = await query.OrderBy(x => x.DisplayName).ThenBy(x => x.Id).Skip((page - 1) * pageSize).Take(pageSize)
            .Select(x => new DietitianReviewItem(x.Id, x.DisplayName, x.LicenseInfo, x.IsVerified)).ToListAsync(cancellationToken);
        return Ok(new PagedResponse<DietitianReviewItem>(items, total));
    }

    [HttpPost("{dietitianId:guid}/verify")]
    [ProducesResponseType<DietitianStatusResponse>(200)]
    public async Task<IActionResult> Verify(Guid dietitianId, CancellationToken cancellationToken)
    {
        if (HasBody || Request.Query.Count != 0) return BadRequest(ApiErrors.Create(HttpContext, 400));
        try { await antiforgery.ValidateRequestAsync(HttpContext); }
        catch (AntiforgeryValidationException) { return BadRequest(ApiErrors.Create(HttpContext, 400)); }
        if (!WebSessionService.TryIdentity(User, out var adminId, out _, out var role) || role != UserRole.Admin)
            return Forbid(WebSessionAuthentication.Scheme);
        await using var transaction = await database.Database.BeginTransactionAsync(cancellationToken);
        // Hold the actor's security lock through the administrative write.
        await database.Users.FromSqlInterpolated($"SELECT * FROM users WHERE id = {adminId} FOR UPDATE")
            .AsNoTracking().ToListAsync(cancellationToken);
        if (!await sessions.ValidateAsync(User, cancellationToken)) return Unauthorized(ApiErrors.Create(HttpContext, 401));
        var targetUserId = await database.DietitianProfiles.Where(x => x.Id == dietitianId)
            .Select(x => (Guid?)x.UserId).SingleOrDefaultAsync(cancellationToken);
        if (targetUserId is null) return NotFound(ApiErrors.Create(HttpContext, 404));
        var target = await database.Users.FromSqlInterpolated($"SELECT * FROM users WHERE id = {targetUserId.Value} FOR UPDATE")
            .AsNoTracking().SingleOrDefaultAsync(cancellationToken);
        if (target?.Role != UserRole.Dietitian) return NotFound(ApiErrors.Create(HttpContext, 404));
        if (!target.IsEmailVerified) return Conflict(ApiErrors.Create(HttpContext, 409));
        var profile = await database.DietitianProfiles.FromSqlInterpolated($"SELECT * FROM dietitian_profiles WHERE id = {dietitianId} FOR UPDATE")
            .AsNoTracking().SingleAsync(cancellationToken);
        if (!profile.IsVerified)
        {
            await database.DietitianProfiles.Where(x => x.Id == profile.Id)
                .ExecuteUpdateAsync(setters => setters.SetProperty(x => x.IsVerified, true), cancellationToken);
            database.AuditEvents.Add(new AuditEvent(adminId, profile.Id, clock.GetUtcNow()));
            await database.SaveChangesAsync(cancellationToken);
        }
        await transaction.CommitAsync(cancellationToken);
        return Ok(new DietitianStatusResponse(profile.Id, profile.DisplayName, true));
    }
}
