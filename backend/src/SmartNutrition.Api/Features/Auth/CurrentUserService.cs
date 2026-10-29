using System.Security.Claims;
using System.Text.Json.Serialization;
using Microsoft.EntityFrameworkCore;
using SmartNutrition.Api.Data;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Features.Auth;

public sealed class CurrentUserService(AppDbContext database, TimeProvider? clock = null)
{
    public async Task<CurrentUserResponse?> GetAsync(ClaimsPrincipal principal, CancellationToken cancellationToken = default)
    {
        if (principal.Identity?.IsAuthenticated != true) return null;
        var subjects = principal.FindAll("sub").ToArray();
        var roles = principal.FindAll("role").ToArray();
        if (subjects.Length != 1 || !Guid.TryParseExact(subjects[0].Value, "D", out var userId) ||
            userId == Guid.Empty || roles.Length != 1 || roles[0].Value is not ("client" or "dietitian" or "admin")) return null;
        var role = Enum.Parse<UserRole>(roles[0].Value, true);
        if (role == UserRole.Admin)
        {
            var now = (clock ?? TimeProvider.System).GetUtcNow();
            if (principal.Identity.AuthenticationType != WebSessionAuthentication.Scheme ||
                !WebSessionService.TryIdentity(principal, out _, out var sessionId, out _) ||
                !await database.AuthSessions.AnyAsync(session => session.Id == sessionId && session.UserId == userId &&
                    session.IsMfaVerified && session.RevokedAt == null && session.IdleExpiresAt > now &&
                    session.AbsoluteExpiresAt > now, cancellationToken)) return null;
        }

        // Project only the approved fields; optional profile navigation becomes a LEFT JOIN.
        // Recheck the current account, so deleted/restricted accounts and stale roles do not expose profile data.
        return await database.Users.AsNoTracking()
            .Where(user => user.Id == userId && user.IsEmailVerified && user.Role == role)
            .Select(user => new CurrentUserResponse(user.Id,
                user.Role == UserRole.Dietitian
                    ? (user.DietitianProfile == null ? null : user.DietitianProfile.DisplayName)
                    : (user.ClientProfile == null ? null : user.ClientProfile.DisplayName),
                user.Email, user.Role, user.IsEmailVerified))
            .SingleOrDefaultAsync(cancellationToken);
    }
}

// An explicit response whitelist; User/ClientProfile entities are never serialized by /auth/me.
public sealed class CurrentUserResponse(Guid id, string? displayName, string email, UserRole role, bool isEmailVerified)
{
    public Guid Id { get; } = id;
    [JsonIgnore(Condition = JsonIgnoreCondition.Never)]
    public string? DisplayName { get; } = displayName;
    public string Email { get; } = email;
    public UserRole Role { get; } = role;
    public bool IsEmailVerified { get; } = isEmailVerified;
}
