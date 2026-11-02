using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using SmartNutrition.Api.Data;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Features.Relationships;

public sealed record ProfileIdentity(Guid UserId, UserRole Role, Guid? ClientId, Guid? DietitianId, bool IsDietitianVerified)
{
    // Role is this request's profile context; the signed account role remains unchanged.
    public UserRole AccountRole { get; init; } = Role;
}
public sealed class RelationshipAccessService(AppDbContext database)
{
    public async Task<ProfileIdentity> RequireAsync(ClaimsPrincipal principal, CancellationToken cancellationToken,
        HttpRequest? request = null, bool asDietitian = false)
    {
        if (!Guid.TryParse(principal.FindFirst("sub")?.Value, out var id) || principal.FindFirst("role")?.Value is not ("client" or "dietitian"))
            throw new ResourceOperationException(401);
        var role = Enum.Parse<UserRole>(principal.FindFirst("role")!.Value, true);
        var actor = await database.Users.AsNoTracking().Where(x => x.Id == id && x.Role == role && x.IsEmailVerified)
            .Select(x => new ProfileIdentity(x.Id, x.Role, x.ClientProfile == null ? null : (Guid?)x.ClientProfile.Id,
                x.DietitianProfile == null ? null : (Guid?)x.DietitianProfile.Id, x.DietitianProfile != null && x.DietitianProfile.IsVerified))
            .SingleOrDefaultAsync(cancellationToken) ?? throw new ResourceOperationException(401);
        string? context = null;
        if (request?.Headers.TryGetValue("X-Profile-Context", out var values) == true)
        {
            if (values.Count != 1 || values[0] is not ("client" or "dietitian")) throw new ResourceOperationException(400);
            context = values[0];
        }
        if (asDietitian || context == "dietitian")
        {
            if (actor.DietitianId is null || !actor.IsDietitianVerified) throw new ResourceOperationException(403);
            return actor with { Role = UserRole.Dietitian };
        }
        if (context == "client")
        {
            if (actor.ClientId is null) throw new ResourceOperationException(403);
            return actor with { Role = UserRole.Client };
        }
        return actor;
    }
    internal async Task LockActorAsync(ProfileIdentity actor, CancellationToken cancellationToken)
    {
        var current = await database.Users.FromSqlInterpolated($"SELECT * FROM users WHERE id = {actor.UserId} FOR UPDATE").AsNoTracking().SingleOrDefaultAsync(cancellationToken);
        if (current is null || current.Role != actor.AccountRole || !current.IsEmailVerified) throw new ResourceOperationException(401);
    }
    internal async Task LockClientAsync(Guid clientId, CancellationToken cancellationToken) =>
        await database.ClientProfiles.FromSqlInterpolated($"SELECT * FROM client_profiles WHERE id = {clientId} FOR UPDATE").AsNoTracking().SingleAsync(cancellationToken);

    public Task<bool> CanAccessNutritionPlansAsync(ProfileIdentity actor, Guid clientId, CancellationToken cancellationToken = default)
    {
        if (actor.Role == UserRole.Client) return Task.FromResult(actor.ClientId == clientId);
        if (actor.Role != UserRole.Dietitian || !actor.IsDietitianVerified || actor.DietitianId is null) return Task.FromResult(false);
        return database.DietitianClientRelationships.AnyAsync(relationship => relationship.ClientId == clientId &&
            relationship.DietitianId == actor.DietitianId && relationship.Status == RelationshipStatus.Active &&
            database.DietitianProfiles.Any(profile => profile.Id == relationship.DietitianId && profile.IsVerified && profile.User.IsEmailVerified && profile.User.Role != UserRole.Admin) &&
            database.DataSharingPermissions.Any(permission => permission.RelationshipId == relationship.Id && permission.Category == "nutrition_plans" && permission.IsGranted), cancellationToken);
    }
}
