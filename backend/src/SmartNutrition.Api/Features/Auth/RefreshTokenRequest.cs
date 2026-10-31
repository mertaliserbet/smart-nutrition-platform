using System.ComponentModel.DataAnnotations;
using System.Text.Json.Serialization;

namespace SmartNutrition.Api.Features.Auth;

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed class RefreshTokenRequest : IValidatableObject
{
    [JsonRequired]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWriting)]
    public string? RefreshToken { get; init; }

    public IEnumerable<ValidationResult> Validate(ValidationContext validationContext)
    {
        if (string.IsNullOrWhiteSpace(RefreshToken))
            yield return new ValidationResult("A refresh token is required.", ["refreshToken"]);
    }
}
