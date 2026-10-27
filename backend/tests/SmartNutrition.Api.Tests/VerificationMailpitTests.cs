using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.EntityFrameworkCore;

namespace SmartNutrition.Api.Tests;

public sealed class VerificationMailpitTests
{
    [MailpitFact]
    [Trait("Category", "Mailpit")]
    public async Task RealSmtpDeliversRegistrationAndResendEmailsAndTheirTokensVerifyThroughHttp()
    {
        var mailpitUri = new Uri(Environment.GetEnvironmentVariable("SMART_NUTRITION_TEST_MAILPIT_URL")!);
        Assert.True(mailpitUri.IsLoopback, "Use only the local development Mailpit instance.");
        using var mailpit = new HttpClient { BaseAddress = mailpitUri };
        var clock = new MailClock();
        await using var factory = await RegistrationApiFactory.CreateAsync(clock: clock, useSmtp: true);
        using var client = factory.Client();
        var email = $"synthetic-verification-{Guid.NewGuid():N}@example.test";
        var messageIds = new List<string>();
        try
        {
            using var registration = await EmailVerificationApiTests.Register(client, email);
            Assert.Equal(HttpStatusCode.Created, registration.StatusCode);
            var first = await ReadNewToken(mailpit, email, messageIds);
            Assert.DoesNotContain(first, await registration.Content.ReadAsStringAsync());
            clock.Advance(TimeSpan.FromSeconds(60));
            using var resend = await client.PostAsJsonAsync("/api/v1/auth/resend-verification", new { email });
            Assert.Equal(HttpStatusCode.Accepted, resend.StatusCode);
            Assert.Empty(await resend.Content.ReadAsStringAsync());
            var second = await ReadNewToken(mailpit, email, messageIds);
            Assert.NotEqual(first, second);
            await using var database = factory.Database();
            var user = await database.Users.SingleAsync();
            var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(second)));
            Assert.Equal(hash, user.EmailVerificationTokenHash);
            using var rotated = await client.PostAsJsonAsync("/api/v1/auth/verify-email", new { token = first });
            Assert.Equal(HttpStatusCode.UnprocessableEntity, rotated.StatusCode);
            using var verified = await client.PostAsJsonAsync("/api/v1/auth/verify-email", new { token = second });
            Assert.Equal(HttpStatusCode.NoContent, verified.StatusCode);
            using var replay = await client.PostAsJsonAsync("/api/v1/auth/verify-email", new { token = second });
            Assert.Equal(HttpStatusCode.UnprocessableEntity, replay.StatusCode);
            await database.Entry(user).ReloadAsync();
            Assert.True(user.IsEmailVerified);
            Assert.Null(user.EmailVerificationTokenHash);
            foreach (var secret in new[] { first, second, hash }) Assert.DoesNotContain(secret, factory.Logs);
        }
        finally
        {
            // Mailpit deletes every message if IDs is empty: never send an empty cleanup request.
            // Only messages for this test's random synthetic recipient are eligible.
            if (messageIds.Count > 0)
            {
                using var request = new HttpRequestMessage(HttpMethod.Delete, "/api/v1/messages")
                { Content = JsonContent.Create(new { IDs = messageIds }) };
                using var deleted = await mailpit.SendAsync(request);
                deleted.EnsureSuccessStatusCode();
            }
        }
    }

    private static async Task<string> ReadNewToken(HttpClient mailpit, string email, List<string> knownIds)
    {
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(15));
        while (true)
        {
            using var search = await mailpit.GetAsync("/api/v1/search?query=" + Uri.EscapeDataString("to:" + email), timeout.Token);
            search.EnsureSuccessStatusCode();
            using var results = JsonDocument.Parse(await search.Content.ReadAsStringAsync(timeout.Token));
            foreach (var message in results.RootElement.GetProperty("messages").EnumerateArray())
            {
                var id = message.GetProperty("ID").GetString()!;
                if (knownIds.Contains(id)) continue;
                knownIds.Add(id);
                using var response = await mailpit.GetAsync("/api/v1/message/" + Uri.EscapeDataString(id), timeout.Token);
                response.EnsureSuccessStatusCode();
                using var detail = JsonDocument.Parse(await response.Content.ReadAsStringAsync(timeout.Token));
                Assert.Contains("E-posta doğrulama", detail.RootElement.GetProperty("Subject").GetString());
                var text = detail.RootElement.GetProperty("Text").GetString()!;
                Assert.Contains("30 dakika", text);
                return Assert.Single(text.Split('\n').Select(line => line.Trim()),
                    line => Regex.IsMatch(line, "^[A-Za-z0-9_-]{43}$"));
            }
            await Task.Delay(50, timeout.Token);
        }
    }

    private sealed class MailClock : TimeProvider
    {
        private long _ticks = DateTimeOffset.UtcNow.Ticks;
        public override DateTimeOffset GetUtcNow() => new(Interlocked.Read(ref _ticks), TimeSpan.Zero);
        public void Advance(TimeSpan duration) => Interlocked.Add(ref _ticks, duration.Ticks);
    }
}

public sealed class MailpitFactAttribute : FactAttribute
{
    public MailpitFactAttribute()
    {
        if (new[] { PostgresFactAttribute.ConnectionVariable, "SMART_NUTRITION_TEST_MAILPIT_URL",
            "SMART_NUTRITION_TEST_SMTP_HOST", "SMART_NUTRITION_TEST_SMTP_PORT", "SMART_NUTRITION_TEST_SMTP_FROM" }
            .Any(key => string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable(key))))
            Skip = "Set the PostgreSQL and local Mailpit/SMTP test variables to exercise real email delivery.";
    }
}
