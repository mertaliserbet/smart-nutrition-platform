using System.ComponentModel.DataAnnotations;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using SmartNutrition.Api.Data;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Features.Auth;

public sealed class PasswordResetOptions
{
    public const string SectionName = "Auth:PasswordReset";
    public int ResendCooldownSeconds { get; set; } = 60;
    public int RequestsPerMinute { get; set; } = 5;
    public int ConsumeRequestsPerMinute { get; set; } = 10;
    public int QueueCapacity { get; set; } = 100;
}

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed class PasswordResetRequest : IValidatableObject
{
    [JsonRequired, JsonIgnore(Condition = JsonIgnoreCondition.WhenWriting)] public string? Email { get; init; }
    public IEnumerable<ValidationResult> Validate(ValidationContext context)
    {
        if (string.IsNullOrWhiteSpace(Email) || !RegisterUserRequest.IsValidEmail(Email))
            yield return new("A valid email is required.");
    }
}

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed class ResetPasswordRequest : IValidatableObject
{
    [JsonRequired, JsonIgnore(Condition = JsonIgnoreCondition.WhenWriting)] public string? Token { get; init; }
    [JsonRequired, JsonIgnore(Condition = JsonIgnoreCondition.WhenWriting)] public string? Password { get; init; }
    public IEnumerable<ValidationResult> Validate(ValidationContext context)
    {
        if (Token is null || Password is null) yield return new("Token and password are required.");
    }
}

public sealed class PasswordResetService(AppDbContext database, ILookupNormalizer normalizer,
    IPasswordHasher<User> hasher, IOptions<RegistrationPasswordPolicy> policy,
    IOptions<PasswordResetOptions> options, WebSessionService sessions, IPasswordResetEmailSender sender, TimeProvider clock)
{
    public static readonly TimeSpan TokenLifetime = TimeSpan.FromMinutes(30);

    public async Task SendAsync(string email, CancellationToken cancellationToken = default)
    {
        var normalized = normalizer.NormalizeEmail(email.Trim())!;
        string token;
        await using (var transaction = await database.Database.BeginTransactionAsync(cancellationToken))
        {
            var user = await database.Users.FromSqlInterpolated($"SELECT * FROM users WHERE email = {normalized} FOR UPDATE")
                .AsNoTracking().SingleOrDefaultAsync(cancellationToken);
            var now = clock.GetUtcNow();
            if (user is null || !Eligible(user) ||
                user.PasswordResetLastSentAt > now.AddSeconds(-options.Value.ResendCooldownSeconds)) return;
            token = WebEncoders.Base64UrlEncode(RandomNumberGenerator.GetBytes(32));
            await database.Users.Where(value => value.Id == user.Id).ExecuteUpdateAsync(setters => setters
                .SetProperty(value => value.PasswordResetTokenHash, Hash(token))
                .SetProperty(value => value.PasswordResetExpiresAt, now.Add(TokenLifetime))
                .SetProperty(value => value.PasswordResetLastSentAt, now), cancellationToken);
            await transaction.CommitAsync(cancellationToken);
        }
        // SMTP runs outside the lock/transaction. A delivery failure never rolls back a committed change.
        await sender.SendResetAsync(normalized, token, cancellationToken);
    }

    public async Task<string?> ResetAsync(string? token, string? password, CancellationToken cancellationToken = default)
    {
        if (!ValidToken(token) || password is null || policy.Value.Validate(password).Count != 0) return null;
        var hash = Hash(token!);
        var candidate = await database.Users.AsNoTracking().SingleOrDefaultAsync(
            user => user.PasswordResetTokenHash == hash, cancellationToken);
        if (candidate is null) return null;
        // Expensive password hashing is outside the row lock; eligibility is checked again under lock.
        var replacement = hasher.HashPassword(candidate, password);
        await using var transaction = await database.Database.BeginTransactionAsync(cancellationToken);
        var locked = await database.Users.FromSqlInterpolated($"SELECT * FROM users WHERE id = {candidate.Id} FOR UPDATE")
            .AsNoTracking().SingleOrDefaultAsync(cancellationToken);
        var now = clock.GetUtcNow();
        if (locked is null || !Eligible(locked) || locked.PasswordResetTokenHash != hash ||
            locked.PasswordResetExpiresAt is null || locked.PasswordResetExpiresAt <= now) return null;
        var version = checked(locked.CredentialsVersion + 1);
        await database.Users.Where(user => user.Id == locked.Id).ExecuteUpdateAsync(setters => setters
            .SetProperty(user => user.PasswordHash, replacement)
            .SetProperty(user => user.CredentialsVersion, version)
            .SetProperty(user => user.UpdatedAt, now)
            .SetProperty(user => user.PasswordResetTokenHash, (string?)null)
            .SetProperty(user => user.PasswordResetExpiresAt, (DateTimeOffset?)null), cancellationToken);
        await sessions.RevokeAllAsync(locked.Id, cancellationToken);
        // Revoke every independent login family, including consumed ancestors; keep replay history.
        await database.RefreshTokens.Where(value => value.UserId == locked.Id && value.RevokedAt == null)
            .ExecuteUpdateAsync(setters => setters.SetProperty(value => value.RevokedAt,
                value => now < value.CreatedAt ? value.CreatedAt : now), cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return locked.Email;
    }

    internal static bool ValidToken(string? token) => token is { Length: 43 } &&
        token.All(character => char.IsAsciiLetterOrDigit(character) || character is '-' or '_');
    internal static string Hash(string token) => Convert.ToHexString(
        SHA256.HashData(Encoding.UTF8.GetBytes("password-reset:v1:" + token)));
    private static bool Eligible(User user) => user.IsEmailVerified && user.Role is UserRole.Client or UserRole.Dietitian;
}
