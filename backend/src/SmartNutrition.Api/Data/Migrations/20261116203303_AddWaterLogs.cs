using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SmartNutrition.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddWaterLogs : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "water_logs",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    client_id = table.Column<Guid>(type: "uuid", nullable: false),
                    amount_ml = table.Column<decimal>(type: "numeric", nullable: false),
                    consumed_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    source = table.Column<string>(type: "text", nullable: false),
                    deleted_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_water_logs", x => x.id);
                    table.CheckConstraint("ck_water_logs_amount", "amount_ml > 0 AND amount_ml < 'Infinity'::numeric");
                    table.CheckConstraint("ck_water_logs_source", "source IN ('manual','wearable','ai_assisted')");
                    table.ForeignKey(
                        name: "fk_water_logs_client_id",
                        column: x => x.client_id,
                        principalTable: "client_profiles",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "ix_water_logs_client_consumed_id",
                table: "water_logs",
                columns: new[] { "client_id", "consumed_at", "id" },
                descending: new[] { false, true, false },
                filter: "deleted_at IS NULL");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql("""
                DO $$ BEGIN
                    IF EXISTS (SELECT 1 FROM water_logs) THEN
                        RAISE EXCEPTION 'Water records exist; an explicit data-preserving rollback is required.';
                    END IF;
                END $$;
                """);
            migrationBuilder.DropTable(
                name: "water_logs");
        }
    }
}
