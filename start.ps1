#requires -Version 7.0
<#
.SYNOPSIS
Starts the existing local development services in one Windows terminal.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $IsWindows) { throw 'start.ps1 Windows ve PowerShell 7 gerektirir.' }

# Callbacks run outside the PowerShell runspace. Keep cancellation and process
# containment here; application commands and configuration stay below.
if (-not ('SmartNutrition.Development.ProcessGroup' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace SmartNutrition.Development
{
    public sealed class ProcessGroup : IDisposable
    {
        [StructLayout(LayoutKind.Sequential)]
        struct BasicLimits
        {
            public long ProcessTime, JobTime;
            public uint Flags;
            public UIntPtr MinWorkingSet, MaxWorkingSet;
            public uint ActiveProcessLimit;
            public UIntPtr Affinity;
            public uint Priority, Scheduling;
        }
        [StructLayout(LayoutKind.Sequential)]
        struct IoCounters { public ulong ReadOps, WriteOps, OtherOps, ReadBytes, WriteBytes, OtherBytes; }
        [StructLayout(LayoutKind.Sequential)]
        struct ExtendedLimits
        {
            public BasicLimits Basic;
            public IoCounters Io;
            public UIntPtr ProcessMemory, JobMemory, PeakProcessMemory, PeakJobMemory;
        }
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern IntPtr CreateJobObject(IntPtr attributes, string name);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool SetInformationJobObject(IntPtr job, int kind, ref ExtendedLimits limits, uint size);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
        [DllImport("kernel32.dll")]
        static extern bool CloseHandle(IntPtr handle);

        IntPtr handle;
        public ProcessGroup()
        {
            handle = CreateJobObject(IntPtr.Zero, null);
            if (handle == IntPtr.Zero) throw new Win32Exception();
            var limits = new ExtendedLimits();
            limits.Basic.Flags = 0x2000; // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
            if (!SetInformationJobObject(handle, 9, ref limits, (uint)Marshal.SizeOf<ExtendedLimits>()))
            {
                var error = new Win32Exception();
                Dispose();
                throw error;
            }
        }
        public void Add(Process process)
        {
            if (!AssignProcessToJobObject(handle, process.Handle))
            {
                // Short-lived probes can already have exited.
                if (process.HasExited) return;
                throw new Win32Exception();
            }
        }
        public void Dispose()
        {
            if (handle != IntPtr.Zero) { CloseHandle(handle); handle = IntPtr.Zero; }
        }
    }
    public static class Cancellation
    {
        public static volatile bool Requested;
        static ConsoleCancelEventHandler handler = (sender, args) => { args.Cancel = true; Requested = true; };
        public static void Listen() { Requested = false; Console.CancelKeyPress += handler; }
        public static void StopListening() { Console.CancelKeyPress -= handler; }
    }
}
'@
}

function Write-ServiceLog([string] $Name, [string] $Message, [ConsoleColor] $Color = 'Gray') {
    Write-Host "[$Name] $Message" -ForegroundColor $Color
}

function Find-Tool([string] $Name) {
    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) { throw "Eksik bağımlılık: $Name PATH içinde bulunamadı. README'deki ilk kurulumu tamamlayın." }
    return $command.Source
}

function Start-ServiceProcess {
    param([string] $Name, [string] $File, [string[]] $Arguments, [string] $Directory,
          [hashtable] $Environment = @{}, [switch] $Quiet)
    if ([SmartNutrition.Development.Cancellation]::Requested) { throw [OperationCanceledException]::new() }
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.WorkingDirectory = $Directory
    $info.UseShellExecute = $false
    # Keep every service windowless, including cmd wrappers for Flutter.
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.RedirectStandardInput = $true
    $info.StandardOutputEncoding = [Text.Encoding]::UTF8
    $info.StandardErrorEncoding = [Text.Encoding]::UTF8
    if ([IO.Path]::GetExtension($File) -in '.bat', '.cmd') {
        $info.FileName = $env:ComSpec
        # cmd /s /c requires an outer pair around the quoted batch path.
        $quoted = ($Arguments | ForEach-Object { '"' + $_ + '"' }) -join ' '
        $info.Arguments = '/d /s /c ""' + $File + '" ' + $quoted + '"'
    } else {
        $info.FileName = $File
        foreach ($argument in $Arguments) { $info.ArgumentList.Add($argument) }
    }
    foreach ($key in $Environment.Keys) { $info.Environment[$key] = $Environment[$key] }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    $started = $false
    try {
        [void] $process.Start()
        $started = $true
        $script:ProcessGroup.Add($process)
        $child = [pscustomobject]@{
            Name = $Name; Process = $process; Quiet = [bool]$Quiet
            Output = [Collections.Generic.List[string]]::new()
            OutTask = $process.StandardOutput.ReadLineAsync()
            ErrTask = $process.StandardError.ReadLineAsync()
        }
        $script:Children.Add($child)
        return $child
    } catch {
        if ($started -and -not $process.HasExited) { $process.Kill($true); [void]$process.WaitForExit(5000) }
        $process.Dispose()
        throw
    }
}

function Receive-ServiceLogs($Child) {
    foreach ($stream in @('Out', 'Err')) {
        $property = $stream + 'Task'
        for ($count = 0; $count -lt 200 -and $null -ne $Child.$property -and $Child.$property.IsCompleted; $count++) {
            $line = $Child.$property.GetAwaiter().GetResult()
            if ($null -eq $line) { $Child.$property = $null; break }
            if ($Child.Quiet -and $stream -eq 'Out') { $Child.Output.Add($line) }
            elseif ($Child.Quiet) { } # Keep diagnostic stderr out of machine-readable JSON/secrets.
            else { Write-ServiceLog $Child.Name $line }
            $Child.$property = if ($stream -eq 'Out') { $Child.Process.StandardOutput.ReadLineAsync() }
                              else { $Child.Process.StandardError.ReadLineAsync() }
        }
    }
}

function Pump-ServiceLogs {
    foreach ($child in $script:Children) { Receive-ServiceLogs $child }
    if ([SmartNutrition.Development.Cancellation]::Requested) { throw [OperationCanceledException]::new() }
}

function Invoke-ServiceCommand {
    param([string] $Name, [string] $File, [string[]] $Arguments, [string] $Directory,
          [int] $TimeoutSeconds = 30, [switch] $Quiet)
    $child = Start-ServiceProcess $Name $File $Arguments $Directory -Quiet:$Quiet
    $timer = [Diagnostics.Stopwatch]::StartNew()
    while (-not $child.Process.HasExited -or $null -ne $child.OutTask -or $null -ne $child.ErrTask) {
        Pump-ServiceLogs
        if ($timer.Elapsed.TotalSeconds -gt $TimeoutSeconds) {
            if (-not $child.Process.HasExited) { $child.Process.Kill($true) }
            throw "$Name işlemi $TimeoutSeconds saniyede tamamlanmadı."
        }
        [Threading.Thread]::Sleep(50)
    }
    if ($child.Process.ExitCode -ne 0) {
        # Quiet output can contain resolved Compose secrets; never dump it on failure.
        throw "$Name başarısız (çıkış $($child.Process.ExitCode)). İlgili kurulum/servis ayarlarını kontrol edin."
    }
    $result = $child.Output -join "`n"
    $child.Output.Clear()
    return $result
}

function Assert-FreePort([int] $Port, [string] $Name) {
    $listeners = [Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()
    if ($listeners.Port -contains $Port) {
        throw "$Name için $Port portu kullanımda. Mevcut servisi kendi terminalinden durdurup yeniden çalıştırın; script başka süreçleri kapatmaz."
    }
}

function Get-BackendSetting([string] $Key) {
    $value = [Environment]::GetEnvironmentVariable($Key.Replace(':', '__'))
    if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
    if ($script:Secrets.ContainsKey($Key)) { return $script:Secrets[$Key] }
    return $null
}

function Wait-ServiceUrl([string] $Name, [string] $Url, $Child, [int] $TimeoutSeconds = 90) {
    $ProgressPreference = 'SilentlyContinue'
    $timer = [Diagnostics.Stopwatch]::StartNew()
    while ($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        Pump-ServiceLogs
        if ($Child.Process.HasExited) { throw "$Name beklenmedik şekilde kapandı (çıkış $($Child.Process.ExitCode)). Yukarıdaki $Name logunu inceleyin." }
        try {
            # Normal certificate validation; never bypass TLS for local Auth.
            $response = Invoke-WebRequest -Uri $Url -TimeoutSec 2 -MaximumRedirection 0 -ErrorAction Stop
            if ($response.StatusCode -eq 200) { Write-ServiceLog $Name "Hazır: $Url" Green; return }
        } catch { }
        [Threading.Thread]::Sleep(200)
    }
    throw "$Name hazır olmadı: $Url. Sertifika, User Secrets ve veritabanı erişimini kontrol edin."
}

function Start-Development {
    $root = $PSScriptRoot
    $backend = Join-Path $root 'backend'
    $web = Join-Path $root 'apps/web'
    $mobile = Join-Path $root 'mobile'
    $script:Children = [Collections.Generic.List[object]]::new()
    $script:ProcessGroup = [SmartNutrition.Development.ProcessGroup]::new()
    $script:Secrets = @{}
    $ownedServices = [Collections.Generic.List[string]]::new()
    $docker = $null
    $flutterApp = $null
    $mobileTunnel = $null
    [SmartNutrition.Development.Cancellation]::Listen()
    try {
        Write-ServiceLog 'Başlatıcı' 'Ön kontroller yapılıyor; Ctrl+C ile durdurabilirsiniz.' Cyan
        $dotnet = Find-Tool 'dotnet'
        $docker = Find-Tool 'docker'
        $node = Find-Tool 'node'
        $flutter = Get-Command flutter -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $flutter) { Write-ServiceLog 'Mobil' 'Flutter PATH içinde yok; mobil atlanacak, diğer servisler devam edecek.' Yellow }

        $project = Join-Path $backend 'src/SmartNutrition.Api/SmartNutrition.Api.csproj'
        $vite = Join-Path $web 'node_modules/vite/bin/vite.js'
        if (-not (Test-Path -LiteralPath $vite)) { throw 'Web bağımlılıkları eksik. apps/web içinde npm ci --include=optional çalıştırın.' }
        $nodeVersion = Invoke-ServiceCommand 'Node' $node @('--version') $web -Quiet
        $version = [version]$nodeVersion.Trim().TrimStart('v')
        if (-not (($version.Major -eq 20 -and $version -ge [version]'20.19') -or $version -ge [version]'22.12')) {
            throw 'Web için Node.js 20.19+ (20.x) veya 22.12+ gereklidir.'
        }
        [void](Invoke-ServiceCommand '.NET SDK' $dotnet @('--version') $backend -Quiet)
        [xml]$projectXml = Get-Content -LiteralPath $project -Raw
        $secretsId = [string]$projectXml.Project.PropertyGroup.UserSecretsId
        $secretsFile = Join-Path $env:APPDATA "Microsoft/UserSecrets/$secretsId/secrets.json"
        if (Test-Path -LiteralPath $secretsFile) {
            try { $script:Secrets = Get-Content -LiteralPath $secretsFile -Raw | ConvertFrom-Json -AsHashtable }
            catch { throw 'Backend User Secrets JSON okunamadı; içerik güvenlik nedeniyle gösterilmiyor.' }
        }
        foreach ($key in @('ConnectionStrings:DefaultConnection', 'Auth:Jwt:Issuer', 'Auth:Jwt:Audience',
                           'Auth:Jwt:SigningKeyBase64', 'Auth:WebSession:Origin', 'Auth:WebSession:KeyRingPath',
                           'Email:Smtp:Host', 'Email:Smtp:FromAddress')) {
            if ([string]::IsNullOrWhiteSpace((Get-BackendSetting $key))) {
                throw "Eksik backend ayarı: $key. backend/README.md üzerinden environment/User Secrets kurulumunu tamamlayın."
            }
        }
        $webUrl = 'https://localhost:5173'
        if ((Get-BackendSetting 'Auth:WebSession:Origin') -ne $webUrl) {
            throw "Auth:WebSession:Origin mevcut Vite adresiyle eşleşmeli: $webUrl. Ayar otomatik değiştirilmez."
        }
        $certificate = $env:SMART_NUTRITION_HTTPS_CERT
        $certificateKey = $env:SMART_NUTRITION_HTTPS_KEY
        if ([string]::IsNullOrWhiteSpace($certificate) -and [string]::IsNullOrWhiteSpace($certificateKey)) {
            $certificate = Join-Path $env:LOCALAPPDATA 'SmartNutrition/dev-cert.pem'
            $certificateKey = Join-Path $env:LOCALAPPDATA 'SmartNutrition/dev-cert.key'
        }
        if (-not $certificate -or -not $certificateKey -or
            -not (Test-Path -LiteralPath $certificate -PathType Leaf) -or
            -not (Test-Path -LiteralPath $certificateKey -PathType Leaf)) {
            throw 'HTTPS PEM/anahtar dosyaları eksik. apps/web/README.md kurulumunu tamamlayın veya SMART_NUTRITION_HTTPS_CERT ve SMART_NUTRITION_HTTPS_KEY verin.'
        }
        [void](Invoke-ServiceCommand 'HTTPS sertifika kontrolü' $dotnet @('dev-certs', 'https', '--check', '--trust') $backend -Quiet)
        $profile = (Get-Content (Join-Path $backend 'src/SmartNutrition.Api/Properties/launchSettings.json') -Raw | ConvertFrom-Json).profiles.https
        $backendUrls = @($profile.applicationUrl.Split(';'))
        foreach ($url in $backendUrls) { Assert-FreePort ([uri]$url).Port 'Backend' }
        Assert-FreePort 5173 'Web'
        $apiUrl = $backendUrls | Where-Object { $_.StartsWith('https://') } | Select-Object -First 1
        if ($apiUrl -ne 'https://localhost:7099') { throw 'HTTPS launch profili ile mevcut Vite API hedefi uyuşmuyor; yapılandırmayı inceleyin.' }

        [void](Invoke-ServiceCommand 'Docker erişimi' $docker @('info', '--format', '{{.ServerVersion}}') $backend -Quiet)
        [void](Invoke-ServiceCommand 'Compose kontrolü' $docker @('compose', 'config', '--quiet') $backend -Quiet)
        $compose = Invoke-ServiceCommand 'Compose ayarları' $docker @('compose', 'config', '--format', 'json') $backend -Quiet | ConvertFrom-Json -AsHashtable
        $running = @( (Invoke-ServiceCommand 'Compose durumu' $docker @('compose', 'ps', '--status', 'running', '--services') $backend -Quiet) -split "`n" )
        foreach ($service in @('postgres', 'mailpit')) {
            if ($service -notin $running) {
                foreach ($port in $compose.services[$service].ports) { Assert-FreePort ([int]$port.published) $service }
                # Record before `up`: cancellation/partial startup still gets cleaned up.
                $ownedServices.Add($service)
            } else { Write-ServiceLog 'Docker' "$service zaten çalışıyor; çıkışta durdurulmayacak." Cyan }
        }
        Write-ServiceLog 'Docker' 'Mevcut Compose ile PostgreSQL ve Mailpit başlatılıyor.' Cyan
        [void](Invoke-ServiceCommand 'Docker' $docker @('compose', 'up', '-d', '--no-recreate', '--wait', '--wait-timeout', '60', 'postgres', 'mailpit') $backend -TimeoutSeconds 120)
        $dockerLogs = Start-ServiceProcess 'Docker' $docker @('compose', 'logs', '--follow', '--tail', '0', '--no-color', 'postgres', 'mailpit') $backend
        $api = Start-ServiceProcess 'Backend' $dotnet @('run', '--project', $project, '--launch-profile', 'https') $backend
        Wait-ServiceUrl 'Backend' "$apiUrl/health/live" $api
        Wait-ServiceUrl 'PostgreSQL' "$apiUrl/health/ready" $api -TimeoutSeconds 30
        $webEnvironment = @{
            SMART_NUTRITION_HTTPS_CERT = [IO.Path]::GetFullPath($certificate)
            SMART_NUTRITION_HTTPS_KEY = [IO.Path]::GetFullPath($certificateKey)
            NODE_EXTRA_CA_CERTS = if ($env:NODE_EXTRA_CA_CERTS) { $env:NODE_EXTRA_CA_CERTS } else { [IO.Path]::GetFullPath($certificate) }
        }
        $webApp = Start-ServiceProcess 'Web' $node @($vite, '--port', '5173', '--strictPort') $web -Environment $webEnvironment
        Wait-ServiceUrl 'Web' "$webUrl/giris" $webApp -TimeoutSeconds 30

        Write-ServiceLog 'Adresler' "Web: $webUrl/giris | Kayıt: $webUrl/kayit" Green
        Write-ServiceLog 'Adresler' "E-posta doğrulama: $webUrl/eposta-dogrulama | API: $apiUrl/swagger" Green
        foreach ($port in $compose.services.postgres.ports) { Write-ServiceLog 'PostgreSQL' "127.0.0.1:$($port.published) (veriler korunur)" Green }
        foreach ($port in $compose.services.mailpit.ports) {
            if ($port.target -eq 8025) { Write-ServiceLog 'Mailpit' "http://127.0.0.1:$($port.published)" Green }
        }
        # Do not retain resolved Compose passwords in memory longer than needed.
        $compose = $null
        $script:Secrets.Clear()
        if ($flutter) {
            try {
                $devices = @(Invoke-ServiceCommand 'Mobil cihaz kontrolü' $flutter.Source @('devices', '--machine') $mobile -TimeoutSeconds 30 -Quiet | ConvertFrom-Json)
                $emulator = $devices | Where-Object { $_.emulator -and $_.isSupported -and $_.targetPlatform -like 'android-*' } | Sort-Object id | Select-Object -First 1
                if ($emulator) {
                    if (-not (Test-Path (Join-Path $mobile '.dart_tool/package_config.json'))) {
                        Write-ServiceLog 'Mobil' 'Flutter paketleri eksik. mobile içinde flutter pub get çalıştırın; diğer servisler açık kalacak.' Yellow
                    } else {
                        Write-ServiceLog 'Mobil' "Android emülatörü: $($emulator.name) ($($emulator.id))." Cyan
                        $adbCommand = Get-Command adb -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
                        $adbPath = if ($adbCommand) { $adbCommand.Source } else { $null }
                        foreach ($sdk in @($env:ANDROID_SDK_ROOT, $env:ANDROID_HOME, (Join-Path $env:LOCALAPPDATA 'Android/sdk'))) {
                            if (-not $adbPath -and -not [string]::IsNullOrWhiteSpace($sdk)) {
                                $candidate = Join-Path $sdk 'platform-tools/adb.exe'
                                if (Test-Path -LiteralPath $candidate -PathType Leaf) { $adbPath = $candidate }
                            }
                        }
                        if (-not $adbPath) { throw 'Android SDK adb bulunamadı; SDK kurulumunu kontrol edin.' }
                        $reverse = Invoke-ServiceCommand 'Mobil HTTPS tünel kontrolü' $adbPath @('-s', $emulator.id, 'reverse', '--list') $mobile -Quiet
                        $httpsTunnel = [regex]::Match($reverse, '(?m)^\S+[ \t]+tcp:7099[ \t]+(?<target>\S+)')
                        if ($httpsTunnel.Success -and $httpsTunnel.Groups['target'].Value -ne 'tcp:7099') { throw 'Emülatörde 7099 portu başka bir hedefe bağlı; mevcut tünel korunuyor.' }
                        if (-not $httpsTunnel.Success) {
                            [void](Invoke-ServiceCommand 'Mobil HTTPS tüneli' $adbPath @('-s', $emulator.id, 'reverse', 'tcp:7099', 'tcp:7099') $mobile -Quiet)
                            $mobileTunnel = @{ Adb = $adbPath; Device = $emulator.id }
                        }
                        # Only the existing public PEM is passed, never its private key.
                        $publicPem = [IO.File]::ReadAllText($certificate)
                        if ($publicPem -match 'PRIVATE KEY' -or $publicPem -notmatch '-----BEGIN CERTIFICATE-----') {
                            throw 'Mobil bağlantı yalnız özel anahtar içermeyen açık PEM sertifikasını kabul eder.'
                        }
                        $publicCertificate = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($publicPem))
                        $publicPem = $null
                        $mobileArguments = @('run', '--no-pub', '-d', $emulator.id, "--dart-define=API_BASE_URL=$apiUrl", "--dart-define=API_DEV_CERT_BASE64=$publicCertificate")
                        $flutterApp = Start-ServiceProcess 'Mobil' $flutter.Source $mobileArguments $mobile -Environment @{ GRADLE_OPTS = "$env:GRADLE_OPTS -Dorg.gradle.daemon=false" }
                        $publicCertificate = $null
                    }
                } else { Write-ServiceLog 'Mobil' 'Çalışan Android emülatörü bulunamadı. Emülatörü kendiniz açıp scripti yeniden çalıştırabilirsiniz; backend/web açık kalacak.' Yellow }
            } catch [OperationCanceledException] { throw }
              catch { Write-ServiceLog 'Mobil' 'Flutter/cihaz kontrolü başarısız. flutter doctor ve flutter devices ile kontrol edin; diğer servisler açık kalacak.' Yellow }
        }
        Write-ServiceLog 'Başlatıcı' 'Servisler bu terminalden yönetiliyor. Durdurmak için Ctrl+C.' Cyan
        while (-not [SmartNutrition.Development.Cancellation]::Requested) {
            Pump-ServiceLogs
            foreach ($child in @($api, $webApp, $dockerLogs)) {
                if ($child.Process.HasExited) { throw "$($child.Name) kapandı (çıkış $($child.Process.ExitCode)); bu çalıştırmanın servisleri durduruluyor." }
            }
            if ($flutterApp -and $flutterApp.Process.HasExited) {
                Write-ServiceLog 'Mobil' "Flutter kapandı (çıkış $($flutterApp.Process.ExitCode)); backend/web açık kalacak." Yellow
                $flutterApp = $null
            }
            [Threading.Thread]::Sleep(100)
        }
    } finally {
        [SmartNutrition.Development.Cancellation]::StopListening()
        $cleanupFailed = $false
        Write-ServiceLog 'Başlatıcı' 'Bu çalıştırmanın süreçleri kapatılıyor…' Cyan
        if ($flutterApp -and -not $flutterApp.Process.HasExited) {
            try { $flutterApp.Process.StandardInput.WriteLine('q'); $flutterApp.Process.StandardInput.Flush(); [void]$flutterApp.Process.WaitForExit(5000) } catch { }
        }
        # Close the owned tree, including descendants whose launcher has already
        # exited (dotnet/node/Dart/Gradle). Unrelated processes are never selected.
        $script:ProcessGroup.Dispose()
        foreach ($child in $script:Children) {
            try { [void]$child.Process.WaitForExit(5000); Receive-ServiceLogs $child } catch { }
            $child.Process.Dispose()
        }
        if ($mobileTunnel -or ($docker -and $ownedServices.Count -gt 0)) {
            # Cleanup must still work after cancellation; volumes/containers are never removed.
            [SmartNutrition.Development.Cancellation]::Requested = $false
            $script:ProcessGroup = [SmartNutrition.Development.ProcessGroup]::new()
            $script:Children = [Collections.Generic.List[object]]::new()
            try {
                if ($mobileTunnel) {
                    try {
                        [void](Invoke-ServiceCommand 'Mobil HTTPS tüneli kapatma' $mobileTunnel.Adb @('-s', $mobileTunnel.Device, 'reverse', '--remove', 'tcp:7099') $mobile -Quiet)
                    } catch {
                        Write-ServiceLog 'Mobil' 'HTTPS tüneli kaldırılamadı; emülatör kapalıysa tünel zaten sona ermiştir.' Yellow
                    }
                }
                if ($docker -and $ownedServices.Count -gt 0) {
                    [void](Invoke-ServiceCommand 'Docker kapatma' $docker (@('compose', 'stop', '--timeout', '10') + $ownedServices.ToArray()) $backend -TimeoutSeconds 30)
                }
            } catch {
                $cleanupFailed = $true
                Write-ServiceLog 'Docker' "Kapatma tamamlanamadı. backend içinde docker compose stop $($ownedServices -join ' ') çalıştırın. Veriler silinmedi." Yellow
            }
            finally {
                $script:ProcessGroup.Dispose()
                foreach ($child in $script:Children) { $child.Process.Dispose() }
            }
        }
        $script:Secrets.Clear()
        if ($cleanupFailed) {
            Write-ServiceLog 'Başlatıcı' 'Uygulama süreçleri kapandı; Docker için yukarıdaki manuel kapatma adımı gerekli.' Yellow
        } else {
            Write-ServiceLog 'Başlatıcı' 'Kapatma tamamlandı. Önceden çalışan Docker servisleri ve emülatör korundu.' Cyan
        }
    }
}

# Dot-sourcing exposes the small helpers for terminal-only verification.
if ($MyInvocation.InvocationName -ne '.') {
    try { Start-Development }
    catch [OperationCanceledException] { }
    catch { Write-ServiceLog 'Hata' $_.Exception.Message Red; exit 1 }
}
