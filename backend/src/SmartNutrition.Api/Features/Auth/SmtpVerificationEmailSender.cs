using System.Net;
using MailKit.Net.Smtp;
using MailKit.Security;
using Microsoft.Extensions.Options;
using MimeKit;

namespace SmartNutrition.Api.Features.Auth;

public interface IVerificationEmailSender
{
    Task SendAsync(string recipient, string token, CancellationToken cancellationToken);
}

public sealed class SmtpVerificationEmailSender(IOptions<SmtpOptions> settings, IHostEnvironment environment)
    : IVerificationEmailSender, IPasswordResetEmailSender
{
    public Task SendAsync(string recipient, string token, CancellationToken cancellationToken) =>
        SendMessageAsync(recipient, "Smart Nutrition — E-posta doğrulama",
            $"E-posta doğrulama kodunuz:\n\n{token}\n\nBu tek kullanımlık kod 30 dakika geçerlidir.\nBu isteği siz yapmadıysanız e-postayı yok sayabilirsiniz.", cancellationToken);

    public Task SendResetAsync(string recipient, string token, CancellationToken cancellationToken) =>
        SendMessageAsync(recipient, "Smart Nutrition — Parola sıfırlama",
            $"Parola sıfırlama kodunuz:\n\n{token}\n\nBu tek kullanımlık kod 30 dakika geçerlidir.\nKodu parola sıfırlama formuna yapıştırın. İsteği siz yapmadıysanız e-postayı yok sayabilirsiniz.", cancellationToken);

    public Task SendResetCompletedAsync(string recipient, CancellationToken cancellationToken) =>
        SendMessageAsync(recipient, "Smart Nutrition — Parolanız değiştirildi",
            "Parolanız değiştirildi ve mevcut oturumlarınız iptal edildi. İşlemi siz yapmadıysanız hesabınızın güvenliğini kontrol edin.", cancellationToken);

    private async Task SendMessageAsync(string recipient, string subject, string body, CancellationToken cancellationToken)
    {
        var options = settings.Value;
        if (string.IsNullOrWhiteSpace(options.Host) || string.IsNullOrWhiteSpace(options.FromAddress) || options.Port is < 1 or > 65535)
            throw new InvalidOperationException("Verification SMTP is not configured.");

        var localHost = options.Host.Equals("localhost", StringComparison.OrdinalIgnoreCase) ||
            (IPAddress.TryParse(options.Host, out var address) && IPAddress.IsLoopback(address));
        var security = options.TlsMode switch
        {
            "StartTls" => SecureSocketOptions.StartTls,
            "SslOnConnect" => SecureSocketOptions.SslOnConnect,
            "None" when environment.IsDevelopment() && localHost => SecureSocketOptions.None,
            _ => throw new InvalidOperationException("Insecure SMTP is allowed only for local development.")
        };

        using var message = new MimeMessage();
        message.From.Add(MailboxAddress.Parse(options.FromAddress));
        message.To.Add(MailboxAddress.Parse(recipient));
        message.Subject = subject;
        message.Body = new TextPart("plain") { Text = body };

        // No protocol logger: SMTP commands, credentials and message bodies must not be logged.
        using var client = new SmtpClient { Timeout = 10000 };
        await client.ConnectAsync(options.Host, options.Port, security, cancellationToken);
        if (!string.IsNullOrEmpty(options.Username))
        {
            if (string.IsNullOrEmpty(options.Password))
                throw new InvalidOperationException("SMTP credentials are incomplete.");
            await client.AuthenticateAsync(options.Username, options.Password, cancellationToken);
        }
        await client.SendAsync(message, cancellationToken);
        await client.DisconnectAsync(true, cancellationToken);
    }
}
