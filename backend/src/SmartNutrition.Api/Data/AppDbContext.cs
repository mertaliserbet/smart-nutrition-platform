using Microsoft.EntityFrameworkCore;
using SmartNutrition.Api.Features.Auth;
using SmartNutrition.Api.Features.Dietitians;

namespace SmartNutrition.Api.Data;

public sealed class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options)
{
    public DbSet<User> Users => Set<User>();
    public DbSet<ClientProfile> ClientProfiles => Set<ClientProfile>();
    public DbSet<AuthSession> AuthSessions => Set<AuthSession>();
    public DbSet<DietitianProfile> DietitianProfiles => Set<DietitianProfile>();
    public DbSet<AuditEvent> AuditEvents => Set<AuditEvent>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);
        AuthModelConfiguration.Configure(modelBuilder);
        AuthSession.Configure(modelBuilder);
        DietitianProfile.Configure(modelBuilder);
        AuditEvent.Configure(modelBuilder);
    }
}
