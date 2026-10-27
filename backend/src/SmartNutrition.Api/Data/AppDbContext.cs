using Microsoft.EntityFrameworkCore;
using SmartNutrition.Api.Features.Auth;

namespace SmartNutrition.Api.Data;

public sealed class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options)
{
    public DbSet<User> Users => Set<User>();
    public DbSet<ClientProfile> ClientProfiles => Set<ClientProfile>();
    public DbSet<AuthSession> AuthSessions => Set<AuthSession>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);
        AuthModelConfiguration.Configure(modelBuilder);
        AuthSession.Configure(modelBuilder);
    }
}
