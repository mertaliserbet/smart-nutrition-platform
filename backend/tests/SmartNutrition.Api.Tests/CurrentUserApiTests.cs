using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Tests;

public sealed class CurrentUserApiTests
{
    private const string Route = "/api/v1/auth/me";
    private const string Password = "sentetik şifre 🔒";

    [PostgresFact]
    public async Task ReturnsOnlyTheOwnersApprovedAccountFieldsWithoutModifyingRecords()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync();
        var own = await Seed(factory, "own@example.test", "Synthetic owner");
        await Seed(factory, "other@example.test", "Synthetic other");
        using var client = factory.Client();
        var token = await Login(client, "own@example.test");
        await using var database = factory.Database();
        var before = await database.Users.SingleAsync(user => user.Id == own.Id);
        var previousUpdatedAt = before.UpdatedAt;
        using var response = await client.GetAsync(Route);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.True(response.Headers.CacheControl?.NoStore);
        Assert.False(response.Headers.Contains("Set-Cookie"));
        var text = await response.Content.ReadAsStringAsync();
        using var json = JsonDocument.Parse(text);
        Assert.Equal(["displayName", "email", "id", "isEmailVerified", "role"],
            json.RootElement.EnumerateObject().Select(field => field.Name).Order().ToArray());
        Assert.Equal(own.Id, json.RootElement.GetProperty("id").GetGuid());
        Assert.NotEqual(own.ProfileId, json.RootElement.GetProperty("id").GetGuid());
        Assert.Equal("Synthetic owner", json.RootElement.GetProperty("displayName").GetString());
        Assert.Equal("OWN@EXAMPLE.TEST", json.RootElement.GetProperty("email").GetString());
        Assert.Equal("client", json.RootElement.GetProperty("role").GetString());
        Assert.True(json.RootElement.GetProperty("isEmailVerified").GetBoolean());
        foreach (var secret in new[] { Password, before.PasswordHash, token, "OTHER@EXAMPLE.TEST", "Synthetic other" })
            Assert.DoesNotContain(secret, text);
        Assert.DoesNotContain(before.PasswordHash, factory.Logs);
        Assert.DoesNotContain(token, factory.Logs);
        Assert.DoesNotContain(Password, factory.Logs);
        await database.Entry(before).ReloadAsync();
        Assert.Equal(previousUpdatedAt, before.UpdatedAt);
        Assert.Equal(2, await database.Users.CountAsync());
        Assert.Equal(2, await database.ClientProfiles.CountAsync());
    }

    [PostgresFact]
    public async Task ClientSuppliedIdentityCannotSelectAnotherUsersAccount()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync();
        var own = await Seed(factory, "own@example.test", "Synthetic owner");
        var other = await Seed(factory, "other@example.test", "Synthetic other");
        using var client = factory.Client();
        await Login(client, "own@example.test");
        foreach (var field in new[] { "userId", "id", "clientId" })
        {
            using var attempt = await client.GetAsync(Route + "?" + field + "=" + other.Id);
            await AssertError(attempt, HttpStatusCode.BadRequest, "invalid_request");
        }
        using var bodyRequest = new HttpRequestMessage(HttpMethod.Get, Route)
        { Content = JsonContent.Create(new { userId = other.Id }) };
        using var bodyResponse = await client.SendAsync(bodyRequest);
        await AssertError(bodyResponse, HttpStatusCode.BadRequest, "invalid_request");
        client.DefaultRequestHeaders.Add("X-User-Id", other.Id.ToString());
        client.DefaultRequestHeaders.Add("X-Client-Id", other.ProfileId.ToString());
        using var ownResponse = await client.GetAsync(Route);
        Assert.Equal(HttpStatusCode.OK, ownResponse.StatusCode);
        using var ownJson = JsonDocument.Parse(await ownResponse.Content.ReadAsStringAsync());
        Assert.Equal(own.Id, ownJson.RootElement.GetProperty("id").GetGuid());
        await Login(client, "other@example.test");
        using var otherResponse = await client.GetAsync(Route);
        Assert.Equal(HttpStatusCode.OK, otherResponse.StatusCode);
        using var otherJson = JsonDocument.Parse(await otherResponse.Content.ReadAsStringAsync());
        Assert.Equal(other.Id, otherJson.RootElement.GetProperty("id").GetGuid());
    }

    [PostgresFact]
    public async Task ClientAndDietitianAccountsWithoutClientProfilesHaveNullDisplayName()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync();
        using var client = factory.Client();
        foreach (var role in new[] { UserRole.Client, UserRole.Dietitian })
        {
            var email = $"synthetic-{role.ToString().ToLowerInvariant()}@example.test";
            var account = await Seed(factory, email, null, role);
            await Login(client, email);
            using var response = await client.GetAsync(Route);
            Assert.Equal(HttpStatusCode.OK, response.StatusCode);
            using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
            Assert.Equal(account.Id, json.RootElement.GetProperty("id").GetGuid());
            Assert.Equal(JsonValueKind.Null, json.RootElement.GetProperty("displayName").ValueKind);
            Assert.Equal(role.ToString().ToLowerInvariant(), json.RootElement.GetProperty("role").GetString());
            Assert.True(json.RootElement.GetProperty("isEmailVerified").GetBoolean());
        }
        await using var database = factory.Database();
        Assert.Empty(await database.ClientProfiles.ToListAsync());
    }

    [PostgresFact]
    public async Task MissingInvalidExpiredAdminAndProfileIdTokensAreRejected()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync();
        var account = await Seed(factory, "own@example.test", "Synthetic owner");
        using var client = factory.Client();
        using var missing = await client.GetAsync(Route);
        await AssertError(missing, HttpStatusCode.Unauthorized, "unauthenticated");
        foreach (var token in new[]
        {
            "synthetic-invalid-token", Sign(factory.Jwt, account.Id, expired: true),
            Sign(factory.Jwt, account.Id, wrongKey: true), Sign(factory.Jwt, account.Id, role: "admin"),
            Sign(factory.Jwt, account.ProfileId!.Value)
        })
        {
            client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
            using var response = await client.GetAsync(Route);
            await AssertError(response, HttpStatusCode.Unauthorized, "unauthenticated");
            Assert.True(response.Headers.CacheControl?.NoStore);
            Assert.Equal("Bearer", response.Headers.WwwAuthenticate.Single().ToString());
            Assert.DoesNotContain(token, await response.Content.ReadAsStringAsync());
            Assert.DoesNotContain(token, factory.Logs);
        }
    }

    [PostgresFact]
    public async Task DeletedAccountWithAnUnexpiredTokenReceivesTheShared401()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync();
        var account = await Seed(factory, "deleted@example.test", "Synthetic deleted");
        using var client = factory.Client();
        await Login(client, "deleted@example.test");
        using var before = await client.GetAsync(Route);
        Assert.Equal(HttpStatusCode.OK, before.StatusCode);
        // Only this factory's random disposable test schema is affected, never application tables.
        await using var database = factory.Database();
        await database.ClientProfiles.Where(profile => profile.UserId == account.Id).ExecuteDeleteAsync();
        await database.Users.Where(user => user.Id == account.Id).ExecuteDeleteAsync();
        using var after = await client.GetAsync(Route);
        await AssertError(after, HttpStatusCode.Unauthorized, "unauthenticated");
        Assert.DoesNotContain("deleted@example.test", await after.Content.ReadAsStringAsync(), StringComparison.OrdinalIgnoreCase);
    }

    [PostgresFact]
    public async Task CurrentDatabaseVerificationAndRoleMustStillMatchTheAuthenticatedAccount()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync();
        using var client = factory.Client();
        foreach (var change in new[] { "unverified", "admin", "changed-role" })
        {
            var email = $"synthetic-{change}@example.test";
            var account = await Seed(factory, email, null);
            await Login(client, email);
            await using var database = factory.Database();
            var user = await database.Users.SingleAsync(user => user.Id == account.Id);
            if (change == "unverified") database.Entry(user).Property(value => value.IsEmailVerified).CurrentValue = false;
            else database.Entry(user).Property(value => value.Role).CurrentValue = change == "admin" ? UserRole.Admin : UserRole.Dietitian;
            await database.SaveChangesAsync();
            using var response = await client.GetAsync(Route);
            await AssertError(response, HttpStatusCode.Unauthorized, "unauthenticated");
        }
    }

    [PostgresFact]
    public async Task AccountNameAndEmailComeFromCurrentOwnedDatabaseRecords()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync();
        var account = await Seed(factory, "old@example.test", "Synthetic old");
        using var client = factory.Client();
        await Login(client, "old@example.test");
        await using var database = factory.Database();
        var user = await database.Users.Include(value => value.ClientProfile).SingleAsync(value => value.Id == account.Id);
        database.Entry(user).Property(value => value.Email).CurrentValue = "UPDATED@EXAMPLE.TEST";
        database.Entry(user.ClientProfile!).Property(value => value.DisplayName).CurrentValue = "Synthetic updated";
        await database.SaveChangesAsync();
        using var response = await client.GetAsync(Route);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal(account.Id, json.RootElement.GetProperty("id").GetGuid());
        Assert.Equal("Synthetic updated", json.RootElement.GetProperty("displayName").GetString());
        Assert.Equal("UPDATED@EXAMPLE.TEST", json.RootElement.GetProperty("email").GetString());
    }

    private static async Task<(Guid Id, Guid? ProfileId)> Seed(RegistrationApiFactory factory, string email,
        string? displayName, UserRole role = UserRole.Client)
    {
        await using var database = factory.Database();
        var user = new User(Guid.NewGuid(), email.ToUpperInvariant(), role, Password, DateTimeOffset.UtcNow, new PasswordHasher<User>());
        var profile = displayName is null ? null : new ClientProfile(Guid.NewGuid(), user, displayName);
        database.Users.Add(user);
        database.Entry(user).Property(value => value.IsEmailVerified).CurrentValue = true;
        await database.SaveChangesAsync();
        return (user.Id, profile?.Id);
    }

    private static async Task<string> Login(HttpClient client, string email)
    {
        using var response = await client.PostAsJsonAsync("/api/v1/auth/login", new { email, password = Password });
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var token = json.RootElement.GetProperty("accessToken").GetString()!;
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return token;
    }

    private static string Sign(JwtTestSettings settings, Guid userId, bool expired = false, bool wrongKey = false, string role = "client")
    {
        var now = DateTime.UtcNow;
        return new JsonWebTokenHandler().CreateToken(new SecurityTokenDescriptor
        {
            Issuer = settings.Issuer, Audience = settings.Audience,
            Claims = new Dictionary<string, object> { ["sub"] = userId.ToString("D"), ["role"] = role },
            IssuedAt = now.AddMinutes(-20), NotBefore = now.AddMinutes(-20),
            Expires = expired ? now.AddSeconds(-1) : now.AddMinutes(15), TokenType = "at+jwt",
            SigningCredentials = new SigningCredentials((wrongKey ? new JwtTestSettings() : settings).Options.CreateSigningKey(), SecurityAlgorithms.HmacSha256)
        });
    }

    private static async Task AssertError(HttpResponseMessage response, HttpStatusCode status, string code)
    {
        Assert.Equal(status, response.StatusCode);
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal(code, json.RootElement.GetProperty("error").GetProperty("code").GetString());
        Assert.False(string.IsNullOrWhiteSpace(json.RootElement.GetProperty("requestId").GetString()));
        Assert.Equal(2, json.RootElement.EnumerateObject().Count());
    }
}
