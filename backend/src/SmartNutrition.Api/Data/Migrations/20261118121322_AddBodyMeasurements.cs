using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SmartNutrition.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddBodyMeasurements : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "body_measurements",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    client_id = table.Column<Guid>(type: "uuid", nullable: false),
                    measured_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    weight_kg = table.Column<decimal>(type: "numeric", nullable: true),
                    waist_cm = table.Column<decimal>(type: "numeric", nullable: true),
                    hip_cm = table.Column<decimal>(type: "numeric", nullable: true),
                    chest_cm = table.Column<decimal>(type: "numeric", nullable: true),
                    body_fat_percent = table.Column<decimal>(type: "numeric", nullable: true),
                    note = table.Column<string>(type: "text", nullable: true),
                    source = table.Column<string>(type: "text", nullable: false),
                    deleted_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_body_measurements", x => x.id);
                    table.CheckConstraint("ck_body_measurements_note", "note IS NULL OR char_length(note) <= 2000");
                    table.CheckConstraint("ck_body_measurements_present", "weight_kg IS NOT NULL OR waist_cm IS NOT NULL OR hip_cm IS NOT NULL OR chest_cm IS NOT NULL OR body_fat_percent IS NOT NULL");
                    table.CheckConstraint("ck_body_measurements_source", "source IN ('manual','wearable','ai_assisted')");
                    table.CheckConstraint("ck_body_measurements_values", "(weight_kg IS NULL OR (weight_kg > 0 AND weight_kg < 'Infinity'::numeric)) AND (waist_cm IS NULL OR (waist_cm > 0 AND waist_cm < 'Infinity'::numeric)) AND (hip_cm IS NULL OR (hip_cm > 0 AND hip_cm < 'Infinity'::numeric)) AND (chest_cm IS NULL OR (chest_cm > 0 AND chest_cm < 'Infinity'::numeric)) AND (body_fat_percent IS NULL OR body_fat_percent BETWEEN 0 AND 100)");
                    table.ForeignKey(
                        name: "fk_body_measurements_client_id",
                        column: x => x.client_id,
                        principalTable: "client_profiles",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "ix_body_measurements_client_measured_id",
                table: "body_measurements",
                columns: new[] { "client_id", "measured_at", "id" },
                filter: "deleted_at IS NULL");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql("""
                DO $$ BEGIN
                    IF EXISTS (SELECT 1 FROM body_measurements) THEN
                        RAISE EXCEPTION 'Body measurements exist; an explicit data-preserving rollback is required.';
                    END IF;
                END $$;
                """);
            migrationBuilder.DropTable(
                name: "body_measurements");
        }
    }
}
