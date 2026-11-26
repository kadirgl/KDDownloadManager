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

1. Download `KDDownloadManager-<version>.dmg` from [kddownloadmanager.com](https://kddownloadmanager.com) or the
   [Releases](../../releases/latest) page and open it.
2. In the window that opens, drag **KDDownloadManager** onto the **Applications** folder next to it, then open it
   from Applications. If you open the app straight from the disk image, it offers to move itself to Applications.
   The app and the disk image are signed with an Apple Developer ID and notarized by Apple, so macOS opens them
   without warnings.
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
scripts/make-dmg.sh              # dist/KDDownloadManager.dmg (drag-to-Applications disk image)
scripts/package-app.sh --install # also installs to /Applications and opens it
```

The source strings are Turkish and double as translation keys; the English text lives in
`Sources/KDDownloadManager/Resources/Localizable.xcstrings`. After adding or changing UI text, run
`scripts/strings.sh sync` to update the catalog and list missing translations. The browser extension is in
[ChromeExtension](ChromeExtension); its strings are in `ChromeExtension/_locales/{tr,en}/messages.json`.

### Tests

Tests for the macOS app, the Windows app (its logic layer also runs on macOS) and the Chrome extension live in
[Tests](Tests) ([layout](Tests/README.md)):

```bash
scripts/test.sh                          # everything
scripts/test.sh mac                      # or: windows, extension
git config core.hooksPath scripts/hooks  # once: run the tests before every git push
```

The release scripts refuse to publish when a test fails.

## Windows

A native Windows version lives in [Windows](Windows): WinUI 3 (Windows App SDK 1.8) and .NET 10, self-contained,
for Windows 10 1809+ and Windows 11 on arm64 and x64. It mirrors the macOS app: a notification-area icon with a
compact acrylic panel (clicking the icon again closes it), Active/Completed lists, categories, search, Add link with
link checking, Settings, Windows notifications, segmented downloads and torrents through aria2c, videos through
yt-dlp and ffmpeg, Turkish and English UI, and in-app updates from GitHub Releases signed with the same Ed25519 key.
The browser bridge uses the same port (47615), endpoints and `Origin` check, so the [extension](ChromeExtension)
works unchanged.

**Install:** download and run `KDDownloadManager-Windows-x64-<version>-Setup.exe` (most PCs) or
`KDDownloadManager-Windows-arm64-<version>-Setup.exe` (ARM PCs) from the latest release. It needs no admin rights and
installs for the current user into `%LOCALAPPDATA%\Programs\KD Download Manager`, with a Start menu shortcut (a
desktop one is optional) and an entry in Settings › Apps to uninstall it. The setup is not code-signed, so SmartScreen
may warn ("Windows protected your PC"): click **More info › Run anyway**. Windows Firewall asks about aria2c on the
first torrent (downloads work either way). The same release also has a `.zip` for those who would rather not install;
such a copy is installed in place by its first in-app update.

**Build (on Windows, .NET 10 SDK):** `powershell -ExecutionPolicy Bypass -File Windows\scripts\package.ps1 [-Arch arm64|x64] [-Version 1.9.3]`
→ `Windows\dist\KDDownloadManager-Windows-<arch>-<version>-Setup.exe` and `.zip` (the setup needs Inno Setup 6:
`ISCC.exe` on PATH, in `C:\kd\inno` or its usual folder, or `-Iscc <path>`; script:
[Windows/installer/KDDownloadManager.iss](Windows/installer/KDDownloadManager.iss)). Helper programs are fetched from their official
releases and checksum-verified by `Windows\scripts\bundle-tools.ps1`. English UI strings come from the macOS
`Localizable.xcstrings` plus [Windows/strings.en.json](Windows/strings.en.json); run `python3 Windows/scripts/strings.py`
after changing UI text. From a Mac, `Windows/scripts/vm-sync.sh '<command>'` copies the sources to a Windows VM in VMware Fusion over SSH and
runs the command there (key `~/.ssh/kd_windows_vm`, user name in `~/.config/kd-download-manager/vm`).

**Release:** after `scripts/release.sh 1.9.3`, run `scripts/release-windows.sh 1.9.3`. It signs the Windows setups and zips
with the Keychain key and attaches them (and their `.sig` files) to the same GitHub release; the macOS app ignores them.
The in-app update downloads the setup, checks its signature and runs it silently into the app's own folder; the zips
stay for 1.9.3 and older, whose updater only knows the zip.
