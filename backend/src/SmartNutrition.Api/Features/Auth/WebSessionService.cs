using System.ComponentModel.DataAnnotations;
using System.Security.Claims;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using SmartNutrition.Api.Data;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Features.Auth;

public sealed class WebSessionService(AppDbContext database, ILookupNormalizer normalizer,
    IPasswordHasher<User> hasher, LoginPasswordVerifier verifier, TimeProvider clock, CurrentUserService currentUser)
{
    public async Task<(AuthSession Session, ClaimsPrincipal Principal, CurrentUserResponse Account)?> LoginAsync(
        LoginUserRequest request, CancellationToken cancellationToken)
    {
        Validator.ValidateObject(request, new ValidationContext(request), true);
        var email = normalizer.NormalizeEmail(request.Email!.Trim())!;
        var candidate = await database.Users.AsNoTracking().SingleOrDefaultAsync(user => user.Email == email, cancellationToken);
        var result = verifier.Verify(hasher, candidate, request.Password!);
        if (candidate is null || result == PasswordVerificationResult.Failed || !candidate.IsEmailVerified ||
            candidate.Role is not (UserRole.Client or UserRole.Dietitian)) return null;

        await using var transaction = await database.Database.BeginTransactionAsync(cancellationToken);
        // Security mutations acquire this same lock before changing User and revoking sessions.
        var locked = await database.Users.FromSqlInterpolated($"SELECT * FROM users WHERE id = {candidate.Id} FOR UPDATE")
            .AsNoTracking().SingleOrDefaultAsync(cancellationToken);
        if (locked is null || locked.PasswordHash != candidate.PasswordHash || !locked.IsEmailVerified || locked.Role != candidate.Role)
            return null;
        if (result == PasswordVerificationResult.SuccessRehashNeeded)
        {
            var replacement = hasher.HashPassword(locked, request.Password!);
            await database.Users.Where(user => user.Id == locked.Id).ExecuteUpdateAsync(setters => setters
                .SetProperty(user => user.PasswordHash, replacement).SetProperty(user => user.UpdatedAt, clock.GetUtcNow()), cancellationToken);
        }
        var session = new AuthSession(locked.Id, clock.GetUtcNow());
        var principal = CreatePrincipal(session, locked.Role);
        var account = await currentUser.GetAsync(principal, cancellationToken);
        if (account is null) return null;
        database.AuthSessions.Add(session);
        await database.SaveChangesAsync(cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return (session, principal, account);
    }

    public static ClaimsPrincipal CreatePrincipal(AuthSession session, UserRole role) => new(new ClaimsIdentity(
        [new Claim("sub", session.UserId.ToString("D")), new Claim("sid", session.Id.ToString("D")),
         new Claim("role", role.ToString().ToLowerInvariant())], WebSessionAuthentication.Scheme, "sub", "role"));

    public static bool TryIdentity(ClaimsPrincipal principal, out Guid userId, out Guid sessionId, out UserRole role)
    {
        userId = sessionId = Guid.Empty;
        role = default;
        var subjects = principal.FindAll("sub").ToArray();
        var sessions = principal.FindAll("sid").ToArray();
        var roles = principal.FindAll("role").ToArray();
        if (principal.Identity?.IsAuthenticated != true || subjects.Length != 1 || sessions.Length != 1 || roles.Length != 1 ||
            !Guid.TryParseExact(subjects[0].Value, "D", out userId) || userId == Guid.Empty ||
            !Guid.TryParseExact(sessions[0].Value, "D", out sessionId) || sessionId == Guid.Empty ||
            roles[0].Value is not ("client" or "dietitian")) return false;
        role = roles[0].Value == "client" ? UserRole.Client : UserRole.Dietitian;
        return true;
    }

    public async Task<bool> ValidateAsync(ClaimsPrincipal principal, CancellationToken cancellationToken)
    {
        if (!TryIdentity(principal, out var userId, out var sessionId, out var role)) return false;
        var now = clock.GetUtcNow();
        return await database.AuthSessions.AsNoTracking().AnyAsync(session => session.Id == sessionId && session.UserId == userId &&
            session.RevokedAt == null && session.IdleExpiresAt > now && session.AbsoluteExpiresAt > now &&
            database.Users.Any(user => user.Id == userId && user.IsEmailVerified && user.Role == role), cancellationToken);
    }

    // Called only after an authorized account read succeeds; authentication/CSRF/probes never extend idle time.
    public async Task<bool> TouchAsync(ClaimsPrincipal principal, CancellationToken cancellationToken)
    {
        if (!TryIdentity(principal, out var userId, out var sessionId, out var role)) return false;
        var now = clock.GetUtcNow();
        var idle = now.AddMinutes(30);
        return await database.AuthSessions.Where(session => session.Id == sessionId && session.UserId == userId && session.RevokedAt == null &&
            session.IdleExpiresAt > now && session.AbsoluteExpiresAt > now &&
            database.Users.Any(user => user.Id == userId && user.IsEmailVerified && user.Role == role))
            .ExecuteUpdateAsync(setters => setters
                .SetProperty(session => session.LastSeenAt, session => session.LastSeenAt > now ? session.LastSeenAt : now)
                .SetProperty(session => session.IdleExpiresAt, session => session.IdleExpiresAt > idle ? session.IdleExpiresAt :
                    idle < session.AbsoluteExpiresAt ? idle : session.AbsoluteExpiresAt), cancellationToken) == 1;
    }

    public async Task RevokeAsync(ClaimsPrincipal principal, CancellationToken cancellationToken)
    {
        if (!TryIdentity(principal, out var userId, out var sessionId, out _)) return;
        var now = clock.GetUtcNow();
        await database.AuthSessions.Where(session => session.Id == sessionId && session.UserId == userId && session.RevokedAt == null)
            .ExecuteUpdateAsync(setters => setters.SetProperty(session => session.RevokedAt,
                session => now < session.CreatedAt ? session.CreatedAt : now), cancellationToken);
    }

    // Future password/role/verification writers MUST use one transaction for this call and their User update.
    public async Task RevokeAllAsync(Guid userId, CancellationToken cancellationToken)
    {
        if (database.Database.CurrentTransaction is null) throw new InvalidOperationException("A security change requires a transaction.");
        await database.Users.FromSqlInterpolated($"SELECT * FROM users WHERE id = {userId} FOR UPDATE")
            .AsNoTracking().ToListAsync(cancellationToken);
        var now = clock.GetUtcNow();
        await database.AuthSessions.Where(session => session.UserId == userId && session.RevokedAt == null)
            .ExecuteUpdateAsync(setters => setters.SetProperty(session => session.RevokedAt,
                session => now < session.CreatedAt ? session.CreatedAt : now), cancellationToken);
    }
}
