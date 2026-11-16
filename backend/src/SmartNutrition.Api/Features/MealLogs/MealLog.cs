using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Features.MealLogs;

/// <summary>
/// The application resolves ClientId from the authenticated User -> ClientProfile.
/// Local invariants do not authorize referenced resources. HTTP uses explicit DTOs.
/// </summary>
public sealed class MealLog
{
    private readonly List<MealLogItem> _items = [];
    private MealLog() { }

    public MealLog(
        Guid id,
        Guid clientId,
        MealType mealType,
        DateTimeOffset consumedAt,
        RecordSource source,
        DateTimeOffset createdAt,
        IEnumerable<MealLogItem> items,
        string? note = null,
        Guid? foodAnalysisId = null)
    {
        if (id == Guid.Empty)
            throw new ArgumentException("A meal-log ID is required.", nameof(id));
        if (clientId == Guid.Empty)
            throw new ArgumentException("A client-profile ID is required.", nameof(clientId));
        if (!Enum.IsDefined(mealType))
            throw new ArgumentException("The meal type is not supported.", nameof(mealType));
        if (!Enum.IsDefined(source))
            throw new ArgumentException("The record source is not supported.", nameof(source));
        if (consumedAt == default)
            throw new ArgumentException("Consumption time is required.", nameof(consumedAt));
        if (createdAt == default)
            throw new ArgumentException("Creation time is required.", nameof(createdAt));
        if (foodAnalysisId == Guid.Empty)
            throw new ArgumentException("An analysis reference must be a non-empty ID.", nameof(foodAnalysisId));

        ArgumentNullException.ThrowIfNull(items);
        var snapshot = items.ToArray();
        if (snapshot.Length == 0 || snapshot.Any(item => item is null))
            throw new ArgumentException("At least one non-null meal-log item is required.", nameof(items));
        if (snapshot.Any(item => item.MealLogId != id))
            throw new ArgumentException("Every item must belong to this meal log.", nameof(items));
        if (snapshot.Select(item => item.Id).Distinct().Count() != snapshot.Length)
            throw new ArgumentException("Meal-log item IDs must be unique within the log.", nameof(items));

        Id = id;
        ClientId = clientId;
        MealType = mealType;
        ConsumedAt = consumedAt.ToUniversalTime();
        Source = source;
        CreatedAt = createdAt.ToUniversalTime();
        _items.AddRange(snapshot);
        Note = note;
        FoodAnalysisId = foodAnalysisId;
    }

    public Guid Id { get; private set; }
    public Guid ClientId { get; private set; }
    public MealType MealType { get; private set; }
    public DateTimeOffset ConsumedAt { get; private set; }
    public string? Note { get; private set; }
    public RecordSource Source { get; private set; }
    public Guid? FoodAnalysisId { get; private set; }
    public DateTimeOffset CreatedAt { get; private set; }
    public IReadOnlyList<MealLogItem> Items => _items.AsReadOnly();
    internal DateTimeOffset? DeletedAt { get; private set; }

    internal void Revise(MealLog validated, bool replaceItems)
    {
        MealType = validated.MealType;
        ConsumedAt = validated.ConsumedAt;
        Note = validated.Note;
        FoodAnalysisId = validated.FoodAnalysisId;
        if (!replaceItems) return;
        _items.Clear();
        _items.AddRange(validated.Items);
    }

    internal void Delete(DateTimeOffset now) => DeletedAt = now.ToUniversalTime();
}
