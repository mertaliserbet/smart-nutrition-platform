using System.ComponentModel.DataAnnotations;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using SmartNutrition.Api.Data;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Features.Auth;

// Explicit local operator command. Does not start HTTP or print enrollment material.
internal static class AdminBootstrap
{
    internal static async Task<int> RunAsync(IServiceProvider services, string inputPath, string outputPath)
    {
        var created = false;
        try
        {
            inputPath = Path.GetFullPath(inputPath); outputPath = Path.GetFullPath(outputPath);
            var repository = new DirectoryInfo(Directory.GetCurrentDirectory());
            while (repository.Parent is not null && !Directory.Exists(Path.Combine(repository.FullName, ".git"))) repository = repository.Parent;
            if (inputPath == outputPath || File.Exists(outputPath) ||
                Path.GetRelativePath(repository.FullName, inputPath).Split(Path.DirectorySeparatorChar)[0] != ".." ||
                Path.GetRelativePath(repository.FullName, outputPath).Split(Path.DirectorySeparatorChar)[0] != "..")
                throw new InvalidOperationException("Private setup files must be outside the repository.");
            var input = JsonSerializer.Deserialize<AdminSetupInput>(await File.ReadAllTextAsync(inputPath), new JsonSerializerOptions
            { PropertyNamingPolicy = JsonNamingPolicy.CamelCase, UnmappedMemberHandling = System.Text.Json.Serialization.JsonUnmappedMemberHandling.Disallow });
            if (input is null || string.IsNullOrWhiteSpace(input.Email) || !RegisterUserRequest.IsValidEmail(input.Email) || string.IsNullOrEmpty(input.Password))
                throw new ValidationException();
            using var scope = services.CreateScope();
            var provider = scope.ServiceProvider;
            if (provider.GetRequiredService<IOptions<RegistrationPasswordPolicy>>().Value.Validate(input.Password).Count != 0)
                throw new ValidationException();
            var database = provider.GetRequiredService<AppDbContext>();
            var email = provider.GetRequiredService<ILookupNormalizer>().NormalizeEmail(input.Email.Trim())!;
            await using var transaction = await database.Database.BeginTransactionAsync();
            var user = await database.Users.FromSqlInterpolated($"SELECT * FROM users WHERE email = {email} FOR UPDATE").SingleOrDefaultAsync();
            if (user is not null)
            {
                // Existing Admin reset also requires its current password; no role conversion.
                if (user.Role != UserRole.Admin || provider.GetRequiredService<IPasswordHasher<User>>()
                        .VerifyHashedPassword(user, user.PasswordHash, input.Password) == PasswordVerificationResult.Failed)
                    throw new ValidationException();
                await provider.GetRequiredService<WebSessionService>().RevokeAllAsync(user.Id, CancellationToken.None);
            }
            else
            {
                user = new User(Guid.NewGuid(), email, UserRole.Admin, input.Password, DateTimeOffset.UtcNow,
                    provider.GetRequiredService<IPasswordHasher<User>>());
                database.Users.Add(user);
            }
            var enrollment = provider.GetRequiredService<AdminMfaService>().Initialize(user, DateTimeOffset.UtcNow);
            // CreateNew prevents overwriting an existing enrollment or another user's file.
            var fileOptions = new FileStreamOptions
            {
                Mode = FileMode.CreateNew, Access = FileAccess.Write, Share = FileShare.None,
                Options = FileOptions.WriteThrough
            };
            if (!OperatingSystem.IsWindows()) fileOptions.UnixCreateMode = UnixFileMode.UserRead | UnixFileMode.UserWrite;
            await using (var stream = new FileStream(outputPath, fileOptions))
            {
                created = true;
                if (OperatingSystem.IsWindows())
                {
                    var owner = WindowsIdentity.GetCurrent().User!;
                    var security = new FileSecurity();
                    security.SetAccessRuleProtection(true, false); security.SetOwner(owner);
                    security.AddAccessRule(new FileSystemAccessRule(owner, FileSystemRights.FullControl, AccessControlType.Allow));
                    new FileInfo(outputPath).SetAccessControl(security);
                }
                await JsonSerializer.SerializeAsync(stream, new
                {
                    manualKey = enrollment.Key,
                    otpAuthUri = $"otpauth://totp/SmartNutrition:{Uri.EscapeDataString(email)}?secret={enrollment.Key}&issuer=SmartNutrition&algorithm=SHA1&digits=6&period=30",
                    recoveryCodes = enrollment.RecoveryCodes
                });
            }
            await database.SaveChangesAsync();
            await transaction.CommitAsync();
            return 0;
        }
        catch
        {
            if (created) { try { File.Delete(outputPath); } catch { /* No secret output on cleanup failure. */ } }
            // Do not send exceptions/credentials/enrollment to console or structured logs.
            return 1;
        }
    }

    private sealed class AdminSetupInput
    {
        public string? Email { get; set; }
        public string? Password { get; set; }
    }
}
