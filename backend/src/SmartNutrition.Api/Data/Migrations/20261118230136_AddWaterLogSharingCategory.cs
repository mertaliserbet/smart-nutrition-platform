using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SmartNutrition.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddWaterLogSharingCategory : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropCheckConstraint(
                name: "ck_permissions_category",
                table: "data_sharing_permissions");

            migrationBuilder.AddCheckConstraint(
                name: "ck_permissions_category",
                table: "data_sharing_permissions",
                sql: "category IN ('nutrition_plans','meal_logs','body_measurements','client_tasks','water_logs') AND consent_record_id IS NULL");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql("""
                DO $$ BEGIN
                    IF EXISTS (SELECT 1 FROM data_sharing_permissions WHERE category = 'water_logs') THEN
                        RAISE EXCEPTION 'Cannot remove water sharing while permission records exist.';
                    END IF;
                END $$;
                """);
            migrationBuilder.DropCheckConstraint(
                name: "ck_permissions_category",
                table: "data_sharing_permissions");

            migrationBuilder.AddCheckConstraint(
                name: "ck_permissions_category",
                table: "data_sharing_permissions",
                sql: "category IN ('nutrition_plans','meal_logs','body_measurements','client_tasks') AND consent_record_id IS NULL");
        }
    }
}
