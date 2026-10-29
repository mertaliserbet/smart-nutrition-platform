using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.EntityFrameworkCore;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Features.Dietitians;
using SmartNutrition.Api.Features.MealLogs;
using SmartNutrition.Api.Features.Relationships;

namespace SmartNutrition.Api.Features.NutritionPlans;

[JsonConverter(typeof(NutritionPlanStatusJsonConverter))]
public enum NutritionPlanStatus { Draft, Active, Archived }
internal sealed class NutritionPlanStatusJsonConverter : JsonStringEnumConverter<NutritionPlanStatus>
{ public NutritionPlanStatusJsonConverter() : base(JsonNamingPolicy.SnakeCaseLower, false) { } }

public sealed record NutritionPlanItem(Guid Id, Guid NutritionPlanId, int? DayOfWeek, MealType MealType,
    string Description, string? RecommendedQuantity, int SortOrder, Guid? RecipeId, Guid? AlternativeGroupId);
public sealed record NutritionPlanSnapshot(string Title, DateOnly StartDate, DateOnly? EndDate,
    decimal? DailyCaloriesTargetKcal, decimal? DailyWaterTargetMl, IReadOnlyList<NutritionPlanItem> Items);

public sealed class NutritionPlan
{
    internal static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web) { UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow };
    private NutritionPlan() { }
    internal NutritionPlan(Guid id, Guid clientId, Guid? dietitianId, NutritionPlanSnapshot content, DateTimeOffset now)
    { Id = id; ClientId = clientId; DietitianId = dietitianId; CreatedAt = RecordTime.Normalize(now); Revise(content); }
    public Guid Id { get; private set; }
    public Guid ClientId { get; private set; }
    public Guid? DietitianId { get; private set; }
    public string Title { get; private set; } = null!;
    public NutritionPlanStatus Status { get; private set; }
    public DateOnly StartDate { get; private set; }
    public DateOnly? EndDate { get; private set; }
    public decimal? DailyCaloriesTargetKcal { get; private set; }
    public decimal? DailyWaterTargetMl { get; private set; }
    public DateTimeOffset CreatedAt { get; private set; }
    public int VersionNumber { get; private set; }
    [JsonIgnore] public string ItemsJson { get; private set; } = "[]";
    internal NutritionPlanSnapshot Snapshot() => new(Title, StartDate, EndDate, DailyCaloriesTargetKcal, DailyWaterTargetMl,
        JsonSerializer.Deserialize<List<NutritionPlanItem>>(ItemsJson, Json) ?? throw new InvalidOperationException("Program content is unavailable."));
    internal void Revise(NutritionPlanSnapshot content)
    {
        Title = content.Title; StartDate = content.StartDate; EndDate = content.EndDate;
        DailyCaloriesTargetKcal = content.DailyCaloriesTargetKcal; DailyWaterTargetMl = content.DailyWaterTargetMl;
        ItemsJson = JsonSerializer.Serialize(content.Items, Json); VersionNumber++;
    }
    internal void SetStatus(NutritionPlanStatus status) => Status = status;
    internal static void Configure(ModelBuilder builder)
    {
        var rows = builder.Entity<NutritionPlan>();
        rows.ToTable("nutrition_plans", table =>
        {
            table.HasCheckConstraint("ck_nutrition_plans_title", "char_length(btrim(title)) BETWEEN 1 AND 120");
            table.HasCheckConstraint("ck_nutrition_plans_dates", "end_date IS NULL OR end_date >= start_date");
            table.HasCheckConstraint("ck_nutrition_plans_targets", "(daily_calories_target_kcal IS NULL OR (daily_calories_target_kcal > 0 AND daily_calories_target_kcal < 'Infinity'::numeric)) AND (daily_water_target_ml IS NULL OR (daily_water_target_ml > 0 AND daily_water_target_ml < 'Infinity'::numeric))");
            table.HasCheckConstraint("ck_nutrition_plans_status", "status IN ('draft','active','archived') AND version_number > 0");
            table.HasCheckConstraint("ck_nutrition_plans_items", "jsonb_typeof(items) = 'array' AND jsonb_array_length(items) BETWEEN 1 AND 100");
        });
        rows.HasKey(x => x.Id).HasName("pk_nutrition_plans"); rows.Property(x => x.Id).HasColumnName("id").ValueGeneratedNever();
        rows.Property(x => x.ClientId).HasColumnName("client_id"); rows.Property(x => x.DietitianId).HasColumnName("dietitian_id");
        rows.Property(x => x.Title).HasColumnName("title").IsRequired(); rows.Property(x => x.Status).HasColumnName("status").HasConversion(x => x.ToString().ToLowerInvariant(), x => Enum.Parse<NutritionPlanStatus>(x, true));
        rows.Property(x => x.StartDate).HasColumnName("start_date").HasColumnType("date"); rows.Property(x => x.EndDate).HasColumnName("end_date").HasColumnType("date");
        rows.Property(x => x.DailyCaloriesTargetKcal).HasColumnName("daily_calories_target_kcal").HasColumnType("numeric");
        rows.Property(x => x.DailyWaterTargetMl).HasColumnName("daily_water_target_ml").HasColumnType("numeric");
        rows.Property(x => x.CreatedAt).HasColumnName("created_at"); rows.Property(x => x.VersionNumber).HasColumnName("version_number");
        rows.Property(x => x.ItemsJson).HasColumnName("items").HasColumnType("jsonb").IsRequired();
        rows.HasOne<ClientProfile>().WithMany().HasForeignKey(x => x.ClientId).OnDelete(DeleteBehavior.NoAction).HasConstraintName("fk_nutrition_plans_client_id");
        rows.HasOne<DietitianProfile>().WithMany().HasForeignKey(x => x.DietitianId).OnDelete(DeleteBehavior.NoAction).HasConstraintName("fk_nutrition_plans_dietitian_id");
        rows.HasIndex(x => x.ClientId).IsUnique().HasFilter("status = 'active'").HasDatabaseName("ux_nutrition_plans_active_client");
        rows.HasIndex(x => x.DietitianId).HasDatabaseName("ix_nutrition_plans_dietitian_id");
    }
}

public sealed class NutritionPlanVersion
{
    private NutritionPlanVersion() { }
    internal NutritionPlanVersion(NutritionPlan plan, Guid actor, DateTimeOffset now)
    {
        Id = Guid.NewGuid(); NutritionPlanId = plan.Id; VersionNumber = plan.VersionNumber;
        RecordedByUserId = actor; CreatedAt = RecordTime.Normalize(now); SnapshotJson = JsonSerializer.Serialize(plan.Snapshot(), NutritionPlan.Json);
    }
    public Guid Id { get; private set; }
    public Guid NutritionPlanId { get; private set; }
    public int VersionNumber { get; private set; }
    [JsonIgnore] public Guid RecordedByUserId { get; private set; }
    public DateTimeOffset CreatedAt { get; private set; }
    [JsonIgnore] public string SnapshotJson { get; private set; } = null!;
    internal static void Configure(ModelBuilder builder)
    {
        var rows = builder.Entity<NutritionPlanVersion>(); rows.ToTable("nutrition_plan_versions", table =>
            table.HasCheckConstraint("ck_plan_versions_snapshot", "version_number > 0 AND jsonb_typeof(snapshot) = 'object'"));
        rows.HasKey(x => x.Id).HasName("pk_nutrition_plan_versions"); rows.Property(x => x.Id).HasColumnName("id").ValueGeneratedNever();
        rows.Property(x => x.NutritionPlanId).HasColumnName("nutrition_plan_id"); rows.Property(x => x.VersionNumber).HasColumnName("version_number");
        rows.Property(x => x.RecordedByUserId).HasColumnName("recorded_by_user_id"); rows.Property(x => x.CreatedAt).HasColumnName("created_at");
        rows.Property(x => x.SnapshotJson).HasColumnName("snapshot").HasColumnType("jsonb").IsRequired();
        rows.HasOne<NutritionPlan>().WithMany().HasForeignKey(x => x.NutritionPlanId).OnDelete(DeleteBehavior.NoAction).HasConstraintName("fk_plan_versions_plan_id");
        rows.HasOne<User>().WithMany().HasForeignKey(x => x.RecordedByUserId).OnDelete(DeleteBehavior.NoAction).HasConstraintName("fk_plan_versions_actor_id");
        rows.HasIndex(x => new { x.NutritionPlanId, x.VersionNumber }).IsUnique().HasDatabaseName("ux_plan_versions_number");
        rows.HasIndex(x => x.RecordedByUserId).HasDatabaseName("ix_plan_versions_actor_id");
        foreach (var property in rows.Metadata.GetProperties().Where(x => !x.IsPrimaryKey()))
            property.SetAfterSaveBehavior(Microsoft.EntityFrameworkCore.Metadata.PropertySaveBehavior.Throw);
    }
}

public sealed record NutritionPlanResponse(Guid Id, Guid ClientId, Guid? DietitianId, string Title, NutritionPlanStatus Status,
    DateOnly StartDate, DateOnly? EndDate, decimal? DailyCaloriesTargetKcal, decimal? DailyWaterTargetMl, DateTimeOffset CreatedAt,
    IReadOnlyList<NutritionPlanItem> Items, Guid VersionId, int VersionNumber)
{
    internal static NutritionPlanResponse From(NutritionPlan plan, Guid versionId) => new(plan.Id, plan.ClientId, plan.DietitianId, plan.Title,
        plan.Status, plan.StartDate, plan.EndDate, plan.DailyCaloriesTargetKcal, plan.DailyWaterTargetMl, plan.CreatedAt, plan.Snapshot().Items, versionId, plan.VersionNumber);
}
public sealed record NutritionPlanVersionInfo(Guid Id, Guid NutritionPlanId, int VersionNumber, DateTimeOffset CreatedAt);
public sealed record NutritionPlanVersionResponse(Guid Id, Guid NutritionPlanId, int VersionNumber, DateTimeOffset CreatedAt, NutritionPlanSnapshot Snapshot);
