using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SmartNutrition.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddNutritionPlansAndVersions : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "nutrition_plans",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    client_id = table.Column<Guid>(type: "uuid", nullable: false),
                    dietitian_id = table.Column<Guid>(type: "uuid", nullable: true),
                    title = table.Column<string>(type: "text", nullable: false),
                    status = table.Column<string>(type: "text", nullable: false),
                    start_date = table.Column<DateOnly>(type: "date", nullable: false),
                    end_date = table.Column<DateOnly>(type: "date", nullable: true),
                    daily_calories_target_kcal = table.Column<decimal>(type: "numeric", nullable: true),
                    daily_water_target_ml = table.Column<decimal>(type: "numeric", nullable: true),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    version_number = table.Column<int>(type: "integer", nullable: false),
                    items = table.Column<string>(type: "jsonb", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_nutrition_plans", x => x.id);
                    table.CheckConstraint("ck_nutrition_plans_dates", "end_date IS NULL OR end_date >= start_date");
                    table.CheckConstraint("ck_nutrition_plans_items", "jsonb_typeof(items) = 'array' AND jsonb_array_length(items) BETWEEN 1 AND 100");
                    table.CheckConstraint("ck_nutrition_plans_status", "status IN ('draft','active','archived') AND version_number > 0");
                    table.CheckConstraint("ck_nutrition_plans_targets", "(daily_calories_target_kcal IS NULL OR (daily_calories_target_kcal > 0 AND daily_calories_target_kcal < 'Infinity'::numeric)) AND (daily_water_target_ml IS NULL OR (daily_water_target_ml > 0 AND daily_water_target_ml < 'Infinity'::numeric))");
                    table.CheckConstraint("ck_nutrition_plans_title", "char_length(btrim(title)) BETWEEN 1 AND 120");
                    table.ForeignKey(
                        name: "fk_nutrition_plans_client_id",
                        column: x => x.client_id,
                        principalTable: "client_profiles",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "fk_nutrition_plans_dietitian_id",
                        column: x => x.dietitian_id,
                        principalTable: "dietitian_profiles",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "nutrition_plan_versions",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    nutrition_plan_id = table.Column<Guid>(type: "uuid", nullable: false),
                    version_number = table.Column<int>(type: "integer", nullable: false),
                    recorded_by_user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    snapshot = table.Column<string>(type: "jsonb", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_nutrition_plan_versions", x => x.id);
                    table.CheckConstraint("ck_plan_versions_snapshot", "version_number > 0 AND jsonb_typeof(snapshot) = 'object'");
                    table.ForeignKey(
                        name: "fk_plan_versions_actor_id",
                        column: x => x.recorded_by_user_id,
                        principalTable: "users",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "fk_plan_versions_plan_id",
                        column: x => x.nutrition_plan_id,
                        principalTable: "nutrition_plans",
                        principalColumn: "id");
                });

            migrationBuilder.CreateIndex(
                name: "ix_plan_versions_actor_id",
                table: "nutrition_plan_versions",
                column: "recorded_by_user_id");

            migrationBuilder.CreateIndex(
                name: "ux_plan_versions_number",
                table: "nutrition_plan_versions",
                columns: new[] { "nutrition_plan_id", "version_number" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_nutrition_plans_dietitian_id",
                table: "nutrition_plans",
                column: "dietitian_id");

            migrationBuilder.CreateIndex(
                name: "ux_nutrition_plans_active_client",
                table: "nutrition_plans",
                column: "client_id",
                unique: true,
                filter: "status = 'active'");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "nutrition_plan_versions");

            migrationBuilder.DropTable(
                name: "nutrition_plans");
        }
    }
}
