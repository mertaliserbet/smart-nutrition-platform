using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using SmartNutrition.Api.Data;
using SmartNutrition.Api.Data.Migrations;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Tests;

public sealed class AuthFoundationTests
{
    private static readonly DateTimeOffset Instant = new(2026, 10, 25, 12, 0, 0, TimeSpan.FromHours(3));
    private const string SyntheticPassword = " Synthetic password! ";

    [Fact]
    public void IdentityHashesAreSaltedVerifiableAndPreservePasswordWhitespace()
    {
        var hasher = new PasswordHasher<User>();
        var first = NewUser(hasher: hasher);
        var second = NewUser(hasher: hasher);

        Assert.NotEqual(SyntheticPassword, first.PasswordHash);
        Assert.NotEqual(first.PasswordHash, second.PasswordHash);
        Assert.Equal(PasswordVerificationResult.Success,
            hasher.VerifyHashedPassword(first, first.PasswordHash, SyntheticPassword));
        Assert.Equal(PasswordVerificationResult.Failed,
            hasher.VerifyHashedPassword(first, first.PasswordHash, SyntheticPassword.Trim()));
        Assert.Equal(PasswordVerificationResult.Failed,
            hasher.VerifyHashedPassword(first, first.PasswordHash, "Incorrect synthetic password"));
        Assert.Equal(TimeSpan.Zero, first.CreatedAt.Offset);
        Assert.Equal(Instant, first.CreatedAt);
        Assert.Equal(first.CreatedAt, first.UpdatedAt);
        Assert.False(first.IsEmailVerified);
    }

    [Fact]
    public void UserAndProfileHaveSeparateIdsWithAnImmutableAccountLink()
    {
        var user = NewUser();
        var profileId = Guid.NewGuid();
        var profile = new ClientProfile(profileId, user, "Synthetic client");

        Assert.Equal(profileId, profile.Id);
        Assert.Equal(user.Id, profile.UserId);
        Assert.Same(user, profile.User);
        Assert.Same(profile, user.ClientProfile);
        Assert.Null(profile.BirthDate);
        Assert.Null(profile.HeightCm);
        Assert.Throws<InvalidOperationException>(() => new ClientProfile(Guid.NewGuid(), user, "Another profile"));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData(" ")]
    [InlineData("invalid-email")]
    public void RejectsMissingOrInvalidEmail(string? email)
    {
        Assert.ThrowsAny<ArgumentException>(() => NewUser(email: email!));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    public void RequiresPasswordWithoutChoosingAnUnapprovedComplexityPolicy(string? password)
    {
        Assert.ThrowsAny<ArgumentException>(() => NewUser(password: password!));
    }

    [Fact]
    public void RequiresExplicitUserIdRoleAndCreationTime()
    {
        Assert.Throws<ArgumentException>(() => NewUser(id: Guid.Empty));
        Assert.Throws<ArgumentException>(() => NewUser(role: (UserRole)99));
        Assert.Throws<ArgumentException>(() => NewUser(createdAt: default(DateTimeOffset)));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("  ")]
    public void RequiresNonBlankProfileName(string? displayName)
    {
        Assert.ThrowsAny<ArgumentException>(() => new ClientProfile(Guid.NewGuid(), NewUser(), displayName!));
    }

    [Fact]
    public void ValidatesProfileIdentityAndPositiveHeightWithoutInventingAgeOrRoundingRules()
    {
        var user = NewUser();
        Assert.Throws<ArgumentException>(() => new ClientProfile(Guid.Empty, user, "Synthetic client"));
        Assert.Throws<ArgumentNullException>(() => new ClientProfile(Guid.NewGuid(), null!, "Synthetic client"));
        Assert.Throws<ArgumentException>(() => new ClientProfile(Guid.NewGuid(), user, "Synthetic client", heightCm: 0));
        Assert.Throws<ArgumentException>(() => new ClientProfile(Guid.NewGuid(), user, "Synthetic client", heightCm: -1));

        var birthDate = new DateOnly(2000, 1, 2);
        var profile = new ClientProfile(Guid.NewGuid(), user, "Synthetic client", birthDate, 170.123456789m);
        Assert.Equal(birthDate, profile.BirthDate);
        Assert.Equal(170.123456789m, profile.HeightCm);
    }

    [Fact]
    public void JsonCannotExposePasswordHashOrTraverseAccountProfileNavigations()
    {
        var user = NewUser();
        var profile = new ClientProfile(Guid.NewGuid(), user, "Synthetic client");
        using var userJson = JsonDocument.Parse(JsonSerializer.Serialize(user, JsonSerializerOptions.Web));
        using var profileJson = JsonDocument.Parse(JsonSerializer.Serialize(profile, JsonSerializerOptions.Web));

        Assert.False(userJson.RootElement.TryGetProperty("passwordHash", out _));
        Assert.False(userJson.RootElement.TryGetProperty("isEmailVerified", out _));
        Assert.False(userJson.RootElement.TryGetProperty("clientProfile", out _));
        Assert.False(profileJson.RootElement.TryGetProperty("user", out _));
        Assert.Equal(user.Id.ToString(), profileJson.RootElement.GetProperty("userId").GetString());
    }

    [Theory]
    [InlineData(UserRole.Client, "client")]
    [InlineData(UserRole.Dietitian, "dietitian")]
    [InlineData(UserRole.Admin, "admin")]
    public void UsesTheCanonicalRoleStrings(UserRole role, string expected)
    {
        Assert.Equal($"\"{expected}\"", JsonSerializer.Serialize(role));
    }

    [Fact]
    public void EfModelMapsOnlyTheApprovedFieldsAndDoesNotChooseDecimalPrecisionOrCascadeDeletion()
    {
        using var database = new AppDbContext(new DbContextOptionsBuilder<AppDbContext>().UseNpgsql().Options);
        var users = database.Model.FindEntityType(typeof(User))!;
        var profiles = database.Model.FindEntityType(typeof(ClientProfile))!;

        Assert.Equal("users", users.GetTableName());
        Assert.Equal("client_profiles", profiles.GetTableName());
        Assert.Equal(["CreatedAt", "Email", "Id", "IsEmailVerified", "PasswordHash", "Role", "UpdatedAt"],
            users.GetProperties().Select(property => property.Name).Order().ToArray());
        Assert.Equal(["BirthDate", "DisplayName", "HeightCm", "Id", "UserId"],
            profiles.GetProperties().Select(property => property.Name).Order().ToArray());
        Assert.True(Assert.Single(users.GetIndexes()).IsUnique);
        Assert.True(Assert.Single(profiles.GetIndexes()).IsUnique);
        var relationship = Assert.Single(profiles.GetForeignKeys());
        Assert.Equal(DeleteBehavior.NoAction, relationship.DeleteBehavior);
        Assert.True(relationship.IsUnique);
        Assert.True(relationship.IsRequired);
        Assert.Equal("UserId", Assert.Single(relationship.Properties).Name);
        Assert.Null(profiles.FindProperty(nameof(ClientProfile.HeightCm))!.GetPrecision());
    }

    [Fact]
    public void MigrationOnlyAddsTheAuthTablesAndIndexes()
    {
        var operations = new AddAuthFoundation().UpOperations;
        Assert.Equal(["client_profiles", "users"], operations
            .OfType<Microsoft.EntityFrameworkCore.Migrations.Operations.CreateTableOperation>()
            .Select(operation => operation.Name).Order().ToArray());
        Assert.All(operations, operation => Assert.True(
            operation is Microsoft.EntityFrameworkCore.Migrations.Operations.CreateTableOperation
                or Microsoft.EntityFrameworkCore.Migrations.Operations.CreateIndexOperation));
    }

    private static User NewUser(
        Guid? id = null, string email = "synthetic@example.test", UserRole role = UserRole.Client,
        string password = SyntheticPassword, DateTimeOffset? createdAt = null, IPasswordHasher<User>? hasher = null) =>
        new(id ?? Guid.NewGuid(), email, role, password, createdAt ?? Instant, hasher ?? new PasswordHasher<User>());
}
