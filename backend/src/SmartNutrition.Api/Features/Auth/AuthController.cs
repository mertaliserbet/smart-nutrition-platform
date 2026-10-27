using System.ComponentModel.DataAnnotations;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using SmartNutrition.Api.Infrastructure;

namespace SmartNutrition.Api.Features.Auth;

[ApiController]
[Route("api/v1/auth")]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public sealed class AuthController(UserRegistrationService registration, EmailVerificationService verification,
    VerificationEmailQueue emailQueue) : ControllerBase
{
    [AllowAnonymous]
    [HttpPost("register")]
    [Consumes("application/json")]
    [ProducesResponseType<RegisterUserResponse>(StatusCodes.Status201Created)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    [ProducesResponseType(StatusCodes.Status415UnsupportedMediaType)]
    [ProducesResponseType(StatusCodes.Status422UnprocessableEntity)]
    [ProducesResponseType(StatusCodes.Status500InternalServerError)]
    public async Task<IActionResult> Register(RegisterUserRequest request, CancellationToken cancellationToken)
    {
        try
        {
            var user = await registration.RegisterAsync(request, cancellationToken);
            emailQueue.Enqueue(user.Email);
            return StatusCode(StatusCodes.Status201Created, new RegisterUserResponse(user.Id));
        }
        catch (ValidationException)
        {
            return StatusCode(StatusCodes.Status422UnprocessableEntity,
                ApiErrors.Create(HttpContext, StatusCodes.Status422UnprocessableEntity));
        }
        catch (RegistrationEmailConflictException)
        {
            return Conflict(ApiErrors.Create(HttpContext, StatusCodes.Status409Conflict));
        }
    }

    [AllowAnonymous]
    [HttpPost("verify-email")]
    [Consumes("application/json")]
    [RequestSizeLimit(4096)]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status413PayloadTooLarge)]
    [ProducesResponseType(StatusCodes.Status415UnsupportedMediaType)]
    [ProducesResponseType(StatusCodes.Status422UnprocessableEntity)]
    [ProducesResponseType(StatusCodes.Status500InternalServerError)]
    public async Task<IActionResult> VerifyEmail(VerifyEmailRequest request, CancellationToken cancellationToken) =>
        await verification.VerifyAsync(request.Token, cancellationToken)
            ? NoContent()
            : StatusCode(StatusCodes.Status422UnprocessableEntity, ApiErrors.Create(HttpContext, StatusCodes.Status422UnprocessableEntity));

    [AllowAnonymous]
    [HttpPost("resend-verification")]
    [Consumes("application/json")]
    [RequestSizeLimit(4096)]
    [EnableRateLimiting("resend-verification")]
    [ProducesResponseType(StatusCodes.Status202Accepted)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status413PayloadTooLarge)]
    [ProducesResponseType(StatusCodes.Status415UnsupportedMediaType)]
    [ProducesResponseType(StatusCodes.Status429TooManyRequests)]
    [ProducesResponseType(StatusCodes.Status500InternalServerError)]
    public IActionResult ResendVerification(ResendVerificationRequest request)
    {
        // All valid addresses take the same path: no existence/verification/cooldown lookup here.
        emailQueue.Enqueue(request.Email!.Trim());
        return Accepted();
    }
}

public sealed record RegisterUserResponse(Guid Id);
