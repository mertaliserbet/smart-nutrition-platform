using System.ComponentModel.DataAnnotations;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Npgsql;
using SmartNutrition.Api.Data;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Models;
using SmartNutrition.Api.Features.Relationships;

namespace SmartNutrition.Api.Features.Dietitians;

public sealed class DietitianApplicationRequest : IValidatableObject
{
    [JsonRequired, JsonIgnore(Condition = JsonIgnoreCondition.WhenWriting)] public string? Email { get; init; }
    [JsonRequired, JsonIgnore(Condition = JsonIgnoreCondition.WhenWriting)] public string? Password { get; init; }
    [JsonRequired, JsonIgnore(Condition = JsonIgnoreCondition.WhenWriting)] public string? DisplayName { get; init; }
    [JsonRequired, JsonIgnore(Condition = JsonIgnoreCondition.WhenWriting)] public string? LicenseInfo { get; init; }
    public IEnumerable<ValidationResult> Validate(ValidationContext context)
    {
        if (string.IsNullOrWhiteSpace(Email) || !RegisterUserRequest.IsValidEmail(Email))
            yield return new("A valid email is required.");
        if (string.IsNullOrEmpty(Password)) yield return new("Password is required.");
        if (string.IsNullOrWhiteSpace(DisplayName)) yield return new("A name is required.");
        if (string.IsNullOrWhiteSpace(LicenseInfo)) yield return new("A professional description is required.");
    }
}

public sealed class DietitianApplicationOptions
{
    public int RequestsPerMinute { get; set; } = 5;
}

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed class ExistingDietitianApplicationRequest : IValidatableObject
{
    [JsonRequired, JsonIgnore(Condition = JsonIgnoreCondition.WhenWriting)] public string? DisplayName { get; init; }
    [JsonRequired, JsonIgnore(Condition = JsonIgnoreCondition.WhenWriting)] public string? LicenseInfo { get; init; }
    public IEnumerable<ValidationResult> Validate(ValidationContext context)
    {
        if (DisplayName is null || LicenseInfo is null) yield return new("Application fields are required.");
    }
}

public sealed class DietitianApplicationService(AppDbContext database, ILookupNormalizer normalizer,
    IPasswordHasher<User> hasher, IOptions<RegistrationPasswordPolicy> policy, TimeProvider clock)
{
    public async Task<DietitianStatusResponse> ApplyExistingAsync(Guid userId, ExistingDietitianApplicationRequest request,
        System.Security.Claims.ClaimsPrincipal principal, WebSessionService sessions, CancellationToken token)
    {
        if (!DietitianProfile.ValidText(request.DisplayName, 120) || !DietitianProfile.ValidText(request.LicenseInfo, 2000))
            throw new ResourceOperationException(422);
        await using var transaction = await database.Database.BeginTransactionAsync(token);
        var user = await database.Users.FromSqlInterpolated($"SELECT * FROM users WHERE id = {userId} FOR UPDATE")
            .SingleOrDefaultAsync(token);
        if (user is null || !user.IsEmailVerified || !await sessions.ValidateAsync(principal, token))
            throw new ResourceOperationException(401);
        if (user.Role is not (UserRole.Client or UserRole.Dietitian)) throw new ResourceOperationException(403);
        if (await database.DietitianProfiles.AnyAsync(x => x.UserId == userId, token)) throw new ResourceOperationException(409);
        if (user.Role != UserRole.Client || !await database.ClientProfiles.AnyAsync(x => x.UserId == userId, token))
            throw new ResourceOperationException(403);
        var profile = new DietitianProfile(user, request.DisplayName!, request.LicenseInfo!);
        await database.SaveChangesAsync(token);
        await transaction.CommitAsync(token);
        return new(profile.Id, profile.DisplayName, profile.IsVerified);
    }

    public async Task<User> ApplyAsync(DietitianApplicationRequest request, CancellationToken cancellationToken)
    {
        Validator.ValidateObject(request, new(request), true);
        if (!DietitianProfile.ValidText(request.DisplayName, 120) || !DietitianProfile.ValidText(request.LicenseInfo, 2000))
            throw new ValidationException("Application text is outside the approved limits.");
        if (policy.Value.Validate(request.Password!).Count != 0) throw new ValidationException("Invalid password policy input.");
        var email = normalizer.NormalizeEmail(request.Email!.Trim())!;
        if (await database.Users.AnyAsync(x => x.Email == email, cancellationToken)) throw new RegistrationEmailConflictException();
        var user = new User(Guid.NewGuid(), email, UserRole.Dietitian, request.Password!, clock.GetUtcNow(), hasher);
        _ = new DietitianProfile(user, request.DisplayName!, request.LicenseInfo!);
        database.Users.Add(user);
        try { await database.SaveChangesAsync(cancellationToken); }
        catch (DbUpdateException error) when (error.InnerException is PostgresException
            { SqlState: PostgresErrorCodes.UniqueViolation, ConstraintName: "ux_users_email" })
        { throw new RegistrationEmailConflictException(); }
        return user;
    }
}
