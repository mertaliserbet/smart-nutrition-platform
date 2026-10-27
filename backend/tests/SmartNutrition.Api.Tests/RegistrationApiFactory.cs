using System.Collections.Concurrent;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Npgsql;
using SmartNutrition.Api.Data;

namespace SmartNutrition.Api.Tests;

// Real HTTP host + real PostgreSQL, isolated in a newly created, disposable schema.
// Public/application tables are never deleted, reset or used for committed test accounts.
internal sealed class RegistrationApiFactory : WebApplicationFactory<Program>
{
    private const string SchemaPrefix = "registration_api_test_";
    private readonly string _schema = SchemaPrefix + Guid.NewGuid().ToString("N");
    private readonly string _adminConnection;
    private readonly string _testConnection;
    private readonly IInterceptor? _interceptor;
    private readonly CaptureLoggerProvider _logs = new();

    private RegistrationApiFactory(IInterceptor? interceptor)
    {
        var builder = new NpgsqlConnectionStringBuilder(
            Environment.GetEnvironmentVariable(PostgresFactAttribute.ConnectionVariable))
        {
            IncludeErrorDetail = false
        };
        _adminConnection = builder.ConnectionString;
        builder.SearchPath = _schema;
        _testConnection = builder.ConnectionString;
        _interceptor = interceptor;
    }

    public static async Task<RegistrationApiFactory> CreateAsync(IInterceptor? interceptor = null)
    {
        var factory = new RegistrationApiFactory(interceptor);
        await using var connection = new NpgsqlConnection(factory._adminConnection);
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = $"CREATE SCHEMA \"{factory.CheckedSchemaName()}\"";
        await command.ExecuteNonQueryAsync();
        try
        {
            await using var scope = factory.Services.CreateAsyncScope();
            await scope.ServiceProvider.GetRequiredService<AppDbContext>().Database.MigrateAsync();
            return factory;
        }
        catch
        {
            await factory.DisposeAsync();
            throw;
        }
    }

    public HttpClient Client() => CreateClient(new WebApplicationFactoryClientOptions
    {
        BaseAddress = new Uri("https://localhost"),
        AllowAutoRedirect = false
    });

    public AppDbContext Database() => new(new DbContextOptionsBuilder<AppDbContext>()
        .UseNpgsql(_testConnection).Options);

    public string Logs => string.Join(Environment.NewLine, _logs.Messages);

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Production");
        builder.ConfigureAppConfiguration((_, configuration) => configuration.AddInMemoryCollection(
            new Dictionary<string, string?> { ["ConnectionStrings:DefaultConnection"] = _testConnection }));
        builder.ConfigureLogging(logging => logging.ClearProviders().AddProvider(_logs));
        if (_interceptor is not null)
            builder.ConfigureServices(services => services.AddDbContext<AppDbContext>(options => options.AddInterceptors(_interceptor)));
    }

    public override async ValueTask DisposeAsync()
    {
        await base.DisposeAsync();
        await using var connection = new NpgsqlConnection(_adminConnection);
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        // Only the random schema created by this instance is eligible for cleanup.
        command.CommandText = $"DROP SCHEMA IF EXISTS \"{CheckedSchemaName()}\" CASCADE";
        await command.ExecuteNonQueryAsync();
    }

    private string CheckedSchemaName()
    {
        if (!_schema.StartsWith(SchemaPrefix, StringComparison.Ordinal) ||
            !Guid.TryParseExact(_schema[SchemaPrefix.Length..], "N", out _))
            throw new InvalidOperationException("Refusing cleanup outside the isolated registration test schema.");
        return _schema;
    }

    private sealed class CaptureLoggerProvider : ILoggerProvider
    {
        public ConcurrentQueue<string> Messages { get; } = new();
        public ILogger CreateLogger(string categoryName) => new CaptureLogger(Messages);
        public void Dispose() { }

        private sealed class CaptureLogger(ConcurrentQueue<string> messages) : ILogger
        {
            public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;
            public bool IsEnabled(LogLevel logLevel) => true;
            public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception? exception,
                Func<TState, Exception?, string> formatter)
            {
                messages.Enqueue(formatter(state, exception));
                if (exception is not null) messages.Enqueue(exception.ToString());
            }
        }
    }
}
