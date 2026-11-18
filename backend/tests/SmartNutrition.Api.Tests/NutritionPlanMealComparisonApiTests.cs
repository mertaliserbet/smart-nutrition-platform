using System.Data.Common;
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Features.Dietitians;
using SmartNutrition.Api.Features.MealLogs;
using SmartNutrition.Api.Features.NutritionPlans;
using SmartNutrition.Api.Features.Relationships;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Tests;

public sealed class NutritionPlanMealComparisonApiTests
{
    private const string Password = "Synthetic comparison password";
    private const string Private = "Synthetic private comparison content";
    private sealed record Pair(User Owner, ClientProfile Client, User Expert, DietitianProfile Profile,
        DietitianClientRelationship Relationship, DataSharingPermission Plans, DataSharingPermission Meals);
    private static string Route(JsonElement plan, string from = "2026-11-18T00:00:00Z", string to = "2026-11-19T00:00:00Z") =>
        $"/api/v1/nutrition-plans/{plan.GetProperty("id").GetGuid()}/versions/{plan.GetProperty("versionId").GetGuid()}/meal-comparison?from={Uri.EscapeDataString(from)}&to={Uri.EscapeDataString(to)}";

    [PostgresFact]
    public async Task AssignedProgramWithNoItemsForSelectedDayKeepsActualConsumptionAndOwnerAccess()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory);
        using var owner = Bearer(factory, pair.Owner, "client"); using var expert = Bearer(factory, pair.Expert);
        using var absent = await owner.GetAsync("/api/v1/nutrition-plans/active"); await Error(absent, HttpStatusCode.NotFound);
        using var created = await expert.PostAsJsonAsync("/api/v1/nutrition-plans", new
        {
            clientId = pair.Client.Id, title = Private, startDate = "2026-11-01", endDate = "2026-11-30",
            dailyCaloriesTargetKcal = 1000m,
            items = new[] { new { dayOfWeek = 4, mealType = "lunch", description = Private, sortOrder = 0 } }
        });
        Assert.Equal(HttpStatusCode.Created, created.StatusCode);
        var plan = await created.Content.ReadFromJsonAsync<JsonElement>();
        using var activated = await expert.PostAsync($"/api/v1/nutrition-plans/{plan.GetProperty("id").GetGuid()}/activate", null);
        Assert.Equal(HttpStatusCode.OK, activated.StatusCode);
        var active = await owner.GetFromJsonAsync<JsonElement>("/api/v1/nutrition-plans/active");
        Assert.Equal(pair.Profile.Id, active.GetProperty("dietitianId").GetGuid());

        // Wednesday has no prescribed items. Neither planned food nor consumption is invented.
        var empty = await Read(owner, plan);
        Assert.All(empty.Meals, meal => { Assert.Empty(meal.PlannedItems); Assert.Equal(0, meal.Actual.ItemCount); });
        Assert.Equal(0, empty.Actual.MealLogCount); Assert.Null(empty.CaloriesDifferenceKcal);
        await Meal(owner, calories: 125.5m, type: "snack");
        var consumed = await Read(expert, plan);
        Assert.All(consumed.Meals, meal => Assert.Empty(meal.PlannedItems));
        Assert.Equal(1, consumed.Meals.Single(x => x.MealType == MealType.Snack).Actual.MealLogCount);
        Assert.Equal(new NutritionValueSummary(125.5m, 0), consumed.Actual.CaloriesKcal);
        Assert.Equal(-874.5m, consumed.CaloriesDifferenceKcal);
        Assert.Equal(plan.GetProperty("versionId").GetGuid(), consumed.NutritionPlanVersion.Id);

        using var ended = await owner.PostAsync($"/api/v1/dietitian-relationships/{pair.Relationship.Id}/end", null);
        Assert.Equal(HttpStatusCode.OK, ended.StatusCode);
        using var denied = await expert.GetAsync(Route(plan)); await Error(denied, HttpStatusCode.NotFound);
        Assert.Equal(consumed.Actual, (await Read(owner, plan)).Actual);
    }

    [PostgresFact]
    public async Task MultipleItemsAndMealTypesPreserveMissingMacrosSeparatelyFromGenuineZero()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory);
        using var owner = Bearer(factory, pair.Owner, "client"); var plan = await Plan(owner);
        using var created = await owner.PostAsJsonAsync("/api/v1/meal-logs", new
        {
            mealType = "breakfast", consumedAt = "2026-11-18T08:00:00Z", source = "manual",
            items = new[]
            {
                new { displayName = "Synthetic first food", isEstimated = false, caloriesKcal = (decimal?)200.25m, proteinGrams = (decimal?)10.5m, carbsGrams = (decimal?)null, fatGrams = (decimal?)0m },
                new { displayName = "Synthetic second food", isEstimated = true, caloriesKcal = (decimal?)null, proteinGrams = (decimal?)0m, carbsGrams = (decimal?)12.25m, fatGrams = (decimal?)null },
                new { displayName = "Synthetic third food", isEstimated = false, caloriesKcal = (decimal?)50.75m, proteinGrams = (decimal?)null, carbsGrams = (decimal?)0m, fatGrams = (decimal?)4.5m }
            }
        });
        Assert.Equal(HttpStatusCode.Created, created.StatusCode);
        await Meal(owner, calories: 100m, type: "dinner");
        var body = await Read(owner, plan);
        Assert.Equal(2, body.Actual.MealLogCount); Assert.Equal(4, body.Actual.ItemCount); Assert.Equal(1, body.Actual.EstimatedItemCount);
        Assert.Equal(new NutritionValueSummary(351m, 1), body.Actual.CaloriesKcal);
        Assert.Equal(new NutritionValueSummary(10.5m, 2), body.Actual.ProteinGrams);
        Assert.Equal(new NutritionValueSummary(12.25m, 2), body.Actual.CarbsGrams);
        Assert.Equal(new NutritionValueSummary(4.5m, 1), body.Actual.FatGrams);
        Assert.Null(body.CaloriesDifferenceKcal);
        var breakfast = body.Meals.Single(x => x.MealType == MealType.Breakfast);
        Assert.Equal(3, breakfast.Actual.ItemCount); Assert.Equal(2, breakfast.PlannedItems.Count);
        Assert.Equal(breakfast.PlannedItems[0].AlternativeGroupId, breakfast.PlannedItems[1].AlternativeGroupId);
        Assert.Equal(new NutritionValueSummary(10.5m, 1), breakfast.Actual.ProteinGrams);
        Assert.Equal(0, body.Meals.Single(x => x.MealType == MealType.Other).Actual.ItemCount);
    }

    [PostgresFact]
    public async Task OwnComparisonWorksWithoutRelationshipAndUsesNullableValuesAndAlternatives()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory);
        using var owner = Bearer(factory, pair.Owner, "client"); var plan = await Plan(owner);
        await Meal(owner, calories: 125.125m); await Meal(owner, calories: null, estimated: true);
        using var response = await owner.GetAsync(Route(plan)); Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Contains("no-store", response.Headers.CacheControl!.ToString());
        var body = (await response.Content.ReadFromJsonAsync<NutritionPlanMealComparisonResponse>())!;
        Assert.Equal(pair.Client.Id, body.ClientId); Assert.Equal(new DateOnly(2026, 11, 18), body.Date);
        Assert.Equal(2, body.Actual.MealLogCount); Assert.Equal(2, body.Actual.ItemCount); Assert.Equal(1, body.Actual.EstimatedItemCount);
        Assert.Equal(new NutritionValueSummary(125.125m, 1), body.Actual.CaloriesKcal);
        Assert.Equal(new NutritionValueSummary(0m, 2), body.Actual.ProteinGrams);
        Assert.Equal(new NutritionValueSummary(0m, 0), body.Actual.FatGrams); Assert.Null(body.CaloriesDifferenceKcal);
        Assert.Equal(Enum.GetValues<MealType>(), body.Meals.Select(x => x.MealType));
        var breakfast = body.Meals[0]; Assert.Equal(2, breakfast.PlannedItems.Count);
        Assert.Equal(breakfast.PlannedItems[0].AlternativeGroupId, breakfast.PlannedItems[1].AlternativeGroupId);
        Assert.Equal(new[] { 0, 1 }, breakfast.PlannedItems.Select(x => x.SortOrder)); Assert.Equal(0, breakfast.Actual.ItemCount);
        Assert.Single(body.Meals[1].PlannedItems); Assert.Equal(2, body.Meals[1].Actual.ItemCount);
        Assert.DoesNotContain(body.Meals.SelectMany(x => x.PlannedItems), x => x.DayOfWeek == 4);
        await using (var db = factory.Database())
            await db.DietitianClientRelationships.Where(x => x.Id == pair.Relationship.Id).ExecuteUpdateAsync(x => x.SetProperty(p => p.Status, RelationshipStatus.Ended));
        using var stillOwn = await owner.GetAsync(Route(plan)); Assert.Equal(HttpStatusCode.OK, stillOwn.StatusCode);
        Assert.DoesNotContain(Private, factory.Logs);
    }

    [PostgresFact]
    public async Task CompleteRecordedCaloriesHaveSignedDifferenceButEmptyDayAndMissingTargetDoNot()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory);
        using var owner = Bearer(factory, pair.Owner, "client"); var plan = await Plan(owner);
        var empty = await Read(owner, plan); Assert.Equal(0, empty.Actual.ItemCount); Assert.Null(empty.CaloriesDifferenceKcal);
        await Meal(owner, calories: 0m); Assert.Equal(-1000m, (await Read(owner, plan)).CaloriesDifferenceKcal);
        await Meal(owner, calories: 1200.25m); Assert.Equal(200.25m, (await Read(owner, plan)).CaloriesDifferenceKcal);
        var withoutTarget = await Plan(owner, target: null); Assert.Null((await Read(owner, withoutTarget)).CaloriesDifferenceKcal);
    }

    [PostgresFact]
    public async Task LocalMidnightBoundsSoftDeleteOtherClientsAndAllRecordsAreHandledOnServer()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory);
        using var owner = Bearer(factory, pair.Owner, "client"); var plan = await Plan(owner);
        await Meal(owner, time: "2026-11-17T20:59:59.999999Z", calories: 900m);
        for (var i = 0; i < 12; i++) await Meal(owner, time: "2026-11-17T21:00:00Z", calories: 10.1m);
        await Meal(owner, time: "2026-11-18T20:59:59.999999Z", calories: 20m, type: "dinner");
        await Meal(owner, time: "2026-11-18T21:00:00Z", calories: 900m);
        var removed = await Meal(owner, calories: 900m);
        using var deletion = await owner.DeleteAsync($"/api/v1/meal-logs/{removed.GetProperty("id").GetGuid()}"); Assert.Equal(HttpStatusCode.NoContent, deletion.StatusCode);
        var stranger = await Seed(factory); using var other = Bearer(factory, stranger.Owner, "client"); await Meal(other, calories: 900m);
        using var expert = Bearer(factory, pair.Expert);
        var body = (await expert.GetFromJsonAsync<NutritionPlanMealComparisonResponse>(Route(plan, "2026-11-18T00:00:00+03:00", "2026-11-19T00:00:00+03:00")))!;
        Assert.Equal(new DateOnly(2026, 11, 18), body.Date); Assert.Equal(13, body.Actual.MealLogCount); Assert.Equal(141.2m, body.Actual.CaloriesKcal.KnownTotal);
        Assert.Equal(12, body.Meals[1].Actual.ItemCount); Assert.Equal(1, body.Meals[2].Actual.ItemCount);
    }

    [PostgresFact]
    public async Task DaylightSavingBoundariesAndExplicitOldSnapshotSurviveProgramRevision()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory);
        using var owner = Bearer(factory, pair.Owner, "client"); var plan = await Plan(owner);
        foreach (var (from, to, hours) in new[] { ("2026-03-29T00:00:00+01:00", "2026-03-30T00:00:00+02:00", 23), ("2026-10-25T00:00:00+02:00", "2026-10-26T00:00:00+01:00", 25) })
        {
            var body = (await owner.GetFromJsonAsync<NutritionPlanMealComparisonResponse>(Route(plan, from, to)))!;
            Assert.Equal(hours, (body.To - body.From).TotalHours);
        }
        await Meal(owner, calories: 1200m);
        using var changed = await owner.PatchAsJsonAsync($"/api/v1/nutrition-plans/{plan.GetProperty("id").GetGuid()}", new { title = "Synthetic revised program", dailyCaloriesTargetKcal = 2000m });
        Assert.Equal(HttpStatusCode.OK, changed.StatusCode); var revised = await changed.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal(200m, (await Read(owner, plan)).CaloriesDifferenceKcal); Assert.Equal(-800m, (await Read(owner, revised)).CaloriesDifferenceKcal);
        Assert.Equal(1, (await Read(owner, plan)).NutritionPlanVersion.VersionNumber);
    }

    [PostgresFact]
    public async Task BothIndependentPermissionsAreRequiredAndWithdrawalCannotLeakPartialSummary()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory);
        using var owner = Bearer(factory, pair.Owner, "client"); using var expert = Bearer(factory, pair.Expert); var plan = await Plan(owner); await Meal(owner);
        foreach (var permission in new[] { pair.Plans, pair.Meals })
        {
            await using (var db = factory.Database())
                await db.DataSharingPermissions.Where(x => x.Id == permission.Id).ExecuteUpdateAsync(x => x.SetProperty(p => p.IsGranted, false));
            using var denied = await expert.GetAsync(Route(plan)); await Error(denied, HttpStatusCode.Forbidden);
            using var independent = await expert.GetAsync(permission.Id == pair.Plans.Id
                ? $"/api/v1/dietitian/clients/{pair.Client.Id}/meal-logs?page=1&pageSize=10" : $"/api/v1/nutrition-plans/{plan.GetProperty("id").GetGuid()}");
            Assert.Equal(HttpStatusCode.OK, independent.StatusCode);
            await using (var db = factory.Database())
                await db.DataSharingPermissions.Where(x => x.Id == permission.Id).ExecuteUpdateAsync(x => x.SetProperty(p => p.IsGranted, true));
        }
        using var allowed = await expert.GetAsync(Route(plan)); Assert.Equal(HttpStatusCode.OK, allowed.StatusCode);
        using var revoke = await owner.PatchAsJsonAsync($"/api/v1/data-sharing-permissions/{pair.Meals.Id}", new { isGranted = false }); Assert.Equal(HttpStatusCode.OK, revoke.StatusCode);
        using var after = await expert.GetAsync(Route(plan)); await Error(after, HttpStatusCode.Forbidden);
    }

    [PostgresFact]
    public async Task ForeignEndedPendingAndUnverifiedExpertsCannotRead()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory);
        using var owner = Bearer(factory, pair.Owner, "client"); var plan = await Plan(owner); var other = await Seed(factory);
        using var foreign = Bearer(factory, other.Expert); using var foreignRead = await foreign.GetAsync(Route(plan)); await Error(foreignRead, HttpStatusCode.NotFound);
        using var foreignOwner = Bearer(factory, other.Owner, "client"); using var ownRead = await foreignOwner.GetAsync(Route(plan)); await Error(ownRead, HttpStatusCode.NotFound);
        using var expert = Bearer(factory, pair.Expert);
        foreach (var status in new[] { RelationshipStatus.Pending, RelationshipStatus.Ended, RelationshipStatus.Active })
        {
            await using var db = factory.Database(); await db.DietitianClientRelationships.Where(x => x.Id == pair.Relationship.Id).ExecuteUpdateAsync(x => x.SetProperty(p => p.Status, status));
            using var response = await expert.GetAsync(Route(plan)); Assert.Equal(status == RelationshipStatus.Active ? HttpStatusCode.OK : HttpStatusCode.NotFound, response.StatusCode);
        }
        await using (var db = factory.Database())
            await db.DietitianProfiles.Where(x => x.Id == pair.Profile.Id).ExecuteUpdateAsync(x => x.SetProperty(p => p.IsVerified, false));
        using var unverified = await expert.GetAsync(Route(plan)); await Error(unverified, HttpStatusCode.Forbidden);
        await using (var db = factory.Database()) await db.Users.Where(x => x.Id == pair.Expert.Id).ExecuteUpdateAsync(x => x.SetProperty(p => p.IsEmailVerified, false));
        using var stale = await expert.GetAsync(Route(plan)); await Error(stale, HttpStatusCode.Unauthorized);
    }

    [PostgresFact]
    public async Task DualProfileCookieAndBearerUseSameAccessAndAdminMfaIsNotHealthPermission()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(webSessions: true); var pair = await Seed(factory, dual: true);
        using var owner = Bearer(factory, pair.Owner, "client"); var plan = await Plan(owner);
        using var jwt = Bearer(factory, pair.Expert); using var jwtRead = await jwt.GetAsync(Route(plan)); Assert.Equal(HttpStatusCode.OK, jwtRead.StatusCode);
        using var web = factory.Client(); await Login(web, pair.Expert);
        using var read = await web.GetAsync(Route(plan)); Assert.Equal(HttpStatusCode.OK, read.StatusCode);
        web.DefaultRequestHeaders.Add("X-Profile-Context", "client"); using var wrongContext = await web.GetAsync(Route(plan)); await Error(wrongContext, HttpStatusCode.Forbidden);
        using var anonymous = factory.Client(false); using var noLogin = await anonymous.GetAsync(Route(plan)); await Error(noLogin, HttpStatusCode.Unauthorized);
        await using var db = factory.Database();
        var admin = new User(Guid.NewGuid(), Guid.NewGuid().ToString("N") + "@EXAMPLE.TEST", UserRole.Admin, Password, DateTimeOffset.UtcNow, new PasswordHasher<User>());
        using var scope = factory.Services.CreateScope(); var setup = scope.ServiceProvider.GetRequiredService<AdminMfaService>().Initialize(admin, DateTimeOffset.UtcNow);
        db.Users.Add(admin); db.Entry(admin).Property(x => x.IsEmailVerified).CurrentValue = true; await db.SaveChangesAsync();
        using var adminWeb = factory.Client(); await Login(adminWeb, admin, setup.RecoveryCodes[0]);
        using var denied = await adminWeb.GetAsync(Route(plan)); await Error(denied, HttpStatusCode.Forbidden);
    }

    [PostgresFact]
    public async Task StrictInputsDateBoundsVersionOwnershipAndReadOnlyMethodsAreEnforced()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory);
        using var owner = Bearer(factory, pair.Owner, "client"); var plan = await Plan(owner); var path = Route(plan).Split('?')[0];
        foreach (var query in new[] { "", "from=2026-11-18T00:00:00Z", "from=invalid&to=2026-11-19T00:00:00Z", "from=2026-11-18T00:00:00&to=2026-11-19T00:00:00Z",
            "from=2026-11-18T01:00:00Z&to=2026-11-19T00:00:00Z", "from=2026-11-18T00:00:00Z&to=2026-11-20T00:00:00Z",
            "from=2026-11-18T00:00:00Z&to=2026-11-18T00:00:00Z", "from=2026-11-18T00:00:00Z&to=2026-11-19T00:00:00Z&from=2026-11-18T00:00:00Z",
            "from=2026-11-18T00:00:00Z&to=2026-11-19T00:00:00Z&page=1" })
        { using var response = await owner.GetAsync(path + "?" + query); await Error(response, HttpStatusCode.BadRequest); }
        using var body = new HttpRequestMessage(HttpMethod.Get, Route(plan)) { Content = JsonContent.Create(new { }) };
        using var withBody = await owner.SendAsync(body); await Error(withBody, HttpStatusCode.BadRequest);
        using var before = await owner.GetAsync(Route(plan, "2025-12-31T00:00:00Z", "2026-01-01T00:00:00Z")); await Error(before, HttpStatusCode.UnprocessableEntity);
        var bounded = await Plan(owner, endDate: "2026-11-18"); using var last = await owner.GetAsync(Route(bounded)); Assert.Equal(HttpStatusCode.OK, last.StatusCode);
        using var after = await owner.GetAsync(Route(bounded, "2026-11-19T00:00:00Z", "2026-11-20T00:00:00Z")); await Error(after, HttpStatusCode.UnprocessableEntity);
        using var wrongVersion = await owner.GetAsync(Route(plan).Replace(plan.GetProperty("versionId").GetString()!, bounded.GetProperty("versionId").GetString())); await Error(wrongVersion, HttpStatusCode.NotFound);
        foreach (var method in new[] { HttpMethod.Post, HttpMethod.Patch, HttpMethod.Delete })
        { using var request = new HttpRequestMessage(method, Route(plan)); using var response = await owner.SendAsync(request); Assert.Equal(HttpStatusCode.MethodNotAllowed, response.StatusCode); }
    }

    [PostgresFact]
    public async Task DecimalOverflowIsRejectedBothWithinAMealAndAcrossMealTypes()
    {
        await using var factory = await RegistrationApiFactory.CreateAsync(); var pair = await Seed(factory);
        using var owner = Bearer(factory, pair.Owner, "client"); var plan = await Plan(owner);
        await Meal(owner, calories: decimal.MaxValue); var second = await Meal(owner, calories: decimal.MaxValue);
        using var sql = await owner.GetAsync(Route(plan)); await Error(sql, HttpStatusCode.UnprocessableEntity);
        using var changed = await owner.PatchAsJsonAsync($"/api/v1/meal-logs/{second.GetProperty("id").GetGuid()}", new { mealType = "dinner" }); Assert.Equal(HttpStatusCode.OK, changed.StatusCode);
        using var total = await owner.GetAsync(Route(plan)); await Error(total, HttpStatusCode.UnprocessableEntity);
    }

    [PostgresFact]
    public async Task WithdrawalAfterStartedSnapshotAllowsOnlyThatReadAndStorageFailureDoesNotExposeData()
    {
        var pause = new AggregatePause(); await using var factory = await RegistrationApiFactory.CreateAsync(interceptor: pause);
        var pair = await Seed(factory); using var owner = Bearer(factory, pair.Owner, "client"); var plan = await Plan(owner); await Meal(owner);
        using var expert = Bearer(factory, pair.Expert); pause.Armed = true; var read = expert.GetAsync(Route(plan));
        try
        {
            await pause.Entered.Task.WaitAsync(TimeSpan.FromSeconds(15));
            using var revoke = await owner.PatchAsJsonAsync($"/api/v1/data-sharing-permissions/{pair.Plans.Id}", new { isGranted = false }); Assert.Equal(HttpStatusCode.OK, revoke.StatusCode);
        }
        finally { pause.Release.TrySetResult(); }
        using var started = await read; Assert.Equal(HttpStatusCode.OK, started.StatusCode);
        using var next = await expert.GetAsync(Route(plan)); await Error(next, HttpStatusCode.Forbidden);
        pause.Fail = true; using var failure = await owner.GetAsync(Route(plan)); await Error(failure, HttpStatusCode.InternalServerError);
        Assert.DoesNotContain(Private, factory.Logs);
    }

    private static async Task<Pair> Seed(RegistrationApiFactory factory, bool dual = false)
    {
        await using var db = factory.Database(); var now = DateTimeOffset.UtcNow;
        var owner = new User(Guid.NewGuid(), Guid.NewGuid().ToString("N") + "@EXAMPLE.TEST", UserRole.Client, Password, now, new PasswordHasher<User>());
        var client = new ClientProfile(Guid.NewGuid(), owner, "Synthetic comparison client");
        var expert = new User(Guid.NewGuid(), Guid.NewGuid().ToString("N") + "@EXAMPLE.TEST", dual ? UserRole.Client : UserRole.Dietitian, Password, now, new PasswordHasher<User>());
        var profile = new DietitianProfile(expert, "Synthetic comparison expert", "Synthetic license"); if (dual) _ = new ClientProfile(Guid.NewGuid(), expert, "Synthetic dual profile");
        db.Users.AddRange(owner, expert); db.Entry(owner).Property(x => x.IsEmailVerified).CurrentValue = true; db.Entry(expert).Property(x => x.IsEmailVerified).CurrentValue = true;
        db.Entry(profile).Property(x => x.IsVerified).CurrentValue = true;
        var relationship = new DietitianClientRelationship(client.Id, profile.Id, now); relationship.Respond(RelationshipStatus.Active, now);
        var plans = new DataSharingPermission(relationship.Id, true, now); var meals = new DataSharingPermission(relationship.Id, true, now, "meal_logs");
        db.DietitianClientRelationships.Add(relationship); db.DataSharingPermissions.AddRange(plans, meals); await db.SaveChangesAsync();
        return new(owner, client, expert, profile, relationship, plans, meals);
    }
    private static HttpClient Bearer(RegistrationApiFactory factory, User user, string context = "dietitian")
    {
        var client = factory.Client(false); var jwt = new JwtAccessTokenService(Options.Create(factory.Jwt.Options), TimeProvider.System).Issue(user);
        client.DefaultRequestHeaders.Authorization = new("Bearer", jwt.AccessToken); client.DefaultRequestHeaders.Add("X-Profile-Context", context); return client;
    }
    private static async Task<JsonElement> Plan(HttpClient owner, decimal? target = 1000m, string? endDate = null)
    {
        var group = Guid.NewGuid(); object Item(int order, string type, int? day, Guid? alternative) => new { mealType = type, description = Private,
            recommendedQuantity = "Synthetic portion", sortOrder = order, dayOfWeek = day, alternativeGroupId = alternative };
        using var response = await owner.PostAsJsonAsync("/api/v1/nutrition-plans", new { title = Private, startDate = "2026-01-01", endDate,
            dailyCaloriesTargetKcal = target, items = new[] { Item(1, "breakfast", null, group), Item(0, "breakfast", null, group), Item(2, "lunch", 3, null), Item(3, "dinner", 4, null) } });
        Assert.Equal(HttpStatusCode.Created, response.StatusCode); return await response.Content.ReadFromJsonAsync<JsonElement>();
    }
    private static async Task<JsonElement> Meal(HttpClient owner, string time = "2026-11-18T12:00:00Z", decimal? calories = 100m, bool estimated = false, string type = "lunch")
    {
        using var response = await owner.PostAsJsonAsync("/api/v1/meal-logs", new { mealType = type, consumedAt = time, source = "manual", note = Private,
            items = new[] { new { displayName = Private, isEstimated = estimated, caloriesKcal = calories, fatGrams = 0m } } });
        Assert.Equal(HttpStatusCode.Created, response.StatusCode); return await response.Content.ReadFromJsonAsync<JsonElement>();
    }
    private static async Task<NutritionPlanMealComparisonResponse> Read(HttpClient client, JsonElement plan) => (await client.GetFromJsonAsync<NutritionPlanMealComparisonResponse>(Route(plan)))!;
    private static async Task Login(HttpClient client, User user, string? recovery = null)
    {
        var csrf = await client.GetFromJsonAsync<JsonElement>("/api/v1/auth/csrf");
        using var request = new HttpRequestMessage(HttpMethod.Post, recovery is null ? "/api/v1/auth/web-session" : "/api/v1/auth/admin-web-session")
        { Content = JsonContent.Create(recovery is null ? (object)new { email = user.Email, password = Password } : new { email = user.Email, password = Password, mfaCode = recovery }) };
        request.Headers.Add("Origin", "https://localhost"); request.Headers.Add("X-CSRF-TOKEN", csrf.GetProperty("requestToken").GetString());
        using var response = await client.SendAsync(request); Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }
    private static async Task Error(HttpResponseMessage response, HttpStatusCode status)
    {
        Assert.Equal(status, response.StatusCode); var text = await response.Content.ReadAsStringAsync(); var body = JsonSerializer.Deserialize<JsonElement>(text);
        Assert.True(body.TryGetProperty("error", out _)); Assert.False(string.IsNullOrWhiteSpace(body.GetProperty("requestId").GetString()));
        Assert.DoesNotContain(Private, text); Assert.False(body.TryGetProperty("actual", out _)); Assert.False(body.TryGetProperty("nutritionPlanVersion", out _));
    }
    private sealed class AggregatePause : DbCommandInterceptor
    {
        public bool Armed { get; set; } public bool Fail { get; set; }
        public TaskCompletionSource Entered { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public TaskCompletionSource Release { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public override async ValueTask<InterceptionResult<DbDataReader>> ReaderExecutingAsync(DbCommand command, CommandEventData eventData,
            InterceptionResult<DbDataReader> result, CancellationToken cancellationToken = default)
        {
            if (command.CommandText.Contains("FROM meal_logs", StringComparison.Ordinal))
            {
                if (Fail) throw new InvalidOperationException("Synthetic comparison storage failure");
                if (Armed) { Armed = false; Entered.TrySetResult(); await Release.Task.WaitAsync(TimeSpan.FromSeconds(15), cancellationToken); }
            }
            return result;
        }
    }
}
