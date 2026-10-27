using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SmartNutrition.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddEmailVerificationTokens : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "email_verification_expires_at",
                table: "users",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "email_verification_last_sent_at",
                table: "users",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "email_verification_token_hash",
                table: "users",
                type: "character varying(64)",
                maxLength: 64,
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "ux_users_email_verification_token_hash",
                table: "users",
                column: "email_verification_token_hash",
                unique: true);

            migrationBuilder.AddCheckConstraint(
                name: "ck_users_email_verification",
                table: "users",
                sql: "(email_verification_token_hash IS NULL AND email_verification_expires_at IS NULL) OR (email_verification_token_hash IS NOT NULL AND email_verification_token_hash ~ '^[0-9A-F]{64}$' AND email_verification_expires_at IS NOT NULL AND email_verification_last_sent_at IS NOT NULL)");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "ux_users_email_verification_token_hash",
                table: "users");

            migrationBuilder.DropCheckConstraint(
                name: "ck_users_email_verification",
                table: "users");

            migrationBuilder.DropColumn(
                name: "email_verification_expires_at",
                table: "users");

            migrationBuilder.DropColumn(
                name: "email_verification_last_sent_at",
                table: "users");

            migrationBuilder.DropColumn(
                name: "email_verification_token_hash",
                table: "users");
        }
    }
}
