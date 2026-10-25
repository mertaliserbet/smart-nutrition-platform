using Microsoft.EntityFrameworkCore;

namespace SmartNutrition.Api.Data;

public sealed class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options)
{
    // Entity mappings are added here with their approved feature implementation.
}
