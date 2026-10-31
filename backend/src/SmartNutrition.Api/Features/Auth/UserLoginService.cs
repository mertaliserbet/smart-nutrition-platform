using System.ComponentModel.DataAnnotations;
using System.Security.Cryptography;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using SmartNutrition.Api.Data;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Features.Auth;

public sealed class UserLoginService(AppDbContext database, ILookupNormalizer normalizer,
    IPasswordHasher<User> passwordHasher, LoginPasswordVerifier verifier, RefreshTokenService refreshTokens, TimeProvider clock)
{
    public async Task<LoginUserResponse?> LoginAsync(LoginUserRequest request, CancellationToken cancellationToken = default)
    {
        Validator.ValidateObject(request, new ValidationContext(request), validateAllProperties: true);
        var email = normalizer.NormalizeEmail(request.Email!.Trim())!;
        var user = await database.Users.AsNoTracking().SingleOrDefaultAsync(account => account.Email == email, cancellationToken);
        // Every valid attempt performs Identity password verification, even if the account does not exist.
        var result = verifier.Verify(passwordHasher, user, request.Password!);
        if (user is null || result == PasswordVerificationResult.Failed || !user.IsEmailVerified ||
            user.Role is not (UserRole.Client or UserRole.Dietitian)) return null;

        await using var transaction = await database.Database.BeginTransactionAsync(cancellationToken);
        var locked = await database.Users.FromSqlInterpolated($"SELECT * FROM users WHERE id = {user.Id} FOR UPDATE")
            .AsNoTracking().SingleOrDefaultAsync(cancellationToken);
        if (locked is null || locked.PasswordHash != user.PasswordHash || !locked.IsEmailVerified || locked.Role != user.Role)
            return null;
        if (result == PasswordVerificationResult.SuccessRehashNeeded)
        {
            var previousHash = user.PasswordHash;
            var replacement = passwordHasher.HashPassword(user, request.Password!);
            var now = clock.GetUtcNow();
            var updated = await database.Users.Where(account => account.Id == user.Id &&
                account.PasswordHash == previousHash && account.IsEmailVerified && account.Role == user.Role)
                .ExecuteUpdateAsync(setters => setters.SetProperty(account => account.PasswordHash, replacement)
                    .SetProperty(account => account.UpdatedAt, now), cancellationToken);
            if (updated != 1) return null;
        }
        var response = await refreshTokens.CreateAsync(locked, cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return response;
    }
}

// Only a one-way hash for comparable password work; no synthetic User, DB row or session is created.
public sealed class LoginPasswordVerifier(IOptions<PasswordHasherOptions> options)
{
    private readonly string _dummyHash = new PasswordHasher<User>(options)
        .HashPassword(null!, Convert.ToBase64String(RandomNumberGenerator.GetBytes(32)));

    public PasswordVerificationResult Verify(IPasswordHasher<User> hasher, User? user, string password)
    {
        try { return hasher.VerifyHashedPassword(user!, user?.PasswordHash ?? _dummyHash, password); }
        catch (FormatException) when (user is not null)
        {
            // A corrupt stored hash must not disclose account existence through a different HTTP error.
            hasher.VerifyHashedPassword(null!, _dummyHash, password);
            return PasswordVerificationResult.Failed;
        }
    }
}
