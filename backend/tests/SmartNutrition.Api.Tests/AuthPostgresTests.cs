using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Npgsql;
using SmartNutrition.Api.Data;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Tests;

// Every write is rolled back. The opted-in database must already have its migration applied.
public sealed class AuthPostgresTests
{
    [PostgresFact]
    [Trait("Category", "PostgreSQL")]
    public async Task PersistsAndReloadsAccountProfileAndIdentityPasswordHash()
    {
        await using var database = CreateContext();
        await using var transaction = await database.Database.BeginTransactionAsync();
        var user = CreateUser();
        var profile = new ClientProfile(Guid.NewGuid(), user, "Synthetic client", new DateOnly(2000, 1, 2), 170.123456789m);
        database.Users.Add(user);
        await database.SaveChangesAsync();
        database.ChangeTracker.Clear();

        var restored = await database.Users.Include(account => account.ClientProfile).SingleAsync(account => account.Id == user.Id);
        Assert.Equal(profile.Id, restored.ClientProfile!.Id);
        Assert.Equal(user.Id, restored.ClientProfile.UserId);
        Assert.Equal(profile.HeightCm, restored.ClientProfile.HeightCm);
        Assert.Equal(profile.BirthDate, restored.ClientProfile.BirthDate);
        Assert.Equal(TimeSpan.Zero, restored.CreatedAt.Offset);
        Assert.Equal(UserRole.Client, restored.Role);
        Assert.Equal(PasswordVerificationResult.Success,
            new PasswordHasher<User>().VerifyHashedPassword(restored, restored.PasswordHash, "Synthetic password!"));
    }

    [PostgresFact]
    [Trait("Category", "PostgreSQL")]
    public Task DuplicateEmailIsRejectedByPostgres() => AssertConstraint(
        async (database, user) =>
        {
            database.Users.Add(CreateUser(user.Email));
            await database.SaveChangesAsync();
        }, PostgresErrorCodes.UniqueViolation);

    [PostgresFact]
    [Trait("Category", "PostgreSQL")]
    public Task DuplicateProfileForTheSameUserIsRejectedByPostgres() => AssertConstraint(
        async (database, user) => await database.Database.ExecuteSqlInterpolatedAsync(
            $"INSERT INTO client_profiles (id, user_id, display_name) VALUES ({Guid.NewGuid()}, {user.Id}, {"Synthetic duplicate"})"),
        PostgresErrorCodes.UniqueViolation);

    [PostgresFact]
    [Trait("Category", "PostgreSQL")]
    public Task ProfileCannotReferenceAnUnknownUser() => AssertConstraint(
        async (database, _) => await database.Database.ExecuteSqlInterpolatedAsync(
            $"INSERT INTO client_profiles (id, user_id, display_name) VALUES ({Guid.NewGuid()}, {Guid.NewGuid()}, {"Synthetic orphan"})"),
        PostgresErrorCodes.ForeignKeyViolation);

    [PostgresFact]
    [Trait("Category", "PostgreSQL")]
    public Task UserDeletionDoesNotCascadeIntoTheProfile() => AssertConstraint(
        async (database, user) => await database.Users.Where(account => account.Id == user.Id).ExecuteDeleteAsync(),
        PostgresErrorCodes.ForeignKeyViolation);

    private static async Task AssertConstraint(Func<AppDbContext, User, Task> operation, string sqlState)
    {
        await using var database = CreateContext();
        await using var transaction = await database.Database.BeginTransactionAsync();
        var user = CreateUser();
        _ = new ClientProfile(Guid.NewGuid(), user, "Synthetic client");
        database.Users.Add(user);
        await database.SaveChangesAsync();

        var error = await Assert.ThrowsAnyAsync<Exception>(() => operation(database, user));
        var postgres = error as PostgresException ?? (error as DbUpdateException)?.InnerException as PostgresException;
        Assert.NotNull(postgres);
        Assert.Equal(sqlState, postgres.SqlState);
    }

    private static AppDbContext CreateContext() => new(new DbContextOptionsBuilder<AppDbContext>()
        .UseNpgsql(Environment.GetEnvironmentVariable(PostgresFactAttribute.ConnectionVariable)).Options);

    private static User CreateUser(string? email = null) => new(
        Guid.NewGuid(), email ?? $"synthetic-{Guid.NewGuid():N}@example.test", UserRole.Client,
        "Synthetic password!", DateTimeOffset.UtcNow, new PasswordHasher<User>());
}
