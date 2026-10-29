using System.Threading.RateLimiting;
using Microsoft.Extensions.Options;

namespace SmartNutrition.Api.Features.Relationships;

public sealed class RelationshipLimitOptions
{
    public int RequestsPerMinute { get; set; } = 5;
    public int InvitationCodesPerMinute { get; set; } = 5;
}
public sealed class RelationshipMutationLimits : IDisposable
{
    private sealed record Key(string Operation, Guid UserId, string Ip);
    private readonly PartitionedRateLimiter<Key> _limiter;
    public RelationshipMutationLimits(IOptions<RelationshipLimitOptions> options)
    {
        var settings = options.Value;
        PartitionedRateLimiter<Key> Create(bool account) => PartitionedRateLimiter.Create<Key, string>(key =>
            RateLimitPartition.GetFixedWindowLimiter(key.Operation + ":" + (account ? key.UserId.ToString() : key.Ip),
                _ => new FixedWindowRateLimiterOptions { PermitLimit = key.Operation == "invite" ? settings.InvitationCodesPerMinute : settings.RequestsPerMinute,
                    Window = TimeSpan.FromMinutes(1), QueueLimit = 0, AutoReplenishment = true }));
        _limiter = PartitionedRateLimiter.CreateChained(Create(true), Create(false));
    }
    internal void Acquire(string operation, Guid userId, string ip)
    { using var lease = _limiter.AttemptAcquire(new(operation, userId, ip)); if (!lease.IsAcquired) throw new ResourceOperationException(429); }
    public void Dispose() => _limiter.Dispose();
}
