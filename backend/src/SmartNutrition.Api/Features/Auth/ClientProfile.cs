using System.Text.Json.Serialization;

namespace SmartNutrition.Api.Features.Auth;

public sealed class ClientProfile
{
    private ClientProfile() { }

    public ClientProfile(
        Guid id,
        User user,
        string displayName,
        DateOnly? birthDate = null,
        decimal? heightCm = null)
    {
        if (id == Guid.Empty)
            throw new ArgumentException("A client-profile ID is required.", nameof(id));
        ArgumentNullException.ThrowIfNull(user);
        ArgumentException.ThrowIfNullOrWhiteSpace(displayName);
        if (heightCm is <= 0)
            throw new ArgumentException("Known height must be positive, in centimetres.", nameof(heightCm));

        Id = id;
        User = user;
        UserId = user.Id;
        DisplayName = displayName;
        BirthDate = birthDate;
        HeightCm = heightCm;
        user.AttachClientProfile(this);
    }

    public Guid Id { get; private set; }
    public Guid UserId { get; private set; }
    public string DisplayName { get; private set; } = null!;
    public DateOnly? BirthDate { get; private set; }
    public decimal? HeightCm { get; private set; }

    [JsonIgnore]
    public User User { get; private set; } = null!;
}
