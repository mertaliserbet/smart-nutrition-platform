using System.Text.Json.Serialization;
using Microsoft.EntityFrameworkCore;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Features.Relationships;

namespace SmartNutrition.Api.Features.MealLogs;

public sealed class MealLogComment
{
    private MealLogComment() { }
    internal MealLogComment(Guid mealLogId, Guid authorUserId, string text, DateTimeOffset createdAt, Guid? parentCommentId)
    {
        if (mealLogId == Guid.Empty || authorUserId == Guid.Empty || parentCommentId == Guid.Empty || createdAt == default)
            throw new ArgumentException("Valid comment references and time are required.");
        Text = text.Trim();
        if (!ValidText(Text)) throw new ArgumentException("Valid comment text is required.");
        Id = Guid.NewGuid(); MealLogId = mealLogId; AuthorUserId = authorUserId;
        CreatedAt = RecordTime.Normalize(createdAt); ParentCommentId = parentCommentId;
    }
    internal static bool ValidText(string? text) => !string.IsNullOrWhiteSpace(text) && !text.Contains('\0') && text.EnumerateRunes().Count() <= 2000;
    public Guid Id { get; private set; }
    public Guid MealLogId { get; private set; }
    public Guid AuthorUserId { get; private set; }
    public string Text { get; private set; } = null!;
    public DateTimeOffset CreatedAt { get; private set; }
    public Guid? ParentCommentId { get; private set; }

    internal static void Configure(ModelBuilder builder)
    {
        var rows = builder.Entity<MealLogComment>();
        rows.ToTable("meal_log_comments", table =>
        {
            table.HasCheckConstraint("ck_meal_log_comments_text", "char_length(text) BETWEEN 1 AND 2000 AND text !~ '^[[:space:]]*$'");
            table.HasCheckConstraint("ck_meal_log_comments_parent", "parent_comment_id IS NULL OR parent_comment_id <> id");
        });
        rows.HasKey(x => x.Id).HasName("pk_meal_log_comments");
        rows.Property(x => x.Id).HasColumnName("id").ValueGeneratedNever();
        rows.Property(x => x.MealLogId).HasColumnName("meal_log_id");
        rows.Property(x => x.AuthorUserId).HasColumnName("author_user_id");
        rows.Property(x => x.Text).HasColumnName("text").IsRequired();
        rows.Property(x => x.CreatedAt).HasColumnName("created_at");
        rows.Property(x => x.ParentCommentId).HasColumnName("parent_comment_id");
        rows.HasOne<MealLog>().WithMany().HasForeignKey(x => x.MealLogId).OnDelete(DeleteBehavior.Restrict).HasConstraintName("fk_meal_log_comments_meal");
        rows.HasOne<User>().WithMany().HasForeignKey(x => x.AuthorUserId).OnDelete(DeleteBehavior.Restrict).HasConstraintName("fk_meal_log_comments_author");
        // The composite FK also prevents a reply from referring to another meal's comment.
        rows.HasAlternateKey(x => new { x.MealLogId, x.Id }).HasName("ak_meal_log_comments_meal_id");
        rows.HasOne<MealLogComment>().WithMany().HasForeignKey(x => new { x.MealLogId, x.ParentCommentId })
            .HasPrincipalKey(x => new { x.MealLogId, x.Id }).OnDelete(DeleteBehavior.Restrict).HasConstraintName("fk_meal_log_comments_parent");
        rows.HasIndex(x => new { x.MealLogId, x.CreatedAt, x.Id }).HasDatabaseName("ix_meal_log_comments_meal_created_id");
        rows.HasIndex(x => x.AuthorUserId).HasDatabaseName("ix_meal_log_comments_author");
        rows.HasIndex(x => new { x.MealLogId, x.ParentCommentId }).HasDatabaseName("ix_meal_log_comments_parent");
        foreach (var property in rows.Metadata.GetProperties().Where(x => !x.IsPrimaryKey()))
            property.SetAfterSaveBehavior(Microsoft.EntityFrameworkCore.Metadata.PropertySaveBehavior.Throw);
    }
}

public sealed class CreateMealLogCommentRequest
{
    [JsonRequired] public string? Text { get; init; }
    public Guid? ParentCommentId { get; init; }
}
public sealed record MealLogCommentResponse(Guid Id, Guid MealLogId, Guid AuthorUserId, string Text, DateTimeOffset CreatedAt, Guid? ParentCommentId)
{
    internal static MealLogCommentResponse From(MealLogComment row) => new(row.Id, row.MealLogId, row.AuthorUserId, row.Text, row.CreatedAt, row.ParentCommentId);
}
