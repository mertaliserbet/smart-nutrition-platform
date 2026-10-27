using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Npgsql;
using SmartNutrition.Api.Data;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Health;
using SmartNutrition.Api.Infrastructure;

var builder = WebApplication.CreateBuilder(args);

// Reuse Identity password hashing without adding default Identity endpoints or tables.
builder.Services.AddScoped<IPasswordHasher<User>, PasswordHasher<User>>();
builder.Services.AddSingleton<ILookupNormalizer, UpperInvariantLookupNormalizer>();
builder.Services.AddOptions<RegistrationPasswordPolicy>()
    .Bind(builder.Configuration.GetSection(RegistrationPasswordPolicy.SectionName));
builder.Services.AddScoped<UserRegistrationService>();
builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddJwtAuthentication(builder.Configuration);
builder.Services.AddWebSessionAuthentication(builder.Configuration, builder.Environment);
builder.Services.AddScoped<UserLoginService>();
builder.Services.AddScoped<CurrentUserService>();
builder.Services.AddSingleton<LoginPasswordVerifier>();
builder.Services.AddOptions<LoginOptions>().Bind(builder.Configuration.GetSection(LoginOptions.SectionName))
    .Validate(options => options.RequestsPerMinute > 0).ValidateOnStart();
builder.Services.AddOptions<EmailVerificationOptions>()
    .Bind(builder.Configuration.GetSection(EmailVerificationOptions.SectionName))
    .Validate(options => options.ResendCooldownSeconds > 0 && options.ResendRequestsPerMinute > 0 && options.QueueCapacity > 0)
    .ValidateOnStart();
builder.Services.AddOptions<SmtpOptions>().Bind(builder.Configuration.GetSection(SmtpOptions.SectionName));
builder.Services.AddScoped<IVerificationEmailSender, SmtpVerificationEmailSender>();
builder.Services.AddScoped<EmailVerificationService>();
builder.Services.AddSingleton<VerificationEmailQueue>();
builder.Services.AddHostedService(services => services.GetRequiredService<VerificationEmailQueue>());
builder.Services.AddRateLimiter(options =>
{
    var settings = builder.Configuration.GetSection(EmailVerificationOptions.SectionName).Get<EmailVerificationOptions>() ?? new();
    options.OnRejected = (context, _) => new ValueTask(ApiErrors.WriteAsync(context.HttpContext, StatusCodes.Status429TooManyRequests));
    options.AddPolicy("resend-verification", context => RateLimitPartition.GetFixedWindowLimiter(
        context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
        _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = settings.ResendRequestsPerMinute, Window = TimeSpan.FromMinutes(1),
            QueueLimit = 0, AutoReplenishment = true
        }));
    var loginSettings = builder.Configuration.GetSection(LoginOptions.SectionName).Get<LoginOptions>() ?? new();
    options.AddPolicy("login", context => RateLimitPartition.GetFixedWindowLimiter(
        context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
        _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = loginSettings.RequestsPerMinute, Window = TimeSpan.FromMinutes(1),
            QueueLimit = 0, AutoReplenishment = true
        }));
    var webSettings = builder.Configuration.GetSection(WebSessionOptions.SectionName).Get<WebSessionOptions>() ?? new();
    options.AddPolicy("csrf", context => RateLimitPartition.GetFixedWindowLimiter(
        context.Connection.RemoteIpAddress?.ToString() ?? "unknown", _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = webSettings.CsrfRequestsPerMinute, Window = TimeSpan.FromMinutes(1),
            QueueLimit = 0, AutoReplenishment = true
        }));
});

builder.Services.AddControllers()
    .AddJsonOptions(options =>
    {
        options.JsonSerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
        options.JsonSerializerOptions.UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow;
    })
    .ConfigureApiBehaviorOptions(options =>
    {
        // Keep MVC status errors (including unsupported media type) in the shared error envelope.
        options.SuppressMapClientErrors = true;
        options.InvalidModelStateResponseFactory = context =>
            new Microsoft.AspNetCore.Mvc.BadRequestObjectResult(
                ApiErrors.Create(context.HttpContext, StatusCodes.Status400BadRequest));
    });
builder.Services.ConfigureHttpJsonOptions(options =>
{
    options.SerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
    options.SerializerOptions.UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow;
});

builder.Services.AddDbContext<AppDbContext>(options =>
{
    var connectionString = builder.Configuration.GetConnectionString("DefaultConnection");
    if (!string.IsNullOrWhiteSpace(connectionString))
        connectionString = new NpgsqlConnectionStringBuilder(connectionString) { IncludeErrorDetail = false }.ConnectionString;
    options.UseNpgsql(
        connectionString,
        postgres => postgres.MigrationsHistoryTable("__ef_migrations_history"))
        .EnableSensitiveDataLogging(false);
});
builder.Services.AddHealthChecks()
    .AddCheck<PostgresHealthCheck>("postgresql", tags: ["ready"], timeout: TimeSpan.FromSeconds(5));

if (builder.Environment.IsDevelopment())
{
    builder.Services.AddOpenApi("v1");
}

var app = builder.Build();

app.Use(async (context, next) =>
{
    if (context.Request.Path.StartsWithSegments("/api/v1/auth", StringComparison.OrdinalIgnoreCase))
        context.Response.OnStarting(() =>
        {
            context.Response.Headers.CacheControl = "no-store";
            return Task.CompletedTask;
        });
    await next(context);
});
app.UseExceptionHandler(handler => handler.Run(context =>
{
    var status = context.Features.Get<IExceptionHandlerFeature>()?.Error is BadHttpRequestException
        { StatusCode: StatusCodes.Status413PayloadTooLarge }
        ? StatusCodes.Status413PayloadTooLarge
        : StatusCodes.Status500InternalServerError;
    return ApiErrors.WriteAsync(context, status);
}));
app.UseStatusCodePages(context =>
    ApiErrors.WriteAsync(context.HttpContext, context.HttpContext.Response.StatusCode));
app.Use(WebSessionAuthentication.GuardAsync);
app.UseHttpsRedirection();
app.UseRateLimiter();
app.UseAuthentication();
app.UseAuthorization();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
    app.UseSwaggerUI(options =>
        options.SwaggerEndpoint("/openapi/v1.json", "Smart Nutrition API v1"));
}

// Infrastructure probes are separate from the versioned business API.
app.MapHealthChecks("/health/live", new HealthCheckOptions { Predicate = _ => false });
app.MapHealthChecks("/health/ready", new HealthCheckOptions
{
    Predicate = registration => registration.Tags.Contains("ready")
});
app.MapControllers();

app.Run();

// Allows the integration test host to reference the minimal hosting entry point.
public partial class Program { }
