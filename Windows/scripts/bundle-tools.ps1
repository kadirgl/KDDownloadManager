<#
  Windows uygulamasının yardımcı programlarını hazırlar (macOS'taki scripts/bundle-tools.sh'nin karşılığı):
    aria2c.exe  → aria2'nin resmi Windows sürümü (yalnızca x64 var; ARM64'te Windows'un x64 emülasyonuyla çalışır)
    yt-dlp      → resmi sürümün klasör hali (onedir): yt-dlp_win_arm64.zip / yt-dlp_win.zip; SHA2-256SUMS ile doğrulanır
    ffmpeg      → BtbN/FFmpeg-Builds'in paylaşımlı (DLL'li) GPL sürümü; ffmpeg.exe, ffprobe.exe ve DLL'ler; checksums.sha256 ile doğrulanır
    qjs.exe     → QuickJS-ng (yt-dlp'nin YouTube doğrulamasını çözmesi için); x64, ARM64'te emülasyonla çalışır
  İndirilenler Windows\dist\cache altında saklanır; sonuç Windows\dist\tools-<mimari>.

    powershell -ExecutionPolicy Bypass -File Windows\scripts\bundle-tools.ps1 -Arch arm64
    $env:YTDLP_VERSION = '2026.11.01'   # yt-dlp sürümünü değiştirmek için
#>
param([ValidateSet('arm64', 'x64')][string]$Arch = 'arm64')
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Root = Resolve-Path (Join-Path $PSScriptRoot '..')
$Cache = Join-Path $Root 'dist\cache'
$Out = Join-Path $Root "dist\tools-$Arch"
$YtDlpVersion = if ($env:YTDLP_VERSION) { $env:YTDLP_VERSION } else { '2026.11.23' }
$Aria2Version = '1.37.0'
# aria2 ve QuickJS sürümleri sağlama toplamı yayımlamıyor; ilk indirmede hesaplanıp buraya sabitlendi.
$Aria2Sha256 = '67d015301eef0b612191212d564c5bb0a14b5b9c4796b76454276a4d28d9b288'
$QuickJsVersion = 'v0.18.0'
$QuickJsSha256 = 'ff03398d74ea6e6bd3a8e58058f7003225abcac229d7d57775b7aaae812a49c7'
$FfmpegRelease = if ($env:FFMPEG_RELEASE) { $env:FFMPEG_RELEASE } else { 'latest' }

New-Item -ItemType Directory -Force $Cache | Out-Null

function Get-File([string]$Url, [string]$Path) {
    if (Test-Path $Path) { return }
    Write-Host "→ $(Split-Path $Url -Leaf) indiriliyor…"
    $part = "$Path.part"
    & curl.exe -fsSL --retry 3 -o $part $Url
    if ($LASTEXITCODE -ne 0) { throw "İndirilemedi: $Url" }
    Move-Item -Force $part $Path
}

function Assert-Hash([string]$Path, [string]$Expected) {
    $actual = (Get-FileHash -Algorithm SHA256 $Path).Hash.ToLowerInvariant()
    if ($Expected -eq 'pin-on-first-download') {
        Write-Warning "$(Split-Path $Path -Leaf) SHA-256: $actual (betiğe sabitleyin)"
        return
    }
    if ($actual -ne $Expected.ToLowerInvariant()) {
        Remove-Item -Force $Path
        throw "$(Split-Path $Path -Leaf) SHA-256 doğrulanamadı ($actual); dosya silindi."
    }
}

function Find-Sum([string]$SumsFile, [string]$Name) {
    foreach ($line in Get-Content $SumsFile) {
        $parts = $line -split '\s+', 2
        if ($parts.Count -eq 2 -and $parts[1].TrimStart('*') -eq $Name) { return $parts[0] }
    }
    throw "$Name için sağlama toplamı yok ($SumsFile)"
}

if (Test-Path $Out) { Remove-Item -Recurse -Force $Out }
New-Item -ItemType Directory -Force $Out | Out-Null

# aria2c
$aria2Zip = Join-Path $Cache "aria2-$Aria2Version-win-64bit-build1.zip"
Get-File "https://github.com/aria2/aria2/releases/download/release-$Aria2Version/aria2-$Aria2Version-win-64bit-build1.zip" $aria2Zip
Assert-Hash $aria2Zip $Aria2Sha256
$temp = Join-Path $env:TEMP "kd-aria2-$PID"
Expand-Archive -Force $aria2Zip $temp
Copy-Item (Get-ChildItem -Recurse $temp -Filter aria2c.exe | Select-Object -First 1).FullName (Join-Path $Out 'aria2c.exe')
Remove-Item -Recurse -Force $temp

# yt-dlp (onedir: hızlı açılır; tek dosyalık sürüm her çalıştırmada kendini açıyor)
$ytName = if ($Arch -eq 'arm64') { 'yt-dlp_win_arm64.zip' } else { 'yt-dlp_win.zip' }
$ytCache = Join-Path $Cache "yt-dlp-$YtDlpVersion"
New-Item -ItemType Directory -Force $ytCache | Out-Null
$release = "https://github.com/yt-dlp/yt-dlp/releases/download/$YtDlpVersion"
Get-File "$release/SHA2-256SUMS" (Join-Path $ytCache 'SHA2-256SUMS')
$ytZip = Join-Path $ytCache $ytName
Get-File "$release/$ytName" $ytZip
Assert-Hash $ytZip (Find-Sum (Join-Path $ytCache 'SHA2-256SUMS') $ytName)
$ytOut = Join-Path $Out 'yt-dlp'
Expand-Archive -Force $ytZip $ytOut
# Zip'in içinde bir üst klasör varsa düzleştir; çalıştırılabilir dosyanın adı her mimaride yt-dlp.exe olsun.
$exe = Get-ChildItem -Recurse $ytOut -Filter 'yt-dlp*.exe' | Select-Object -First 1
if ($exe.DirectoryName -ne $ytOut) {
    Get-ChildItem $exe.DirectoryName | Move-Item -Destination $ytOut
}
$exe = Get-ChildItem $ytOut -Filter 'yt-dlp*.exe' | Select-Object -First 1
if ($exe.Name -ne 'yt-dlp.exe') { Rename-Item $exe.FullName 'yt-dlp.exe' }
Set-Content -NoNewline -Encoding ascii (Join-Path $Out 'yt-dlp.version') $YtDlpVersion

# ffmpeg (paylaşımlı: ffmpeg.exe + ffprobe.exe aynı DLL'leri kullanıyor; statik sürümden ~2,5 kat küçük)
$ffArch = if ($Arch -eq 'arm64') { 'winarm64' } else { 'win64' }
$ffName = "ffmpeg-n9.0-latest-$ffArch-gpl-shared-9.0.zip"
$ffCache = Join-Path $Cache "ffmpeg-$FfmpegRelease-$((Get-Date).ToString('yyyyMMdd'))"
if ($FfmpegRelease -ne 'latest') { $ffCache = Join-Path $Cache "ffmpeg-$FfmpegRelease" }
New-Item -ItemType Directory -Force $ffCache | Out-Null
$ffRelease = "https://github.com/BtbN/FFmpeg-Builds/releases/download/$FfmpegRelease"
$existing = Get-ChildItem $Cache -Recurse -Filter $ffName -ErrorAction SilentlyContinue | Select-Object -First 1
if ($existing -and (Test-Path (Join-Path $existing.DirectoryName 'checksums.sha256'))) { $ffCache = $existing.DirectoryName }
Get-File "$ffRelease/checksums.sha256" (Join-Path $ffCache 'checksums.sha256')
$ffZip = Join-Path $ffCache $ffName
Get-File "$ffRelease/$ffName" $ffZip
Assert-Hash $ffZip (Find-Sum (Join-Path $ffCache 'checksums.sha256') $ffName)
$temp = Join-Path $env:TEMP "kd-ffmpeg-$PID"
Expand-Archive -Force $ffZip $temp
$bin = (Get-ChildItem -Recurse $temp -Filter ffmpeg.exe | Select-Object -First 1).DirectoryName
$ffOut = Join-Path $Out 'ffmpeg'
New-Item -ItemType Directory -Force $ffOut | Out-Null
Copy-Item (Join-Path $bin 'ffmpeg.exe'), (Join-Path $bin 'ffprobe.exe') $ffOut
Copy-Item (Join-Path $bin '*.dll') $ffOut
$license = Get-ChildItem -Recurse $temp -Filter 'LICENSE*' | Select-Object -First 1
if ($license) { Copy-Item $license.FullName (Join-Path $ffOut 'LICENSE.txt') }
Remove-Item -Recurse -Force $temp

# QuickJS
$qjs = Join-Path $Cache "qjs-$QuickJsVersion-windows-x86_64.exe"
Get-File "https://github.com/quickjs-ng/quickjs/releases/download/$QuickJsVersion/qjs-windows-x86_64.exe" $qjs
Assert-Hash $qjs $QuickJsSha256
Copy-Item $qjs (Join-Path $Out 'qjs.exe')

# Çalışıyorlar mı?
& (Join-Path $Out 'aria2c.exe') --version | Select-Object -First 1
& (Join-Path $Out 'yt-dlp\yt-dlp.exe') --version
& (Join-Path $Out 'ffmpeg\ffmpeg.exe') -hide_banner -version | Select-Object -First 1
$size = (Get-ChildItem -Recurse $Out | Measure-Object -Sum Length).Sum / 1MB
Write-Host ("✓ Araçlar hazır: {0:N0} MB ({1})" -f $size, $Out)
