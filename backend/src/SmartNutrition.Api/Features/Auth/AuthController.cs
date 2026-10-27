using System.ComponentModel.DataAnnotations;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using SmartNutrition.Api.Infrastructure;

namespace SmartNutrition.Api.Features.Auth;

[ApiController]
[Route("api/v1/auth")]
public sealed class AuthController(UserRegistrationService registration) : ControllerBase
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
}

public sealed record RegisterUserResponse(Guid Id);
