using System.ComponentModel.DataAnnotations;
using System.Text.Json.Serialization;

namespace SmartNutrition.Api.Features.Auth;

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed class LoginUserRequest : IValidatableObject
{
    [JsonRequired]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWriting)]
    public string? Email { get; init; }
    [JsonRequired]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWriting)]
    public string? Password { get; init; }

    public IEnumerable<ValidationResult> Validate(ValidationContext validationContext)
    {
        if (string.IsNullOrWhiteSpace(Email) || !RegisterUserRequest.IsValidEmail(Email))
            yield return new ValidationResult("A valid email address is required.", ["email"]);
        // Whitespace is meaningful. Login does not reapply a newer registration complexity policy.
        if (string.IsNullOrEmpty(Password))
            yield return new ValidationResult("Password is required.", ["password"]);
    }
}

// A class rather than a record: ToString must not print the access token.
public sealed class LoginUserResponse(string accessToken, DateTimeOffset expiresAt)
{
    public string AccessToken { get; } = accessToken;
    public string TokenType => "Bearer";
    public DateTimeOffset ExpiresAt { get; } = expiresAt;
}
