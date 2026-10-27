using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;
using SmartNutrition.Api.Infrastructure;

namespace SmartNutrition.Api.Features.Auth;

internal static class JwtAuthentication
{
    public static IServiceCollection AddJwtAuthentication(this IServiceCollection services, IConfiguration configuration)
    {
        services.AddOptions<JwtOptions>().Bind(configuration.GetSection(JwtOptions.SectionName))
            .Validate(options => options.IsValid(), "JWT issuer, audience and a Base64 signing key of at least 32 bytes are required.")
            .ValidateOnStart();
        services.AddScoped<JwtAccessTokenService>();
        services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer();
        services.AddOptions<JwtBearerOptions>(JwtBearerDefaults.AuthenticationScheme)
            .Configure<IOptions<JwtOptions>>((bearer, settings) =>
            {
                var jwt = settings.Value;
                bearer.MapInboundClaims = false;
                bearer.SaveToken = false;
                bearer.IncludeErrorDetails = false;
                bearer.TokenValidationParameters = new TokenValidationParameters
                {
                    ValidateIssuerSigningKey = true, IssuerSigningKey = jwt.CreateSigningKey(),
                    ValidateIssuer = true, ValidIssuer = jwt.Issuer,
                    ValidateAudience = true, RequireAudience = true, ValidAudience = jwt.Audience,
                    IgnoreTrailingSlashWhenValidatingAudience = false,
                    ValidateLifetime = true, RequireExpirationTime = true, RequireSignedTokens = true,
                    ClockSkew = TimeSpan.Zero, ValidAlgorithms = [SecurityAlgorithms.HmacSha256], ValidTypes = ["at+jwt"],
                    NameClaimType = "sub", RoleClaimType = "role", IncludeTokenOnFailedValidation = false,
                    LogTokenId = false, LogValidationExceptions = false
                };
                bearer.Events = new JwtBearerEvents
                {
                    OnTokenValidated = context =>
                    {
                        var subjects = context.Principal!.FindAll("sub").ToArray();
                        var roles = context.Principal.FindAll("role").ToArray();
                        // Admin tokens remain unusable until an approved MFA flow exists.
                        if (subjects.Length != 1 || !Guid.TryParseExact(subjects[0].Value, "D", out var userId) ||
                            userId == Guid.Empty || roles.Length != 1 || roles[0].Value is not ("client" or "dietitian"))
                            context.Fail("The access token is invalid.");
                        return Task.CompletedTask;
                    },
                    OnChallenge = context =>
                    {
                        context.HandleResponse();
                        context.Response.Headers.WWWAuthenticate = "Bearer";
                        context.Response.Headers.CacheControl = "no-store";
                        return ApiErrors.WriteAsync(context.HttpContext, StatusCodes.Status401Unauthorized);
                    },
                    OnForbidden = context =>
                    {
                        context.Response.Headers.CacheControl = "no-store";
                        return ApiErrors.WriteAsync(context.HttpContext, StatusCodes.Status403Forbidden);
                    }
                };
            });
        // Framework authentication exceptions are not an application audit trail and may contain token artifacts.
        services.AddLogging(logging => logging.AddFilter("Microsoft.AspNetCore.Authentication.JwtBearer", LogLevel.None));
        services.AddAuthorization();
        return services;
    }
}
