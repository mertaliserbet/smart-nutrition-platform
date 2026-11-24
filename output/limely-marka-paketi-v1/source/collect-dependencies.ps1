$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path -Parent $PSScriptRoot
$iconCommit = '7981a0798a4f7184296bf42e94b6a8677f3ef2a0'
$fontCommit = '83c62e30d87daa70216dab6b984d00d20d96d585'
$iconNames = @(
  'house','bell','plus','minus','arrow-left','arrow-right','chevron-left','chevron-right','chevron-down',
  'calendar','calendar-days','calendar-check','calendar-clock','chart-column','chart-no-axes-column',
  'message-circle','messages-square','user-round','circle-user-round','users','grid-2x2','utensils',
  'inbox','package','layers','smartphone','globe','settings','video','wallet','triangle-alert',
  'search','check','circle-check','circle','scale','dumbbell','shield-check','salad','info',
  'armchair','footprints','activity','sprout','pencil','rotate-ccw','person-standing','ruler',
  'clipboard-list','clipboard-check','clock','menu','x','leaf','glass-water','notebook-pen'
)
$downloads = [System.Collections.Generic.List[object]]::new()
foreach ($iconName in $iconNames) {
  $upstreamName = if ($iconName -eq 'triangle-alert') { 'triangle-exclamation-point' } else { $iconName }
  $downloads.Add([pscustomobject]@{ Url="https://raw.githubusercontent.com/lucide-icons/lucide/$iconCommit/icons/$upstreamName.svg"; Relative="source/lucide/$iconName.svg" })
}
$downloads.Add([pscustomobject]@{ Url="https://raw.githubusercontent.com/lucide-icons/lucide/$iconCommit/LICENSE"; Relative='lisanslar/LUCIDE-LICENSE.txt' })
foreach ($family in @('fredoka','figtree','manrope','inter')) {
  $files = Invoke-RestMethod -Uri "https://api.github.com/repos/google/fonts/contents/ofl/${family}?ref=$fontCommit" -Headers @{ 'User-Agent'='Limely-asset-package' } -TimeoutSec 30
  foreach ($fontFile in $files) {
    if ($fontFile.name -like '*.ttf') {
      $suffix = if ($fontFile.name -like '*Italic*') { '-italic' } else { '' }
      $downloads.Add([pscustomobject]@{ Url=$fontFile.download_url; Relative="fontlar/$family/$family$suffix.ttf" })
    } elseif ($fontFile.name -eq 'OFL.txt') {
      $downloads.Add([pscustomobject]@{ Url=$fontFile.download_url; Relative="fontlar/$family/OFL.txt" })
    }
  }
}
$results = $downloads | ForEach-Object -Parallel {
  $ErrorActionPreference = 'Stop'
  $download = $_
  $destination = Join-Path $using:packageRoot $download.Relative
  [void][IO.Directory]::CreateDirectory((Split-Path -Parent $destination))
  try { Invoke-WebRequest -Uri $download.Url -OutFile $destination -Headers @{ 'User-Agent'='Limely-asset-package' } -TimeoutSec 60 }
  catch { throw "Download failed: $($download.Url) — $($_.Exception.Message)" }
  [pscustomobject]@{ url=$download.Url; file=$download.Relative; sha256=(Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant() }
} -ThrottleLimit 6
if ($results.Count -ne $downloads.Count) { throw 'Not all dependencies downloaded' }
$records = @{ lucideCommit=$iconCommit; googleFontsCommit=$fontCommit; files=@($results | Sort-Object file) }
$records | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'dis-kaynaklar.json') -Encoding utf8
[pscustomobject]@{ Downloaded=$results.Count; Icons=$iconNames.Count; Fonts=@($results | Where-Object file -like '*.ttf').Count }
