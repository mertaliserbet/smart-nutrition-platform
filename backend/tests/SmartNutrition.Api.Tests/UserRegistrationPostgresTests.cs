using System.Globalization;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Npgsql;
using SmartNutrition.Api.Data;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Tests;

public sealed class UserRegistrationPostgresTests
{
    [PostgresFact]
    [Trait("Category", "PostgreSQL")]
    public async Task PreparationNormalizesEmailPreservesPasswordAndOnlyBuildsAnUntrackedClient()
    {
        await using var database = CreateContext();
        await using var transaction = await database.Database.BeginTransactionAsync();
        var originalCulture = CultureInfo.CurrentCulture;
        try
        {
            CultureInfo.CurrentCulture = new CultureInfo("tr-TR");
            var email = $"synthetic-{Guid.NewGuid():N}@Example.test";
            const string password = " Synthetic pass1! ";
            var user = await CreateService(database).PrepareAsync(new RegisterUserRequest
            {
                Email = $"  {email}  ",
                Password = password,
                Role = UserRole.Client
            });
            Assert.Equal(email.Normalize().ToUpperInvariant(), user.Email);
            Assert.Equal(UserRole.Client, user.Role);
            Assert.Null(user.ClientProfile);
            Assert.Equal(PasswordVerificationResult.Success,
                new PasswordHasher<User>().VerifyHashedPassword(user, user.PasswordHash, password));
            Assert.Equal(PasswordVerificationResult.Failed,
                new PasswordHasher<User>().VerifyHashedPassword(user, user.PasswordHash, password.Trim()));
            Assert.Empty(database.ChangeTracker.Entries());
            Assert.False(await database.Users.AnyAsync(account => account.Id == user.Id));
        }
        finally { CultureInfo.CurrentCulture = originalCulture; }
    }

    [PostgresFact]
    [Trait("Category", "PostgreSQL")]
    public async Task AvailabilityCheckFindsLegacyMixedCaseEmailWithoutChangingExistingRows()
    {
        await using var database = CreateContext();
        await using var transaction = await database.Database.BeginTransactionAsync();
        var email = $"Synthetic-{Guid.NewGuid():N}@Example.test";
        database.Users.Add(CreateUser(email));
        await database.SaveChangesAsync();
        var errors = await CreateService(database).ValidateAsync(new RegisterUserRequest
        {
            Email = email.ToLowerInvariant(),
            Password = "Synthetic pass1!"
        });

        Assert.Contains(errors, error => error.MemberNames.Contains("email"));
        Assert.Equal(email, await database.Users.Where(user => user.Email == email.ToUpperInvariant()).Select(user => user.Email).SingleAsync());
    }

    [PostgresFact]
    [Trait("Category", "PostgreSQL")]
    public async Task UniqueIndexRejectsCaseVariantsEvenWhenThePreparationCheckIsBypassed()
    {
        await AssertDuplicate(email => email.ToUpperInvariant());
    }

    [PostgresFact]
    [Trait("Category", "PostgreSQL")]
    public async Task CanonicallyEquivalentUnicodeEmailsCannotCreateDuplicateAccounts()
    {
        await AssertDuplicate(email => email.Normalize(System.Text.NormalizationForm.FormD).ToUpperInvariant());
    }

    [PostgresFact]
    [Trait("Category", "PostgreSQL")]
    public async Task CaseInsensitiveEmailComparisonKeepsAccentsSignificant()
    {
        await using var database = CreateContext();
        await using var transaction = await database.Database.BeginTransactionAsync();
        var stem = $"synthetic-{Guid.NewGuid():N}";
        database.Users.AddRange(CreateUser($"{stem}-cafe@example.test"), CreateUser($"{stem}-café@example.test"));
        await database.SaveChangesAsync();
        Assert.Equal(2, await database.Users.CountAsync(user => user.Email == $"{stem}-cafe@example.test" || user.Email == $"{stem}-café@example.test"));
    }

    private static async Task AssertDuplicate(Func<string, string> variant)
    {
        await using var database = CreateContext();
        await using var transaction = await database.Database.BeginTransactionAsync();
        var email = $"Synthetic-{Guid.NewGuid():N}-café@Example.test";
        database.Users.Add(CreateUser(email));
        await database.SaveChangesAsync();
        database.Users.Add(CreateUser(variant(email)));

        var error = await Assert.ThrowsAsync<DbUpdateException>(() => database.SaveChangesAsync());
        var postgres = Assert.IsType<PostgresException>(error.InnerException);
        Assert.Equal(PostgresErrorCodes.UniqueViolation, postgres.SqlState);
        Assert.Equal("ux_users_email", postgres.ConstraintName);
    }

    private static AppDbContext CreateContext() => new(new DbContextOptionsBuilder<AppDbContext>()
        .UseNpgsql(Environment.GetEnvironmentVariable(PostgresFactAttribute.ConnectionVariable)).Options);

    private static UserRegistrationService CreateService(AppDbContext database) => new(database,
        new UpperInvariantLookupNormalizer(), new PasswordHasher<User>(), Options.Create(UserRegistrationTests.TestPolicy()));

    private static User CreateUser(string email) => new(Guid.NewGuid(), email, UserRole.Client,
        "Synthetic pass1!", DateTimeOffset.UtcNow, new PasswordHasher<User>());
}
