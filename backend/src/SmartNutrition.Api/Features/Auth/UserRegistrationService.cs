using System.ComponentModel.DataAnnotations;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using SmartNutrition.Api.Data;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Features.Auth;

public sealed class UserRegistrationService(
    AppDbContext database,
    ILookupNormalizer emailNormalizer,
    IPasswordHasher<User> passwordHasher,
    IOptions<RegistrationPasswordPolicy> passwordPolicy)
{
    public async Task<IReadOnlyList<ValidationResult>> ValidateAsync(
        RegisterUserRequest request, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(request);
        var errors = new List<ValidationResult>();
        if (!Validator.TryValidateObject(request, new ValidationContext(request), errors, validateAllProperties: true))
            return errors;

        errors.AddRange(passwordPolicy.Value.Validate(request.Password!));
        if (errors.Count != 0) return errors;

        var email = emailNormalizer.NormalizeEmail(request.Email!.Trim())!;
        // Column collation and its unique index also cover legacy mixed-case addresses and concurrent writes.
        if (await database.Users.AnyAsync(user => user.Email == email, cancellationToken))
            errors.Add(new ValidationResult("Registration cannot use this email address.", ["email"]));
        return errors;
    }

    // Prepares an untracked User, not a persisted registration or API response.
    // Profile creation/save and unique-conflict handling belong to the future approved registration flow.
    public async Task<User> PrepareAsync(RegisterUserRequest request, CancellationToken cancellationToken = default)
    {
        var errors = await ValidateAsync(request, cancellationToken);
        if (errors.Count != 0)
            throw new ValidationException("The registration request could not be validated.");

        return new User(Guid.NewGuid(), emailNormalizer.NormalizeEmail(request.Email!.Trim())!,
            UserRole.Client, request.Password!, DateTimeOffset.UtcNow, passwordHasher);
    }
}
