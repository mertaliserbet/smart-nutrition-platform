using SmartNutrition.Api.Features.Relationships;

namespace SmartNutrition.Api.Features.WaterLogs;

internal static class WaterLogCalendar
{
    internal const int MaximumDays = 31;
    internal static void Single(DateTimeOffset from, DateTimeOffset to)
    {
        if (from >= to || from.TimeOfDay != TimeSpan.Zero || to.TimeOfDay != TimeSpan.Zero ||
            from.Date == DateTime.MaxValue.Date || to.Date != from.Date.AddDays(1)) throw new ResourceOperationException(400);
    }
    internal static (DateTimeOffset From, DateTimeOffset To)[] Days(DateTimeOffset from, DateTimeOffset to, string? timeZone)
    {
        if (string.IsNullOrEmpty(timeZone) || timeZone.Length > 128 ||
            timeZone != "UTC" && !TimeZoneInfo.TryConvertIanaIdToWindowsId(timeZone, out _)) throw new ResourceOperationException(400);
        TimeZoneInfo zone;
        try { zone = TimeZoneInfo.FindSystemTimeZoneById(timeZone); }
        catch (TimeZoneNotFoundException) { throw new ResourceOperationException(400); }
        catch (InvalidTimeZoneException) { throw new ResourceOperationException(400); }
        var count = (to.Date - from.Date).Days;
        if (from.TimeOfDay != TimeSpan.Zero || to.TimeOfDay != TimeSpan.Zero || count is < 1 or > MaximumDays)
            throw new ResourceOperationException(400);
        DateTimeOffset Boundary(DateTime date)
        {
            var local = DateTime.SpecifyKind(date, DateTimeKind.Unspecified);
            // Never guess a skipped/ambiguous midnight or manufacture a calendar day.
            if (zone.IsInvalidTime(local) || zone.IsAmbiguousTime(local)) throw new ResourceOperationException(400);
            return new(local, zone.GetUtcOffset(local));
        }
        var boundaries = Enumerable.Range(0, count + 1).Select(i => Boundary(from.Date.AddDays(i))).ToArray();
        if (boundaries[0] != from || boundaries[0].Offset != from.Offset || boundaries[^1] != to || boundaries[^1].Offset != to.Offset)
            throw new ResourceOperationException(400);
        var days = boundaries.Zip(boundaries.Skip(1), (start, end) => (From: start, To: end)).ToArray();
        if (days.Any(d => (d.To - d.From).TotalHours is < 22 or > 26)) throw new ResourceOperationException(400);
        return days;
    }
}
