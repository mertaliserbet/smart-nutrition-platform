using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using SmartNutrition.Api.Data;

namespace SmartNutrition.Api.Health;

public sealed class PostgresHealthCheck(
    IServiceScopeFactory scopeFactory,
    IConfiguration configuration) : IHealthCheck
{
    public async Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(configuration.GetConnectionString("DefaultConnection")))
        {
            return HealthCheckResult.Unhealthy("PostgreSQL is not configured.");
        }

        try
        {
            await using var scope = scopeFactory.CreateAsyncScope();
            var database = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            return await database.Database.CanConnectAsync(cancellationToken)
                ? HealthCheckResult.Healthy()
                : HealthCheckResult.Unhealthy("PostgreSQL is unavailable.");
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception)
        {
            // Never expose connection strings or provider exceptions to probes.
            return HealthCheckResult.Unhealthy("PostgreSQL is unavailable.");
        }
    }
}
