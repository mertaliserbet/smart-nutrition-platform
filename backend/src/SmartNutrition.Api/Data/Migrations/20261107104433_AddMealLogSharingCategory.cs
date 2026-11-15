using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SmartNutrition.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddMealLogSharingCategory : Migration
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
                sql: "category IN ('nutrition_plans','meal_logs') AND consent_record_id IS NULL");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropCheckConstraint(
                name: "ck_permissions_category",
                table: "data_sharing_permissions");

            migrationBuilder.AddCheckConstraint(
                name: "ck_permissions_category",
                table: "data_sharing_permissions",
                sql: "category = 'nutrition_plans' AND consent_record_id IS NULL");
        }
    }
}
