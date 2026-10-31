using Microsoft.EntityFrameworkCore;
using SmartNutrition.Api.Data;

namespace SmartNutrition.Api.Features.Auth;

internal sealed class RefreshTokenCleanup(IServiceScopeFactory scopes, TimeProvider clock,
    ILogger<RefreshTokenCleanup> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromMinutes(10), clock);
        do
        {
            try
            {
                await using var scope = scopes.CreateAsyncScope();
                // Every descendant retains its family's absolute expiry. Never
                // delete consumed ancestors while any descendant can still refresh.
                await DeleteExpiredAsync(scope.ServiceProvider.GetRequiredService<AppDbContext>(), clock.GetUtcNow(), stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { return; }
            catch { logger.LogError("Refresh token cleanup could not complete."); }
        } while (await timer.WaitForNextTickAsync(stoppingToken));
    }

    internal static Task<int> DeleteExpiredAsync(AppDbContext database, DateTimeOffset now, CancellationToken cancellationToken) =>
        database.RefreshTokens.Where(token => token.ExpiresAt <= now).ExecuteDeleteAsync(cancellationToken);
}
