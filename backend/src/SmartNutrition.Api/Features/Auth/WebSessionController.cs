using Microsoft.AspNetCore.Antiforgery;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using SmartNutrition.Api.Infrastructure;

namespace SmartNutrition.Api.Features.Auth;

[ApiController]
[Route("api/v1/auth")]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public sealed class WebSessionController(IAntiforgery antiforgery, WebSessionService sessions) : ControllerBase
{
    [HttpPost("admin-web-session")]
    [ProducesResponseType<CurrentUserResponse>(200)]
    [ProducesResponseType(400), ProducesResponseType(401), ProducesResponseType(403), ProducesResponseType(409)]
    [ProducesResponseType(413), ProducesResponseType(415), ProducesResponseType(429), ProducesResponseType(500)]
    [Consumes("application/json")]
    [RequestSizeLimit(4096)]
    [EnableRateLimiting("login")]
    public async Task<IActionResult> AdminLogin(AdminLoginRequest request, CancellationToken cancellationToken)
    {
        if (Request.Query.Count != 0) return BadRequest(ApiErrors.Create(HttpContext, 400));
        await AuthenticateCookie();
        if (!await ValidCsrf()) return BadRequest(ApiErrors.Create(HttpContext, 400));
        if (User.Identity?.IsAuthenticated == true) return Conflict(ApiErrors.Create(HttpContext, 409));
        var login = await sessions.AdminLoginAsync(request, cancellationToken);
        if (login is null) return Unauthorized(ApiErrors.Create(HttpContext, 401));
        await HttpContext.SignInAsync(WebSessionAuthentication.Scheme, login.Value.Principal, new AuthenticationProperties
        {
            IsPersistent = false, AllowRefresh = false,
            IssuedUtc = login.Value.Session.CreatedAt, ExpiresUtc = login.Value.Session.AbsoluteExpiresAt
        });
        return Ok(login.Value.Account);
    }

    private bool HasBody => HttpContext.Features.Get<IHttpRequestBodyDetectionFeature>()?.CanHaveBody == true;
    private async Task AuthenticateCookie()
    {
        var result = await HttpContext.AuthenticateAsync(WebSessionAuthentication.Scheme);
        HttpContext.User = result.Succeeded ? result.Principal! : new();
    }

    private async Task<bool> ValidCsrf()
    {
        try { await antiforgery.ValidateRequestAsync(HttpContext); return true; }
        catch (AntiforgeryValidationException) { return false; }
    }

    [HttpGet("csrf")]
    [EnableRateLimiting("csrf")]
    [ProducesResponseType<CsrfTokenResponse>(200)]
    [ProducesResponseType(400)]
    [ProducesResponseType(403)]
    [ProducesResponseType(429)]
    [ProducesResponseType(500)]
    public async Task<IActionResult> Csrf()
    {
        if (Request.Query.Count != 0 || HasBody) return BadRequest(ApiErrors.Create(HttpContext, 400));
        await AuthenticateCookie();
        return Ok(new CsrfTokenResponse(antiforgery.GetAndStoreTokens(HttpContext).RequestToken!));
    }

    [HttpPost("web-session")]
    [Consumes("application/json")]
    [RequestSizeLimit(4096)]
    [EnableRateLimiting("login")]
    [ProducesResponseType<CurrentUserResponse>(200)]
    [ProducesResponseType(400)]
    [ProducesResponseType(401)]
    [ProducesResponseType(403)]
    [ProducesResponseType(409)]
    [ProducesResponseType(413)]
    [ProducesResponseType(415)]
    [ProducesResponseType(429)]
    [ProducesResponseType(500)]
    public async Task<IActionResult> Login(LoginUserRequest request, CancellationToken cancellationToken)
    {
        if (Request.Query.Count != 0) return BadRequest(ApiErrors.Create(HttpContext, 400));
        await AuthenticateCookie();
        if (!await ValidCsrf()) return BadRequest(ApiErrors.Create(HttpContext, 400));
        if (User.Identity?.IsAuthenticated == true) return Conflict(ApiErrors.Create(HttpContext, 409));
        var login = await sessions.LoginAsync(request, cancellationToken);
        if (login is null) return Unauthorized(ApiErrors.Create(HttpContext, 401));
        await HttpContext.SignInAsync(WebSessionAuthentication.Scheme, login.Value.Principal, new AuthenticationProperties
        {
            IsPersistent = false, AllowRefresh = false,
            IssuedUtc = login.Value.Session.CreatedAt, ExpiresUtc = login.Value.Session.AbsoluteExpiresAt
        });
        return Ok(login.Value.Account);
    }

    [HttpDelete("web-session")]
    [ProducesResponseType(204)]
    [ProducesResponseType(400)]
    [ProducesResponseType(403)]
    [ProducesResponseType(500)]
    public async Task<IActionResult> Logout(CancellationToken cancellationToken)
    {
        if (Request.Query.Count != 0 || HasBody) return BadRequest(ApiErrors.Create(HttpContext, 400));
        await AuthenticateCookie();
        if (!await ValidCsrf()) return BadRequest(ApiErrors.Create(HttpContext, 400));
        await sessions.RevokeAsync(User, cancellationToken);
        await HttpContext.SignOutAsync(WebSessionAuthentication.Scheme);
        Response.Cookies.Delete(WebSessionAuthentication.CsrfCookieName, new CookieOptions
        { Path = "/", Secure = true, HttpOnly = true, SameSite = SameSiteMode.Strict });
        return NoContent();
    }
}

public sealed record CsrfTokenResponse(string RequestToken);
