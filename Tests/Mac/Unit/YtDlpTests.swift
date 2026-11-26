import Foundation
import Testing
@testable import KDDownloadManager

/// yt-dlp yalnızca uygulamayla güncellenir; uygulama içinden indirilmez.
@Suite("yt-dlp")
@MainActor
struct YtDlpTests {
    @Test("Eski sürümlerin indirdiği yt-dlp kopyaları silinir, diğer dosyalara dokunulmaz")
    func removesDownloadedCopies() throws {
        TestEnvironment.prepare()
        let tools = AppFolders.support.appendingPathComponent("Tools", isDirectory: true)
        let manager = FileManager.default
        try manager.createDirectory(at: tools.appendingPathComponent("yt-dlp-2026.11.23/_internal"), withIntermediateDirectories: true)
        manager.createFile(atPath: tools.appendingPathComponent("yt-dlp-2026.11.23/yt-dlp_macos").path, contents: Data("x".utf8))
        manager.createFile(atPath: tools.appendingPathComponent("yt-dlp.version").path, contents: Data("2026.11.23".utf8))
        let other = AppFolders.support.appendingPathComponent("downloads-test.json")
        manager.createFile(atPath: other.path, contents: Data("[]".utf8))

        YtDlp.removeDownloadedCopies()
        #expect(!manager.fileExists(atPath: tools.path))
        #expect(manager.fileExists(atPath: other.path))
        // Klasör yokken de sorun çıkmaz.
        YtDlp.removeDownloadedCopies()
    }

    @Test("Kalite listesi JS bilmecesini çözmeden alınır (hız); indirme çözmeye devam eder")
    func listingSkipsJavaScript() {
        #expect(VideoFormats.listingArguments == ["--no-js-runtimes", "--extractor-args", "youtube:player_skip=js"])
    }

    @Test("Mac ve Windows paketleri aynı yt-dlp sürümünü kullanıyor")
    func sameBundledVersion() throws {
        let repo = TestEnvironment.repository
        let mac = try String(contentsOf: repo.appendingPathComponent("scripts/bundle-tools.sh"), encoding: .utf8)
        let windows = try String(contentsOf: repo.appendingPathComponent("Windows/scripts/bundle-tools.ps1"), encoding: .utf8)
        let macVersion = try #require(mac.firstMatch(of: /YTDLP_VERSION="\$\{YTDLP_VERSION:-([0-9.]+)\}"/)?.1)
        let windowsVersion = try #require(windows.firstMatch(of: /else \{ '([0-9.]+)' \}/)?.1)
        #expect(macVersion == windowsVersion)
    }

    @Test("Ayarlarda yt-dlp güncelleme bölümü yok")
    func noUpdaterInSettings() throws {
        let repo = TestEnvironment.repository
        let mac = try String(contentsOf: repo.appendingPathComponent("Sources/KDDownloadManager/Views/SettingsView.swift"), encoding: .utf8)
        let windows = try String(contentsOf: repo.appendingPathComponent("Windows/KDDownloadManager/Views/SettingsPage.cs"), encoding: .utf8)
        #expect(!mac.contains("YtDlpSettings"))
        #expect(!windows.contains("Video indirici (yt-dlp)"))
        #expect(!FileManager.default.fileExists(atPath: repo.appendingPathComponent("Windows/KDDownloadManager/Support/YtDlpUpdater.cs").path))
    }
}
