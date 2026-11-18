using System.Data;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.ModelBinding;
using Microsoft.EntityFrameworkCore;
using SmartNutrition.Api.Data;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Features.Dietitians;
using SmartNutrition.Api.Features.MealLogs;
using SmartNutrition.Api.Features.Relationships;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Features.WaterLogs;

[ApiController, Route("api/v1/dietitian/clients/{clientId}/water-logs")]
[Authorize(AuthenticationSchemes = WebSessionAuthentication.AccountScheme, Roles = "client,dietitian")]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public sealed class DietitianWaterLogsController(AppDbContext database, RelationshipAccessService access, WaterLogService logs) : ControllerBase
{
    private void Query(params string[] keys)
    {
        if (HttpContext.Features.Get<IHttpRequestBodyDetectionFeature>()?.CanHaveBody == true ||
            Request.Query.Any(x => !keys.Contains(x.Key) || x.Value.Count != 1)) throw new ResourceOperationException(400);
    }
    private static void Page(int page, int size)
    {
        if (page < 1 || size is < 1 or > 100 || (long)(page - 1) * size > int.MaxValue) throw new ResourceOperationException(400);
    }
    private (DateTimeOffset? From, DateTimeOffset? To) Range(string? from, string? to)
    {
        DateTimeOffset? start = null, end = null;
        if (Request.Query.ContainsKey("from"))
        {
            if (!MealLogInstantJsonConverter.TryParse(from, out var value)) throw new ResourceOperationException(400);
            start = value;
        }
        if (Request.Query.ContainsKey("to"))
        {
            if (!MealLogInstantJsonConverter.TryParse(to, out var value)) throw new ResourceOperationException(400);
            end = value;
        }
        if (start is not null && end is not null && start >= end) throw new ResourceOperationException(400);
        return (start, end);
    }
    private async Task AuthorizeClient(Guid clientId, CancellationToken token)
    {
        // This runs inside the same RepeatableRead transaction as rows/count/totals.
        var actor = await access.RequireAsync(User, token, Request, asDietitian: true);
        var relationship = await database.DietitianClientRelationships.AsNoTracking()
            .Where(x => x.ClientId == clientId && x.DietitianId == actor.DietitianId && x.Status == RelationshipStatus.Active)
            .Select(x => new { Granted = database.DataSharingPermissions.Any(p => p.RelationshipId == x.Id && p.Category == "water_logs" && p.IsGranted) })
            .SingleOrDefaultAsync(token) ?? throw new ResourceOperationException(404);
        if (!relationship.Granted) throw new ResourceOperationException(403);
    }
    [HttpGet, ProducesResponseType<PagedResponse<WaterLogResponse>>(200)]
    public async Task<IActionResult> List(Guid clientId, [FromQuery, BindRequired] int page, [FromQuery, BindRequired] int pageSize,
        [FromQuery] string? from, [FromQuery] string? to, CancellationToken token)
    {
        Query("page", "pageSize", "from", "to"); Page(page, pageSize); var range = Range(from, to);
        await using var tx = await database.Database.BeginTransactionAsync(IsolationLevel.RepeatableRead, token);
        await AuthorizeClient(clientId, token);
        var result = await logs.ReadListAsync(clientId, page, pageSize, range.From, range.To, token);
        await tx.CommitAsync(token); return Ok(result);
    }
    [HttpGet("daily-total"), ProducesResponseType<WaterLogDailyTotalResponse>(200)]
    public async Task<IActionResult> Daily(Guid clientId, [FromQuery] string? from, [FromQuery] string? to, CancellationToken token)
    {
        Query("from", "to"); var range = Range(from, to);
        if (range.From is not { } start || range.To is not { } end) throw new ResourceOperationException(400);
        WaterLogCalendar.Single(start, end);
        await using var tx = await database.Database.BeginTransactionAsync(IsolationLevel.RepeatableRead, token);
        await AuthorizeClient(clientId, token);
        var result = await logs.DailyTotalAsync(clientId, start, end, token);
        await tx.CommitAsync(token); return Ok(result);
    }
    [HttpGet("daily-history"), ProducesResponseType<PagedResponse<WaterLogDailyTotalResponse>>(200)]
    public async Task<IActionResult> History(Guid clientId, [FromQuery, BindRequired] int page, [FromQuery, BindRequired] int pageSize,
        [FromQuery] string? from, [FromQuery] string? to, [FromQuery] string? timeZone, CancellationToken token)
    {
        Query("page", "pageSize", "from", "to", "timeZone"); Page(page, pageSize); var range = Range(from, to);
        if (range.From is not { } start || range.To is not { } end) throw new ResourceOperationException(400);
        var days = WaterLogCalendar.Days(start, end, timeZone);
        await using var tx = await database.Database.BeginTransactionAsync(IsolationLevel.RepeatableRead, token);
        await AuthorizeClient(clientId, token);
        List<WaterLogDailyTotalResponse> totals = [];
        foreach (var day in days.Skip((page - 1) * pageSize).Take(pageSize))
            totals.Add(await logs.DailyTotalAsync(clientId, day.From, day.To, token));
        await tx.CommitAsync(token);
        return Ok(new PagedResponse<WaterLogDailyTotalResponse>(totals, days.Length));
    }
}
