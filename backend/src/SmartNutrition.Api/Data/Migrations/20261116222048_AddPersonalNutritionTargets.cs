using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SmartNutrition.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddPersonalNutritionTargets : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "personal_nutrition_targets",
                columns: table => new
                {
                    client_id = table.Column<Guid>(type: "uuid", nullable: false),
                    daily_calories_target_kcal = table.Column<decimal>(type: "numeric", nullable: true),
                    daily_protein_target_grams = table.Column<decimal>(type: "numeric", nullable: true),
                    daily_carbs_target_grams = table.Column<decimal>(type: "numeric", nullable: true),
                    daily_fat_target_grams = table.Column<decimal>(type: "numeric", nullable: true),
                    daily_water_target_ml = table.Column<decimal>(type: "numeric", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_personal_nutrition_targets", x => x.client_id);
                    table.CheckConstraint("ck_personal_nutrition_targets_calories", "daily_calories_target_kcal IS NULL OR (daily_calories_target_kcal > 0 AND daily_calories_target_kcal <= 10000)");
                    table.CheckConstraint("ck_personal_nutrition_targets_carbs", "daily_carbs_target_grams IS NULL OR (daily_carbs_target_grams > 0 AND daily_carbs_target_grams <= 1000)");
                    table.CheckConstraint("ck_personal_nutrition_targets_fat", "daily_fat_target_grams IS NULL OR (daily_fat_target_grams > 0 AND daily_fat_target_grams <= 1000)");
                    table.CheckConstraint("ck_personal_nutrition_targets_protein", "daily_protein_target_grams IS NULL OR (daily_protein_target_grams > 0 AND daily_protein_target_grams <= 1000)");
                    table.CheckConstraint("ck_personal_nutrition_targets_water", "daily_water_target_ml IS NULL OR (daily_water_target_ml > 0 AND daily_water_target_ml <= 15000)");
                    table.ForeignKey(
                        name: "fk_personal_nutrition_targets_client_id",
                        column: x => x.client_id,
                        principalTable: "client_profiles",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql("""
                DO $$ BEGIN
                    IF EXISTS (SELECT 1 FROM personal_nutrition_targets) THEN
                        RAISE EXCEPTION 'Personal targets exist; an explicit data-preserving rollback is required.';
                    END IF;
                END $$;
                """);
            migrationBuilder.DropTable(
                name: "personal_nutrition_targets");
        }
    }
}
