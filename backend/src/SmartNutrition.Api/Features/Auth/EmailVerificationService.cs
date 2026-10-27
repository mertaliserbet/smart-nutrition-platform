using System.Security.Cryptography;
using System.Text;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using SmartNutrition.Api.Data;

namespace SmartNutrition.Api.Features.Auth;

public sealed class EmailVerificationService(
    AppDbContext database,
    ILookupNormalizer normalizer,
    IVerificationEmailSender sender,
    TimeProvider clock,
    IOptions<EmailVerificationOptions> options)
{
    public static readonly TimeSpan TokenLifetime = TimeSpan.FromMinutes(30);

    public async Task SendAsync(string email, CancellationToken cancellationToken = default)
    {
        var normalizedEmail = normalizer.NormalizeEmail(email.Trim())!;
        var now = clock.GetUtcNow();
        var expiresAt = now.Add(TokenLifetime);
        var earliestPreviousSend = now.AddSeconds(-options.Value.ResendCooldownSeconds);
        var token = WebEncoders.Base64UrlEncode(RandomNumberGenerator.GetBytes(32));
        var hash = Hash(token);

        // One atomic update serializes concurrent sends across API instances. Rotation invalidates the old token.
        var issued = await database.Users.Where(user => user.Email == normalizedEmail && !user.IsEmailVerified &&
            (user.EmailVerificationLastSentAt == null || user.EmailVerificationLastSentAt <= earliestPreviousSend))
            .ExecuteUpdateAsync(setters => setters
                .SetProperty(user => user.EmailVerificationTokenHash, hash)
                .SetProperty(user => user.EmailVerificationExpiresAt, expiresAt)
                .SetProperty(user => user.EmailVerificationLastSentAt, now), cancellationToken);

        if (issued == 0) return;
        // Only the SMTP message receives the raw token. The database and all HTTP responses receive no raw token.
        await sender.SendAsync(normalizedEmail, token, cancellationToken);
    }

    public async Task<bool> VerifyAsync(string? token, CancellationToken cancellationToken = default)
    {
        if (token is null || token.Length != 43 || token.Any(character =>
            !char.IsAsciiLetterOrDigit(character) && character is not '-' and not '_')) return false;

        var hash = Hash(token);
        var now = clock.GetUtcNow();
        // Consume and verify in the same SQL statement: only one concurrent request can succeed.
        var consumed = await database.Users.Where(user => !user.IsEmailVerified &&
            user.EmailVerificationTokenHash == hash && user.EmailVerificationExpiresAt > now)
            .ExecuteUpdateAsync(setters => setters
                .SetProperty(user => user.IsEmailVerified, true)
                .SetProperty(user => user.EmailVerificationTokenHash, (string?)null)
                .SetProperty(user => user.EmailVerificationExpiresAt, (DateTimeOffset?)null)
                .SetProperty(user => user.UpdatedAt, now), cancellationToken);
        return consumed == 1;
    }

    private static string Hash(string token) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(token)));
}
