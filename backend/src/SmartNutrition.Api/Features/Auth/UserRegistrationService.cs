using System.ComponentModel.DataAnnotations;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Npgsql;
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
        var errors = ValidateRequest(request);
        if (errors.Count != 0) return errors;

        var email = emailNormalizer.NormalizeEmail(request.Email!.Trim())!;
        // Column collation and its unique index also cover legacy mixed-case addresses and concurrent writes.
        if (await database.Users.AnyAsync(user => user.Email == email, cancellationToken))
            errors.Add(new ValidationResult("Registration cannot use this email address.", ["email"]));
        return errors;
    }

    // Prepares an untracked User, not a persisted registration or API response.
    public async Task<User> PrepareAsync(RegisterUserRequest request, CancellationToken cancellationToken = default)
    {
        var errors = await ValidateAsync(request, cancellationToken);
        if (errors.Count != 0)
            throw new ValidationException("The registration request could not be validated.");

        return CreateUser(request);
    }

    public async Task<User> RegisterAsync(RegisterUserRequest request, CancellationToken cancellationToken = default)
    {
        if (ValidateRequest(request).Count != 0)
            throw new ValidationException("The registration request could not be validated.");

        var email = emailNormalizer.NormalizeEmail(request.Email!.Trim())!;
        if (await database.Users.AnyAsync(user => user.Email == email, cancellationToken))
            throw new RegistrationEmailConflictException();

        var user = CreateUser(request);
        _ = new ClientProfile(Guid.NewGuid(), user, request.DisplayName!);
        database.Users.Add(user);
        try
        {
            // EF commits both inserts in one SaveChanges transaction, or rolls both back.
            await database.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateException exception) when (exception.InnerException is PostgresException
        {
            SqlState: PostgresErrorCodes.UniqueViolation, ConstraintName: "ux_users_email"
        })
        {
            // The precheck cannot prevent a concurrent registration. Never expose the DB exception.
            throw new RegistrationEmailConflictException();
        }
        return user;
    }

    private List<ValidationResult> ValidateRequest(RegisterUserRequest request)
    {
        ArgumentNullException.ThrowIfNull(request);
        var errors = new List<ValidationResult>();
        if (Validator.TryValidateObject(request, new ValidationContext(request), errors, validateAllProperties: true))
            errors.AddRange(passwordPolicy.Value.Validate(request.Password!));
        return errors;
    }

    private User CreateUser(RegisterUserRequest request) =>
        new(Guid.NewGuid(), emailNormalizer.NormalizeEmail(request.Email!.Trim())!,
            UserRole.Client, request.Password!, DateTimeOffset.UtcNow, passwordHasher);
}

internal sealed class RegistrationEmailConflictException : Exception
{
    public RegistrationEmailConflictException() : base("Registration conflicts with an existing account.") { }
}
