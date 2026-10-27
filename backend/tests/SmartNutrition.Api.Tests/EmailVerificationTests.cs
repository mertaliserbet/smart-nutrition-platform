using System.ComponentModel.DataAnnotations;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Options;
using SmartNutrition.Api.Data;
using SmartNutrition.Api.Data.Migrations;
using SmartNutrition.Api.Features.Auth;

namespace SmartNutrition.Api.Tests;

public sealed class EmailVerificationTests
{
    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData(" ")]
    [InlineData("not-an-email")]
    public void ResendRejectsInvalidAddresses(string? email)
    {
        var request = new ResendVerificationRequest { Email = email };
        Assert.NotEmpty(request.Validate(new ValidationContext(request)));
    }

    [Fact]
    public void SensitiveRequestFieldsAreInputOnlyAndUnknownFieldsAreRejected()
    {
        const string token = "synthetic-sensitive-token";
        var request = JsonSerializer.Deserialize<VerifyEmailRequest>($$"""{"token":"{{token}}"}""", JsonSerializerOptions.Web)!;
        Assert.Equal(token, request.Token);
        Assert.DoesNotContain(token, JsonSerializer.Serialize(request, JsonSerializerOptions.Web));
        Assert.DoesNotContain(token, request.ToString());
        Assert.DoesNotContain("synthetic@example.test", JsonSerializer.Serialize(
            new ResendVerificationRequest { Email = "synthetic@example.test" }, JsonSerializerOptions.Web));
        Assert.Throws<JsonException>(() => JsonSerializer.Deserialize<VerifyEmailRequest>("{}", JsonSerializerOptions.Web));
        Assert.Throws<JsonException>(() => JsonSerializer.Deserialize<VerifyEmailRequest>(
            "{\"token\":\"synthetic\",\"userId\":\"synthetic\"}", JsonSerializerOptions.Web));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("short")]
    [InlineData("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA+")]
    [InlineData("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA ")]
    public async Task InvalidTokenShapesAreRejectedBeforeDatabaseAccess(string? token)
    {
        await using var database = new AppDbContext(new DbContextOptionsBuilder<AppDbContext>().UseNpgsql().Options);
        var service = new EmailVerificationService(database, new UpperInvariantLookupNormalizer(),
            new UnusedSender(), TimeProvider.System, Options.Create(new EmailVerificationOptions()));
        Assert.False(await service.VerifyAsync(token));
    }

    [Theory]
    [InlineData("Production", "127.0.0.1")]
    [InlineData("Development", "smtp.example.test")]
    public async Task PlaintextSmtpIsRefusedOutsideLoopbackDevelopment(string environment, string host)
    {
        var sender = new SmtpVerificationEmailSender(Options.Create(new SmtpOptions
        {
            Host = host, Port = 1025, FromAddress = "synthetic@example.test", TlsMode = "None"
        }), new TestEnvironment(environment));
        await Assert.ThrowsAsync<InvalidOperationException>(() => sender.SendAsync("synthetic@example.test", "synthetic-token", default));
    }

    [Fact]
    public void MigrationAddsOnlyNullableVerificationMetadataAndIntegrityConstraints()
    {
        var operations = new AddEmailVerificationTokens().UpOperations;
        var columns = operations.OfType<Microsoft.EntityFrameworkCore.Migrations.Operations.AddColumnOperation>().ToArray();
        Assert.Equal(3, columns.Length);
        Assert.All(columns, column => { Assert.True(column.IsNullable); Assert.Equal("users", column.Table); });
        Assert.All(operations, operation => Assert.True(operation is
            Microsoft.EntityFrameworkCore.Migrations.Operations.AddColumnOperation or
            Microsoft.EntityFrameworkCore.Migrations.Operations.CreateIndexOperation or
            Microsoft.EntityFrameworkCore.Migrations.Operations.AddCheckConstraintOperation));
    }

    private sealed class UnusedSender : IVerificationEmailSender
    {
        public Task SendAsync(string recipient, string token, CancellationToken cancellationToken) =>
            throw new InvalidOperationException("No email expected.");
    }

    private sealed class TestEnvironment(string name) : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = name;
        public string ApplicationName { get; set; } = "Synthetic test";
        public string ContentRootPath { get; set; } = "";
        public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
    }
}
