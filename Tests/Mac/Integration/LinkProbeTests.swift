import Foundation
import Testing
@testable import KDDownloadManager

/// Link ekle'deki denetim ve Chrome indirmesini devralma kararı, yerel sunucuya karşı.
@Suite("Bağlantı denetimi (yerel sunucu)")
@MainActor
struct LinkProbeTests {
    let server: TestHTTPServer

    init() async throws {
        TestEnvironment.prepare()
        server = try await TestHTTPServer()
    }

    private func file(_ outcome: LinkProbe.Outcome) -> LinkProbe.FileInfo? {
        if case .file(let info) = outcome { return info }
        Issue.record("dosya beklenirken: \(outcome)")
        return nil
    }

    @Test("Parçalı indirmeyi destekleyen sunucu: boyut Content-Range'ten, ad Content-Disposition'dan")
    func resumable() async {
        server.route("/indir", .file(.pattern(size: 123_456), headers: ["Content-Disposition": "attachment; filename=\"Kurulum.dmg\""]))
        let info = file(await LinkProbe.check(server.url("/indir?token=1")))
        #expect(info?.size == 123_456)
        #expect(info?.resumable == true)
        #expect(info?.name == "Kurulum.dmg")
        #expect(server.requests(to: "/indir").first?.headers["range"] == "bytes=0-0")
    }

    @Test("Range desteklemeyen sunucu: boyut Content-Length'ten, ad adresten")
    func notResumable() async {
        var response = TestHTTPServer.Response.file(.pattern(size: 5_000))
        response.acceptsRanges = false
        server.route("/dosyalar/Rapor%202026.pdf", response)
        let info = file(await LinkProbe.check(server.url("/dosyalar/Rapor%202026.pdf")))
        #expect(info?.size == 5_000)
        #expect(info?.resumable == false)
        #expect(info?.name == "Rapor 2026.pdf")
    }

    @Test("404/410 ve 4xx: indirmek anlamsız; 403/5xx: uyarı, yine de denenebilir")
    func statuses() async {
        server.route("/yok", .status(404))
        server.route("/gitti", .status(410))
        server.route("/kotu", .status(400))
        server.route("/yasak", .status(403))
        server.route("/hata", .status(500))
        for path in ["/yok", "/gitti", "/kotu"] {
            guard case .invalid = await LinkProbe.check(server.url(path)) else { Issue.record("\(path) geçersiz sayılmadı"); continue }
        }
        for path in ["/yasak", "/hata"] {
            guard case .warning = await LinkProbe.check(server.url(path)) else { Issue.record("\(path) uyarı olmadı"); continue }
        }
    }

    @Test("Kapalı port: sunucuya bağlanılamadı")
    func refused() async throws {
        let closed = try await TestHTTPServer()
        let link = closed.url("/a.zip")
        closed.stop()
        try await Task.sleep(for: .milliseconds(100))
        guard case .invalid = await LinkProbe.check(link) else { Issue.record("kapalı port geçersiz sayılmadı"); return }
    }

    @Test("Bozuk adres ve FTP")
    func otherSchemes() async {
        guard case .invalid = await LinkProbe.check("bu bir adres değil") else { Issue.record("bozuk adres"); return }
        let ftp = file(await LinkProbe.check("ftp://ftp.example.com/pub/a.iso"))
        #expect(ftp?.name == "a.iso")
        #expect(ftp?.resumable == false)
    }

    @Test("Torrent denetlenmez")
    func torrent() async {
        #expect(file(await LinkProbe.check("magnet:?xt=urn:btih:abc"))?.resumable == true)
    }

    // MARK: - Chrome indirmesini devralma

    @Test("Broadcom: türsüz 'filename=' ile verilen ad alınır; tarayıcının çerezi/referrer'ı/kimliği gönderilir")
    func takeOverBroadcom() async {
        server.route("/", .file(.pattern(size: 64), headers: [
            "Content-Disposition": "filename=VMware-Fusion-26H1u1_universal.dmg",
            "Content-Type": "application/octet-stream",
        ]))
        var request = DownloadRequest(url: server.url("/?file=abc&token=xyz"), referrer: "https://support.broadcom.com/",
                                      userAgent: "TestBrowser/1.0", cookies: "session=1")
        request.fromBrowserDownload = true
        request.mime = "application/x-apple-diskimage"
        guard case .accept(let name) = await LinkProbe.canTakeOver(request) else { Issue.record("reddedildi"); return }
        #expect(name == "VMware-Fusion-26H1u1_universal.dmg")
        let sent = server.requests(to: "/").last?.headers
        #expect(sent?["cookie"] == "session=1")
        #expect(sent?["referer"] == "https://support.broadcom.com/")
        #expect(sent?["user-agent"] == "TestBrowser/1.0")
    }

    @Test("Dosya yerine HTML sayfası dönüyorsa (service worker) Chrome'a bırakılır")
    func takeOverRefusesHTML() async {
        server.route("/sw.pdf", .file(Data("<html>".utf8), headers: ["Content-Type": "text/html; charset=utf-8"]))
        var request = DownloadRequest(url: server.url("/sw.pdf"))
        request.mime = "application/pdf"
        guard case .refuse = await LinkProbe.canTakeOver(request) else { Issue.record("kabul edildi"); return }

        // Chrome da HTML indiriyorsa sorun yok.
        request.mime = "text/html"
        guard case .accept = await LinkProbe.canTakeOver(request) else { Issue.record("HTML indirmesi reddedildi"); return }
    }

    @Test("Yeniden istenemeyen adres (403, 404) ve http olmayanlar")
    func takeOverStatuses() async {
        server.route("/tek-kullanim", .status(403))
        guard case .refuse = await LinkProbe.canTakeOver(DownloadRequest(url: server.url("/tek-kullanim"))) else {
            Issue.record("403 kabul edildi"); return
        }
        // blob:/data: gibi adreslerin adı yok ama karar eklentide; burada kabul.
        guard case .accept(nil) = await LinkProbe.canTakeOver(DownloadRequest(url: "magnet:?xt=urn:btih:1")) else {
            Issue.record("http olmayan"); return
        }
    }
}
