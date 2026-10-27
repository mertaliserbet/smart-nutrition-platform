using System.Security.Cryptography.X509Certificates;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.Extensions.Options;

namespace SmartNutrition.Api.Features.Auth;

// Resolve options after all configuration providers (including integration hosts) are installed.
internal sealed class WebSessionKeyProtection : IDataProtectionProvider, IDisposable
{
    private readonly IDataProtectionProvider _provider;
    private readonly X509Certificate2? _certificate;

    public WebSessionKeyProtection(IOptions<WebSessionOptions> settings)
    {
        var configuration = settings.Value;
        if (!configuration.Enabled) { _provider = new EphemeralDataProtectionProvider(); return; }
        if (!string.IsNullOrEmpty(configuration.KeyProtectionCertificatePath))
            _certificate = X509CertificateLoader.LoadPkcs12FromFile(configuration.KeyProtectionCertificatePath, configuration.KeyProtectionCertificatePassword);
        _provider = DataProtectionProvider.Create(new DirectoryInfo(configuration.KeyRingPath), builder =>
        {
            builder.SetApplicationName("SmartNutrition.WebSession.v1");
            // Use the public framework configuration so PFX decryption is registered as well as encryption.
            if (_certificate is not null) builder.ProtectKeysWithCertificate(_certificate);
            else if (OperatingSystem.IsWindows()) builder.ProtectKeysWithDpapi();
            else throw new InvalidOperationException("Protected web session keys are required.");
        });
    }

    public IDataProtector CreateProtector(string purpose) => _provider.CreateProtector(purpose);

    public void Dispose() { (_provider as IDisposable)?.Dispose(); _certificate?.Dispose(); }
}
