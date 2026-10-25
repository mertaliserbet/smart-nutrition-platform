using System.Text.Json;
using System.Text.Json.Serialization;

namespace SmartNutrition.Api.Features.MealLogs;

[JsonConverter(typeof(MealTypeJsonConverter))]
public enum MealType
{
    Breakfast,
    Lunch,
    Dinner,
    Snack,
    Other
}

internal sealed class MealTypeJsonConverter : JsonStringEnumConverter<MealType>
{
    public MealTypeJsonConverter() : base(JsonNamingPolicy.SnakeCaseLower, allowIntegerValues: false) { }
}
