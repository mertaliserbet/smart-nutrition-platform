using System.Security.Claims;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.EntityFrameworkCore;
using SmartNutrition.Api.Data;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Tests;

public sealed class CurrentUserTests
{
    [Theory]
    [InlineData("unauthenticated")]
    [InlineData("missing-sub")]
    [InlineData("invalid-sub")]
    [InlineData("empty-sub")]
    [InlineData("duplicate-sub")]
    [InlineData("legacy-id-only")]
    [InlineData("missing-role")]
    [InlineData("duplicate-role")]
    [InlineData("admin")]
    [InlineData("unknown-role")]
    public async Task RejectsUntrustedOrAmbiguousIdentityBeforeDatabaseAccess(string variant)
    {
        var claims = new List<Claim> { new("sub", Guid.NewGuid().ToString("D")), new("role", "client") };
        if (variant is "missing-sub" or "legacy-id-only") claims.RemoveAll(claim => claim.Type == "sub");
        if (variant == "legacy-id-only") claims.Add(new Claim(ClaimTypes.NameIdentifier, Guid.NewGuid().ToString()));
        if (variant == "invalid-sub") claims[0] = new Claim("sub", "not-a-user-id");
        if (variant == "empty-sub") claims[0] = new Claim("sub", Guid.Empty.ToString());
        if (variant == "duplicate-sub") claims.Add(new Claim("sub", Guid.NewGuid().ToString()));
        if (variant == "missing-role") claims.RemoveAll(claim => claim.Type == "role");
        if (variant == "duplicate-role") claims.Add(new Claim("role", "dietitian"));
        if (variant is "admin" or "unknown-role") claims[1] = new Claim("role", variant);
        var principal = new ClaimsPrincipal(new ClaimsIdentity(claims, variant == "unauthenticated" ? null : "Bearer"));
        await using var database = new AppDbContext(new DbContextOptionsBuilder<AppDbContext>().UseNpgsql().Options);
        Assert.Null(await new CurrentUserService(database).GetAsync(principal));
    }

    [Fact]
    public void ResponseIsAnExplicitFiveFieldWhitelistAndKeepsMissingDisplayNameNull()
    {
        var userId = Guid.NewGuid();
        var response = new CurrentUserResponse(userId, null, "synthetic@example.test", UserRole.Dietitian, true);
        var options = new JsonSerializerOptions(JsonSerializerDefaults.Web)
        { DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull };
        using var json = JsonDocument.Parse(JsonSerializer.Serialize(response, options));
        Assert.Equal(["displayName", "email", "id", "isEmailVerified", "role"],
            json.RootElement.EnumerateObject().Select(field => field.Name).Order().ToArray());
        Assert.Equal(JsonValueKind.Null, json.RootElement.GetProperty("displayName").ValueKind);
        Assert.Equal(userId, json.RootElement.GetProperty("id").GetGuid());
        Assert.Equal("dietitian", json.RootElement.GetProperty("role").GetString());
        Assert.True(json.RootElement.GetProperty("isEmailVerified").GetBoolean());
        Assert.DoesNotContain(response.Email, response.ToString());
    }
}
