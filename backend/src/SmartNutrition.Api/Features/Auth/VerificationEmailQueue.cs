using System.Threading.Channels;
using Microsoft.Extensions.Options;

namespace SmartNutrition.Api.Features.Auth;

// SMTP is off the request path, so resend latency does not disclose whether an account exists.
public sealed class VerificationEmailQueue : BackgroundService
{
    private readonly Channel<string> _emails;
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly ILogger<VerificationEmailQueue> _logger;

    public VerificationEmailQueue(IServiceScopeFactory scopeFactory, IOptions<EmailVerificationOptions> options,
        ILogger<VerificationEmailQueue> logger)
    {
        _scopeFactory = scopeFactory;
        _logger = logger;
        _emails = Channel.CreateBounded<string>(new BoundedChannelOptions(options.Value.QueueCapacity)
        {
            SingleReader = true, FullMode = BoundedChannelFullMode.Wait
        });
    }

    public void Enqueue(string email)
    {
        if (!_emails.Writer.TryWrite(email))
            _logger.LogWarning("Verification email queue is full; delivery can be retried through resend.");
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await foreach (var email in _emails.Reader.ReadAllAsync(stoppingToken))
        {
            try
            {
                await using var scope = _scopeFactory.CreateAsyncScope();
                await scope.ServiceProvider.GetRequiredService<EmailVerificationService>().SendAsync(email, stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { break; }
            catch (Exception)
            {
                // Do not attach the exception: SMTP responses can contain recipient, message or credential data.
                _logger.LogWarning("Verification email delivery failed; the account remains unverified and resend is available.");
            }
        }
    }
}
