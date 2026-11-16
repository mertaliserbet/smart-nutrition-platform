using Microsoft.EntityFrameworkCore;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Features.Relationships;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Features.WaterLogs;

public sealed class WaterLog
{
    private WaterLog() { }
    public WaterLog(Guid id, Guid clientId, decimal amountMl, DateTimeOffset consumedAt, RecordSource source)
    {
        if (id == Guid.Empty || clientId == Guid.Empty) throw new ArgumentException("Non-empty record and client IDs are required.");
        if (!Enum.IsDefined(source)) throw new ArgumentException("The source is not supported.", nameof(source));
        Id = id; ClientId = clientId; Source = source;
        Revise(amountMl, consumedAt);
    }
    public Guid Id { get; private set; }
    public Guid ClientId { get; private set; }
    public decimal AmountMl { get; private set; }
    public DateTimeOffset ConsumedAt { get; private set; }
    public RecordSource Source { get; private set; }
    internal DateTimeOffset? DeletedAt { get; private set; }

    internal void Revise(decimal amountMl, DateTimeOffset consumedAt)
    {
        if (amountMl <= 0) throw new ArgumentOutOfRangeException(nameof(amountMl));
        if (consumedAt == default) throw new ArgumentException("Consumption time is required.", nameof(consumedAt));
        AmountMl = amountMl; ConsumedAt = RecordTime.Normalize(consumedAt);
    }
    internal void Delete(DateTimeOffset now) => DeletedAt = RecordTime.Normalize(now);

    internal static void Configure(ModelBuilder builder)
    {
        var rows = builder.Entity<WaterLog>();
        rows.ToTable("water_logs", table =>
        {
            table.HasCheckConstraint("ck_water_logs_amount", "amount_ml > 0 AND amount_ml < 'Infinity'::numeric");
            table.HasCheckConstraint("ck_water_logs_source", "source IN ('manual','wearable','ai_assisted')");
        });
        rows.HasKey(x => x.Id).HasName("pk_water_logs");
        rows.Property(x => x.Id).HasColumnName("id").ValueGeneratedNever();
        rows.Property(x => x.ClientId).HasColumnName("client_id");
        rows.Property(x => x.AmountMl).HasColumnName("amount_ml").HasColumnType("numeric");
        rows.Property(x => x.ConsumedAt).HasColumnName("consumed_at");
        rows.Property(x => x.Source).HasColumnName("source").HasConversion(
            x => x == RecordSource.AiAssisted ? "ai_assisted" : x.ToString().ToLowerInvariant(),
            x => x == "ai_assisted" ? RecordSource.AiAssisted : Enum.Parse<RecordSource>(x, true));
        rows.Property(x => x.DeletedAt).HasColumnName("deleted_at");
        rows.HasQueryFilter(x => x.DeletedAt == null);
        rows.HasOne<ClientProfile>().WithMany().HasForeignKey(x => x.ClientId).OnDelete(DeleteBehavior.Restrict)
            .HasConstraintName("fk_water_logs_client_id");
        rows.HasIndex(x => new { x.ClientId, x.ConsumedAt, x.Id }).IsDescending(false, true, false)
            .HasFilter("deleted_at IS NULL").HasDatabaseName("ix_water_logs_client_consumed_id");
    }
}
