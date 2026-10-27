using System.Collections.Concurrent;
using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading.Channels;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using SmartNutrition.Api.Features.Auth;

namespace SmartNutrition.Api.Tests;

public sealed class EmailVerificationApiTests
{
    private const string VerifyRoute = "/api/v1/auth/verify-email";
    private const string ResendRoute = "/api/v1/auth/resend-verification";

    [PostgresFact]
    public async Task RegistrationSendsRandomTokenStoresOnlyHashAndVerificationIsSingleUse()
    {
        var clock = new TestClock();
        var sender = new CaptureSender();
        await using var factory = await RegistrationApiFactory.CreateAsync(clock: clock, sender: sender);
        using var client = factory.Client();
        using var registration = await Register(client);
        Assert.Equal(HttpStatusCode.Created, registration.StatusCode);
        var message = await sender.NextAsync();
        Assert.Equal("SYNTHETIC@EXAMPLE.TEST", message.Recipient);
        Assert.Matches("^[A-Za-z0-9_-]{43}$", message.Token);
        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(message.Token)));
        await using var database = factory.Database();
        var user = await database.Users.SingleAsync();
        Assert.Equal(hash, user.EmailVerificationTokenHash);
        Assert.Equal(clock.GetUtcNow().AddMinutes(30), user.EmailVerificationExpiresAt);
        Assert.Equal(clock.GetUtcNow(), user.EmailVerificationLastSentAt);
        Assert.False(user.IsEmailVerified);
        var serialized = JsonSerializer.Serialize(user, JsonSerializerOptions.Web);
        foreach (var hidden in new[] { "isEmailVerified", "emailVerificationTokenHash", "emailVerificationExpiresAt", "emailVerificationLastSentAt" })
            Assert.DoesNotContain(hidden, serialized);
        var responseBody = await registration.Content.ReadAsStringAsync();
        Assert.DoesNotContain(message.Token, responseBody);
        Assert.DoesNotContain(hash, responseBody);

        using var verified = await client.PostAsJsonAsync(VerifyRoute, new { token = message.Token });
        Assert.Equal(HttpStatusCode.NoContent, verified.StatusCode);
        Assert.Empty(await verified.Content.ReadAsStringAsync());
        Assert.True(verified.Headers.CacheControl?.NoStore);
        using var replay = await client.PostAsJsonAsync(VerifyRoute, new { token = message.Token });
        await AssertError(replay, HttpStatusCode.UnprocessableEntity, "validation_failed");
        await database.Entry(user).ReloadAsync();
        Assert.True(user.IsEmailVerified);
        Assert.Null(user.EmailVerificationTokenHash);
        Assert.Null(user.EmailVerificationExpiresAt);
        Assert.DoesNotContain(message.Token, factory.Logs);
        Assert.DoesNotContain(hash, factory.Logs);
    }

    [PostgresFact]
    public async Task TokenExpiresAtExactlyThirtyMinutesAndResendRotatesTheOldToken()
    {
        var clock = new TestClock();
        var sender = new CaptureSender();
        await using var factory = await RegistrationApiFactory.CreateAsync(clock: clock, sender: sender);
        using var client = factory.Client();
        using var registration = await Register(client);
        var first = await sender.NextAsync();
        clock.Advance(TimeSpan.FromMinutes(30));
        using var expired = await client.PostAsJsonAsync(VerifyRoute, new { token = first.Token });
        await AssertError(expired, HttpStatusCode.UnprocessableEntity, "validation_failed");

        await Send(factory, "synthetic@example.test");
        var second = await sender.NextAsync();
        Assert.NotEqual(first.Token, second.Token);
        using var old = await client.PostAsJsonAsync(VerifyRoute, new { token = first.Token });
        Assert.Equal(HttpStatusCode.UnprocessableEntity, old.StatusCode);
        clock.Advance(TimeSpan.FromMinutes(30) - TimeSpan.FromTicks(10));
        using var valid = await client.PostAsJsonAsync(VerifyRoute, new { token = second.Token });
        Assert.Equal(HttpStatusCode.NoContent, valid.StatusCode);
    }

    [PostgresFact]
    public async Task CooldownAndConcurrentResendsAllowOnlyOneNewTokenAtTheBoundary()
    {
        var clock = new TestClock();
        var sender = new CaptureSender();
        await using var factory = await RegistrationApiFactory.CreateAsync(clock: clock, sender: sender);
        using var client = factory.Client();
        using var registration = await Register(client);
        var first = await sender.NextAsync();
        clock.Advance(TimeSpan.FromSeconds(59));
        await Send(factory, "synthetic@example.test");
        Assert.Single(sender.Messages);
        clock.Advance(TimeSpan.FromSeconds(1));
        await Task.WhenAll(Send(factory, "synthetic@example.test"), Send(factory, "  SYNTHETIC@example.TEST  "));
        var second = await sender.NextAsync();
        Assert.Equal(2, sender.Messages.Count);
        Assert.NotEqual(first.Token, second.Token);
        using var invalidated = await client.PostAsJsonAsync(VerifyRoute, new { token = first.Token });
        Assert.Equal(HttpStatusCode.UnprocessableEntity, invalidated.StatusCode);
        await Send(factory, "unknown@example.test");
        Assert.Equal(2, sender.Messages.Count);
    }

    [PostgresFact]
    public async Task ConcurrentVerificationConsumesTokenOnlyOnce()
    {
        var sender = new CaptureSender();
        await using var factory = await RegistrationApiFactory.CreateAsync(sender: sender);
        using var client = factory.Client();
        using var registration = await Register(client);
        var message = await sender.NextAsync();
        var responses = await Task.WhenAll(client.PostAsJsonAsync(VerifyRoute, new { token = message.Token }),
            client.PostAsJsonAsync(VerifyRoute, new { token = message.Token }));
        try
        {
            Assert.Single(responses, response => response.StatusCode == HttpStatusCode.NoContent);
            Assert.Single(responses, response => response.StatusCode == HttpStatusCode.UnprocessableEntity);
        }
        finally { foreach (var response in responses) response.Dispose(); }
    }

    [PostgresFact]
    public async Task ResendIsNeutralForUnknownCoolingDownAndVerifiedAccountsAndHasAnIpLimit()
    {
        var sender = new CaptureSender();
        await using var factory = await RegistrationApiFactory.CreateAsync(sender: sender);
        using var client = factory.Client();
        using var registration = await Register(client);
        var message = await sender.NextAsync();
        foreach (var email in new[] { "unknown@example.test", "synthetic@example.test" })
        {
            using var response = await client.PostAsJsonAsync(ResendRoute, new { email });
            Assert.Equal(HttpStatusCode.Accepted, response.StatusCode);
            Assert.Empty(await response.Content.ReadAsStringAsync());
        }
        using var verify = await client.PostAsJsonAsync(VerifyRoute, new { token = message.Token });
        Assert.Equal(HttpStatusCode.NoContent, verify.StatusCode);
        foreach (var email in new[] { "synthetic@example.test", "unknown@example.test", "another@example.test" })
        {
            using var response = await client.PostAsJsonAsync(ResendRoute, new { email });
            Assert.Equal(HttpStatusCode.Accepted, response.StatusCode);
            Assert.Empty(await response.Content.ReadAsStringAsync());
        }
        using var limited = await client.PostAsJsonAsync(ResendRoute, new { email = "unknown@example.test" });
        await AssertError(limited, HttpStatusCode.TooManyRequests, "rate_limited");
    }

    [PostgresFact]
    public async Task InvalidBodiesAndUnknownTokensReturnSharedErrorsWithoutEchoingInputs()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync();
        using var client = factory.Client();
        foreach (var json in new[] { "{}", "{", "null", "{\"token\":123}", "{\"token\":\"sensitive\",\"userId\":\"synthetic\"}" })
        {
            using var response = await client.PostAsync(VerifyRoute, new StringContent(json, Encoding.UTF8, "application/json"));
            await AssertError(response, HttpStatusCode.BadRequest, "invalid_request");
        }
        foreach (var token in new[] { null, "", "sensitive-invalid-token", new string('A', 43) })
        {
            using var response = await client.PostAsJsonAsync(VerifyRoute, new { token });
            await AssertError(response, HttpStatusCode.UnprocessableEntity, "validation_failed");
            Assert.DoesNotContain("sensitive-invalid-token", await response.Content.ReadAsStringAsync());
        }
        using var invalidEmail = await client.PostAsJsonAsync(ResendRoute, new { email = "invalid" });
        await AssertError(invalidEmail, HttpStatusCode.BadRequest, "invalid_request");
    }

    [PostgresFact]
    public async Task SmtpFailureDoesNotUndoRegistrationExposeTokenOrChangeResendResponse()
    {
        var sender = new CaptureSender(fail: true);
        await using var factory = await RegistrationApiFactory.CreateAsync(sender: sender);
        using var client = factory.Client();
        using var registration = await Register(client);
        Assert.Equal(HttpStatusCode.Created, registration.StatusCode);
        var message = await sender.NextAsync();
        await WaitUntil(() => factory.Logs.Contains("Verification email delivery failed", StringComparison.Ordinal));
        await using var database = factory.Database();
        var user = await database.Users.SingleAsync();
        Assert.False(user.IsEmailVerified);
        Assert.NotNull(user.EmailVerificationTokenHash);
        Assert.DoesNotContain(message.Token, factory.Logs);
        using var resend = await client.PostAsJsonAsync(ResendRoute, new { email = "synthetic@example.test" });
        Assert.Equal(HttpStatusCode.Accepted, resend.StatusCode);
        Assert.Empty(await resend.Content.ReadAsStringAsync());
    }

    internal static Task<HttpResponseMessage> Register(HttpClient client, string email = "synthetic@example.test") =>
        client.PostAsJsonAsync("/api/v1/auth/register", new { email, password = "sentetik parola", displayName = "Synthetic client" });

    private static async Task Send(RegistrationApiFactory factory, string email)
    {
        await using var scope = factory.Services.CreateAsyncScope();
        await scope.ServiceProvider.GetRequiredService<EmailVerificationService>().SendAsync(email);
    }

    private static async Task AssertError(HttpResponseMessage response, HttpStatusCode status, string code)
    {
        Assert.Equal(status, response.StatusCode);
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal(code, json.RootElement.GetProperty("error").GetProperty("code").GetString());
        Assert.False(string.IsNullOrWhiteSpace(json.RootElement.GetProperty("requestId").GetString()));
    }

    private static async Task WaitUntil(Func<bool> predicate)
    {
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        while (!predicate()) await Task.Delay(20, timeout.Token);
    }

    private sealed class TestClock : TimeProvider
    {
        private long _ticks = new DateTimeOffset(2026, 10, 27, 12, 0, 0, TimeSpan.Zero).Ticks;
        public override DateTimeOffset GetUtcNow() => new(Interlocked.Read(ref _ticks), TimeSpan.Zero);
        public void Advance(TimeSpan duration) => Interlocked.Add(ref _ticks, duration.Ticks);
    }

    private sealed class CaptureSender(bool fail = false) : IVerificationEmailSender
    {
        private readonly Channel<(string Recipient, string Token)> _channel = Channel.CreateUnbounded<(string, string)>();
        public ConcurrentQueue<(string Recipient, string Token)> Messages { get; } = new();
        public Task SendAsync(string recipient, string token, CancellationToken cancellationToken)
        {
            Messages.Enqueue((recipient, token));
            _channel.Writer.TryWrite((recipient, token));
            // Deliberately include the secret in a transport exception to verify it never reaches logs.
            return fail ? Task.FromException(new InvalidOperationException(token)) : Task.CompletedTask;
        }
        public async Task<(string Recipient, string Token)> NextAsync()
        {
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(10));
            return await _channel.Reader.ReadAsync(timeout.Token);
        }
    }
}
