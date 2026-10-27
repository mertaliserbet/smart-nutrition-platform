using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using SmartNutrition.Api.Data;
using SmartNutrition.Api.Features.Auth;

namespace SmartNutrition.Api.Tests;

public sealed class InfrastructureTests
{
    [Theory]
    [InlineData("Auth:Jwt:Issuer")]
    [InlineData("Auth:Jwt:Audience")]
    [InlineData("Auth:Jwt:SigningKeyBase64")]
    public async Task MissingJwtConfigurationFailsClosedBeforeServingRequests(string missingSetting)
    {
        await using var factory = new ApiFactory(missingJwtSetting: missingSetting);
        Assert.Throws<OptionsValidationException>(() => factory.CreateClient());
    }

    [Theory]
    [InlineData("verify-email", "token")]
    [InlineData("resend-verification", "email")]
    [InlineData("login", "email")]
    public async Task OversizedVerificationRequestsReturnShared413OnRealKestrel(string route, string field)
    {
        // TestServer does not enforce Kestrel's request-size feature.
        await using var factory = new ApiFactory();
        factory.UseKestrel(0);
        using var client = factory.CreateClient();
        using var response = await client.PostAsJsonAsync("/api/v1/auth/" + route,
            new Dictionary<string, string> { [field] = new('A', 5000) });
        Assert.Equal(HttpStatusCode.RequestEntityTooLarge, response.StatusCode);
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal("payload_too_large", body.RootElement.GetProperty("error").GetProperty("code").GetString());
        Assert.False(string.IsNullOrWhiteSpace(body.RootElement.GetProperty("requestId").GetString()));
    }

    [Fact]
    public async Task Liveness_DoesNotRequireDatabaseConfiguration()
    {
        await using var factory = new ApiFactory();
        using var client = CreateClient(factory);
        using var response = await client.GetAsync("/health/live");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("Healthy", await response.Content.ReadAsStringAsync());
    }

    [Fact]
    public async Task Readiness_IsUnavailableWhenDatabaseIsNotConfigured()
    {
        await using var factory = new ApiFactory();
        using var client = CreateClient(factory);
        using var response = await client.GetAsync("/health/ready");

        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        Assert.Equal("Unhealthy", await response.Content.ReadAsStringAsync());
    }

    [Fact]
    public async Task Readiness_IsUnavailableWhenPostgresCannotBeReached()
    {
        // Synthetic loopback target; no real credentials or health data.
        const string connection = "Host=127.0.0.1;Port=1;Database=synthetic_test;Timeout=1;CommandTimeout=1";
        await using var factory = new ApiFactory(connectionString: connection);
        using var client = CreateClient(factory);
        using var response = await client.GetAsync("/health/ready");

        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        Assert.Equal("Unhealthy", await response.Content.ReadAsStringAsync());
    }

    [Fact]
    public async Task Context_UsesPostgresWithOnlyTheAuthFoundationAndIdentityPasswordHasher()
    {
        await using var factory = new ApiFactory();
        await using var scope = factory.Services.CreateAsyncScope();
        var database = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        Assert.Equal("Npgsql.EntityFrameworkCore.PostgreSQL", database.Database.ProviderName);
        Assert.Equal([typeof(AuthSession).FullName!, typeof(ClientProfile).FullName!, typeof(User).FullName!],
            database.Model.GetEntityTypes().Select(entity => entity.Name).Order().ToArray());
        Assert.Collection(database.Database.GetMigrations(),
            migration => Assert.EndsWith("_AddAuthFoundation", migration),
            migration => Assert.EndsWith("_EnforceCaseInsensitiveEmails", migration),
            migration => Assert.EndsWith("_AddUserEmailVerificationState", migration),
            migration => Assert.EndsWith("_AddEmailVerificationTokens", migration),
            migration => Assert.EndsWith("_AddWebAuthSessions", migration));
        Assert.IsType<PasswordHasher<User>>(scope.ServiceProvider.GetRequiredService<IPasswordHasher<User>>());
        Assert.IsType<UpperInvariantLookupNormalizer>(scope.ServiceProvider.GetRequiredService<ILookupNormalizer>());
        Assert.NotNull(scope.ServiceProvider.GetRequiredService<UserRegistrationService>());
    }

    [PostgresFact]
    [Trait("Category", "PostgreSQL")]
    public async Task ConfiguredPostgres_CanExecuteQueryAndPassReadiness()
    {
        var connection = Environment.GetEnvironmentVariable(PostgresFactAttribute.ConnectionVariable);
        await using var factory = new ApiFactory(connectionString: connection);
        await using var scope = factory.Services.CreateAsyncScope();
        var database = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        Assert.True(await database.Database.CanConnectAsync());
        await database.Database.OpenConnectionAsync();
        await using (var command = database.Database.GetDbConnection().CreateCommand())
        {
            command.CommandText = "SELECT 1";
            command.CommandTimeout = 5;
            Assert.Equal(1, await command.ExecuteScalarAsync());
        }
        await database.Database.CloseConnectionAsync();

        using var client = CreateClient(factory);
        using var response = await client.GetAsync("/health/ready");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("Healthy", await response.Content.ReadAsStringAsync());
    }

    [Fact]
    public async Task OpenApiAndSwagger_AreAvailableInDevelopment()
    {
        await using var factory = new ApiFactory("Development");
        using var client = CreateClient(factory);
        using var response = await client.GetAsync("/openapi/v1.json");
        response.EnsureSuccessStatusCode();
        using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.StartsWith("3.", document.RootElement.GetProperty("openapi").GetString());
        var paths = document.RootElement.GetProperty("paths");
        Assert.Equal(7, paths.EnumerateObject().Count());
        Assert.True(paths.GetProperty("/api/v1/auth/csrf").TryGetProperty("get", out _));
        var webSession = paths.GetProperty("/api/v1/auth/web-session");
        Assert.True(webSession.TryGetProperty("post", out _));
        Assert.True(webSession.TryGetProperty("delete", out _));
        var currentUser = paths.GetProperty("/api/v1/auth/me").GetProperty("get");
        Assert.False(currentUser.TryGetProperty("requestBody", out _));
        var currentUserSchema = currentUser.GetProperty("responses").GetProperty("200").GetProperty("content")
            .GetProperty("application/json").GetProperty("schema");
        if (currentUserSchema.TryGetProperty("$ref", out var currentUserReference))
            currentUserSchema = document.RootElement.GetProperty("components").GetProperty("schemas")
                .GetProperty(currentUserReference.GetString()!.Split('/').Last());
        Assert.Equal(["displayName", "email", "id", "isEmailVerified", "role"],
            currentUserSchema.GetProperty("properties").EnumerateObject().Select(field => field.Name).Order().ToArray());
        var login = paths.GetProperty("/api/v1/auth/login").GetProperty("post");
        var loginSchema = login.GetProperty("requestBody").GetProperty("content").GetProperty("application/json").GetProperty("schema");
        if (loginSchema.TryGetProperty("$ref", out var loginReference))
            loginSchema = document.RootElement.GetProperty("components").GetProperty("schemas")
                .GetProperty(loginReference.GetString()!.Split('/').Last());
        Assert.Equal(["email", "password"], loginSchema.GetProperty("properties").EnumerateObject().Select(field => field.Name).Order().ToArray());
        Assert.Equal(["email", "password"], loginSchema.GetProperty("required").EnumerateArray().Select(field => field.GetString()!).Order().ToArray());
        var loginResponse = login.GetProperty("responses").GetProperty("200").GetProperty("content").GetProperty("application/json").GetProperty("schema");
        if (loginResponse.TryGetProperty("$ref", out var responseReference))
            loginResponse = document.RootElement.GetProperty("components").GetProperty("schemas")
                .GetProperty(responseReference.GetString()!.Split('/').Last());
        Assert.Equal(["accessToken", "expiresAt", "tokenType"], loginResponse.GetProperty("properties").EnumerateObject().Select(field => field.Name).Order().ToArray());
        Assert.True(paths.GetProperty("/api/v1/auth/verify-email").TryGetProperty("post", out _));
        Assert.True(paths.GetProperty("/api/v1/auth/resend-verification").TryGetProperty("post", out _));
        foreach (var (route, input, success) in new[]
        {
            ("verify-email", "token", "204"), ("resend-verification", "email", "202")
        })
        {
            var operation = paths.GetProperty("/api/v1/auth/" + route).GetProperty("post");
            Assert.True(operation.GetProperty("responses").TryGetProperty(success, out _));
            var schema = operation.GetProperty("requestBody").GetProperty("content").GetProperty("application/json").GetProperty("schema");
            if (schema.TryGetProperty("$ref", out var schemaReference))
                schema = document.RootElement.GetProperty("components").GetProperty("schemas")
                    .GetProperty(schemaReference.GetString()!.Split('/').Last());
            Assert.Equal(input, Assert.Single(schema.GetProperty("properties").EnumerateObject()).Name);
            Assert.Contains(schema.GetProperty("required").EnumerateArray(), required => required.GetString() == input);
        }
        var registration = paths.EnumerateObject().Single(path => path.Name == "/api/v1/auth/register");
        Assert.Equal("/api/v1/auth/register", registration.Name);
        Assert.True(registration.Value.TryGetProperty("post", out _));
        var requestSchema = registration.Value.GetProperty("post").GetProperty("requestBody")
            .GetProperty("content").GetProperty("application/json").GetProperty("schema");
        if (requestSchema.TryGetProperty("$ref", out var reference))
            requestSchema = document.RootElement.GetProperty("components").GetProperty("schemas")
                .GetProperty(reference.GetString()!.Split('/').Last());
        foreach (var field in new[] { "email", "password", "displayName", "role" })
            Assert.True(requestSchema.GetProperty("properties").TryGetProperty(field, out _), $"Missing registration input: {field}");
        foreach (var field in new[] { "email", "password", "displayName" })
            Assert.Contains(requestSchema.GetProperty("required").EnumerateArray(), required => required.GetString() == field);
        using var swagger = await client.GetAsync("/swagger/index.html");
        Assert.Equal(HttpStatusCode.OK, swagger.StatusCode);
        Assert.Contains("Swagger UI", await swagger.Content.ReadAsStringAsync());
    }

    [Theory]
    [InlineData("/openapi/v1.json")]
    [InlineData("/swagger/index.html")]
    public async Task Documentation_IsNotExposedInProduction(string path)
    {
        await using var factory = new ApiFactory();
        using var client = CreateClient(factory);
        using var response = await client.GetAsync(path);

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Theory]
    [InlineData("/api/v1/meal-logs")]
    [InlineData("/weatherforecast")]
    public async Task UnimplementedRoutes_UseTheSharedErrorFormat(string path)
    {
        await using var factory = new ApiFactory();
        using var client = CreateClient(factory);
        using var response = await client.GetAsync(path);
        using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        Assert.Equal("not_found", document.RootElement.GetProperty("error").GetProperty("code").GetString());
        Assert.False(string.IsNullOrWhiteSpace(document.RootElement.GetProperty("requestId").GetString()));
        Assert.Equal(2, document.RootElement.EnumerateObject().Count());
    }

    private static HttpClient CreateClient(ApiFactory factory) => factory.CreateClient(
        new WebApplicationFactoryClientOptions
        {
            BaseAddress = new Uri("https://localhost"),
            AllowAutoRedirect = false
        });

    private sealed class ApiFactory(
        string environment = "Production",
        string? connectionString = null, string? missingJwtSetting = null) : WebApplicationFactory<Program>
    {
        private readonly JwtTestSettings _jwt = new();
        protected override void ConfigureWebHost(IWebHostBuilder builder)
        {
            builder.UseEnvironment(environment);
            builder.ConfigureAppConfiguration((_, configuration) =>
            {
                var settings = _jwt.Configuration;
                settings["ConnectionStrings:DefaultConnection"] = connectionString;
                if (missingJwtSetting is not null) settings[missingJwtSetting] = "";
                configuration.AddInMemoryCollection(settings);
            });
        }
    }
}

// Real database access is opt-in and never falls back to a developer's secrets.
public sealed class PostgresFactAttribute : FactAttribute
{
    public const string ConnectionVariable = "SMART_NUTRITION_TEST_CONNECTION_STRING";

    public PostgresFactAttribute()
    {
        if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable(ConnectionVariable)))
        {
            Skip = $"Set {ConnectionVariable} to run the real PostgreSQL check.";
        }
    }
}
