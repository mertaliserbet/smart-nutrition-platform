using Microsoft.EntityFrameworkCore;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Features.MealLogs;

internal static class MealLogMapping
{
    internal static void Configure(ModelBuilder builder)
    {
        var logs = builder.Entity<MealLog>();
        logs.ToTable("meal_logs", table =>
        {
            table.HasCheckConstraint("ck_meal_logs_type", "meal_type IN ('breakfast','lunch','dinner','snack','other')");
            table.HasCheckConstraint("ck_meal_logs_source", "source IN ('manual','wearable','ai_assisted')");
            table.HasCheckConstraint("ck_meal_logs_note", "note IS NULL OR char_length(note) <= 2000");
            table.HasCheckConstraint("ck_meal_logs_analysis", "food_analysis_id IS NULL OR food_analysis_id <> '00000000-0000-0000-0000-000000000000'::uuid");
        });
        logs.HasKey(x => x.Id).HasName("pk_meal_logs");
        logs.Property(x => x.Id).HasColumnName("id").ValueGeneratedNever();
        logs.Property(x => x.ClientId).HasColumnName("client_id");
        logs.Property(x => x.MealType).HasColumnName("meal_type").HasConversion(x => x.ToString().ToLowerInvariant(), x => Enum.Parse<MealType>(x, true));
        logs.Property(x => x.ConsumedAt).HasColumnName("consumed_at");
        logs.Property(x => x.Note).HasColumnName("note");
        logs.Property(x => x.Source).HasColumnName("source").HasConversion(x => x == RecordSource.AiAssisted ? "ai_assisted" : x.ToString().ToLowerInvariant(),
            x => x == "ai_assisted" ? RecordSource.AiAssisted : Enum.Parse<RecordSource>(x, true));
        logs.Property(x => x.FoodAnalysisId).HasColumnName("food_analysis_id");
        logs.Property(x => x.CreatedAt).HasColumnName("created_at");
        logs.Property(x => x.DeletedAt).HasColumnName("deleted_at");
        logs.HasQueryFilter(x => x.DeletedAt == null);
        logs.HasOne<ClientProfile>().WithMany().HasForeignKey(x => x.ClientId).OnDelete(DeleteBehavior.Restrict).HasConstraintName("fk_meal_logs_client_id");
        logs.HasIndex(x => new { x.ClientId, x.ConsumedAt, x.Id }).IsDescending(false, true, false)
            .HasFilter("deleted_at IS NULL").HasDatabaseName("ix_meal_logs_client_consumed_id");
        logs.HasMany(x => x.Items).WithOne().HasForeignKey(x => x.MealLogId).OnDelete(DeleteBehavior.Restrict).HasConstraintName("fk_meal_log_items_meal_log_id");
        logs.Navigation(x => x.Items).HasField("_items").UsePropertyAccessMode(PropertyAccessMode.Field);

        var items = builder.Entity<MealLogItem>();
        items.ToTable("meal_log_items", table =>
        {
            table.HasCheckConstraint("ck_meal_log_items_name", "char_length(btrim(display_name)) BETWEEN 1 AND 2000");
            table.HasCheckConstraint("ck_meal_log_items_quantity", "quantity_grams IS NULL OR (quantity_grams > 0 AND quantity_grams < 'Infinity'::numeric)");
            foreach (var column in new[] { "calories_kcal", "protein_grams", "carbs_grams", "fat_grams" })
                table.HasCheckConstraint("ck_meal_log_items_" + column, $"{column} IS NULL OR ({column} >= 0 AND {column} < 'Infinity'::numeric)");
            table.HasCheckConstraint("ck_meal_log_items_references", "(food_item_id IS NULL OR food_item_id <> '00000000-0000-0000-0000-000000000000'::uuid) AND (recipe_id IS NULL OR recipe_id <> '00000000-0000-0000-0000-000000000000'::uuid)");
            table.HasCheckConstraint("ck_meal_log_items_position", "position >= 0");
        });
        items.HasKey(x => x.Id).HasName("pk_meal_log_items");
        items.Property(x => x.Id).HasColumnName("id").ValueGeneratedNever();
        items.Property(x => x.MealLogId).HasColumnName("meal_log_id");
        items.Property(x => x.FoodItemId).HasColumnName("food_item_id");
        items.Property(x => x.RecipeId).HasColumnName("recipe_id");
        items.Property(x => x.DisplayName).HasColumnName("display_name").IsRequired();
        items.Property(x => x.QuantityGrams).HasColumnName("quantity_grams").HasColumnType("numeric");
        items.Property(x => x.CaloriesKcal).HasColumnName("calories_kcal").HasColumnType("numeric");
        items.Property(x => x.ProteinGrams).HasColumnName("protein_grams").HasColumnType("numeric");
        items.Property(x => x.CarbsGrams).HasColumnName("carbs_grams").HasColumnType("numeric");
        items.Property(x => x.FatGrams).HasColumnName("fat_grams").HasColumnType("numeric");
        items.Property(x => x.IsEstimated).HasColumnName("is_estimated");
        // Internal storage order, never an additional HTTP field.
        items.Property<int>("Position").HasColumnName("position");
        items.HasIndex(x => new { x.MealLogId }).HasDatabaseName("ix_meal_log_items_meal_log_id");
    }
}
