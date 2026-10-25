using System.Text.Json;
using System.Text.Json.Serialization;

namespace SmartNutrition.Api.Models;

// Shared canonical source vocabulary; this does not enable device or AI ingestion.
[JsonConverter(typeof(RecordSourceJsonConverter))]
public enum RecordSource
{
    Manual,
    Wearable,
    AiAssisted
}

internal sealed class RecordSourceJsonConverter : JsonStringEnumConverter<RecordSource>
{
    public RecordSourceJsonConverter() : base(JsonNamingPolicy.SnakeCaseLower, allowIntegerValues: false) { }
}
