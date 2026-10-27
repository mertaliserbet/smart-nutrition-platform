using System.ComponentModel.DataAnnotations;
using System.Text.Json.Serialization;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Features.Auth;

// Known inputs only; profile composition and the public response schema remain open.
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed class RegisterUserRequest : IValidatableObject
{
    // Inbound only, so accidental JSON serialization cannot echo credentials or email.
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWriting)]
    public string? Email { get; init; }
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWriting)]
    public string? Password { get; init; }
    public UserRole? Role { get; init; }

    public IEnumerable<ValidationResult> Validate(ValidationContext validationContext)
    {
        if (string.IsNullOrWhiteSpace(Email))
            yield return new ValidationResult("Email is required.", ["email"]);
        else if (!IsValidEmail(Email))
            yield return new ValidationResult("A valid email address is required.", ["email"]);
        if (string.IsNullOrEmpty(Password))
            yield return new ValidationResult("Password is required.", ["password"]);
        if (Role.HasValue && Role != UserRole.Client)
            yield return new ValidationResult("Only client registration is available.", ["role"]);
    }

    private static bool IsValidEmail(string email)
    {
        try
        {
            // Also reject malformed UTF-16 before the Identity normalizer is called.
            return new EmailAddressAttribute().IsValid(email.Trim().Normalize());
        }
        catch (ArgumentException)
        {
            return false;
        }
    }
}
