using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SmartNutrition.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddMealLogs : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "meal_logs",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    client_id = table.Column<Guid>(type: "uuid", nullable: false),
                    meal_type = table.Column<string>(type: "text", nullable: false),
                    consumed_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    note = table.Column<string>(type: "text", nullable: true),
                    source = table.Column<string>(type: "text", nullable: false),
                    food_analysis_id = table.Column<Guid>(type: "uuid", nullable: true),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    deleted_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_meal_logs", x => x.id);
                    table.CheckConstraint("ck_meal_logs_analysis", "food_analysis_id IS NULL OR food_analysis_id <> '00000000-0000-0000-0000-000000000000'::uuid");
                    table.CheckConstraint("ck_meal_logs_note", "note IS NULL OR char_length(note) <= 2000");
                    table.CheckConstraint("ck_meal_logs_source", "source IN ('manual','wearable','ai_assisted')");
                    table.CheckConstraint("ck_meal_logs_type", "meal_type IN ('breakfast','lunch','dinner','snack','other')");
                    table.ForeignKey(
                        name: "fk_meal_logs_client_id",
                        column: x => x.client_id,
                        principalTable: "client_profiles",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "meal_log_items",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    meal_log_id = table.Column<Guid>(type: "uuid", nullable: false),
                    food_item_id = table.Column<Guid>(type: "uuid", nullable: true),
                    recipe_id = table.Column<Guid>(type: "uuid", nullable: true),
                    display_name = table.Column<string>(type: "text", nullable: false),
                    quantity_grams = table.Column<decimal>(type: "numeric", nullable: true),
                    calories_kcal = table.Column<decimal>(type: "numeric", nullable: true),
                    protein_grams = table.Column<decimal>(type: "numeric", nullable: true),
                    carbs_grams = table.Column<decimal>(type: "numeric", nullable: true),
                    fat_grams = table.Column<decimal>(type: "numeric", nullable: true),
                    is_estimated = table.Column<bool>(type: "boolean", nullable: false),
                    position = table.Column<int>(type: "integer", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_meal_log_items", x => x.id);
                    table.CheckConstraint("ck_meal_log_items_calories_kcal", "calories_kcal IS NULL OR (calories_kcal >= 0 AND calories_kcal < 'Infinity'::numeric)");
                    table.CheckConstraint("ck_meal_log_items_carbs_grams", "carbs_grams IS NULL OR (carbs_grams >= 0 AND carbs_grams < 'Infinity'::numeric)");
                    table.CheckConstraint("ck_meal_log_items_fat_grams", "fat_grams IS NULL OR (fat_grams >= 0 AND fat_grams < 'Infinity'::numeric)");
                    table.CheckConstraint("ck_meal_log_items_name", "char_length(btrim(display_name)) BETWEEN 1 AND 2000");
                    table.CheckConstraint("ck_meal_log_items_position", "position >= 0");
                    table.CheckConstraint("ck_meal_log_items_protein_grams", "protein_grams IS NULL OR (protein_grams >= 0 AND protein_grams < 'Infinity'::numeric)");
                    table.CheckConstraint("ck_meal_log_items_quantity", "quantity_grams IS NULL OR (quantity_grams > 0 AND quantity_grams < 'Infinity'::numeric)");
                    table.CheckConstraint("ck_meal_log_items_references", "(food_item_id IS NULL OR food_item_id <> '00000000-0000-0000-0000-000000000000'::uuid) AND (recipe_id IS NULL OR recipe_id <> '00000000-0000-0000-0000-000000000000'::uuid)");
                    table.ForeignKey(
                        name: "fk_meal_log_items_meal_log_id",
                        column: x => x.meal_log_id,
                        principalTable: "meal_logs",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "ix_meal_log_items_meal_log_id",
                table: "meal_log_items",
                column: "meal_log_id");

            migrationBuilder.CreateIndex(
                name: "ix_meal_logs_client_consumed_id",
                table: "meal_logs",
                columns: new[] { "client_id", "consumed_at", "id" },
                descending: new[] { false, true, false },
                filter: "deleted_at IS NULL");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql("""
                DO $$ BEGIN
                    IF EXISTS (SELECT 1 FROM meal_logs) THEN
                        RAISE EXCEPTION 'Meal tables contain records; an explicit data-preserving rollback is required.';
                    END IF;
                END $$;
                """);
            migrationBuilder.DropTable(
                name: "meal_log_items");

            migrationBuilder.DropTable(
                name: "meal_logs");
        }
    }
}
