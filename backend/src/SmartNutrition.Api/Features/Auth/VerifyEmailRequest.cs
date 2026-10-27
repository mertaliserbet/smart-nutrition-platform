using System.ComponentModel.DataAnnotations;
using System.Text.Json.Serialization;

namespace SmartNutrition.Api.Features.Auth;

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed class VerifyEmailRequest
{
    [JsonRequired]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWriting)]
    public string? Token { get; init; }
}

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed class ResendVerificationRequest : IValidatableObject
{
    [JsonRequired]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWriting)]
    public string? Email { get; init; }

    public IEnumerable<ValidationResult> Validate(ValidationContext validationContext)
    {
        if (string.IsNullOrWhiteSpace(Email) || !RegisterUserRequest.IsValidEmail(Email))
            yield return new ValidationResult("A valid email address is required.", ["email"]);
    }
}
