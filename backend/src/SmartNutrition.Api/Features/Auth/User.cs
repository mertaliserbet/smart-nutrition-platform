using System.ComponentModel.DataAnnotations;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Identity;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Features.Auth;

public sealed class User
{
    // EF materialization only. Public construction always hashes the supplied password.
    private User() { }

    public User(
        Guid id,
        string email,
        UserRole role,
        string password,
        DateTimeOffset createdAt,
        IPasswordHasher<User> passwordHasher)
    {
        if (id == Guid.Empty)
            throw new ArgumentException("A user ID is required.", nameof(id));
        ArgumentException.ThrowIfNullOrWhiteSpace(email);
        if (!new EmailAddressAttribute().IsValid(email))
            throw new ArgumentException("A valid email address is required.", nameof(email));
        if (!Enum.IsDefined(role))
            throw new ArgumentException("The user role is not supported.", nameof(role));
        // No trimming or unapproved length/complexity policy.
        ArgumentException.ThrowIfNullOrEmpty(password);
        if (createdAt == default)
            throw new ArgumentException("Creation time is required.", nameof(createdAt));
        ArgumentNullException.ThrowIfNull(passwordHasher);

        Id = id;
        Email = email;
        Role = role;
        CreatedAt = createdAt.ToUniversalTime();
        UpdatedAt = CreatedAt;
        PasswordHash = passwordHasher.HashPassword(this, password);
    }

    public Guid Id { get; private set; }
    public string Email { get; private set; } = null!;
    [JsonIgnore]
    public string PasswordHash { get; private set; } = null!;
    public UserRole Role { get; private set; }
    [JsonIgnore]
    public bool IsEmailVerified { get; private set; }
    [JsonIgnore]
    public string? EmailVerificationTokenHash { get; private set; }
    [JsonIgnore]
    public DateTimeOffset? EmailVerificationExpiresAt { get; private set; }
    [JsonIgnore]
    public DateTimeOffset? EmailVerificationLastSentAt { get; private set; }
    public DateTimeOffset CreatedAt { get; private set; }
    public DateTimeOffset UpdatedAt { get; private set; }

    [JsonIgnore]
    public ClientProfile? ClientProfile { get; private set; }

    internal void AttachClientProfile(ClientProfile profile)
    {
        if (ClientProfile is not null)
            throw new InvalidOperationException("This user already has a client profile.");
        ClientProfile = profile;
    }
}
