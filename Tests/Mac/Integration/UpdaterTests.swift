import CryptoKit
import Foundation
import Testing
@testable import KDDownloadManager

/// Uygulama güncellemesi: GitHub sürüm bilgisinin okunması ve imza denetimi. GitHub yerine yerel sunucu
/// (KD_UPDATE_API), gerçek anahtar yerine testte üretilen anahtar (KD_UPDATE_KEY) kullanılır; gerçek imza
/// anahtarına hiç dokunulmaz.
@Suite("Uygulama güncellemesi", .serialized)
@MainActor
struct UpdaterTests {
    let server: TestHTTPServer
    let key = Curve25519.Signing.PrivateKey()

    init() async throws {
        TestEnvironment.prepare()
        server = try await TestHTTPServer()
        setenv("KD_UPDATE_API", server.url("/releases/latest"), 1)
        setenv("KD_UPDATE_KEY", key.publicKey.rawRepresentation.base64EncodedString(), 1)
        setenv("KD_UPDATE_TARGET", TestEnvironment.scratch().appendingPathComponent("KDDownloadManager.app").path, 1)
    }

    private func release(tag: String, assets: [String]) -> Data {
        let list = assets.map { name in
            #"{"name":"\#(name)","browser_download_url":"\#(server.url("/dl/" + name))","size":1000}"#
        }.joined(separator: ",")
        return Data(#"{"tag_name":"\#(tag)","body":"  Notlar  ","html_url":"https://github.com/x/y/releases/tag/\#(tag)","assets":[\#(list)]}"#.utf8)
    }

    @Test("Zip'i ve imzası olan daha yeni sürüm bulunur")
    func available() async {
        server.route("/releases/latest", .file(release(tag: "v99.1.0", assets: [
            "KDDownloadManager-99.1.0.zip", "KDDownloadManager-99.1.0.zip.sig", "KDDownloadManager-Windows-x64-99.1.0-Setup.exe",
        ])))
        await AppUpdater.shared.check()
        guard case .available(let release) = AppUpdater.shared.state else {
            Issue.record("sürüm bulunmadı: \(AppUpdater.shared.state)"); return
        }
        #expect(release.version == "99.1.0")
        #expect(release.notes == "Notlar")
        #expect(release.archive.lastPathComponent == "KDDownloadManager-99.1.0.zip")
        #expect(release.signature.lastPathComponent == "KDDownloadManager-99.1.0.zip.sig")
        #expect(release.size == 1000)
    }

    @Test("Mac paketi ya da imzası olmayan sürüm güncelleme sayılmaz (yalnızca Windows'a çıkan sürüm)")
    func ignoresIncompleteReleases() async {
        server.route("/releases/latest", .file(release(tag: "v99.2.0", assets: ["KDDownloadManager-99.2.0.zip"])))
        await AppUpdater.shared.check()
        #expect(AppUpdater.shared.state == .upToDate)

        server.route("/releases/latest", .file(release(tag: "v99.2.0", assets: [
            "KDDownloadManager-Windows-arm64-99.2.0-Setup.exe", "KDDownloadManager-Windows-arm64-99.2.0-Setup.exe.sig",
        ])))
        await AppUpdater.shared.check()
        #expect(AppUpdater.shared.state == .upToDate)
    }

    @Test("Hiç sürüm yoksa (404) güncel; anlaşılmayan etiket hata")
    func odd() async {
        server.route("/releases/latest", .status(404))
        await AppUpdater.shared.check()
        #expect(AppUpdater.shared.state == .upToDate)

        server.route("/releases/latest", .file(release(tag: "nightly", assets: [])))
        await AppUpdater.shared.check()
        #expect(AppUpdater.shared.state == .failed("Sürüm numarası anlaşılamadı: nightly"))

        server.route("/releases/latest", .status(500))
        await AppUpdater.shared.check(quietly: true)
        #expect(AppUpdater.shared.state == .idle)
    }

    @Test("İmzası tutmayan paket kurulmaz")
    func rejectsBadSignature() async {
        let archive = Data.pattern(size: 50_000)
        let tampered = archive + Data([0])
        let signature = try! key.signature(for: archive).base64EncodedString()
        server.route("/releases/latest", .file(release(tag: "v99.3.0", assets: [
            "KDDownloadManager-99.3.0.zip", "KDDownloadManager-99.3.0.zip.sig",
        ])))
        server.route("/dl/KDDownloadManager-99.3.0.zip", .file(tampered))
        server.route("/dl/KDDownloadManager-99.3.0.zip.sig", .file(Data(signature.utf8)))
        await AppUpdater.shared.check()
        AppUpdater.shared.install()
        #expect(await TestEnvironment.wait(timeout: 20) {
            if case .failed = AppUpdater.shared.state { true } else { false }
        })
        #expect(AppUpdater.shared.state == .failed("Güncellemenin imzası doğrulanamadı; kurulmadı"))
    }

    @Test("Başka bir anahtarla imzalanmış paket de kurulmaz")
    func rejectsForeignKey() async {
        let archive = Data.pattern(size: 10_000)
        let signature = try! Curve25519.Signing.PrivateKey().signature(for: archive).base64EncodedString()
        server.route("/releases/latest", .file(release(tag: "v99.4.0", assets: [
            "KDDownloadManager-99.4.0.zip", "KDDownloadManager-99.4.0.zip.sig",
        ])))
        server.route("/dl/KDDownloadManager-99.4.0.zip", .file(archive))
        server.route("/dl/KDDownloadManager-99.4.0.zip.sig", .file(Data(signature.utf8)))
        await AppUpdater.shared.check()
        AppUpdater.shared.install()
        #expect(await TestEnvironment.wait(timeout: 20) {
            if case .failed = AppUpdater.shared.state { true } else { false }
        })
        #expect(AppUpdater.shared.state == .failed("Güncellemenin imzası doğrulanamadı; kurulmadı"))
    }
}
