using System.Data;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using SmartNutrition.Api.Data;
using SmartNutrition.Api.Features.MealLogs;
using SmartNutrition.Api.Features.Relationships;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Features.NutritionPlans;

public sealed class NutritionPlanMealComparisonService(AppDbContext database, RelationshipAccessService access)
{
    public async Task<NutritionPlanMealComparisonResponse> CompareAsync(HttpRequest request,
        System.Security.Claims.ClaimsPrincipal principal, Guid planId, Guid versionId,
        DateTimeOffset from, DateTimeOffset to, CancellationToken token)
    {
        try
        {
            // Authorization, immutable content and all aggregates use one database snapshot.
            await using var transaction = await database.Database.BeginTransactionAsync(IsolationLevel.RepeatableRead, token);
            var actor = await access.RequireAsync(principal, token, request);
            var clientId = await database.NutritionPlans.AsNoTracking().Where(x => x.Id == planId)
                .Select(x => (Guid?)x.ClientId).SingleOrDefaultAsync(token) ?? throw new ResourceOperationException(404);
            if (actor.Role == UserRole.Client)
            {
                if (actor.ClientId != clientId) throw new ResourceOperationException(404);
            }
            else
            {
                var relationship = await database.DietitianClientRelationships.AsNoTracking()
                    .Where(x => x.ClientId == clientId && x.DietitianId == actor.DietitianId && x.Status == RelationshipStatus.Active)
                    .Select(x => new
                    {
                        Allowed = database.DataSharingPermissions.Any(p => p.RelationshipId == x.Id && p.Category == "nutrition_plans" && p.IsGranted)
                            && database.DataSharingPermissions.Any(p => p.RelationshipId == x.Id && p.Category == "meal_logs" && p.IsGranted)
                    }).SingleOrDefaultAsync(token) ?? throw new ResourceOperationException(404);
                if (!relationship.Allowed) throw new ResourceOperationException(403);
            }
            var version = await database.NutritionPlanVersions.AsNoTracking()
                .SingleOrDefaultAsync(x => x.Id == versionId && x.NutritionPlanId == planId, token) ?? throw new ResourceOperationException(404);
            var snapshot = JsonSerializer.Deserialize<NutritionPlanSnapshot>(version.SnapshotJson, NutritionPlan.Json)
                ?? throw new InvalidOperationException("Program version is unavailable.");
            var date = DateOnly.FromDateTime(from.Date);
            if (date < snapshot.StartDate || (snapshot.EndDate is { } last && date > last)) throw new ResourceOperationException(422);
            var start = from.ToUniversalTime(); var end = to.ToUniversalTime();
            var logs = database.MealLogs.AsNoTracking().Where(x => x.ClientId == clientId && x.ConsumedAt >= start && x.ConsumedAt < end);
            var logCounts = await logs.GroupBy(x => x.MealType)
                .Select(g => new { MealType = g.Key, Count = g.Count() }).ToDictionaryAsync(x => x.MealType, x => x.Count, token);
            // Aggregating in SQL keeps response size and application memory independent of log count.
            var groups = await logs.SelectMany(log => log.Items.Select(item => new
                { log.MealType, item.IsEstimated, item.CaloriesKcal, item.ProteinGrams, item.CarbsGrams, item.FatGrams }))
                .GroupBy(x => x.MealType).Select(g => new
                {
                    MealType = g.Key, Count = g.Count(), Estimated = g.Count(x => x.IsEstimated),
                    Calories = g.Sum(x => x.CaloriesKcal) ?? 0m, CaloriesMissing = g.Count(x => x.CaloriesKcal == null),
                    Protein = g.Sum(x => x.ProteinGrams) ?? 0m, ProteinMissing = g.Count(x => x.ProteinGrams == null),
                    Carbs = g.Sum(x => x.CarbsGrams) ?? 0m, CarbsMissing = g.Count(x => x.CarbsGrams == null),
                    Fat = g.Sum(x => x.FatGrams) ?? 0m, FatMissing = g.Count(x => x.FatGrams == null)
                }).ToDictionaryAsync(x => x.MealType, token);
            var day = ((int)date.DayOfWeek + 6) % 7 + 1;
            var meals = Enum.GetValues<MealType>().Select(type =>
            {
                var actual = groups.TryGetValue(type, out var g)
                    ? new MealLogNutritionSummary(logCounts[type], g.Count, g.Estimated,
                        new(g.Calories, g.CaloriesMissing), new(g.Protein, g.ProteinMissing),
                        new(g.Carbs, g.CarbsMissing), new(g.Fat, g.FatMissing)) : Empty();
                return new NutritionPlanMealComparison(type, snapshot.Items
                    .Where(x => x.MealType == type && (x.DayOfWeek is null || x.DayOfWeek == day)).OrderBy(x => x.SortOrder).ToArray(), actual);
            }).ToArray();
            var summaries = meals.Select(x => x.Actual).ToArray();
            var total = new MealLogNutritionSummary(summaries.Sum(x => x.MealLogCount), summaries.Sum(x => x.ItemCount),
                summaries.Sum(x => x.EstimatedItemCount), Sum(summaries.Select(x => x.CaloriesKcal)), Sum(summaries.Select(x => x.ProteinGrams)),
                Sum(summaries.Select(x => x.CarbsGrams)), Sum(summaries.Select(x => x.FatGrams)));
            decimal? difference = total.ItemCount > 0 && total.CaloriesKcal.MissingItemCount == 0 && snapshot.DailyCaloriesTargetKcal is { } target
                ? total.CaloriesKcal.KnownTotal - target : null;
            await transaction.CommitAsync(token);
            return new(clientId, new(version.Id, planId, version.VersionNumber, version.CreatedAt, snapshot), date, start, end, total, difference, meals);
        }
        catch (OverflowException) { throw new ResourceOperationException(422); }
    }

    private static MealLogNutritionSummary Empty() => new(0, 0, 0, new(0, 0), new(0, 0), new(0, 0), new(0, 0));
    private static NutritionValueSummary Sum(IEnumerable<NutritionValueSummary> values)
    {
        var rows = values.ToArray(); return new(rows.Sum(x => x.KnownTotal), rows.Sum(x => x.MissingItemCount));
    }
}
