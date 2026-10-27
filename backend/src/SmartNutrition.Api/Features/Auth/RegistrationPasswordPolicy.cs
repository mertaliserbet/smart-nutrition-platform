using System.Buffers;
using System.ComponentModel.DataAnnotations;
using System.Text;

namespace SmartNutrition.Api.Features.Auth;

public sealed class RegistrationPasswordPolicy
{
    public const string SectionName = "Auth:RegistrationPasswordPolicy";

    // Values are centrally configured; the first API policy is specified in appsettings.json.
    public int? RequiredLength { get; set; }
    public int? MaximumLength { get; set; }
    public int? RequiredUniqueChars { get; set; }
    public bool? RequireDigit { get; set; }
    public bool? RequireLowercase { get; set; }
    public bool? RequireUppercase { get; set; }
    public bool? RequireNonAlphanumeric { get; set; }

    public IReadOnlyList<ValidationResult> Validate(string password)
    {
        if (RequiredLength is not > 0 || MaximumLength is null || MaximumLength < RequiredLength ||
            RequiredUniqueChars is not > 0 || RequiredUniqueChars > MaximumLength ||
            RequireDigit is null || RequireLowercase is null || RequireUppercase is null || RequireNonAlphanumeric is null)
        {
            // A missing server policy is not an invalid user request, and does not stop health probes.
            throw new InvalidOperationException("Registration password policy is not fully configured.");
        }

        ArgumentNullException.ThrowIfNull(password);
        var errors = new List<ValidationResult>();
        var remaining = password.AsSpan();
        var characterCount = 0;
        var distinctCharacters = new HashSet<Rune>();
        while (!remaining.IsEmpty)
        {
            if (Rune.DecodeFromUtf16(remaining, out var character, out var consumed) != OperationStatus.Done)
                return [Error("Password must contain valid Unicode characters.")];
            characterCount++;
            if (characterCount > MaximumLength)
                return [Error("Password exceeds the configured maximum length.")];
            distinctCharacters.Add(character);
            remaining = remaining[consumed..];
        }
        if (characterCount < RequiredLength)
            errors.Add(Error("Password does not meet the configured minimum length."));
        if (distinctCharacters.Count < RequiredUniqueChars)
            errors.Add(Error("Password does not contain enough distinct characters."));
        if (RequireDigit == true && !password.Any(char.IsDigit))
            errors.Add(Error("Password must contain a digit."));
        if (RequireLowercase == true && !password.Any(char.IsLower))
            errors.Add(Error("Password must contain a lowercase letter."));
        if (RequireUppercase == true && !password.Any(char.IsUpper))
            errors.Add(Error("Password must contain an uppercase letter."));
        if (RequireNonAlphanumeric == true && password.All(char.IsLetterOrDigit))
            errors.Add(Error("Password must contain a non-alphanumeric character."));
        return errors;
    }

    private static ValidationResult Error(string message) => new(message, ["password"]);
}
