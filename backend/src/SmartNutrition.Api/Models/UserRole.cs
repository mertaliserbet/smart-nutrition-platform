using System.Text.Json;
using System.Text.Json.Serialization;

namespace SmartNutrition.Api.Models;

[JsonConverter(typeof(UserRoleJsonConverter))]
public enum UserRole
{
    Client,
    Dietitian,
    Admin
}

internal sealed class UserRoleJsonConverter : JsonStringEnumConverter<UserRole>
{
    public UserRoleJsonConverter() : base(JsonNamingPolicy.SnakeCaseLower, allowIntegerValues: false) { }
}
