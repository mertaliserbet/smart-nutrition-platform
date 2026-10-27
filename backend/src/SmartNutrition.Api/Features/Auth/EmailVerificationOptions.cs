namespace SmartNutrition.Api.Features.Auth;

public sealed class EmailVerificationOptions
{
    public const string SectionName = "Auth:EmailVerification";
    public int ResendCooldownSeconds { get; set; } = 60;
    public int ResendRequestsPerMinute { get; set; } = 5;
    public int QueueCapacity { get; set; } = 100;
}

public sealed class SmtpOptions
{
    public const string SectionName = "Email:Smtp";
    public string? Host { get; set; }
    public int Port { get; set; } = 587;
    public string? FromAddress { get; set; }
    public string TlsMode { get; set; } = "StartTls";
    public string? Username { get; set; }
    public string? Password { get; set; }
}
