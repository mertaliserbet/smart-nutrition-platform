using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.ModelBinding;
using Microsoft.EntityFrameworkCore;
using SmartNutrition.Api.Data;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Features.Dietitians;
using SmartNutrition.Api.Infrastructure;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Features.Relationships;

public sealed record ClientListItem(Guid Id, string DisplayName);
public sealed record ClientDashboardResponse(Guid ClientId, string DisplayName);

[ApiController, Route("api/v1/dietitian/clients")]
[Authorize(AuthenticationSchemes = WebSessionAuthentication.AccountScheme, Roles = "dietitian")]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public sealed class DietitianClientsController(AppDbContext database, RelationshipAccessService access) : ControllerBase
{
    private bool HasBody => HttpContext.Features.Get<IHttpRequestBodyDetectionFeature>()?.CanHaveBody == true;
    private async Task<ProfileIdentity> Actor(CancellationToken token)
    {
        var actor = await access.RequireAsync(User, token);
        if (actor.DietitianId is null || !actor.IsDietitianVerified) throw new ResourceOperationException(403);
        return actor;
    }
    private IQueryable<ClientProfile> Clients(Guid dietitianId) => database.ClientProfiles.AsNoTracking().Where(client =>
        client.User.IsEmailVerified && client.User.Role == UserRole.Client && database.DietitianClientRelationships.Any(relationship =>
            relationship.ClientId == client.Id && relationship.DietitianId == dietitianId && relationship.Status == RelationshipStatus.Active));

    [HttpGet, ProducesResponseType<PagedResponse<ClientListItem>>(200)]
    public async Task<IActionResult> List([FromQuery, BindRequired] int page, [FromQuery, BindRequired] int pageSize,
        [FromQuery] string? query, [FromQuery] string? sortOrder, CancellationToken token)
    {
        if (!DietitiansController.ValidPage(page, pageSize) || HasBody || sortOrder is not (null or "asc" or "desc") ||
            Request.Query.Keys.Any(x => x is not ("page" or "pageSize" or "query" or "sortOrder"))) return BadRequest(ApiErrors.Create(HttpContext, 400));
        var actor = await Actor(token); var clients = Clients(actor.DietitianId!.Value);
        if (!string.IsNullOrWhiteSpace(query))
        {
            var pattern = "%" + query.Trim().Replace("\\", "\\\\").Replace("%", "\\%").Replace("_", "\\_") + "%";
            clients = clients.Where(x => EF.Functions.ILike(x.DisplayName, pattern, "\\"));
        }
        var total = await clients.CountAsync(token);
        var ordered = sortOrder == "desc" ? clients.OrderByDescending(x => x.DisplayName).ThenBy(x => x.Id) : clients.OrderBy(x => x.DisplayName).ThenBy(x => x.Id);
        return Ok(new PagedResponse<ClientListItem>(await ordered.Skip((page - 1) * pageSize).Take(pageSize).Select(x => new ClientListItem(x.Id, x.DisplayName)).ToListAsync(token), total));
    }
    [HttpGet("{clientId:guid}/dashboard"), ProducesResponseType<ClientDashboardResponse>(200)]
    public async Task<IActionResult> Dashboard(Guid clientId, CancellationToken token)
    {
        if (HasBody || Request.Query.Count != 0) return BadRequest(ApiErrors.Create(HttpContext, 400));
        var actor = await Actor(token);
        return Ok(await Clients(actor.DietitianId!.Value).Where(x => x.Id == clientId).Select(x => new ClientDashboardResponse(x.Id, x.DisplayName)).SingleOrDefaultAsync(token)
            ?? throw new ResourceOperationException(404));
    }
}
