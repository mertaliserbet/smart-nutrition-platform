using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SmartNutrition.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddPasswordReset : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<long>(
                name: "credentials_version",
                table: "users",
                type: "bigint",
                nullable: false,
                defaultValue: 0L);

            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "password_reset_expires_at",
                table: "users",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "password_reset_last_sent_at",
                table: "users",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "password_reset_token_hash",
                table: "users",
                type: "character varying(64)",
                maxLength: 64,
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "ux_users_password_reset_token_hash",
                table: "users",
                column: "password_reset_token_hash",
                unique: true);

            migrationBuilder.AddCheckConstraint(
                name: "ck_users_credentials_version",
                table: "users",
                sql: "credentials_version >= 0");

            migrationBuilder.AddCheckConstraint(
                name: "ck_users_password_reset",
                table: "users",
                sql: "(password_reset_token_hash IS NULL AND password_reset_expires_at IS NULL) OR (password_reset_token_hash IS NOT NULL AND password_reset_token_hash ~ '^[0-9A-F]{64}$' AND password_reset_expires_at IS NOT NULL AND password_reset_last_sent_at IS NOT NULL AND password_reset_expires_at > password_reset_last_sent_at)");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "ux_users_password_reset_token_hash",
                table: "users");

            migrationBuilder.DropCheckConstraint(
                name: "ck_users_credentials_version",
                table: "users");

            migrationBuilder.DropCheckConstraint(
                name: "ck_users_password_reset",
                table: "users");

            migrationBuilder.DropColumn(
                name: "credentials_version",
                table: "users");

            migrationBuilder.DropColumn(
                name: "password_reset_expires_at",
                table: "users");

            migrationBuilder.DropColumn(
                name: "password_reset_last_sent_at",
                table: "users");

            migrationBuilder.DropColumn(
                name: "password_reset_token_hash",
                table: "users");
        }
    }
}
