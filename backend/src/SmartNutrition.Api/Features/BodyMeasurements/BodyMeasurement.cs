using Microsoft.EntityFrameworkCore;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Features.Relationships;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Features.BodyMeasurements;

public sealed class BodyMeasurement
{
    private BodyMeasurement() { }
    public BodyMeasurement(Guid id, Guid clientId, DateTimeOffset measuredAt, RecordSource source,
        decimal? weightKg = null, decimal? waistCm = null, decimal? hipCm = null, decimal? chestCm = null,
        decimal? bodyFatPercent = null, string? note = null)
    {
        if (id == Guid.Empty || clientId == Guid.Empty) throw new ArgumentException("Non-empty record and client IDs are required.");
        if (!Enum.IsDefined(source)) throw new ArgumentException("The source is not supported.", nameof(source));
        Id = id; ClientId = clientId; Source = source;
        Revise(measuredAt, weightKg, waistCm, hipCm, chestCm, bodyFatPercent, note);
    }
    public Guid Id { get; private set; }
    public Guid ClientId { get; private set; }
    public DateTimeOffset MeasuredAt { get; private set; }
    public decimal? WeightKg { get; private set; }
    public decimal? WaistCm { get; private set; }
    public decimal? HipCm { get; private set; }
    public decimal? ChestCm { get; private set; }
    public decimal? BodyFatPercent { get; private set; }
    public string? Note { get; private set; }
    public RecordSource Source { get; private set; }
    internal DateTimeOffset? DeletedAt { get; private set; }

    internal static bool Valid(DateTimeOffset at, decimal? weight, decimal? waist, decimal? hip, decimal? chest, decimal? fat, string? note) =>
        at != default && (weight is not null || waist is not null || hip is not null || chest is not null || fat is not null) &&
        !(weight <= 0 || waist <= 0 || hip <= 0 || chest <= 0 || fat < 0 || fat > 100) &&
        (note is null || (!note.Contains('\0') && note.EnumerateRunes().Count() <= 2000));

    internal void Revise(DateTimeOffset at, decimal? weight, decimal? waist, decimal? hip, decimal? chest, decimal? fat, string? note)
    {
        if (!Valid(at, weight, waist, hip, chest, fat, note)) throw new ArgumentException("Valid time and at least one measurement are required.");
        MeasuredAt = RecordTime.Normalize(at); WeightKg = weight; WaistCm = waist; HipCm = hip; ChestCm = chest; BodyFatPercent = fat; Note = note;
    }
    internal void Delete(DateTimeOffset now) => DeletedAt = RecordTime.Normalize(now);

    internal static void Configure(ModelBuilder builder)
    {
        var rows = builder.Entity<BodyMeasurement>();
        rows.ToTable("body_measurements", table =>
        {
            table.HasCheckConstraint("ck_body_measurements_present", "weight_kg IS NOT NULL OR waist_cm IS NOT NULL OR hip_cm IS NOT NULL OR chest_cm IS NOT NULL OR body_fat_percent IS NOT NULL");
            table.HasCheckConstraint("ck_body_measurements_values", "(weight_kg IS NULL OR (weight_kg > 0 AND weight_kg < 'Infinity'::numeric)) AND (waist_cm IS NULL OR (waist_cm > 0 AND waist_cm < 'Infinity'::numeric)) AND (hip_cm IS NULL OR (hip_cm > 0 AND hip_cm < 'Infinity'::numeric)) AND (chest_cm IS NULL OR (chest_cm > 0 AND chest_cm < 'Infinity'::numeric)) AND (body_fat_percent IS NULL OR body_fat_percent BETWEEN 0 AND 100)");
            table.HasCheckConstraint("ck_body_measurements_source", "source IN ('manual','wearable','ai_assisted')");
            table.HasCheckConstraint("ck_body_measurements_note", "note IS NULL OR char_length(note) <= 2000");
        });
        rows.HasKey(x => x.Id).HasName("pk_body_measurements");
        rows.Property(x => x.Id).HasColumnName("id").ValueGeneratedNever();
        rows.Property(x => x.ClientId).HasColumnName("client_id");
        rows.Property(x => x.MeasuredAt).HasColumnName("measured_at");
        rows.Property(x => x.WeightKg).HasColumnName("weight_kg").HasColumnType("numeric");
        rows.Property(x => x.WaistCm).HasColumnName("waist_cm").HasColumnType("numeric");
        rows.Property(x => x.HipCm).HasColumnName("hip_cm").HasColumnType("numeric");
        rows.Property(x => x.ChestCm).HasColumnName("chest_cm").HasColumnType("numeric");
        rows.Property(x => x.BodyFatPercent).HasColumnName("body_fat_percent").HasColumnType("numeric");
        rows.Property(x => x.Note).HasColumnName("note");
        rows.Property(x => x.Source).HasColumnName("source").HasConversion(
            x => x == RecordSource.AiAssisted ? "ai_assisted" : x.ToString().ToLowerInvariant(),
            x => x == "ai_assisted" ? RecordSource.AiAssisted : Enum.Parse<RecordSource>(x, true));
        rows.Property(x => x.DeletedAt).HasColumnName("deleted_at");
        rows.HasQueryFilter(x => x.DeletedAt == null);
        rows.HasOne<ClientProfile>().WithMany().HasForeignKey(x => x.ClientId).OnDelete(DeleteBehavior.Restrict).HasConstraintName("fk_body_measurements_client_id");
        rows.HasIndex(x => new { x.ClientId, x.MeasuredAt, x.Id }).HasFilter("deleted_at IS NULL").HasDatabaseName("ix_body_measurements_client_measured_id");
    }
}
