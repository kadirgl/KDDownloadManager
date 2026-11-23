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
bad signature is never installed. Running downloads resume when the app reopens, and the browser extension
updates itself too. The video downloader (yt-dlp) is kept up to date from its own official releases.

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
