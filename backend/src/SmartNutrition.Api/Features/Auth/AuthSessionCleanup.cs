using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using SmartNutrition.Api.Data;

namespace SmartNutrition.Api.Features.Auth;

internal sealed class AuthSessionCleanup(IServiceScopeFactory scopes, IOptions<WebSessionOptions> settings,
    TimeProvider clock, ILogger<AuthSessionCleanup> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (!settings.Value.Enabled) return;
        using var timer = new PeriodicTimer(TimeSpan.FromMinutes(10), clock);
        do
        {
            try
            {
                await using var scope = scopes.CreateAsyncScope();
                await DeleteExpiredAsync(scope.ServiceProvider.GetRequiredService<AppDbContext>(), clock.GetUtcNow(), stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { return; }
            catch { logger.LogError("Web session cleanup could not complete."); }
        } while (await timer.WaitForNextTickAsync(stoppingToken));
    }

    // A ten-minute margin keeps the normal cleanup deadline within 24 hours of expiry/revocation.
    internal static Task<int> DeleteExpiredAsync(AppDbContext database, DateTimeOffset now, CancellationToken cancellationToken) =>
        database.AuthSessions.Where(session => session.IdleExpiresAt <= now.AddHours(-23).AddMinutes(-50) ||
            session.AbsoluteExpiresAt <= now.AddHours(-23).AddMinutes(-50) || session.RevokedAt <= now.AddHours(-23).AddMinutes(-50))
            .ExecuteDeleteAsync(cancellationToken);
}
