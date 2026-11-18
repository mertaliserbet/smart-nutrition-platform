using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SmartNutrition.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddMealLogComments : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "meal_log_comments",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    meal_log_id = table.Column<Guid>(type: "uuid", nullable: false),
                    author_user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    text = table.Column<string>(type: "text", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    parent_comment_id = table.Column<Guid>(type: "uuid", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_meal_log_comments", x => x.id);
                    table.UniqueConstraint("ak_meal_log_comments_meal_id", x => new { x.meal_log_id, x.id });
                    table.CheckConstraint("ck_meal_log_comments_parent", "parent_comment_id IS NULL OR parent_comment_id <> id");
                    table.CheckConstraint("ck_meal_log_comments_text", "char_length(text) BETWEEN 1 AND 2000 AND text !~ '^[[:space:]]*$'");
                    table.ForeignKey(
                        name: "fk_meal_log_comments_author",
                        column: x => x.author_user_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_meal_log_comments_meal",
                        column: x => x.meal_log_id,
                        principalTable: "meal_logs",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_meal_log_comments_parent",
                        columns: x => new { x.meal_log_id, x.parent_comment_id },
                        principalTable: "meal_log_comments",
                        principalColumns: new[] { "meal_log_id", "id" },
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "ix_meal_log_comments_author",
                table: "meal_log_comments",
                column: "author_user_id");

            migrationBuilder.CreateIndex(
                name: "ix_meal_log_comments_parent",
                table: "meal_log_comments",
                columns: new[] { "meal_log_id", "parent_comment_id" });

            migrationBuilder.CreateIndex(
                name: "ix_meal_log_comments_meal_created_id",
                table: "meal_log_comments",
                columns: new[] { "meal_log_id", "created_at", "id" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql("""
                DO $$ BEGIN
                    IF EXISTS (SELECT 1 FROM meal_log_comments) THEN
                        RAISE EXCEPTION 'Cannot remove meal comments while records exist.';
                    END IF;
                END $$;
                """);
            migrationBuilder.DropTable(
                name: "meal_log_comments");
        }
    }
}
