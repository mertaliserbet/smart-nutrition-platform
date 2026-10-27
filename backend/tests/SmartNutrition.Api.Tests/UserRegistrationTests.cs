using System.ComponentModel.DataAnnotations;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using SmartNutrition.Api.Data;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Tests;

public sealed class UserRegistrationTests
{
    [Theory]
    [InlineData(null, "password", "email")]
    [InlineData(" ", "password", "email")]
    [InlineData("invalid", "password", "email")]
    [InlineData("synthetic@example.test", null, "password")]
    [InlineData("synthetic@example.test", "", "password")]
    public void ValidatesKnownRequiredInputsWithoutEchoingThem(string? email, string? password, string field)
    {
        var request = new RegisterUserRequest { Email = email, Password = password };
        var errors = Validate(request);
        Assert.Contains(errors, error => error.MemberNames.Contains(field));
        Assert.All(errors, error => Assert.DoesNotContain("synthetic@example.test", error.ErrorMessage!));
    }

    [Theory]
    [InlineData(UserRole.Admin)]
    [InlineData(UserRole.Dietitian)]
    [InlineData((UserRole)99)]
    public async Task PrivilegedOrUndefinedRolesAreRejectedBeforePolicyHashingOrDatabaseAccess(UserRole role)
    {
        using var database = new AppDbContext(new DbContextOptionsBuilder<AppDbContext>().UseNpgsql().Options);
        var service = new UserRegistrationService(database, new UpperInvariantLookupNormalizer(),
            new PasswordHasher<User>(), Options.Create(new RegistrationPasswordPolicy()));
        var request = new RegisterUserRequest { Email = "synthetic@example.test", Password = "Synthetic!", Role = role };

        var errors = await service.ValidateAsync(request);
        Assert.Contains(errors, error => error.MemberNames.Contains("role"));
        await Assert.ThrowsAsync<ValidationException>(() => service.PrepareAsync(request));
        Assert.Empty(database.ChangeTracker.Entries());
    }

    [Fact]
    public void OnlyClientOrUnspecifiedRoleIsAcceptedAndMalformedUnicodeIsRejected()
    {
        foreach (var role in new UserRole?[] { null, UserRole.Client })
            Assert.Empty(Validate(new RegisterUserRequest { Email = "  Synthetic@Example.test  ", Password = "Synthetic!", Role = role }));
        Assert.NotEmpty(Validate(new RegisterUserRequest { Email = "\ud800@example.test", Password = "Synthetic!" }));
    }

    [Theory]
    [InlineData("role", "\"admin\"")]
    [InlineData("role", "\"dietitian\"")]
    public void JsonRoleCannotGrantPrivileges(string property, string value)
    {
        var json = $"{{\"email\":\"synthetic@example.test\",\"password\":\"Synthetic!\",\"{property}\":{value}}}";
        var request = JsonSerializer.Deserialize<RegisterUserRequest>(json, JsonSerializerOptions.Web)!;
        Assert.Contains(Validate(request), error => error.MemberNames.Contains("role"));
    }

    [Theory]
    [InlineData("id")]
    [InlineData("userId")]
    [InlineData("clientId")]
    [InlineData("isVerified")]
    [InlineData("passwordHash")]
    [InlineData("clientProfile")]
    public void JsonCannotOverpostIdentitySecurityOrStillOpenProfileFields(string property)
    {
        Assert.Throws<JsonException>(() => JsonSerializer.Deserialize<RegisterUserRequest>(
            $"{{\"email\":\"synthetic@example.test\",\"password\":\"Synthetic!\",\"{property}\":null}}", JsonSerializerOptions.Web));
    }

    [Fact]
    public void CredentialsCanBeReadButCannotBeEchoedByJsonOrDefaultToString()
    {
        const string email = "synthetic@example.test";
        const string password = " Synthetic secret! ";
        var request = JsonSerializer.Deserialize<RegisterUserRequest>(
            "{\"email\":\"synthetic@example.test\",\"password\":\" Synthetic secret! \",\"role\":\"client\"}",
            JsonSerializerOptions.Web)!;

        Assert.Equal(email, request.Email);
        Assert.Equal(password, request.Password);
        var json = JsonSerializer.Serialize(request, JsonSerializerOptions.Web);
        Assert.DoesNotContain(email, json);
        Assert.DoesNotContain(password, json);
        Assert.DoesNotContain(email, request.ToString()!);
        Assert.DoesNotContain(password, request.ToString()!);
    }

    [Fact]
    public void UnconfiguredOrPartiallyConfiguredPolicyDoesNotSilentlyUseIdentityDefaults()
    {
        Assert.Throws<InvalidOperationException>(() => new RegistrationPasswordPolicy().Validate("Synthetic!"));
        Assert.Throws<InvalidOperationException>(() => new RegistrationPasswordPolicy { RequiredLength = 12 }.Validate("Synthetic!"));
    }

    [Theory]
    [InlineData(0, 128, 1)]
    [InlineData(12, 8, 1)]
    [InlineData(12, 128, 0)]
    [InlineData(12, 128, 129)]
    public void InvalidPolicyConfigurationFailsClosed(int minimum, int maximum, int unique)
    {
        var policy = TestPolicy();
        policy.RequiredLength = minimum;
        policy.MaximumLength = maximum;
        policy.RequiredUniqueChars = unique;
        Assert.Throws<InvalidOperationException>(() => policy.Validate("Synthetic password1!"));
    }

    [Theory]
    [InlineData("Aa1!")]
    [InlineData("synthetic-password1!")]
    [InlineData("SYNTHETIC-PASSWORD1!")]
    [InlineData("Synthetic-password!")]
    [InlineData("SyntheticPassword1")]
    public void ConfiguredLengthAndCompositionRulesAreAppliedWithoutEchoingPasswords(string password)
    {
        var errors = TestPolicy().Validate(password);
        Assert.NotEmpty(errors);
        Assert.All(errors, error =>
        {
            Assert.Contains("password", error.MemberNames);
            Assert.DoesNotContain(password, error.ErrorMessage!);
        });
    }

    [Fact]
    public void MaximumAndDistinctCharacterRulesAreConfigurableAndPasswordIsNotTrimmed()
    {
        Assert.NotEmpty(TestPolicy().Validate(new string('A', 129)));
        var policy = TestPolicy();
        policy.RequiredUniqueChars = 8;
        Assert.NotEmpty(policy.Validate("Aa1!Aa1!Aa1!"));
        Assert.Empty(policy.Validate(" Synthetic pass1! "));
    }

    internal static RegistrationPasswordPolicy TestPolicy() => new()
    {
        // Synthetic test settings only. These values are not approved product defaults.
        RequiredLength = 12,
        MaximumLength = 128,
        RequiredUniqueChars = 4,
        RequireDigit = true,
        RequireLowercase = true,
        RequireUppercase = true,
        RequireNonAlphanumeric = true
    };

    private static IReadOnlyList<ValidationResult> Validate(RegisterUserRequest request)
    {
        var errors = new List<ValidationResult>();
        Validator.TryValidateObject(request, new ValidationContext(request), errors, validateAllProperties: true);
        return errors;
    }
}
