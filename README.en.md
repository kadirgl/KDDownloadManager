# KD Download Manager

*[Türkçe](README.md)*

A fast, simple download manager that lives in the macOS menu bar. It downloads files over multiple
connections (aria2), saves videos from YouTube and ~1,800 other sites in the quality you pick (yt-dlp +
ffmpeg), and opens torrents and magnet links. Its extension for Chromium-based browsers (Chrome, Edge,
Brave, Arc, Vivaldi, Opera) sends browser downloads and videos straight to the app.

- Segmented (multi-connection) downloads, pause/resume, picks up where it left off after a restart
- Video quality choice (up to 4K, with estimated sizes) and audio only (MP3)
- Torrents and magnet links
- Overall and per-download speed limits, maximum simultaneous downloads
- Categories, search, notifications, light/dark theme and accent color
- English and Turkish interface (follows the system language; change it in **Settings › Appearance › Language**)
- Automatic in-app updates

## Installation

1. Download `KDDownloadManager-<version>.zip` from the [Releases](../../releases/latest) page and unzip it.
2. Move **KDDownloadManager.app** to the **Applications** folder and open it. The app is signed with an
   Apple Developer ID and notarized by Apple, so macOS opens it without warnings.
3. On first launch the app walks you through installing the browser extension.

Requirements: Apple Silicon (M1 or later), macOS 14 Sonoma or later. aria2, yt-dlp, ffmpeg and QuickJS
ship inside the app; Homebrew isn't needed.

## Updates

Once a day the app checks GitHub for the latest release. When there is a new version it sends a
notification and shows a banner above the list; install it with **Settings › App update › Update and
restart**. The downloaded package is verified with an Ed25519 signature before installing; a package with a
bad signature is never installed. Running downloads resume when the app reopens. The browser keeps the
extension installed from the Chrome Web Store up to date; a copy loaded in developer mode is refreshed with the app. The video downloader (yt-dlp) is kept up to date from its own official releases.

## Building from source

```bash
swift build                      # development build (.build/debug/KDDownloadManager)
scripts/package-app.sh           # dist/KDDownloadManager.app + .zip
scripts/package-app.sh --install # also installs to /Applications and opens it
```

The source strings are Turkish and double as translation keys; the English text lives in
`Sources/KDDownloadManager/Resources/Localizable.xcstrings`. After adding or changing UI text, run
`scripts/strings.sh sync` to update the catalog and list missing translations. The browser extension is in
[ChromeExtension](ChromeExtension); its strings are in `ChromeExtension/_locales/{tr,en}/messages.json`.

## Windows

A native Windows version lives in [Windows](Windows): WinUI 3 (Windows App SDK 1.8) and .NET 10, self-contained,
for Windows 10 1809+ and Windows 11 on arm64 and x64. It mirrors the macOS app: a notification-area icon with a
compact acrylic panel (clicking the icon again closes it), Active/Completed lists, categories, search, Add link with
link checking, Settings, Windows notifications, segmented downloads and torrents through aria2c, videos through
yt-dlp and ffmpeg, Turkish and English UI, and in-app updates from GitHub Releases signed with the same Ed25519 key.
The browser bridge uses the same port (47615), endpoints and `Origin` check, so the [extension](ChromeExtension)
works unchanged.

**Install:** unzip `KDDownloadManager-Windows-<arm64|x64>-<version>.zip`, move the `KDDownloadManager` folder to e.g.
`%LOCALAPPDATA%\Programs` and run `KDDownloadManager.exe`. The app is not code-signed, so SmartScreen may warn on the
first launch, and Windows Firewall asks about aria2c on the first torrent (downloads work either way).

**Build (on Windows, .NET 10 SDK):** `powershell -ExecutionPolicy Bypass -File Windows\scripts\package.ps1 [-Arch arm64|x64] [-Version 1.9.3]`
→ `Windows\dist\KDDownloadManager-Windows-<arch>-<version>.zip`. Helper programs are fetched from their official
releases and checksum-verified by `Windows\scripts\bundle-tools.ps1`. English UI strings come from the macOS
`Localizable.xcstrings` plus [Windows/strings.en.json](Windows/strings.en.json); run `python3 Windows/scripts/strings.py`
after changing UI text. From a Mac, `Windows/scripts/utm-sync.sh '<command>'` builds inside a UTM Windows VM.

**Release:** after `scripts/release.sh 1.9.3`, run `scripts/release-windows.sh 1.9.3`. It signs the Windows zips with
the Keychain key and attaches them (and their `.sig` files) to the same GitHub release; the macOS app ignores them.
