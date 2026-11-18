using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SmartNutrition.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddHealthDataSync : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "wearable_connections",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    client_id = table.Column<Guid>(type: "uuid", nullable: false),
                    provider = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    status = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    version_number = table.Column<int>(type: "integer", nullable: false),
                    last_synced_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    last_attempt_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    last_sync_status = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    last_error_code = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_wearable_connections", x => x.id);
                    table.UniqueConstraint("AK_wearable_connections_id_client_id", x => new { x.id, x.client_id });
                    table.CheckConstraint("ck_wearable_provider", "provider IN ('health_connect','health_kit')");
                    table.CheckConstraint("ck_wearable_status", "status IN ('active','revoked') AND version_number > 0");
                    table.CheckConstraint("ck_wearable_sync_status", "last_sync_status IN ('never','succeeded','failed') AND (last_sync_status <> 'succeeded' OR last_synced_at IS NOT NULL)");
                    table.ForeignKey(
                        name: "FK_wearable_connections_client_profiles_client_id",
                        column: x => x.client_id,
                        principalTable: "client_profiles",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "wearable_records",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    client_id = table.Column<Guid>(type: "uuid", nullable: false),
                    wearable_connection_id = table.Column<Guid>(type: "uuid", nullable: false),
                    source_id = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    external_record_id = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    raw_type = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    metric = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    source_name = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    recording_method = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: true),
                    exercise_type = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    raw_unit = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    version_number = table.Column<int>(type: "integer", nullable: false),
                    is_deleted = table.Column<bool>(type: "boolean", nullable: false),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_wearable_records", x => x.id);
                    table.UniqueConstraint("AK_wearable_records_id_client_id", x => new { x.id, x.client_id });
                    table.UniqueConstraint("AK_wearable_records_id_wearable_connection_id_client_id", x => new { x.id, x.wearable_connection_id, x.client_id });
                    table.CheckConstraint("ck_wearable_record_identity", "length(btrim(source_id)) > 0 AND length(btrim(external_record_id)) > 0 AND version_number > 0");
                    table.CheckConstraint("ck_wearable_record_metric", "metric IN ('steps','distance','exercise','active_energy','heart_rate')");
                    table.CheckConstraint("ck_wearable_record_unit", "(metric = 'steps' AND raw_unit = 'COUNT' AND raw_type = 'STEPS') OR (metric = 'distance' AND raw_unit = 'METER' AND raw_type IN ('DISTANCE_DELTA','DISTANCE_WALKING_RUNNING','DISTANCE_CYCLING','DISTANCE_SWIMMING')) OR (metric = 'exercise' AND raw_unit = 'MINUTE' AND raw_type = 'WORKOUT') OR (metric = 'active_energy' AND raw_unit = 'KILOCALORIE' AND raw_type = 'ACTIVE_ENERGY_BURNED') OR (metric = 'heart_rate' AND raw_unit = 'BEATS_PER_MINUTE' AND raw_type = 'HEART_RATE')");
                    table.ForeignKey(
                        name: "FK_wearable_records_client_profiles_client_id",
                        column: x => x.client_id,
                        principalTable: "client_profiles",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_wearable_records_wearable_connections_wearable_connection_i~",
                        columns: x => new { x.wearable_connection_id, x.client_id },
                        principalTable: "wearable_connections",
                        principalColumns: new[] { "id", "client_id" },
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "wearable_sync_batches",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    client_id = table.Column<Guid>(type: "uuid", nullable: false),
                    wearable_connection_id = table.Column<Guid>(type: "uuid", nullable: false),
                    batch_id = table.Column<Guid>(type: "uuid", nullable: false),
                    request_hash = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    response_json = table.Column<string>(type: "jsonb", nullable: false),
                    committed_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_wearable_sync_batches", x => x.id);
                    table.ForeignKey(
                        name: "FK_wearable_sync_batches_client_profiles_client_id",
                        column: x => x.client_id,
                        principalTable: "client_profiles",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_wearable_sync_batches_wearable_connections_wearable_connect~",
                        columns: x => new { x.wearable_connection_id, x.client_id },
                        principalTable: "wearable_connections",
                        principalColumns: new[] { "id", "client_id" },
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "activity_logs",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    client_id = table.Column<Guid>(type: "uuid", nullable: false),
                    activity_type = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    started_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    ended_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    duration_minutes = table.Column<decimal>(type: "numeric", nullable: true),
                    raw_duration_minutes = table.Column<decimal>(type: "numeric", nullable: true),
                    distance_km = table.Column<decimal>(type: "numeric", nullable: true),
                    calories_kcal = table.Column<decimal>(type: "numeric", nullable: true),
                    source = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    wearable_connection_id = table.Column<Guid>(type: "uuid", nullable: true),
                    wearable_record_id = table.Column<Guid>(type: "uuid", nullable: true),
                    external_record_id = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    version_number = table.Column<int>(type: "integer", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    is_deleted = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_activity_logs", x => x.id);
                    table.CheckConstraint("ck_activity_interval", "(duration_minutes IS NULL AND ended_at IS NULL) OR (duration_minutes IS NOT NULL AND ended_at > started_at AND ended_at - started_at <= interval '7 days')");
                    table.CheckConstraint("ck_activity_source", "(source = 'manual' AND wearable_connection_id IS NULL AND wearable_record_id IS NULL AND external_record_id IS NULL AND raw_duration_minutes IS NULL) OR (source = 'wearable' AND wearable_connection_id IS NOT NULL AND wearable_record_id IS NOT NULL AND external_record_id IS NOT NULL AND raw_duration_minutes IS NOT NULL AND raw_duration_minutes > 0 AND raw_duration_minutes <= 10081)");
                    table.CheckConstraint("ck_activity_values", "version_number > 0 AND length(btrim(activity_type)) > 0 AND (duration_minutes IS NOT NULL OR distance_km IS NOT NULL OR calories_kcal IS NOT NULL) AND (duration_minutes IS NULL OR (duration_minutes > 0 AND duration_minutes <= 10080)) AND (distance_km IS NULL OR (distance_km >= 0 AND distance_km <= 1000000000000)) AND (calories_kcal IS NULL OR (calories_kcal >= 0 AND calories_kcal <= 1000000000000))");
                    table.ForeignKey(
                        name: "FK_activity_logs_client_profiles_client_id",
                        column: x => x.client_id,
                        principalTable: "client_profiles",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_activity_logs_wearable_connections_wearable_connection_id_c~",
                        columns: x => new { x.wearable_connection_id, x.client_id },
                        principalTable: "wearable_connections",
                        principalColumns: new[] { "id", "client_id" },
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_activity_logs_wearable_records_wearable_record_id_wearable_~",
                        columns: x => new { x.wearable_record_id, x.wearable_connection_id, x.client_id },
                        principalTable: "wearable_records",
                        principalColumns: new[] { "id", "wearable_connection_id", "client_id" },
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "health_metric_samples",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    client_id = table.Column<Guid>(type: "uuid", nullable: false),
                    wearable_record_id = table.Column<Guid>(type: "uuid", nullable: false),
                    sample_key = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    started_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    ended_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    raw_value = table.Column<decimal>(type: "numeric", nullable: false),
                    value = table.Column<decimal>(type: "numeric", nullable: false),
                    unit = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    is_deleted = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_health_metric_samples", x => x.id);
                    table.CheckConstraint("ck_health_sample_interval", "ended_at >= started_at AND ended_at - started_at <= interval '7 days'");
                    table.CheckConstraint("ck_health_sample_value", "raw_value >= 0 AND raw_value <= 1000000000000 AND value >= 0 AND value <= 1000000000000 AND unit IN ('count','km','kcal','bpm') AND (unit <> 'count' OR value = trunc(value)) AND (unit <> 'bpm' OR value > 0)");
                    table.ForeignKey(
                        name: "FK_health_metric_samples_client_profiles_client_id",
                        column: x => x.client_id,
                        principalTable: "client_profiles",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_health_metric_samples_wearable_records_wearable_record_id_c~",
                        columns: x => new { x.wearable_record_id, x.client_id },
                        principalTable: "wearable_records",
                        principalColumns: new[] { "id", "client_id" },
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "IX_activity_logs_client_id_started_at_id",
                table: "activity_logs",
                columns: new[] { "client_id", "started_at", "id" });

            migrationBuilder.CreateIndex(
                name: "IX_activity_logs_wearable_connection_id_client_id",
                table: "activity_logs",
                columns: new[] { "wearable_connection_id", "client_id" });

            migrationBuilder.CreateIndex(
                name: "IX_activity_logs_wearable_record_id",
                table: "activity_logs",
                column: "wearable_record_id",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_activity_logs_wearable_record_id_wearable_connection_id_cli~",
                table: "activity_logs",
                columns: new[] { "wearable_record_id", "wearable_connection_id", "client_id" });

            migrationBuilder.CreateIndex(
                name: "IX_health_metric_samples_client_id_started_at_id",
                table: "health_metric_samples",
                columns: new[] { "client_id", "started_at", "id" });

            migrationBuilder.CreateIndex(
                name: "IX_health_metric_samples_wearable_record_id_client_id",
                table: "health_metric_samples",
                columns: new[] { "wearable_record_id", "client_id" });

            migrationBuilder.CreateIndex(
                name: "IX_health_metric_samples_wearable_record_id_sample_key",
                table: "health_metric_samples",
                columns: new[] { "wearable_record_id", "sample_key" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_wearable_connections_client_id_provider",
                table: "wearable_connections",
                columns: new[] { "client_id", "provider" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_wearable_records_client_id",
                table: "wearable_records",
                column: "client_id");

            migrationBuilder.CreateIndex(
                name: "IX_wearable_records_wearable_connection_id_client_id",
                table: "wearable_records",
                columns: new[] { "wearable_connection_id", "client_id" });

            migrationBuilder.CreateIndex(
                name: "IX_wearable_records_wearable_connection_id_source_id_raw_type_~",
                table: "wearable_records",
                columns: new[] { "wearable_connection_id", "source_id", "raw_type", "external_record_id" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_wearable_sync_batches_client_id",
                table: "wearable_sync_batches",
                column: "client_id");

            migrationBuilder.CreateIndex(
                name: "IX_wearable_sync_batches_wearable_connection_id_batch_id",
                table: "wearable_sync_batches",
                columns: new[] { "wearable_connection_id", "batch_id" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_wearable_sync_batches_wearable_connection_id_client_id",
                table: "wearable_sync_batches",
                columns: new[] { "wearable_connection_id", "client_id" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql("""
                DO $$ BEGIN
                    IF EXISTS (SELECT 1 FROM activity_logs) OR EXISTS (SELECT 1 FROM health_metric_samples)
                        OR EXISTS (SELECT 1 FROM wearable_records) OR EXISTS (SELECT 1 FROM wearable_connections)
                        OR EXISTS (SELECT 1 FROM wearable_sync_batches) THEN
                        RAISE EXCEPTION 'Cannot remove health synchronization while health records or connections exist.';
                    END IF;
                END $$;
                """);
            migrationBuilder.DropTable(
                name: "activity_logs");

            migrationBuilder.DropTable(
                name: "health_metric_samples");

            migrationBuilder.DropTable(
                name: "wearable_sync_batches");

            migrationBuilder.DropTable(
                name: "wearable_records");

            migrationBuilder.DropTable(
                name: "wearable_connections");
        }
    }
}
