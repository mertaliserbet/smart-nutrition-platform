using System.Security.Cryptography;
using System.Text;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using SmartNutrition.Api.Data;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Features.Auth;

public sealed class RefreshTokenService(AppDbContext database, JwtAccessTokenService accessTokens,
    IOptions<RefreshTokenOptions> settings, TimeProvider clock)
{
    // Login holds the same User lock as refresh/logout and web security mutations.
    internal Task<LoginUserResponse> CreateAsync(User user, CancellationToken cancellationToken)
    {
        if (database.Database.CurrentTransaction is null)
            throw new InvalidOperationException("A login transaction is required.");
        return IssueAsync(user, Guid.NewGuid(), UtcNow().AddDays(settings.Value.LifetimeDays), cancellationToken);
    }

    public async Task<LoginUserResponse?> RefreshAsync(string? rawToken, CancellationToken cancellationToken = default)
    {
        var candidate = await FindAsync(rawToken, cancellationToken);
        if (candidate is null) return null;
        await using var transaction = await database.Database.BeginTransactionAsync(cancellationToken);
        // Consistent lock order: User first, then this family's rotation rows.
        var user = await LockUserAsync(candidate.UserId, cancellationToken);
        var token = await database.RefreshTokens.AsNoTracking().SingleOrDefaultAsync(
            value => value.Id == candidate.Id, cancellationToken);
        var now = UtcNow();
        if (token is null) return null;
        if (token.ConsumedAt is not null || token.RevokedAt is not null || token.ExpiresAt <= now ||
            user is null || !user.IsEmailVerified || user.Role != token.Role ||
            user.Role is not (UserRole.Client or UserRole.Dietitian))
        {
            // Retain consumed hashes until absolute family expiry to detect reuse
            // of any ancestor, even after multiple successful rotations.
            await RevokeAsync(token.FamilyId, now, cancellationToken);
            await transaction.CommitAsync(cancellationToken);
            return null;
        }
        var consumed = await database.RefreshTokens.Where(value => value.Id == token.Id &&
            value.ConsumedAt == null && value.RevokedAt == null && value.ExpiresAt > now)
            .ExecuteUpdateAsync(setters => setters.SetProperty(value => value.ConsumedAt, now), cancellationToken);
        if (consumed != 1)
        {
            await RevokeAsync(token.FamilyId, now, cancellationToken);
            await transaction.CommitAsync(cancellationToken);
            return null;
        }
        var response = await IssueAsync(user, token.FamilyId, token.ExpiresAt, cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return response;
    }

    public async Task LogoutAsync(string? rawToken, CancellationToken cancellationToken = default)
    {
        var candidate = await FindAsync(rawToken, cancellationToken);
        if (candidate is null) return;
        await using var transaction = await database.Database.BeginTransactionAsync(cancellationToken);
        await LockUserAsync(candidate.UserId, cancellationToken);
        // A known consumed token also revokes its family (e.g. a lost rotation response).
        await RevokeAsync(candidate.FamilyId, UtcNow(), cancellationToken);
        await transaction.CommitAsync(cancellationToken);
    }

    private Task<User?> LockUserAsync(Guid userId, CancellationToken cancellationToken) =>
        database.Users.FromSqlInterpolated($"SELECT * FROM users WHERE id = {userId} FOR UPDATE")
            .AsNoTracking().SingleOrDefaultAsync(cancellationToken);

    private async Task<LoginUserResponse> IssueAsync(User user, Guid familyId, DateTimeOffset expiresAt,
        CancellationToken cancellationToken)
    {
        var access = accessTokens.Issue(user); // Existing 15-minute JWT, unchanged claims/MFA restrictions.
        var rawToken = WebEncoders.Base64UrlEncode(RandomNumberGenerator.GetBytes(32));
        database.RefreshTokens.Add(new RefreshToken(user.Id, user.Role, familyId, Hash(rawToken), UtcNow(), expiresAt));
        await database.SaveChangesAsync(cancellationToken);
        return new LoginUserResponse(access.AccessToken, access.ExpiresAt, rawToken, expiresAt);
    }

    private Task<int> RevokeAsync(Guid familyId, DateTimeOffset now, CancellationToken cancellationToken) =>
        database.RefreshTokens.Where(token => token.FamilyId == familyId && token.RevokedAt == null)
            .ExecuteUpdateAsync(setters => setters.SetProperty(token => token.RevokedAt, now), cancellationToken);

    private Task<RefreshToken?> FindAsync(string? rawToken, CancellationToken cancellationToken)
    {
        if (rawToken is null || rawToken.Length != 43 || rawToken.Any(character =>
            !char.IsAsciiLetterOrDigit(character) && character is not '-' and not '_'))
            return Task.FromResult<RefreshToken?>(null);
        var hash = Hash(rawToken);
        return database.RefreshTokens.AsNoTracking().SingleOrDefaultAsync(token => token.TokenHash == hash, cancellationToken);
    }

    private static string Hash(string token) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(token)));

    // PostgreSQL timestamptz stores microseconds; return that exact same instant
    // on initial issue and every rotation instead of losing 100ns on DB roundtrip.
    private DateTimeOffset UtcNow() => new(clock.GetUtcNow().UtcTicks / 10 * 10, TimeSpan.Zero);
}
