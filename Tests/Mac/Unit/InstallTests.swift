import Foundation
import Testing
@testable import KDDownloadManager

/// Kurulum diski (DMG) ve uygulamanın kendini Uygulamalar'a taşıması.
@Suite("Kurulum")
@MainActor
struct InstallTests {
    @Test("Kurulum diskinin içinden açılınca taşıma önerilir")
    func diskImage() {
        #expect(ApplicationsMover.isOnDiskImage(path: "/Volumes/KD Download Manager/KDDownloadManager.app", volumeIsReadOnly: true))
        #expect(ApplicationsMover.isOnDiskImage(path: "/Volumes/KD Download Manager 1/KDDownloadManager.app/", volumeIsReadOnly: true))
    }

    @Test("Uygulamalar'dan, yazılabilir harici diskten ya da geliştirme klasöründen açılınca önerilmez")
    func notDiskImage() {
        #expect(!ApplicationsMover.isOnDiskImage(path: "/Applications/KDDownloadManager.app", volumeIsReadOnly: false))
        // Salt okunur sistem birimi de /Volumes altında değil.
        #expect(!ApplicationsMover.isOnDiskImage(path: "/Applications/KDDownloadManager.app", volumeIsReadOnly: true))
        #expect(!ApplicationsMover.isOnDiskImage(path: "/Volumes/USB/KDDownloadManager.app", volumeIsReadOnly: false))
        #expect(!ApplicationsMover.isOnDiskImage(path: "/Volumes/KD Download Manager", volumeIsReadOnly: true))
        #expect(!ApplicationsMover.isOnDiskImage(path: "/Users/x/projects/KDDownloadManager/.build/debug/KDDownloadManager",
                                                 volumeIsReadOnly: false))
    }

    @Test("DMG betiği ile arka plan çizimi aynı pencere ve ikon yerlerini kullanıyor")
    func layoutMatches() throws {
        let repo = TestEnvironment.repository
        let script = try String(contentsOf: repo.appendingPathComponent("scripts/make-dmg.sh"), encoding: .utf8)
        let drawing = try String(contentsOf: repo.appendingPathComponent("scripts/render-dmg-background.swift"), encoding: .utf8)
        func value(_ name: String) -> String? {
            script.range(of: "\(name)=([0-9]+)", options: .regularExpression)
                .map { String(script[$0].split(separator: "=")[1]) }
        }
        let (appX, appY) = (try #require(value("APP_X")), try #require(value("APP_Y")))
        let (dirX, dirY) = (try #require(value("APPLICATIONS_X")), try #require(value("APPLICATIONS_Y")))
        let (width, height) = (try #require(value("WIDTH")), try #require(value("HEIGHT")))
        #expect(drawing.contains("static let app = NSPoint(x: \(appX), y: \(appY))"))
        #expect(drawing.contains("static let applications = NSPoint(x: \(dirX), y: \(dirY))"))
        #expect(drawing.contains("NSSize(width: \(width), height: \(height))"))
    }

    @Test("Site Mac'te önce kurulum diskini, yoksa zip'i sunar; yayın betiği diski yükler")
    func siteAndRelease() throws {
        let repo = TestEnvironment.repository
        let site = try String(contentsOf: repo.appendingPathComponent("docs/index.html"), encoding: .utf8)
        #expect(site.contains(#"mac: findAsset(releases, [/^KDDownloadManager-\d[\d.]*\.dmg$/, /^KDDownloadManager-\d[\d.]*\.zip$/])"#))
        let release = try String(contentsOf: repo.appendingPathComponent("scripts/release.sh"), encoding: .utf8)
        #expect(release.contains(#"gh release create "$TAG" "$DMG" "$ASSET" "$ASSET.sig""#))
        // Uygulama içi güncelleme zip + imza ister; disk onun yerine geçmemeli.
        let updater = try String(contentsOf: repo.appendingPathComponent("Sources/KDDownloadManager/Support/AppUpdater.swift"), encoding: .utf8)
        #expect(updater.contains(#"let name = "KDDownloadManager-\(version).zip""#))
    }
}
