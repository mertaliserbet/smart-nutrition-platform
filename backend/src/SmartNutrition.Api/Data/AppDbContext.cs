using Microsoft.EntityFrameworkCore;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Features.Dietitians;
using SmartNutrition.Api.Features.Relationships;
using SmartNutrition.Api.Features.NutritionPlans;

namespace SmartNutrition.Api.Data;

public sealed class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options)
{
    public DbSet<User> Users => Set<User>();
    public DbSet<ClientProfile> ClientProfiles => Set<ClientProfile>();
    public DbSet<AuthSession> AuthSessions => Set<AuthSession>();
    public DbSet<RefreshToken> RefreshTokens => Set<RefreshToken>();
    public DbSet<DietitianProfile> DietitianProfiles => Set<DietitianProfile>();
    public DbSet<AuditEvent> AuditEvents => Set<AuditEvent>();
    public DbSet<DietitianClientRelationship> DietitianClientRelationships => Set<DietitianClientRelationship>();
    public DbSet<DataSharingPermission> DataSharingPermissions => Set<DataSharingPermission>();
    public DbSet<NutritionPlan> NutritionPlans => Set<NutritionPlan>();
    public DbSet<NutritionPlanVersion> NutritionPlanVersions => Set<NutritionPlanVersion>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);
        AuthModelConfiguration.Configure(modelBuilder);
        AuthSession.Configure(modelBuilder);
        RefreshToken.Configure(modelBuilder);
        DietitianProfile.Configure(modelBuilder);
        AuditEvent.Configure(modelBuilder);
        DietitianClientRelationship.Configure(modelBuilder);
        DataSharingPermission.Configure(modelBuilder);
        NutritionPlan.Configure(modelBuilder);
        NutritionPlanVersion.Configure(modelBuilder);
    }
}
