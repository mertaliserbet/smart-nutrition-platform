using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Features.Dietitians;
using SmartNutrition.Api.Features.Relationships;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Tests;

public sealed class CrossFeatureAccessRegressionTests
{
    [PostgresFact]
    public async Task EverySharingCategoryOpensOnlyItsOwnFeatureAndRevocationDoesNotChangeOtherGrants()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(mealLogSharing: true,
            bodyMeasurementSharing: true, clientTaskSharing: true, waterLogSharing: true, environment: "Development");
        var now = DateTimeOffset.UtcNow; var hasher = new PasswordHasher<User>();
        var owner = new User(Guid.NewGuid(), "synthetic-u6-owner@example.test", UserRole.Client, "Synthetic U6 password", now, hasher);
        var profile = new ClientProfile(Guid.NewGuid(), owner, "Synthetic U6 client");
        var expert = new User(Guid.NewGuid(), "synthetic-u6-expert@example.test", UserRole.Dietitian, "Synthetic U6 password", now, hasher);
        var dietitian = new DietitianProfile(expert, "Synthetic U6 expert", "Synthetic license");
        var relationship = new DietitianClientRelationship(profile.Id, dietitian.Id, now); relationship.Respond(RelationshipStatus.Active, now);
        await using (var db = factory.Database())
        {
            db.Users.AddRange(owner, expert); db.Entry(owner).Property(u => u.IsEmailVerified).CurrentValue = true;
            db.Entry(expert).Property(u => u.IsEmailVerified).CurrentValue = true; db.Entry(dietitian).Property(d => d.IsVerified).CurrentValue = true;
            db.DietitianClientRelationships.Add(relationship); await db.SaveChangesAsync();
        }
        using var client = Bearer(owner, "client"); using var reader = Bearer(expert, "dietitian");
        var routes = new Dictionary<string, string>
        {
            ["nutrition_plans"] = $"/api/v1/nutrition-plans?clientId={profile.Id}&page=1&pageSize=10",
            ["meal_logs"] = $"/api/v1/dietitian/clients/{profile.Id}/meal-logs?page=1&pageSize=10",
            ["body_measurements"] = $"/api/v1/dietitian/clients/{profile.Id}/body-measurements?page=1&pageSize=10",
            ["client_tasks"] = $"/api/v1/client-tasks?clientId={profile.Id}&page=1&pageSize=10",
            ["water_logs"] = $"/api/v1/dietitian/clients/{profile.Id}/water-logs?page=1&pageSize=10"
        };
        var grants = new Dictionary<string, Guid>();
        foreach (var (category, path) in routes)
        {
            using var denied = await reader.GetAsync(path); await Denied(denied, HttpStatusCode.Forbidden);
            using var permission = await client.PostAsJsonAsync("/api/v1/data-sharing-permissions", new { relationshipId = relationship.Id, category, isGranted = false });
            Assert.Equal(HttpStatusCode.Created, permission.StatusCode);
            grants[category] = (await permission.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid();
        }
        foreach (var enabled in routes.Keys)
        {
            await SetGrant(enabled, true);
            foreach (var (category, path) in routes)
            {
                using var response = await reader.GetAsync(path);
                if (category == enabled) Assert.Equal(HttpStatusCode.OK, response.StatusCode);
                else await Denied(response, HttpStatusCode.Forbidden);
            }
            await SetGrant(enabled, false);
            await using var db = factory.Database(); Assert.False(await db.DataSharingPermissions.AnyAsync(p => p.IsGranted));
        }
        foreach (var category in routes.Keys) await SetGrant(category, true);
        // Removing current expert verification closes every category without deleting grants or client data.
        await using (var db = factory.Database()) await db.DietitianProfiles.Where(p => p.Id == dietitian.Id).ExecuteUpdateAsync(s => s.SetProperty(p => p.IsVerified, false));
        foreach (var path in routes.Values) { using var response = await reader.GetAsync(path); await Denied(response, HttpStatusCode.Forbidden); }
        foreach (var path in new[] { "/api/v1/water-logs?page=1&pageSize=10", "/api/v1/body-measurements?page=1&pageSize=10", "/api/v1/client-tasks?page=1&pageSize=10" })
        { using var response = await client.GetAsync(path); Assert.Equal(HttpStatusCode.OK, response.StatusCode); }
        await using (var db = factory.Database()) Assert.Equal(5, await db.DataSharingPermissions.CountAsync(p => p.IsGranted));

        async Task SetGrant(string category, bool isGranted)
        {
            using var response = await client.PatchAsJsonAsync("/api/v1/data-sharing-permissions/" + grants[category], new { isGranted });
            Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        }
        HttpClient Bearer(User user, string context)
        {
            var result = factory.Client(false);
            result.DefaultRequestHeaders.Authorization = new("Bearer", new JwtAccessTokenService(Options.Create(factory.Jwt.Options), TimeProvider.System).Issue(user).AccessToken);
            result.DefaultRequestHeaders.Add("X-Profile-Context", context); return result;
        }
    }
    private static async Task Denied(HttpResponseMessage response, HttpStatusCode status)
    {
        Assert.Equal(status, response.StatusCode); Assert.Contains("no-store", response.Headers.CacheControl!.ToString());
        var body = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.True(body.TryGetProperty("error", out _)); Assert.False(body.TryGetProperty("items", out _)); Assert.False(body.TryGetProperty("totalCount", out _));
    }
}
