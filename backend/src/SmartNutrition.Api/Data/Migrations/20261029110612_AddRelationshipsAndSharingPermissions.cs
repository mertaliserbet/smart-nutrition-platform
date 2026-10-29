using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SmartNutrition.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddRelationshipsAndSharingPermissions : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "invitation_code_expires_at",
                table: "dietitian_profiles",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "invitation_code_hash",
                table: "dietitian_profiles",
                type: "character varying(64)",
                maxLength: 64,
                nullable: true);

            migrationBuilder.CreateTable(
                name: "dietitian_client_relationships",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    client_id = table.Column<Guid>(type: "uuid", nullable: false),
                    dietitian_id = table.Column<Guid>(type: "uuid", nullable: false),
                    status = table.Column<string>(type: "text", nullable: false),
                    requested_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    responded_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    ended_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_dietitian_client_relationships", x => x.id);
                    table.CheckConstraint("ck_relationships_status", "status IN ('pending','active','rejected','ended')");
                    table.CheckConstraint("ck_relationships_times", "(responded_at IS NULL OR responded_at >= requested_at) AND (ended_at IS NULL OR ended_at >= requested_at)");
                    table.ForeignKey(
                        name: "fk_relationships_client_id",
                        column: x => x.client_id,
                        principalTable: "client_profiles",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "fk_relationships_dietitian_id",
                        column: x => x.dietitian_id,
                        principalTable: "dietitian_profiles",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "data_sharing_permissions",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    relationship_id = table.Column<Guid>(type: "uuid", nullable: false),
                    category = table.Column<string>(type: "text", nullable: false),
                    is_granted = table.Column<bool>(type: "boolean", nullable: false),
                    consent_record_id = table.Column<Guid>(type: "uuid", nullable: true),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_data_sharing_permissions", x => x.id);
                    table.CheckConstraint("ck_permissions_category", "category = 'nutrition_plans' AND consent_record_id IS NULL");
                    table.CheckConstraint("ck_permissions_times", "updated_at >= created_at");
                    table.ForeignKey(
                        name: "fk_permissions_relationship_id",
                        column: x => x.relationship_id,
                        principalTable: "dietitian_client_relationships",
                        principalColumn: "id");
                });

            migrationBuilder.CreateIndex(
                name: "ux_dietitian_profiles_invitation_code_hash",
                table: "dietitian_profiles",
                column: "invitation_code_hash",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ux_permissions_relationship_category",
                table: "data_sharing_permissions",
                columns: new[] { "relationship_id", "category" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_relationships_dietitian_id",
                table: "dietitian_client_relationships",
                column: "dietitian_id");

            migrationBuilder.CreateIndex(
                name: "ux_relationships_active_client",
                table: "dietitian_client_relationships",
                column: "client_id",
                unique: true,
                filter: "status = 'active'");

            migrationBuilder.CreateIndex(
                name: "ux_relationships_pending_pair",
                table: "dietitian_client_relationships",
                columns: new[] { "client_id", "dietitian_id" },
                unique: true,
                filter: "status = 'pending'");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "data_sharing_permissions");

            migrationBuilder.DropTable(
                name: "dietitian_client_relationships");

            migrationBuilder.DropIndex(
                name: "ux_dietitian_profiles_invitation_code_hash",
                table: "dietitian_profiles");

            migrationBuilder.DropColumn(
                name: "invitation_code_expires_at",
                table: "dietitian_profiles");

            migrationBuilder.DropColumn(
                name: "invitation_code_hash",
                table: "dietitian_profiles");
        }
    }
}
