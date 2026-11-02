#requires -Version 7.5
<#
.SYNOPSIS
Creates a private, per-developer CA for the local Android browser only.
Trust installation is explicit; no machine-wide store or Android system image is changed.
#>
[CmdletBinding()]
param([string] $EmulatorId)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'Bu kurulum Windows ve PowerShell 7.5+ gerektirir.' }

$directory = Join-Path $env:LOCALAPPDATA 'SmartNutrition/browser-https'
[void][IO.Directory]::CreateDirectory($directory)
# Restrict access before writing any private key. The CA key is also DPAPI encrypted.
$identity = [Security.Principal.WindowsIdentity]::GetCurrent().User
& icacls $directory /inheritance:r /grant:r "*$($identity.Value):(OI)(CI)F" '*S-1-5-18:(OI)(CI)F' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Özel geliştirme dizini izinleri sınırlandırılamadı.' }
$unexpected = @((Get-Acl $directory).GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]) | Where-Object {
    $_.AccessControlType -eq 'Allow' -and
    $_.IdentityReference.Value -notin @($identity.Value, 'S-1-5-18')
})
if ($unexpected.Count -gt 0) { throw 'Özel geliştirme dizinine başka hesapların erişimi var; izinleri inceleyin.' }

$rootPath = Join-Path $directory 'root-ca.crt'
$protectedKeyPath = Join-Path $directory 'root-key.dpapi'
$certificatePath = Join-Path $directory 'localhost.pem'
$keyPath = Join-Path $directory 'localhost.key'
foreach ($privatePath in @($protectedKeyPath, $keyPath)) {
    if (Test-Path $privatePath) {
        $unexpected = @((Get-Acl $privatePath).GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]) | Where-Object {
            $_.AccessControlType -eq 'Allow' -and $_.IdentityReference.Value -notin @($identity.Value, 'S-1-5-18')
        })
        if ($unexpected.Count -gt 0) { throw 'Özel anahtar erişim izinleri genişletilmiş; izinleri inceleyin.' }
    }
}
$hash = [Security.Cryptography.HashAlgorithmName]::SHA256
$padding = [Security.Cryptography.RSASignaturePadding]::Pkcs1
$now = [DateTimeOffset]::UtcNow
$caKey = [Security.Cryptography.RSA]::Create(3072)
$leafKey = $null
$root = $null
$leaf = $null
$privateBytes = $null
try {
    if ((Test-Path $rootPath) -ne (Test-Path $protectedKeyPath)) {
        throw 'CA dosyaları eksik. Mevcut güven kayıtlarını incelemeden yeni CA oluşturulmaz.'
    }
    if (Test-Path $rootPath) {
        $publicRoot = [Security.Cryptography.X509Certificates.X509CertificateLoader]::LoadCertificateFromFile($rootPath)
        try {
            $privateBytes = [Security.Cryptography.ProtectedData]::Unprotect(
                [IO.File]::ReadAllBytes($protectedKeyPath), $null,
                [Security.Cryptography.DataProtectionScope]::CurrentUser)
            $read = 0
            $caKey.ImportPkcs8PrivateKey($privateBytes, [ref]$read)
            $root = [Security.Cryptography.X509Certificates.RSACertificateExtensions]::CopyWithPrivateKey($publicRoot, $caKey)
        } finally { $publicRoot.Dispose() }
        if ($root.NotAfter.ToUniversalTime() -lt $now.AddDays(190).UtcDateTime) {
            throw 'CA süresi yenileme gerektiriyor; mevcut güveni kaldırıp kurulumu yeniden hazırlayın.'
        }
    } else {
        $request = [Security.Cryptography.X509Certificates.CertificateRequest]::new(
            'CN=Smart Nutrition Local Development CA', $caKey, $hash, $padding)
        $request.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new($true, $true, 0, $true))
        $request.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509KeyUsageExtension]::new(
            [Security.Cryptography.X509Certificates.X509KeyUsageFlags]::KeyCertSign -bor
            [Security.Cryptography.X509Certificates.X509KeyUsageFlags]::CrlSign, $true))
        $request.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509SubjectKeyIdentifierExtension]::new($request.PublicKey, $false))
        $root = $request.CreateSelfSigned($now.AddMinutes(-5), $now.AddYears(2))
        $privateBytes = $caKey.ExportPkcs8PrivateKey()
        $protectedBytes = [Security.Cryptography.ProtectedData]::Protect($privateBytes, $null,
            [Security.Cryptography.DataProtectionScope]::CurrentUser)
        [IO.File]::WriteAllBytes($protectedKeyPath, $protectedBytes)
        [IO.File]::WriteAllBytes($rootPath, $root.Export([Security.Cryptography.X509Certificates.X509ContentType]::Cert))
    }
    $renew = $true
    if ((Test-Path $certificatePath) -and (Test-Path $keyPath)) {
        $existing = [Security.Cryptography.X509Certificates.X509Certificate2]::CreateFromPemFile($certificatePath, $keyPath)
        try { $renew = $existing.NotAfter.ToUniversalTime() -lt $now.AddDays(7).UtcDateTime }
        finally { $existing.Dispose() }
    }
    if ($renew) {
        $leafKey = [Security.Cryptography.RSA]::Create(2048)
        $request = [Security.Cryptography.X509Certificates.CertificateRequest]::new('CN=localhost', $leafKey, $hash, $padding)
        $request.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new($false, $false, 0, $true))
        $request.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509KeyUsageExtension]::new(
            [Security.Cryptography.X509Certificates.X509KeyUsageFlags]::DigitalSignature -bor
            [Security.Cryptography.X509Certificates.X509KeyUsageFlags]::KeyEncipherment, $true))
        $oids = [Security.Cryptography.OidCollection]::new()
        [void]$oids.Add([Security.Cryptography.Oid]::new('1.3.6.1.5.5.7.3.1'))
        $request.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new($oids, $false))
        $san = [Security.Cryptography.X509Certificates.SubjectAlternativeNameBuilder]::new()
        $san.AddDnsName('localhost')
        $san.AddIpAddress([Net.IPAddress]::Loopback)
        $san.AddIpAddress([Net.IPAddress]::IPv6Loopback)
        $request.CertificateExtensions.Add($san.Build())
        $request.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509SubjectKeyIdentifierExtension]::new($request.PublicKey, $false))
        $serial = [Security.Cryptography.RandomNumberGenerator]::GetBytes(16)
        $leaf = $request.Create($root, $now.AddMinutes(-5), $now.AddDays(180), $serial)
        [IO.File]::WriteAllText($certificatePath, $leaf.ExportCertificatePem())
        [IO.File]::WriteAllText($keyPath, $leafKey.ExportPkcs8PrivateKeyPem())
    }
    Write-Host "Geliştirme CA SHA-256: $($root.GetCertHashString($hash))"
    Write-Host "Açık CA sertifikası: $rootPath"
    Write-Host "Web sertifikası: $certificatePath (localhost, 127.0.0.1, ::1)"
    Write-Host 'Windows güven depoları değiştirilmedi. CA yalnız test emülatörüne kurulmalıdır.'
    if ($EmulatorId) {
        if ($EmulatorId -notmatch '^emulator-\d+$') { throw 'Yalnız test Android emülatörü kabul edilir.' }
        $adb = Join-Path $env:LOCALAPPDATA 'Android/sdk/platform-tools/adb.exe'
        if (-not (Test-Path $adb)) { throw 'Android SDK adb bulunamadı.' }
        $qemu = & $adb -s $EmulatorId shell getprop ro.kernel.qemu
        if ($LASTEXITCODE -ne 0 -or $qemu.Trim() -ne '1') { throw 'Hedefin emülatör olduğu doğrulanamadı.' }
        & $adb -s $EmulatorId push $rootPath /sdcard/Download/smart-nutrition-dev-ca.crt
        if ($LASTEXITCODE -ne 0) { throw 'Açık CA sertifikası kopyalanamadı.' }
        Write-Host 'Android Ayarlar > Güvenlik ve gizlilik > Diğer güvenlik > Şifreleme ve kimlik bilgileri > Sertifika yükle > CA sertifikası yolundan bu dosyayı seçin. Sistem deposu değiştirilmez; cihaz onayı/PIN gerekebilir.'
    }
} finally {
    if ($privateBytes) { [Security.Cryptography.CryptographicOperations]::ZeroMemory($privateBytes) }
    if ($leaf) { $leaf.Dispose() }
    if ($root) { $root.Dispose() }
    if ($leafKey) { $leafKey.Dispose() }
    $caKey.Dispose()
}
