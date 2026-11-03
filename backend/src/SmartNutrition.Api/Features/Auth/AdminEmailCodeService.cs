using System.Globalization;
using System.Net;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using SmartNutrition.Api.Data;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Features.Auth;

public sealed class AdminEmailCodeOptions
{
    public const string SectionName = "Auth:AdminEmailCode";
    public bool Enabled { get; set; }
}

public interface IAdminEmailCodeSender
{
    Task SendAdminCodeAsync(string recipient, string code, CancellationToken cancellationToken);
}

// Development-only, process-local challenges. Restarting the API invalidates them.
// Never persist codes or alter the existing TOTP enrollment/recovery codes.
public sealed class AdminEmailCodeStore(IHostEnvironment environment, IOptions<AdminEmailCodeOptions> settings,
    IOptions<SmtpOptions> smtp)
{
    internal const string DevelopmentClaim = "developmentAdminEmailCode";
    private readonly object _sync = new();
    private readonly Dictionary<Guid, Entry> _entries = [];

    public bool Enabled => environment.IsDevelopment() && settings.Value.Enabled && smtp.Value.Port == 1025 &&
        (string.Equals(smtp.Value.Host, "localhost", StringComparison.OrdinalIgnoreCase) ||
         IPAddress.TryParse(smtp.Value.Host, out var address) && IPAddress.IsLoopback(address));

    internal bool AllowsPrincipal(ClaimsPrincipal principal) =>
        !principal.HasClaim(claim => claim.Type == DevelopmentClaim) || Enabled;

    internal (string Code, object Ticket)? Issue(User user, DateTimeOffset now)
    {
        if (!Enabled || user.Role != UserRole.Admin || !user.IsEmailVerified || user.TotpSecretProtected is null) return null;
        lock (_sync)
        {
            if (_entries.TryGetValue(user.Id, out var current) && current.SentAt.AddSeconds(60) > now) return null;
            var code = RandomNumberGenerator.GetInt32(1_000_000).ToString("D6", CultureInfo.InvariantCulture);
            var salt = RandomNumberGenerator.GetBytes(32);
            var entry = new Entry(Hash(salt, code), salt, now, user.PasswordHash, user.CredentialsVersion, user.TotpSecretProtected);
            _entries[user.Id] = entry;
            return (code, entry);
        }
    }

    internal void Delivered(Guid userId, object ticket, bool success)
    {
        lock (_sync)
        {
            if (!_entries.TryGetValue(userId, out var entry) || !ReferenceEquals(entry, ticket)) return;
            if (success) entry.Delivered = true;
            else _entries.Remove(userId);
        }
    }

    internal bool TryConsume(User user, string code, DateTimeOffset now)
    {
        if (!Enabled) return false;
        code = code.Trim();
        if (code.Length != 6 || !code.All(char.IsAsciiDigit)) return false;
        lock (_sync)
        {
            if (!_entries.TryGetValue(user.Id, out var entry) || !entry.Delivered) return false;
            if (entry.SentAt.AddMinutes(5) <= now || entry.PasswordHash != user.PasswordHash ||
                entry.CredentialsVersion != user.CredentialsVersion || entry.MfaEnrollment != user.TotpSecretProtected ||
                entry.Used || entry.Attempts >= 5) return false;
            entry.Attempts++;
            if (!CryptographicOperations.FixedTimeEquals(entry.Hash, Hash(entry.Salt, code))) return false;
            // Fail closed even if the subsequent DB transaction fails. No automatic login retry.
            entry.Used = true;
            return true;
        }
    }

    private static byte[] Hash(byte[] salt, string code) => SHA256.HashData([.. salt, .. Encoding.ASCII.GetBytes(code)]);
    private sealed class Entry(byte[] hash, byte[] salt, DateTimeOffset sentAt, string passwordHash, long credentialsVersion, string mfaEnrollment)
    {
        public byte[] Hash { get; } = hash;
        public byte[] Salt { get; } = salt;
        public DateTimeOffset SentAt { get; } = sentAt;
        public string PasswordHash { get; } = passwordHash;
        public long CredentialsVersion { get; } = credentialsVersion;
        public string MfaEnrollment { get; } = mfaEnrollment;
        public int Attempts { get; set; }
        public bool Delivered { get; set; }
        public bool Used { get; set; }
    }
}

public sealed class AdminEmailCodeService(AppDbContext database, ILookupNormalizer normalizer,
    IPasswordHasher<User> hasher, LoginPasswordVerifier verifier, AdminEmailCodeStore store,
    IAdminEmailCodeSender sender, TimeProvider clock)
{
    public async Task RequestAsync(LoginUserRequest request, CancellationToken cancellationToken)
    {
        var email = normalizer.NormalizeEmail(request.Email!.Trim());
        var user = await database.Users.AsNoTracking().SingleOrDefaultAsync(x => x.Email == email, cancellationToken);
        var verified = verifier.Verify(hasher, user, request.Password!);
        if (user is null || verified == PasswordVerificationResult.Failed) return;
        var challenge = store.Issue(user, clock.GetUtcNow());
        if (challenge is null) return;
        try
        {
            await sender.SendAdminCodeAsync(user.Email, challenge.Value.Code, cancellationToken);
            store.Delivered(user.Id, challenge.Value.Ticket, true);
        }
        catch (Exception) when (!cancellationToken.IsCancellationRequested)
        {
            // Match the generic 202 without leaking SMTP errors, account existence or code.
            store.Delivered(user.Id, challenge.Value.Ticket, false);
        }
    }
}
