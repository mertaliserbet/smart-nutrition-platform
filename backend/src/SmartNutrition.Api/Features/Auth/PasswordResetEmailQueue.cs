using System.Threading.Channels;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using SmartNutrition.Api.Data;

namespace SmartNutrition.Api.Features.Auth;

public interface IPasswordResetEmailSender
{
    Task SendResetAsync(string recipient, string token, CancellationToken cancellationToken);
    Task SendResetCompletedAsync(string recipient, CancellationToken cancellationToken);
}

public sealed class PasswordResetEmailQueue : BackgroundService
{
    private readonly Channel<(string Email, bool Completed)> _jobs;
    private readonly IServiceScopeFactory _scopes;
    private readonly ILogger<PasswordResetEmailQueue> _logger;
    public PasswordResetEmailQueue(IServiceScopeFactory scopes, IOptions<PasswordResetOptions> options,
        ILogger<PasswordResetEmailQueue> logger)
    {
        _scopes = scopes; _logger = logger;
        _jobs = Channel.CreateBounded<(string, bool)>(new BoundedChannelOptions(options.Value.QueueCapacity)
            { SingleReader = true, FullMode = BoundedChannelFullMode.Wait });
    }
    public void Enqueue(string email, bool completed = false)
    {
        if (!_jobs.Writer.TryWrite((email, completed)))
            _logger.LogWarning("Password reset email queue is full.");
    }
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await foreach (var job in _jobs.Reader.ReadAllAsync(stoppingToken))
        {
            try
            {
                await using var scope = _scopes.CreateAsyncScope();
                if (job.Completed)
                    await scope.ServiceProvider.GetRequiredService<IPasswordResetEmailSender>()
                        .SendResetCompletedAsync(job.Email, stoppingToken);
                else await scope.ServiceProvider.GetRequiredService<PasswordResetService>().SendAsync(job.Email, stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { break; }
            catch { _logger.LogWarning("Password reset email delivery failed."); }
        }
    }
}

internal sealed class PasswordResetCleanup(IServiceScopeFactory scopes, TimeProvider clock,
    ILogger<PasswordResetCleanup> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromMinutes(10), clock);
        do
        {
            try
            {
                await using var scope = scopes.CreateAsyncScope();
                await DeleteExpiredAsync(scope.ServiceProvider.GetRequiredService<AppDbContext>(), clock.GetUtcNow(), stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { return; }
            catch { logger.LogError("Password reset metadata cleanup failed."); }
        } while (await timer.WaitForNextTickAsync(stoppingToken));
    }
    internal static async Task DeleteExpiredAsync(AppDbContext database, DateTimeOffset now, CancellationToken cancellationToken)
    {
        await database.Users.Where(user => user.PasswordResetExpiresAt <= now).ExecuteUpdateAsync(setters => setters
            .SetProperty(user => user.PasswordResetTokenHash, (string?)null)
            .SetProperty(user => user.PasswordResetExpiresAt, (DateTimeOffset?)null), cancellationToken);
        // Do not clear cooldown metadata while any live reset code depends on it.
        await database.Users.Where(user => user.PasswordResetExpiresAt == null && user.PasswordResetLastSentAt <= now.AddHours(-24))
            .ExecuteUpdateAsync(setters => setters.SetProperty(user => user.PasswordResetLastSentAt, (DateTimeOffset?)null), cancellationToken);
    }
}
