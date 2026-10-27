using Microsoft.AspNetCore.Antiforgery;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.Extensions.Options;
using SmartNutrition.Api.Infrastructure;

namespace SmartNutrition.Api.Features.Auth;

internal static class WebSessionAuthentication
{
    public const string Scheme = "WebSession";
    public const string AccountScheme = "Account";
    public const string CookieName = "__Host-smart-nutrition-session";
    public const string CsrfCookieName = "__Host-smart-nutrition-csrf";

    public static IServiceCollection AddWebSessionAuthentication(this IServiceCollection services, IConfiguration configuration, IWebHostEnvironment environment)
    {
        services.AddOptions<WebSessionOptions>().Bind(configuration.GetSection(WebSessionOptions.SectionName))
            .Validate(options => options.IsValid(environment.ContentRootPath), "Web sessions require one HTTPS origin and a protected key ring outside the repository.")
            .ValidateOnStart();
        services.AddDataProtection().SetApplicationName("SmartNutrition.WebSession.v1");
        services.AddSingleton<WebSessionKeyProtection>();
        services.AddSingleton<IDataProtectionProvider>(provider => provider.GetRequiredService<WebSessionKeyProtection>());
        services.AddScoped<WebSessionService>();
        services.AddHostedService<AuthSessionCleanup>();
        services.AddSingleton<IAntiforgeryAdditionalDataProvider, SessionAntiforgeryData>();
        services.AddAntiforgery(options =>
        {
            options.HeaderName = "X-CSRF-TOKEN";
            options.Cookie.Name = CsrfCookieName;
            options.Cookie.HttpOnly = true;
            options.Cookie.SecurePolicy = CookieSecurePolicy.Always;
            options.Cookie.SameSite = SameSiteMode.Strict;
            options.Cookie.Path = "/";
        });
        services.AddAuthentication().AddPolicyScheme(AccountScheme, AccountScheme, options =>
            options.ForwardDefaultSelector = context => context.Request.Headers.ContainsKey("Authorization") ? JwtBearerDefaults.AuthenticationScheme : Scheme)
            .AddCookie(Scheme, options =>
            {
                options.Cookie.Name = CookieName;
                options.Cookie.HttpOnly = true;
                options.Cookie.SecurePolicy = CookieSecurePolicy.Always;
                options.Cookie.SameSite = SameSiteMode.Strict;
                options.Cookie.Path = "/";
                options.ExpireTimeSpan = TimeSpan.FromHours(8);
                options.SlidingExpiration = false; // Only the DB idle deadline slides; the protected ticket expires absolutely.
                options.Events = new CookieAuthenticationEvents
                {
                    OnValidatePrincipal = async context =>
                    {
                        var configured = context.HttpContext.RequestServices.GetRequiredService<IOptions<WebSessionOptions>>().Value.Enabled;
                        if (!configured || !context.Request.IsHttps ||
                            !await context.HttpContext.RequestServices.GetRequiredService<WebSessionService>()
                                .ValidateAsync(context.Principal!, context.HttpContext.RequestAborted))
                        {
                            context.RejectPrincipal();
                            await context.HttpContext.SignOutAsync(Scheme);
                        }
                    },
                    OnRedirectToLogin = context => ApiErrors.WriteAsync(context.HttpContext, StatusCodes.Status401Unauthorized),
                    OnRedirectToAccessDenied = context => ApiErrors.WriteAsync(context.HttpContext, StatusCodes.Status403Forbidden)
                };
            });
        services.AddOptions<CookieAuthenticationOptions>(Scheme).Configure<TimeProvider>((options, clock) => options.TimeProvider = clock);
        services.AddLogging(logging => logging.AddFilter("Microsoft.AspNetCore.Authentication.Cookies", LogLevel.None)
            .AddFilter("Microsoft.AspNetCore.Antiforgery", LogLevel.None));
        return services;
    }

    public static async Task GuardAsync(HttpContext context, RequestDelegate next)
    {
        // MVC routes are case-insensitive and accept trailing slashes; guards must cover the same paths.
        var path = context.Request.Path.Value?.TrimEnd('/').ToLowerInvariant();
        var web = path is "/api/v1/auth/csrf" or "/api/v1/auth/web-session";
        var account = path == "/api/v1/auth/me";
        if (web || account)
        {
            context.Response.Headers.CacheControl = "no-store";
            var authorization = context.Request.Headers.ContainsKey("Authorization");
            if (authorization && (web || context.Request.Cookies.ContainsKey(CookieName)))
            {
                await ApiErrors.WriteAsync(context, StatusCodes.Status400BadRequest);
                return;
            }
        }
        if (web)
        {
            var settings = context.RequestServices.GetRequiredService<IOptions<WebSessionOptions>>().Value;
            if (!settings.Enabled) { await ApiErrors.WriteAsync(context, 500); return; }
            if (!context.Request.IsHttps || context.Request.Headers["Sec-Fetch-Site"] == "cross-site")
            { await ApiErrors.WriteAsync(context, 403); return; }
            var origin = context.Request.Headers.Origin;
            var writes = !HttpMethods.IsGet(context.Request.Method);
            if ((writes || origin.Count != 0) && (origin.Count != 1 || origin[0] != settings.Origin))
            { await ApiErrors.WriteAsync(context, 403); return; }
        }
        await next(context);
    }

    // Also binds to the session, so a new session for the SAME User invalidates an older tab's token.
    private sealed class SessionAntiforgeryData : IAntiforgeryAdditionalDataProvider
    {
        private static string Context(HttpContext context) => context.User.Identity?.IsAuthenticated == true
            ? context.User.FindFirst("sid")?.Value ?? "invalid" : "anonymous";
        public string GetAdditionalData(HttpContext context) => Context(context);
        public bool ValidateAdditionalData(HttpContext context, string additionalData) => additionalData == Context(context);
    }
}
