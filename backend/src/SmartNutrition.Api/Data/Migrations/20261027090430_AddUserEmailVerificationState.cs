using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SmartNutrition.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddUserEmailVerificationState : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<bool>(
                name: "is_email_verified",
                table: "users",
                type: "boolean",
                nullable: false,
                defaultValue: false);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "is_email_verified",
                table: "users");
        }
    }
}
