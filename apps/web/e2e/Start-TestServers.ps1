param([Parameter(Mandatory)][string]$Artifacts, [switch]$Stop)
$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$Artifacts = [IO.Path]::GetFullPath($Artifacts)
if ($Artifacts.StartsWith($workspace + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Test secrets/artifacts must be outside the repository.' }
$stateFile = Join-Path $Artifacts 'u6-servers.json'
$ownerFile = Join-Path $Artifacts 'u6-owner.json'
function Stop-OwnedServers {
    if (!(Test-Path -LiteralPath $ownerFile)) { throw 'No U6 ownership marker; resources will not be removed.' }
    $owner = Get-Content -LiteralPath $ownerFile -Raw | ConvertFrom-Json
    if ($owner.Workspace -ne $workspace -or $owner.Artifacts -ne $Artifacts) { throw 'Test artifact ownership does not match.' }
    if (Test-Path -LiteralPath $stateFile) {
        $records = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
        foreach ($record in $records) {
            $running = Get-Process -Id $record.Id -ErrorAction SilentlyContinue
            if ($running -and $running.StartTime.ToUniversalTime().Ticks -eq $record.StartTicks -and $running.Path -eq $record.Path) { Stop-Process -Id $running.Id }
        }
        Remove-Item -LiteralPath $stateFile
    }
    foreach ($file in $owner.Keys) {
        if ($file.Name -notin @('localhost.key','localhost.pfx')) { throw 'Unexpected test key path.' }
        $target = Join-Path $Artifacts $file.Name
        if (Test-Path -LiteralPath $target) {
            if ((Get-FileHash -LiteralPath $target).Hash -ne $file.Hash) { throw 'Test key changed; preserving the file.' }
            Remove-Item -LiteralPath $target
        }
    }
    $ring = [IO.Path]::GetFullPath((Join-Path $Artifacts 'keyring'))
    if ((Test-Path -LiteralPath $ring) -and $ring.StartsWith($Artifacts + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        if ((Get-Item -LiteralPath $ring).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Refusing to remove a linked key ring.' }
        Remove-Item -LiteralPath $ring -Recurse
    }
    Remove-Item -LiteralPath $ownerFile
}
if ($Stop) { Stop-OwnedServers; exit }
if (Test-Path -LiteralPath $stateFile) { throw 'An existing test run must be stopped explicitly first.' }
foreach ($port in @(7099,5446)) { if (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue) { throw "Port $port is occupied; no existing process will be stopped." } }
foreach ($container in @('nutrition-u6-postgres','nutrition-u6-mailpit')) {
    $label = docker inspect --format '{{index .Config.Labels "smart-nutrition.test"}}' $container
    if ($LASTEXITCODE -ne 0 -or $label -ne 'U6') { throw 'Owned U6 containers are required.' }
}
New-Item -ItemType Directory -Path $Artifacts -Force | Out-Null
foreach ($file in @('localhost.key','localhost.pfx',$ownerFile)) {
    $candidate = if ([IO.Path]::IsPathFullyQualified($file)) { $file } else { Join-Path $Artifacts $file }
    if (Test-Path -LiteralPath $candidate) { throw 'Test artifacts already exist; preserve them and use a new directory.' }
}
$trusted = @(Get-ChildItem Cert:/CurrentUser/Root).Thumbprint
$cert = Get-ChildItem Cert:/CurrentUser/My | Where-Object { $_.Subject -eq 'CN=localhost' -and $_.HasPrivateKey -and $_.NotAfter -gt (Get-Date) -and $trusted -contains $_.Thumbprint } | Select-Object -First 1
if (!$cert) { throw 'A valid, already trusted localhost development certificate is required. TLS validation is never disabled.' }
$pass = [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
[IO.File]::WriteAllBytes((Join-Path $Artifacts 'localhost.pfx'), $cert.Export([Security.Cryptography.X509Certificates.X509ContentType]::Pfx, $pass))
[IO.File]::WriteAllText((Join-Path $Artifacts 'localhost.pem'), $cert.ExportCertificatePem())
$rsa = [Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)
try { [IO.File]::WriteAllText((Join-Path $Artifacts 'localhost.key'), $rsa.ExportPkcs8PrivateKeyPem()) } finally { $rsa.Dispose() }
@{ Workspace=$workspace; Artifacts=$Artifacts; Keys=@(foreach ($name in @('localhost.key','localhost.pfx')) { @{ Name=$name; Hash=(Get-FileHash -LiteralPath (Join-Path $Artifacts $name)).Hash } }) } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $ownerFile
$env:ASPNETCORE_ENVIRONMENT = 'Development'
$env:ConnectionStrings__DefaultConnection = 'Host=127.0.0.1;Port=55586;Database=nutrition_u6_test;Username=nutrition_test;Pooling=true'
$env:Auth__Jwt__Issuer = 'synthetic-u6'; $env:Auth__Jwt__Audience = 'synthetic-u6'
$env:Auth__Jwt__SigningKeyBase64 = [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
$env:Auth__WebSession__Origin = 'https://localhost:5446'; $env:Auth__WebSession__KeyRingPath = Join-Path $Artifacts 'keyring'
$env:Auth__WebSession__KeyProtectionCertificatePath = Join-Path $Artifacts 'localhost.pfx'; $env:Auth__WebSession__KeyProtectionCertificatePassword = $pass
$env:Kestrel__Certificates__Default__Path = Join-Path $Artifacts 'localhost.pfx'; $env:Kestrel__Certificates__Default__Password = $pass
$env:Email__Smtp__Host = '127.0.0.1'; $env:Email__Smtp__Port = '51028'; $env:Email__Smtp__TlsMode = 'None'; $env:Email__Smtp__FromAddress = 'synthetic-u6@example.test'
$env:Relationships__Sharing__ClientTasksEnabled = 'true'; $env:Relationships__Sharing__WaterLogsEnabled = 'true'
$env:Relationships__Sharing__MealLogsEnabled = 'true'; $env:Relationships__Sharing__BodyMeasurementsEnabled = 'true'
$env:Logging__LogLevel__Default = 'Warning'
$env:Auth__AdminEmailCode__Enabled = 'false'
$env:SMART_NUTRITION_HTTPS_CERT = Join-Path $Artifacts 'localhost.pem'; $env:SMART_NUTRITION_HTTPS_KEY = Join-Path $Artifacts 'localhost.key'
$env:NODE_EXTRA_CA_CERTS = $env:SMART_NUTRITION_HTTPS_CERT
$records = @()
try {
    $backend = Join-Path $workspace 'backend/src/SmartNutrition.Api'
    $dll = Join-Path $backend 'bin/Debug/net10.0/SmartNutrition.Api.dll'
    $api = Start-Process (Get-Command dotnet).Source -ArgumentList @($dll, '--urls', 'https://localhost:7099', '--Email:Smtp:Username=', '--Email:Smtp:Password=') -WorkingDirectory $backend -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $Artifacts 'api.stdout.log') -RedirectStandardError (Join-Path $Artifacts 'api.stderr.log')
    $records += @{ Id=$api.Id; StartTicks=$api.StartTime.ToUniversalTime().Ticks; Path=$api.Path }
    $records | ConvertTo-Json | Set-Content -LiteralPath $stateFile
    $web = Join-Path $workspace 'apps/web'
    $vite = Start-Process (Get-Command node).Source -ArgumentList @('node_modules/vite/bin/vite.js', '--port', '5446') -WorkingDirectory $web -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $Artifacts 'web.stdout.log') -RedirectStandardError (Join-Path $Artifacts 'web.stderr.log')
    $records += @{ Id=$vite.Id; StartTicks=$vite.StartTime.ToUniversalTime().Ticks; Path=$vite.Path }
    $records | ConvertTo-Json | Set-Content -LiteralPath $stateFile
    Write-Output 'Owned test API and Vite started. Set SNP_E2E_TEST_ENV=nutrition_u6_test and NODE_EXTRA_CA_CERTS to the generated localhost.pem before running test:e2e.'
} catch { Stop-OwnedServers; throw }
