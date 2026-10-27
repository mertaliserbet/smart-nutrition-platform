using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;

namespace SmartNutrition.Api.Features.Auth;

public sealed class WebSessionOptions
{
    public const string SectionName = "Auth:WebSession";
    public string Origin { get; set; } = "";
    public string KeyRingPath { get; set; } = "";
    public string KeyProtectionCertificatePath { get; set; } = "";
    public string KeyProtectionCertificatePassword { get; set; } = "";
    public int CsrfRequestsPerMinute { get; set; } = 30;
    public bool Enabled => !string.IsNullOrEmpty(Origin);

    public bool IsValid(string contentRoot)
    {
        if (!Enabled) return true; // Existing mobile/JWT deployments can leave web sessions unconfigured.
        if (!Uri.TryCreate(Origin, UriKind.Absolute, out var origin) || origin.Scheme != "https" ||
            Origin != origin.GetLeftPart(UriPartial.Authority) || !string.IsNullOrEmpty(origin.UserInfo) ||
            !Path.IsPathFullyQualified(KeyRingPath) || CsrfRequestsPerMinute <= 0) return false;
        var root = new DirectoryInfo(contentRoot);
        while (root.Parent is not null && !Directory.Exists(Path.Combine(root.FullName, ".git"))) root = root.Parent;
        var repositoryRoot = root.Parent is null ? contentRoot : root.FullName;
        var relative = Path.GetRelativePath(repositoryRoot, KeyRingPath);
        if (relative == "." || (!Path.IsPathRooted(relative) && relative != ".." && !relative.StartsWith(".." + Path.DirectorySeparatorChar))) return false;
        if (string.IsNullOrEmpty(KeyProtectionCertificatePath)) return OperatingSystem.IsWindows();
        try
        {
            using var certificate = X509CertificateLoader.LoadPkcs12FromFile(KeyProtectionCertificatePath, KeyProtectionCertificatePassword);
            return certificate.HasPrivateKey;
        }
        catch (Exception error) when (error is CryptographicException or IOException or ArgumentException) { return false; }
    }
}
