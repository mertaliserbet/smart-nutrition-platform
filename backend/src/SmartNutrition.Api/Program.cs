using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using SmartNutrition.Api.Data;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Health;
using SmartNutrition.Api.Infrastructure;

var builder = WebApplication.CreateBuilder(args);

// Password hashing only: no sign-in scheme, cookies, tokens or Identity endpoints.
builder.Services.AddScoped<IPasswordHasher<User>, PasswordHasher<User>>();
builder.Services.AddSingleton<ILookupNormalizer, UpperInvariantLookupNormalizer>();
builder.Services.AddOptions<RegistrationPasswordPolicy>()
    .Bind(builder.Configuration.GetSection(RegistrationPasswordPolicy.SectionName));
builder.Services.AddScoped<UserRegistrationService>();

builder.Services.AddControllers()
    .AddJsonOptions(options =>
    {
        options.JsonSerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
        options.JsonSerializerOptions.UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow;
    })
    .ConfigureApiBehaviorOptions(options =>
    {
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
    options.UseNpgsql(
        builder.Configuration.GetConnectionString("DefaultConnection"),
        postgres => postgres.MigrationsHistoryTable("__ef_migrations_history")));
builder.Services.AddHealthChecks()
    .AddCheck<PostgresHealthCheck>("postgresql", tags: ["ready"], timeout: TimeSpan.FromSeconds(5));

if (builder.Environment.IsDevelopment())
{
    builder.Services.AddOpenApi("v1");
}

var app = builder.Build();

app.UseExceptionHandler(handler => handler.Run(context =>
    ApiErrors.WriteAsync(context, StatusCodes.Status500InternalServerError)));
app.UseStatusCodePages(context =>
    ApiErrors.WriteAsync(context.HttpContext, context.HttpContext.Response.StatusCode));
app.UseHttpsRedirection();

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
