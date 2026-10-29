using System.Text.Json;
using System.Text.Json.Serialization;

namespace SmartNutrition.Api.Models;

[JsonConverter(typeof(RelationshipStatusJsonConverter))]
public enum RelationshipStatus { Pending, Active, Rejected, Ended }
internal sealed class RelationshipStatusJsonConverter : JsonStringEnumConverter<RelationshipStatus>
{ public RelationshipStatusJsonConverter() : base(JsonNamingPolicy.SnakeCaseLower, allowIntegerValues: false) { } }
