using System.Net;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Tests;

public sealed class RegistrationApiTests
{
    private const string Route = "/api/v1/auth/register";

    [PostgresFact]
    [Trait("Category", "PostgreSQL")]
    public async Task RegistrationPersistsClientAndProfileWithoutVerificationSessionOrSecrets()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync();
        using var client = factory.Client();
        const string password = " şifre 🔒 ";
        using var response = await Post(client, "  Synthetic@Example.test  ", password);
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal("id", Assert.Single(body.RootElement.EnumerateObject()).Name);
        var id = body.RootElement.GetProperty("id").GetGuid();
        Assert.False(response.Headers.Contains("Set-Cookie"));
        Assert.False(response.Headers.Contains("Authorization"));

        await using var database = factory.Database();
        var user = await database.Users.Include(account => account.ClientProfile).SingleAsync();
        Assert.Equal(id, user.Id);
        Assert.Equal("SYNTHETIC@EXAMPLE.TEST", user.Email);
        Assert.Equal(UserRole.Client, user.Role);
        Assert.False(user.IsEmailVerified);
        Assert.NotNull(user.ClientProfile);
        Assert.Equal(id, user.ClientProfile.UserId);
        Assert.NotEqual(id, user.ClientProfile.Id);
        Assert.Equal("Synthetic client", user.ClientProfile.DisplayName);
        Assert.Null(user.ClientProfile.BirthDate);
        Assert.Null(user.ClientProfile.HeightCm);
        Assert.Equal(1, await database.ClientProfiles.CountAsync());
        Assert.Equal(PasswordVerificationResult.Success,
            new PasswordHasher<User>().VerifyHashedPassword(user, user.PasswordHash, password));
        Assert.Equal(PasswordVerificationResult.Failed,
            new PasswordHasher<User>().VerifyHashedPassword(user, user.PasswordHash, password.Trim()));
        Assert.DoesNotContain(password, factory.Logs);
        Assert.DoesNotContain(user.PasswordHash, factory.Logs);
    }

    [PostgresFact]
    [Trait("Category", "PostgreSQL")]
    public async Task DuplicateNormalizedEmailReturnsSharedConflictWithoutCreatingAnotherProfile()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync();
        using var client = factory.Client();
        using var first = await Post(client, "Synthetic@Example.test");
        Assert.Equal(HttpStatusCode.Created, first.StatusCode);
        using var duplicate = await Post(client, "  synthetic@example.TEST  ");
        await AssertError(duplicate, HttpStatusCode.Conflict, "conflict");
        await using var database = factory.Database();
        Assert.Equal(1, await database.Users.CountAsync());
        Assert.Equal(1, await database.ClientProfiles.CountAsync());
    }

    [PostgresFact]
    [Trait("Category", "PostgreSQL")]
    public async Task InvalidRequestsUseSharedErrorsAndDoNotPersistAnyAccounts()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync();
        using var client = factory.Client();
        foreach (var json in new[]
        {
            "{}", "{", "null",
            "{\"email\":\"invalid\",\"password\":\"abcdefgh\",\"displayName\":\"Synthetic\"}",
            "{\"email\":\"synthetic@example.test\",\"password\":\"abcdefgh\"}",
            "{\"email\":\"synthetic@example.test\",\"password\":\"abcdefgh\",\"displayName\":\"   \"}",
            "{\"email\":\"synthetic@example.test\",\"password\":\"abcdefgh\",\"displayName\":\"Synthetic\",\"role\":\"admin\"}",
            "{\"email\":\"synthetic@example.test\",\"password\":\"abcdefgh\",\"displayName\":\"Synthetic\",\"role\":\"dietitian\"}",
            "{\"email\":\"synthetic@example.test\",\"password\":\"abcdefgh\",\"displayName\":\"Synthetic\",\"role\":0}",
            "{\"email\":\"synthetic@example.test\",\"password\":\"abcdefgh\",\"displayName\":\"Synthetic\",\"isEmailVerified\":true}",
            "{\"email\":\"synthetic@example.test\",\"password\":\"abcdefgh\",\"displayName\":\"Synthetic\",\"userId\":\"00000000-0000-0000-0000-000000000001\"}"
        })
        {
            using var content = new StringContent(json, Encoding.UTF8, "application/json");
            using var response = await client.PostAsync(Route, content);
            await AssertError(response, HttpStatusCode.BadRequest, "invalid_request");
        }
        foreach (var password in new[] { "abcdefg", new string('a', 129), string.Concat(Enumerable.Repeat("🔒", 7)) })
        {
            using var response = await Post(client, "synthetic@example.test", password);
            await AssertError(response, HttpStatusCode.UnprocessableEntity, "validation_failed");
        }
        using var unsupported = await client.PostAsync(Route, new StringContent("Synthetic plaintext"));
        await AssertError(unsupported, HttpStatusCode.UnsupportedMediaType, "unsupported_media_type");
        await using var database = factory.Database();
        Assert.Empty(await database.Users.ToListAsync());
        Assert.Empty(await database.ClientProfiles.ToListAsync());
    }

    [PostgresFact]
    [Trait("Category", "PostgreSQL")]
    public async Task SpaceOnlyAndBoundaryUnicodePasswordsAreAcceptedWithoutExtraCharacterRules()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync();
        using var client = factory.Client();
        foreach (var password in new[] { "        ", new string('a', 128), string.Concat(Enumerable.Repeat("🔒", 128)) })
        {
            using var response = await Post(client, $"synthetic-{Guid.NewGuid():N}@example.test", password);
            Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        }
        await using var database = factory.Database();
        Assert.Equal(3, await database.Users.CountAsync());
        Assert.Equal(3, await database.ClientProfiles.CountAsync());
    }

    [PostgresFact]
    [Trait("Category", "PostgreSQL")]
    public async Task ConcurrentRequestsReturnOneCreatedAndOneConflictAfterBothPrechecksPass()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(new ConcurrentSaveGate());
        using var client = factory.Client();
        var responses = await Task.WhenAll(Post(client, "Synthetic@Example.test"), Post(client, "synthetic@example.TEST"));
        try
        {
            Assert.Equal(1, responses.Count(response => response.StatusCode == HttpStatusCode.Created));
            await AssertError(Assert.Single(responses, response => response.StatusCode == HttpStatusCode.Conflict),
                HttpStatusCode.Conflict, "conflict");
            await using var database = factory.Database();
            Assert.Equal(1, await database.Users.CountAsync());
            Assert.Equal(1, await database.ClientProfiles.CountAsync());
            var hash = await database.Users.Select(user => user.PasswordHash).SingleAsync();
            Assert.DoesNotContain(hash, factory.Logs);
            Assert.DoesNotContain("synthetic-pass", factory.Logs);
        }
        finally { foreach (var response in responses) response.Dispose(); }
    }

    [PostgresFact]
    [Trait("Category", "PostgreSQL")]
    public async Task ProfileInsertFailureRollsBackTheAccountAndReturnsASanitizedServerError()
    {
        var failure = new InvalidProfileAtSave();
        await using var factory = await RegistrationApiFactory.CreateAsync(failure);
        using var client = factory.Client();
        using var response = await Post(client, "synthetic@example.test");
        await AssertError(response, HttpStatusCode.InternalServerError, "internal_error");
        await using var database = factory.Database();
        Assert.Equal(0, await database.Users.CountAsync());
        Assert.Equal(0, await database.ClientProfiles.CountAsync());
        Assert.DoesNotContain("synthetic-pass", factory.Logs);
        Assert.False(string.IsNullOrEmpty(failure.CapturedHash));
        Assert.DoesNotContain(failure.CapturedHash, factory.Logs);
        Assert.DoesNotContain(failure.CapturedHash, await response.Content.ReadAsStringAsync());
    }

    private static Task<HttpResponseMessage> Post(HttpClient client, string email, string password = "synthetic-pass") =>
        client.PostAsJsonAsync(Route, new { email, password, displayName = "Synthetic client" });

    private static async Task AssertError(HttpResponseMessage response, HttpStatusCode status, string code)
    {
        Assert.Equal(status, response.StatusCode);
        var text = await response.Content.ReadAsStringAsync();
        using var json = JsonDocument.Parse(text);
        Assert.Equal(2, json.RootElement.EnumerateObject().Count());
        Assert.Equal(code, json.RootElement.GetProperty("error").GetProperty("code").GetString());
        Assert.False(string.IsNullOrWhiteSpace(json.RootElement.GetProperty("requestId").GetString()));
        Assert.DoesNotContain("password", text, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("synthetic-pass", text);
    }

    private sealed class ConcurrentSaveGate : SaveChangesInterceptor
    {
        private readonly TaskCompletionSource _bothArrived = new(TaskCreationOptions.RunContinuationsAsynchronously);
        private int _arrivals;
        public override async ValueTask<InterceptionResult<int>> SavingChangesAsync(DbContextEventData eventData,
            InterceptionResult<int> result, CancellationToken cancellationToken = default)
        {
            if (eventData.Context!.ChangeTracker.Entries<User>().Any(entry => entry.State == EntityState.Added))
            {
                if (Interlocked.Increment(ref _arrivals) == 2) _bothArrived.TrySetResult();
                await _bothArrived.Task.WaitAsync(TimeSpan.FromSeconds(10), cancellationToken);
            }
            return result;
        }
    }

    private sealed class InvalidProfileAtSave : SaveChangesInterceptor
    {
        public string CapturedHash { get; private set; } = "";

        public override ValueTask<InterceptionResult<int>> SavingChangesAsync(DbContextEventData eventData,
            InterceptionResult<int> result, CancellationToken cancellationToken = default)
        {
            CapturedHash = eventData.Context!.ChangeTracker.Entries<User>().Single().Entity.PasswordHash;
            foreach (var profile in eventData.Context!.ChangeTracker.Entries<ClientProfile>())
                if (profile.State == EntityState.Added)
                    profile.Property(nameof(ClientProfile.DisplayName)).CurrentValue = "";
            return ValueTask.FromResult(result);
        }
    }
}
