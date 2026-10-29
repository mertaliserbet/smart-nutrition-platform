using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SmartNutrition.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddDietitianApplicationsAndAdminMfa : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<long>(
                name: "last_used_totp_step",
                table: "users",
                type: "bigint",
                nullable: true);

            migrationBuilder.AddColumn<string[]>(
                name: "mfa_recovery_code_hashes",
                table: "users",
                type: "text[]",
                nullable: false,
                defaultValue: new string[0]);

            migrationBuilder.AddColumn<string>(
                name: "totp_secret_protected",
                table: "users",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<bool>(
                name: "is_mfa_verified",
                table: "auth_sessions",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.CreateTable(
                name: "audit_events",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    actor_user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    action = table.Column<string>(type: "text", nullable: false),
                    resource_type = table.Column<string>(type: "text", nullable: false),
                    resource_id = table.Column<Guid>(type: "uuid", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    metadata = table.Column<string>(type: "jsonb", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_audit_events", x => x.id);
                    table.ForeignKey(
                        name: "fk_audit_events_users_actor_user_id",
                        column: x => x.actor_user_id,
                        principalTable: "users",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "dietitian_profiles",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    display_name = table.Column<string>(type: "text", nullable: false),
                    license_info = table.Column<string>(type: "text", nullable: false),
                    is_verified = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_dietitian_profiles", x => x.id);
                    table.CheckConstraint("ck_dietitian_profiles_license", "char_length(btrim(license_info)) BETWEEN 1 AND 2000");
                    table.CheckConstraint("ck_dietitian_profiles_name", "char_length(btrim(display_name)) BETWEEN 1 AND 120");
                    table.ForeignKey(
                        name: "fk_dietitian_profiles_users_user_id",
                        column: x => x.user_id,
                        principalTable: "users",
                        principalColumn: "id");
                });

            migrationBuilder.CreateIndex(
                name: "ix_audit_events_actor_user_id",
                table: "audit_events",
                column: "actor_user_id");

            migrationBuilder.CreateIndex(
                name: "ux_dietitian_profiles_user_id",
                table: "dietitian_profiles",
                column: "user_id",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "audit_events");

            migrationBuilder.DropTable(
                name: "dietitian_profiles");

            migrationBuilder.DropColumn(
                name: "last_used_totp_step",
                table: "users");

            migrationBuilder.DropColumn(
                name: "mfa_recovery_code_hashes",
                table: "users");

            migrationBuilder.DropColumn(
                name: "totp_secret_protected",
                table: "users");

            migrationBuilder.DropColumn(
                name: "is_mfa_verified",
                table: "auth_sessions");
        }
    }
}
