using Microsoft.EntityFrameworkCore;
using SmartNutrition.Api.Features.Auth;

namespace SmartNutrition.Api.Features.PersonalNutritionTargets;

// One current set of user-entered daily targets per client; not a program or consumption record.
public sealed class PersonalNutritionTarget
{
    internal const decimal MaxCaloriesKcal = 10000, MaxMacroGrams = 1000, MaxWaterMl = 15000;
    private PersonalNutritionTarget() { }
    internal PersonalNutritionTarget(Guid clientId)
    {
        if (clientId == Guid.Empty) throw new ArgumentException("A client-profile ID is required.", nameof(clientId));
        ClientId = clientId;
    }
    public Guid ClientId { get; private set; }
    public decimal? DailyCaloriesTargetKcal { get; private set; }
    public decimal? DailyProteinTargetGrams { get; private set; }
    public decimal? DailyCarbsTargetGrams { get; private set; }
    public decimal? DailyFatTargetGrams { get; private set; }
    public decimal? DailyWaterTargetMl { get; private set; }

    internal static bool Valid(decimal? value, decimal maximum) => value is null || value > 0 && value <= maximum;
    internal void Revise(decimal? calories, decimal? protein, decimal? carbs, decimal? fat, decimal? water)
    {
        if (!Valid(calories, MaxCaloriesKcal) || !Valid(protein, MaxMacroGrams) || !Valid(carbs, MaxMacroGrams) ||
            !Valid(fat, MaxMacroGrams) || !Valid(water, MaxWaterMl))
            throw new ArgumentOutOfRangeException(nameof(calories), "Known daily targets must be positive and within storage limits.");
        DailyCaloriesTargetKcal = calories; DailyProteinTargetGrams = protein; DailyCarbsTargetGrams = carbs;
        DailyFatTargetGrams = fat; DailyWaterTargetMl = water;
    }
    internal static void Configure(ModelBuilder builder)
    {
        var rows = builder.Entity<PersonalNutritionTarget>();
        rows.ToTable("personal_nutrition_targets", table =>
        {
            table.HasCheckConstraint("ck_personal_nutrition_targets_calories", "daily_calories_target_kcal IS NULL OR (daily_calories_target_kcal > 0 AND daily_calories_target_kcal <= 10000)");
            table.HasCheckConstraint("ck_personal_nutrition_targets_protein", "daily_protein_target_grams IS NULL OR (daily_protein_target_grams > 0 AND daily_protein_target_grams <= 1000)");
            table.HasCheckConstraint("ck_personal_nutrition_targets_carbs", "daily_carbs_target_grams IS NULL OR (daily_carbs_target_grams > 0 AND daily_carbs_target_grams <= 1000)");
            table.HasCheckConstraint("ck_personal_nutrition_targets_fat", "daily_fat_target_grams IS NULL OR (daily_fat_target_grams > 0 AND daily_fat_target_grams <= 1000)");
            table.HasCheckConstraint("ck_personal_nutrition_targets_water", "daily_water_target_ml IS NULL OR (daily_water_target_ml > 0 AND daily_water_target_ml <= 15000)");
        });
        rows.HasKey(x => x.ClientId).HasName("pk_personal_nutrition_targets");
        rows.Property(x => x.ClientId).HasColumnName("client_id").ValueGeneratedNever();
        rows.Property(x => x.DailyCaloriesTargetKcal).HasColumnName("daily_calories_target_kcal").HasColumnType("numeric");
        rows.Property(x => x.DailyProteinTargetGrams).HasColumnName("daily_protein_target_grams").HasColumnType("numeric");
        rows.Property(x => x.DailyCarbsTargetGrams).HasColumnName("daily_carbs_target_grams").HasColumnType("numeric");
        rows.Property(x => x.DailyFatTargetGrams).HasColumnName("daily_fat_target_grams").HasColumnType("numeric");
        rows.Property(x => x.DailyWaterTargetMl).HasColumnName("daily_water_target_ml").HasColumnType("numeric");
        rows.HasOne<ClientProfile>().WithOne().HasForeignKey<PersonalNutritionTarget>(x => x.ClientId)
            .OnDelete(DeleteBehavior.Restrict).HasConstraintName("fk_personal_nutrition_targets_client_id");
    }
}
