using System.ComponentModel.DataAnnotations;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.JsonWebTokens;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Tests;

public sealed class LoginTests
{
    [Fact]
    public void RequestAndResponseToStringCannotPrintSecretsAndRequestFieldsAreInputOnly()
    {
        const string password = "synthetic-sensitive-password";
        var request = new LoginUserRequest { Email = "synthetic@example.test", Password = password };
        Assert.DoesNotContain(password, request.ToString());
        Assert.Equal("{}", JsonSerializer.Serialize(request, JsonSerializerOptions.Web));
        Assert.Throws<JsonException>(() => JsonSerializer.Deserialize<LoginUserRequest>("{}", JsonSerializerOptions.Web));
        Assert.Throws<JsonException>(() => JsonSerializer.Deserialize<LoginUserRequest>(
            "{\"email\":\"synthetic@example.test\",\"password\":\"synthetic\",\"role\":\"admin\"}", JsonSerializerOptions.Web));
        var response = new LoginUserResponse("synthetic-sensitive-token", DateTimeOffset.UtcNow);
        Assert.DoesNotContain(response.AccessToken, response.ToString());
    }

    [Theory]
    [InlineData(null, "synthetic")]
    [InlineData("invalid", "synthetic")]
    [InlineData("synthetic@example.test", null)]
    [InlineData("synthetic@example.test", "")]
    public void RequiresEmailAndPassword(string? email, string? password)
    {
        var request = new LoginUserRequest { Email = email, Password = password };
        Assert.NotEmpty(request.Validate(new ValidationContext(request)));
    }

    [Fact]
    public void LoginPreservesWhitespaceAndDoesNotApplyRegistrationMinimumLength()
    {
        foreach (var password in new[] { "        ", " şifre 🔒 ", "short" })
        {
            var request = new LoginUserRequest { Email = "  Synthetic@example.test  ", Password = password };
            Assert.Empty(request.Validate(new ValidationContext(request)));
            Assert.Equal(password, request.Password);
        }
    }

    [Fact]
    public void UnknownAccountStillPerformsIdentityPasswordVerification()
    {
        var verifier = new LoginPasswordVerifier(Options.Create(new PasswordHasherOptions()));
        var hasher = new CountingHasher();
        Assert.Equal(PasswordVerificationResult.Failed, verifier.Verify(hasher, null, "synthetic password"));
        Assert.Equal(1, hasher.Calls);
    }

    [Fact]
    public void CorruptStoredHashFailsWithoutExposingAnAccountSpecificException()
    {
        var user = SyntheticUser();
        typeof(User).GetProperty(nameof(User.PasswordHash))!.SetValue(user, "synthetic-invalid-base64");
        var verifier = new LoginPasswordVerifier(Options.Create(new PasswordHasherOptions()));
        Assert.Equal(PasswordVerificationResult.Failed, verifier.Verify(new PasswordHasher<User>(), user, "synthetic password"));
    }

    [Fact]
    public void JwtRequiresIssuerAudienceAndAtLeast256BitsOfBase64KeyMaterial()
    {
        var settings = new JwtTestSettings();
        Assert.True(settings.Options.IsValid());
        Assert.False(new JwtOptions { Issuer = settings.Issuer, Audience = settings.Audience }.IsValid());
        Assert.False(new JwtOptions { Issuer = settings.Issuer, Audience = settings.Audience, SigningKeyBase64 = "invalid" }.IsValid());
        Assert.False(new JwtOptions { Issuer = settings.Issuer, Audience = settings.Audience,
            SigningKeyBase64 = Convert.ToBase64String(new byte[31]) }.IsValid());
        Assert.False(new JwtOptions { Issuer = " ", Audience = settings.Audience, SigningKeyBase64 = settings.SigningKeyBase64 }.IsValid());
        Assert.False(new JwtOptions { Issuer = settings.Issuer, Audience = "", SigningKeyBase64 = settings.SigningKeyBase64 }.IsValid());
    }

    [Fact]
    public void JwtHasExactlyFifteenMinutesAndOnlyIdentityRoleAndRequiredStandardClaims()
    {
        var settings = new JwtTestSettings();
        var instant = DateTimeOffset.FromUnixTimeSeconds(1_800_000_000).AddMilliseconds(123);
        var service = new JwtAccessTokenService(Options.Create(settings.Options), new FixedClock(instant));
        var user = SyntheticUser();
        typeof(User).GetProperty(nameof(User.IsEmailVerified))!.SetValue(user, true);
        var result = service.Issue(user);
        var token = new JsonWebToken(result.AccessToken);
        Assert.Equal("HS256", token.Alg);
        Assert.Equal("at+jwt", token.Typ);
        Assert.Equal(user.Id.ToString("D"), token.Subject);
        Assert.Equal("client", token.GetClaim("role").Value);
        Assert.Equal(["aud", "exp", "iat", "iss", "nbf", "role", "sub"], token.Claims.Select(claim => claim.Type).Order().ToArray());
        Assert.Equal(TimeSpan.FromMinutes(15), token.ValidTo - token.ValidFrom);
        Assert.Equal(token.ValidTo, result.ExpiresAt.UtcDateTime);
        Assert.Equal("Bearer", result.TokenType);
        Assert.DoesNotContain(user.Email, result.AccessToken);
        Assert.DoesNotContain(user.PasswordHash, result.AccessToken);
    }

    [Theory]
    [InlineData(UserRole.Client, false)]
    [InlineData(UserRole.Admin, true)]
    public void IssuerCannotBypassVerificationOrAdminMfa(UserRole role, bool verified)
    {
        var service = new JwtAccessTokenService(Options.Create(new JwtTestSettings().Options), TimeProvider.System);
        var user = SyntheticUser(role);
        typeof(User).GetProperty(nameof(User.IsEmailVerified))!.SetValue(user, verified);
        Assert.Throws<InvalidOperationException>(() => service.Issue(user));
    }

    private static User SyntheticUser(UserRole role = UserRole.Client) => new(Guid.NewGuid(), "synthetic@example.test", role,
        "sentetik parola", DateTimeOffset.UtcNow, new PasswordHasher<User>());

    private sealed class FixedClock(DateTimeOffset instant) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => instant;
    }

    private sealed class CountingHasher : IPasswordHasher<User>
    {
        public int Calls { get; private set; }
        public string HashPassword(User user, string password) => throw new NotSupportedException();
        public PasswordVerificationResult VerifyHashedPassword(User user, string hashedPassword, string providedPassword)
        {
            Calls++;
            return new PasswordHasher<User>().VerifyHashedPassword(user, hashedPassword, providedPassword);
        }
    }
}
