using Microsoft.AspNetCore.Authentication.JwtBearer;
using System.Globalization;
using Microsoft.EntityFrameworkCore;
using SmartNutrition.Api.Data;
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
                    OnMessageReceived = context =>
                    {
                        var path = context.Request.Path.Value?.TrimEnd('/');
                        // Reset identity is selected exclusively by the reset code, never by a
                        // supplied bearer. This also keeps account lookup off the request path.
                        if (string.Equals(path, "/api/v1/auth/password-reset-requests", StringComparison.OrdinalIgnoreCase) ||
                            string.Equals(path, "/api/v1/auth/reset-password", StringComparison.OrdinalIgnoreCase)) context.NoResult();
                        return Task.CompletedTask;
                    },
                    OnTokenValidated = async context =>
                    {
                        var subjects = context.Principal!.FindAll("sub").ToArray();
                        var roles = context.Principal.FindAll("role").ToArray();
                        // Admin tokens remain unusable until an approved MFA flow exists.
                        if (subjects.Length != 1 || !Guid.TryParseExact(subjects[0].Value, "D", out var userId) ||
                            userId == Guid.Empty || roles.Length != 1 || roles[0].Value is not ("client" or "dietitian"))
                        {
                            context.Fail("The access token is invalid.");
                            return;
                        }
                        var versions = context.Principal.FindAll("credentialsVersion").ToArray();
                        if (versions.Length != 1 || versions[0].ValueType != System.Security.Claims.ClaimValueTypes.String || !long.TryParse(versions[0].Value, NumberStyles.None,
                                CultureInfo.InvariantCulture, out var version) || version < 0 ||
                            version.ToString(CultureInfo.InvariantCulture) != versions[0].Value)
                        {
                            context.Fail("The access token is invalid.");
                            return;
                        }
                        try
                        {
                            var database = context.HttpContext.RequestServices.GetRequiredService<AppDbContext>();
                            var role = Enum.Parse<SmartNutrition.Api.Models.UserRole>(roles[0].Value, true);
                            if (!await database.Users.AsNoTracking().AnyAsync(user => user.Id == userId &&
                                user.IsEmailVerified && user.Role == role && user.CredentialsVersion == version,
                                context.HttpContext.RequestAborted)) context.Fail("The access token is invalid.");
                        }
                        catch (Exception) when (!context.HttpContext.RequestAborted.IsCancellationRequested)
                        {
                            // JwtBearer normally converts validation exceptions into 401. Preserve an
                            // infrastructure failure as 500 without exposing the underlying exception.
                            throw new CredentialsCheckUnavailableException();
                        }
                    },
                    OnAuthenticationFailed = context => context.Exception is CredentialsCheckUnavailableException
                        ? Task.FromException(context.Exception) : Task.CompletedTask,
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

    private sealed class CredentialsCheckUnavailableException : Exception;
}
