namespace SmartNutrition.Api.Infrastructure;

internal static class ApiErrors
{
    public static object Create(HttpContext context, int statusCode, string? codeOverride = null)
    {
        var (code, message) = statusCode switch
        {
            400 => ("invalid_request", "The request is invalid."),
            401 => ("unauthenticated", "Authentication is required."),
            403 => ("forbidden", "Access is not permitted."),
            404 => ("not_found", "The resource was not found."),
            409 => ("conflict", "The request conflicts with the current state."),
            413 => ("payload_too_large", "The payload is too large."),
            415 => ("unsupported_media_type", "The media type is not supported."),
            422 => ("validation_failed", "The request could not be validated."),
            429 => ("rate_limited", "Too many requests."),
            >= 500 => ("internal_error", "An unexpected error occurred."),
            _ => ("invalid_request", "The request could not be processed.")
        };

        if (statusCode == 409 && codeOverride == "active_nutrition_plan_conflict")
            (code, message) = (codeOverride, "An active nutrition plan already exists.");
        return new { error = new { code, message }, requestId = context.TraceIdentifier };
    }

    public static Task WriteAsync(HttpContext context, int statusCode, string? codeOverride = null)
    {
        context.Response.StatusCode = statusCode;
        return context.Response.WriteAsJsonAsync(Create(context, statusCode, codeOverride));
    }
}
