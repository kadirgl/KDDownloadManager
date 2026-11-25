<#
  KD Download Manager'ın Windows paketini üretir (macOS'taki scripts/package-app.sh'nin karşılığı).

    powershell -ExecutionPolicy Bypass -File Windows\scripts\package.ps1                 → arm64 ve x64
    powershell -ExecutionPolicy Bypass -File Windows\scripts\package.ps1 -Arch arm64 -Version 1.9.3

  Her mimari için:
    1. yardımcı programlar (bundle-tools.ps1 → Windows\dist\tools-<mimari>)
    2. dotnet publish: Release, self-contained (.NET ve Windows App SDK kurulu olmasa da çalışır)
    3. tools\, BrowserExtension\ (ChromeExtension, sürümü uygulamanınkiyle eşit) ve Strings\ eklenir
    4. Windows\dist\KDDownloadManager-Windows-<mimari>-<sürüm>.zip (içinde tek klasör: KDDownloadManager\)
    5. Windows\dist\KDDownloadManager-Windows-<mimari>-<sürüm>-Setup.exe (Inno Setup, Windows\installer\KDDownloadManager.iss)
  Kullanıcılar kurulumu indirir; zip, 1.9.3 ve öncesinin uygulama içi güncellemesi (yalnızca zip'i tanır) ve kurulum
  istemeyenler için. İmzalar (uygulama içi güncelleme için) Mac'te scripts/release-windows.sh ile atılır; gizli anahtar
  Mac'in Anahtar Zinciri'nden çıkmaz.

  Gerekenler: .NET 10 SDK (dotnet PATH'te ya da C:\kd\dotnet), Inno Setup 6 (ISCC.exe PATH'te, C:\kd\inno'da ya da
  olağan kurulum klasöründe; -Iscc ile de verilebilir), internet (ilk çalıştırmada araçlar ve NuGet paketleri).
#>
param(
    [string[]]$Arch = @('arm64', 'x64'),
    [string]$Version = '',
    [string]$Iscc = ''
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Windows = Resolve-Path (Join-Path $PSScriptRoot '..')
$Repo = Resolve-Path (Join-Path $Windows '..')
$Project = Join-Path $Windows 'KDDownloadManager\KDDownloadManager.csproj'
$Dist = Join-Path $Windows 'dist'
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue) -and (Test-Path 'C:\kd\dotnet\dotnet.exe')) { $env:PATH = "C:\kd\dotnet;$env:PATH" }
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:DOTNET_NOLOGO = '1'

if (-not $Version) {
    $Version = ([xml](Get-Content $Project)).Project.PropertyGroup.Version | Where-Object { $_ } | Select-Object -First 1
}
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "Sürüm anlaşılamadı: '$Version' (örn. -Version 1.9.3)" }

if (-not $Iscc) {
    $Iscc = @(
        (Get-Command ISCC.exe -ErrorAction SilentlyContinue).Source,
        'C:\kd\inno\ISCC.exe',
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
        (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe')
    ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}
if (-not $Iscc -or -not (Test-Path $Iscc)) { throw 'Inno Setup 6 bulunamadı (ISCC.exe); https://jrsoftware.org/isdl.php ya da -Iscc <yol>' }
$Installer = Join-Path $Windows 'installer\KDDownloadManager.iss'

# Güncelleme imzasının açık anahtarı macOS uygulamasıyla aynı olmalı (derlemeye gömülüyor).
$key = (Get-Content -Raw (Join-Path $Repo 'scripts\update-public-key.txt')).Trim()
if ([Convert]::FromBase64String($key).Length -ne 32) { throw 'scripts\update-public-key.txt geçerli bir Ed25519 açık anahtarı değil' }

foreach ($a in $Arch) {
    $platform = if ($a -eq 'arm64') { 'ARM64' } else { 'x64' }
    Write-Host "== $a ($Version)"
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'bundle-tools.ps1') -Arch $a
    if ($LASTEXITCODE -ne 0) { throw "bundle-tools.ps1 başarısız ($a)" }

    $stage = Join-Path $Dist "stage-$a"
    $app = Join-Path $stage 'KDDownloadManager'
    if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
    & dotnet publish $Project -c Release -r "win-$a" "-p:Platform=$platform" --self-contained true `
        "-p:Version=$Version" -p:DebugType=none -p:PublishReadyToRun=false -o $app -clp:ErrorsOnly
    if ($LASTEXITCODE -ne 0) { throw "dotnet publish başarısız ($a)" }

    Copy-Item -Recurse (Join-Path $Dist "tools-$a") (Join-Path $app 'tools')
    $extension = Join-Path $app 'BrowserExtension'
    Copy-Item -Recurse (Join-Path $Repo 'ChromeExtension') $extension
    Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $extension 'README.md')
    # Eklenti ve uygulama hep aynı sürümde (eklenti, uygulamanın klasöründeki sürüm değişince kendini yeniden yükler).
    $manifest = Join-Path $extension 'manifest.json'
    $text = [IO.File]::ReadAllText($manifest)
    $text = [regex]::Replace($text, '"version": "[^"]*"', "`"version`": `"$Version`"")
    [IO.File]::WriteAllText($manifest, $text, (New-Object Text.UTF8Encoding $false))

    $exe = Join-Path $app 'KDDownloadManager.exe'
    $info = (Get-Item $exe).VersionInfo
    if ("$($info.FileMajorPart).$($info.FileMinorPart).$($info.FileBuildPart)" -ne $Version) { throw "Paketteki sürüm $($info.FileVersion), beklenen $Version" }

    $zip = Join-Path $Dist "KDDownloadManager-Windows-$a-$Version.zip"
    if (Test-Path $zip) { Remove-Item -Force $zip }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip, [IO.Compression.CompressionLevel]::Optimal, $false)
    $size = (Get-Item $zip).Length / 1MB
    Write-Host ("✓ {0} ({1:N0} MB)" -f $zip, $size)

    $setup = Join-Path $Dist "KDDownloadManager-Windows-$a-$Version-Setup.exe"
    if (Test-Path $setup) { Remove-Item -Force $setup }
    & $Iscc /Q "/DVersion=$Version" "/DArch=$a" "/DAppDir=$app" "/DOutputDir=$Dist" $Installer
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $setup)) { throw "Inno Setup başarısız ($a)" }
    $info = (Get-Item $setup).VersionInfo
    if ("$($info.FileMajorPart).$($info.FileMinorPart).$($info.FileBuildPart)" -ne $Version) { throw "Kurulumun sürümü $($info.FileVersion), beklenen $Version" }
    $size = (Get-Item $setup).Length / 1MB
    Write-Host ("✓ {0} ({1:N0} MB)" -f $setup, $size)
}
