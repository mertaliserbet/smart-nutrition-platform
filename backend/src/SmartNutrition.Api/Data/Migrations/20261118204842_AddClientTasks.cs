using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SmartNutrition.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddClientTasks : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropCheckConstraint(
                name: "ck_permissions_category",
                table: "data_sharing_permissions");

            migrationBuilder.AddUniqueConstraint(
                name: "ak_relationships_id_client_dietitian",
                table: "dietitian_client_relationships",
                columns: new[] { "id", "client_id", "dietitian_id" });

            migrationBuilder.CreateTable(
                name: "client_tasks",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    client_id = table.Column<Guid>(type: "uuid", nullable: false),
                    dietitian_id = table.Column<Guid>(type: "uuid", nullable: false),
                    relationship_id = table.Column<Guid>(type: "uuid", nullable: false),
                    description = table.Column<string>(type: "text", nullable: false),
                    status = table.Column<string>(type: "text", nullable: false),
                    due_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    is_reminder_enabled = table.Column<bool>(type: "boolean", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    version_number = table.Column<int>(type: "integer", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_client_tasks", x => x.id);
                    table.CheckConstraint("ck_client_tasks_description", "char_length(description) BETWEEN 1 AND 2000 AND description !~ '^[[:space:]]*$'");
                    table.CheckConstraint("ck_client_tasks_reminder", "NOT is_reminder_enabled OR due_at IS NOT NULL");
                    table.CheckConstraint("ck_client_tasks_status", "status IN ('pending','in_progress','completed','cancelled') AND version_number > 0");
                    table.CheckConstraint("ck_client_tasks_times", "isfinite(created_at) AND isfinite(updated_at) AND updated_at >= created_at AND (due_at IS NULL OR (isfinite(due_at) AND due_at > created_at))");
                    table.ForeignKey(
                        name: "fk_client_tasks_relationship_pair",
                        columns: x => new { x.relationship_id, x.client_id, x.dietitian_id },
                        principalTable: "dietitian_client_relationships",
                        principalColumns: new[] { "id", "client_id", "dietitian_id" },
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "client_task_versions",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    client_task_id = table.Column<Guid>(type: "uuid", nullable: false),
                    version_number = table.Column<int>(type: "integer", nullable: false),
                    recorded_by_user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    snapshot = table.Column<string>(type: "jsonb", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_client_task_versions", x => x.id);
                    table.CheckConstraint("ck_client_task_versions_snapshot", "(version_number > 0 AND jsonb_typeof(snapshot) = 'object' AND snapshot->>'id' = client_task_id::text AND (snapshot->>'versionNumber')::integer = version_number) IS TRUE");
                    table.ForeignKey(
                        name: "fk_client_task_versions_actor",
                        column: x => x.recorded_by_user_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_client_task_versions_task",
                        column: x => x.client_task_id,
                        principalTable: "client_tasks",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.AddCheckConstraint(
                name: "ck_permissions_category",
                table: "data_sharing_permissions",
                sql: "category IN ('nutrition_plans','meal_logs','body_measurements','client_tasks') AND consent_record_id IS NULL");

            migrationBuilder.CreateIndex(
                name: "ix_client_task_versions_actor",
                table: "client_task_versions",
                column: "recorded_by_user_id");

            migrationBuilder.CreateIndex(
                name: "ux_client_task_versions_number",
                table: "client_task_versions",
                columns: new[] { "client_task_id", "version_number" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_client_tasks_client_created_id",
                table: "client_tasks",
                columns: new[] { "client_id", "created_at", "id" });

            migrationBuilder.CreateIndex(
                name: "ix_client_tasks_relationship_pair",
                table: "client_tasks",
                columns: new[] { "relationship_id", "client_id", "dietitian_id" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql("""
                DO $$ BEGIN
                    IF EXISTS (SELECT 1 FROM client_tasks) OR EXISTS (SELECT 1 FROM client_task_versions)
                        OR EXISTS (SELECT 1 FROM data_sharing_permissions WHERE category = 'client_tasks') THEN
                        RAISE EXCEPTION 'Cannot remove client tasks while task, history or permission records exist.';
                    END IF;
                END $$;
                """);
            migrationBuilder.DropTable(
                name: "client_task_versions");

            migrationBuilder.DropTable(
                name: "client_tasks");

            migrationBuilder.DropUniqueConstraint(
                name: "ak_relationships_id_client_dietitian",
                table: "dietitian_client_relationships");

            migrationBuilder.DropCheckConstraint(
                name: "ck_permissions_category",
                table: "data_sharing_permissions");

            migrationBuilder.AddCheckConstraint(
                name: "ck_permissions_category",
                table: "data_sharing_permissions",
                sql: "category IN ('nutrition_plans','meal_logs','body_measurements') AND consent_record_id IS NULL");
        }
    }
}
