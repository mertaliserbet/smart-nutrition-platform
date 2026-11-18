using System.Data;
using Microsoft.EntityFrameworkCore;
using SmartNutrition.Api.Data;
using SmartNutrition.Api.Features.Relationships;

namespace SmartNutrition.Api.Features.HealthData;

public sealed class ActivitySummaryService(AppDbContext db)
{
    private sealed record Candidate(Guid Id, DateTimeOffset Start, DateTimeOffset? End, decimal Value, string Rank, string Key);
    public async Task<ActivityDailySummaryResponse> DailyAsync(Guid client, DateTimeOffset from, DateTimeOffset to, CancellationToken token)
    {
        var start = from.ToUniversalTime(); var end = to.ToUniversalTime();
        await using var tx = await db.Database.BeginTransactionAsync(IsolationLevel.RepeatableRead, token);
        Dictionary<string, List<Candidate>> selected = [];
        var overlaps = 0; var unallocated = 0;
        foreach (var metric in new[] { "steps", "distance", "active_energy", "exercise", "heart_rate" })
        {
            var day = await CandidatesAsync(client, metric, start, end, token);
            unallocated += day.Count(c => c.End is null);
            var bounded = day.Where(c => c.End is not null).ToList();
            List<Candidate> candidates = [];
            if (bounded.Count > 0)
            {
                // Include every direct overlap, including a higher-priority interval
                // starting outside the day. Selection therefore does not depend on
                // which daily window happened to be requested first.
                var lower = bounded.Min(c => c.Start);
                var upper = bounded.Max(c => c.End == c.Start ? c.Start.AddTicks(10) : c.End!.Value);
                candidates = await CandidatesAsync(client, metric, lower, upper, token);
            }
            var occupied = new IntervalUnion(); List<Candidate> accepted = [];
            foreach (var c in candidates.Where(c => c.End is not null).OrderBy(c => c.Rank, StringComparer.Ordinal)
                         .ThenByDescending(c => (c.End!.Value - c.Start).Ticks).ThenBy(c => c.Start).ThenBy(c => c.Key, StringComparer.Ordinal))
            {
                var collision = occupied.Add(c.Start.UtcTicks, c.End == c.Start ? c.Start.UtcTicks + 10 : c.End!.Value.UtcTicks);
                if (!Touches(c, start, end)) continue;
                if (collision) { overlaps++; continue; }
                if (metric != "exercise" && (c.Start < start || c.End > end)) { unallocated++; continue; }
                accepted.Add(c);
            }
            selected[metric] = accepted;
        }
        decimal? Sum(string metric) => selected[metric].Count == 0 ? null : selected[metric].Sum(c => c.Value);
        var exercises = selected["exercise"];
        var heart = selected["heart_rate"];
        var result = new ActivityDailySummaryResponse(start, end, Sum("steps"), Sum("distance"), Sum("active_energy"),
            exercises.Count == 0 ? null : exercises.Sum(c => (Min(c.End!.Value, end) - Max(c.Start, start)).Ticks / (decimal)TimeSpan.TicksPerMinute),
            exercises.Count, heart.Count, heart.Count == 0 ? null : heart.Average(c => c.Value),
            heart.Count == 0 ? null : heart.Min(c => c.Value), heart.Count == 0 ? null : heart.Max(c => c.Value),
            overlaps, unallocated, overlaps + unallocated > 0, "conservative_overlap_v1");
        await tx.CommitAsync(token);
        return result;
    }
    private static bool Touches(Candidate c, DateTimeOffset from, DateTimeOffset to) => c.Start < to &&
        (c.End > from || c.End == c.Start && c.Start >= from);
    private static DateTimeOffset Min(DateTimeOffset a, DateTimeOffset b) => a < b ? a : b;
    private static DateTimeOffset Max(DateTimeOffset a, DateTimeOffset b) => a > b ? a : b;

    private async Task<List<Candidate>> CandidatesAsync(Guid client, string metric, DateTimeOffset lower, DateTimeOffset upper, CancellationToken token)
    {
        List<Candidate> result = [];
        if (metric != "exercise")
        {
            var samples = await (from s in db.HealthMetricSamples.AsNoTracking()
                                 join r in db.WearableRecords on s.WearableRecordId equals r.Id
                                 join c in db.WearableConnections on r.WearableConnectionId equals c.Id
                                 where s.ClientId == client && r.ClientId == client && c.ClientId == client && !s.IsDeleted && !r.IsDeleted && r.Metric == metric &&
                                     s.StartedAt < upper && (s.EndedAt > lower || s.StartedAt == s.EndedAt && s.StartedAt >= lower)
                                 select new { s.Id, s.StartedAt, s.EndedAt, s.Value, c.Provider, r.SourceId, r.ExternalRecordId, r.RawType, s.SampleKey })
                .Take(HealthDataValidation.MaximumSummaryRows + 1).ToListAsync(token);
            result.AddRange(samples.Select(s => new Candidate(s.Id, s.StartedAt, s.EndedAt, s.Value,
                (s.Provider == "health_connect" ? "1|" : "2|") + s.SourceId,
                s.ExternalRecordId + "|" + s.RawType + "|" + s.SampleKey + "|" + s.Id)));
        }
        if (metric is "exercise" or "distance" or "active_energy")
        {
            var query = db.ActivityLogs.AsNoTracking().Where(a => a.ClientId == client && !a.IsDeleted && a.StartedAt < upper &&
                (a.EndedAt > lower || a.EndedAt == null && a.StartedAt >= lower));
            query = metric switch
            {
                "exercise" => query.Where(a => a.DurationMinutes != null),
                "distance" => query.Where(a => a.Source == "manual" && a.DistanceKm != null),
                _ => query.Where(a => a.Source == "manual" && a.CaloriesKcal != null)
            };
            var rows = await (from a in query
                              join r in db.WearableRecords on a.WearableRecordId equals (Guid?)r.Id into records
                              from r in records.DefaultIfEmpty()
                              join c in db.WearableConnections on a.WearableConnectionId equals (Guid?)c.Id into connections
                              from c in connections.DefaultIfEmpty()
                              select new { Activity = a, Provider = c == null ? null : c.Provider, SourceId = r == null ? null : r.SourceId })
                .Take(HealthDataValidation.MaximumSummaryRows + 1).ToListAsync(token);
            result.AddRange(rows.Select(x => new Candidate(x.Activity.Id, x.Activity.StartedAt, x.Activity.EndedAt,
                metric == "exercise" ? x.Activity.DurationMinutes!.Value : metric == "distance" ? x.Activity.DistanceKm!.Value : x.Activity.CaloriesKcal!.Value,
                x.Activity.Source == "manual" ? "0" : (x.Provider == "health_connect" ? "1|" : "2|") + x.SourceId,
                (x.Activity.ExternalRecordId ?? "") + "|" + x.Activity.Id)));
        }
        if (result.Count > HealthDataValidation.MaximumSummaryRows) throw new ResourceOperationException(422, "aggregation_limit_exceeded");
        return result;
    }
    // All preceding intervals enter the union, even if excluded. This conservative
    // rule avoids query-window-dependent chains of overlap and invented allocation.
    private sealed class IntervalUnion
    {
        private readonly SortedSet<(long Start, long End)> ranges = [];
        internal bool Add(long start, long end)
        {
            var collision = false;
            var before = ranges.GetViewBetween((long.MinValue, long.MinValue), (start, long.MaxValue));
            if (before.Count > 0)
            {
                var prior = before.Max;
                if (prior.End >= start)
                {
                    collision = prior.End > start;
                    start = prior.Start; end = Math.Max(end, prior.End); ranges.Remove(prior);
                }
            }
            while (true)
            {
                var after = ranges.GetViewBetween((start, long.MinValue), (long.MaxValue, long.MaxValue));
                if (after.Count == 0 || after.Min.Start > end) break;
                var next = after.Min;
                collision |= next.Start < end;
                end = Math.Max(end, next.End); ranges.Remove(next);
            }
            ranges.Add((start, end)); return collision;
        }
    }
}
