import Foundation
import Testing
@testable import KDDownloadManager

/// Gerçek aria2c ile uçtan uca indirme: liste → motor → disk. aria2c yoksa (brew install aria2) atlanır.
@Suite("aria2 ile gerçek indirme (yerel sunucu)", .enabled(if: Executables.find("aria2c") != nil, "aria2c bulunamadı"),
       .timeLimit(.minutes(2)))
@MainActor
struct Aria2DownloadTests {
    let server: TestHTTPServer
    let store: DownloadStore
    let folder: URL

    init() async throws {
        TestEnvironment.prepare()
        server = try await TestHTTPServer()
        store = DownloadStore(engine: Aria2Engine())
        folder = SettingsKey.downloadFolderURL
    }

    private func finished(_ item: DownloadItem, within seconds: Double = 30) async -> Bool {
        await TestEnvironment.wait(timeout: seconds) { item.status == .completed || item.isFailed }
    }

    @Test("Broadcom senaryosu: adres '/?file=…', ad yalnızca Content-Disposition'da → dosya doğru adla ve bozulmadan iner")
    func broadcomName() async throws {
        let name = "VMware-Fusion-\(UUID().uuidString.prefix(6)).dmg"
        let content = Data.pattern(size: 2_500_000)
        server.route("/", .file(content, headers: ["Content-Disposition": "filename=\(name)"]))
        // Köprü, devralırken sunucunun verdiği adı isteğe yazıyor (LinkProbeTests.takeOverBroadcom).
        store.add([DownloadRequest(url: server.url("/?file=\(UUID().uuidString)"), filename: name)])
        let item = try #require(store.items.first)

        #expect(await finished(item))
        #expect(item.status == .completed)
        let file = folder.appendingPathComponent(name)
        #expect(item.destination?.lastPathComponent == name)
        #expect(try Data(contentsOf: file) == content)
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("index.html").path))
    }

    @Test("Büyük dosya birkaç bağlantıyla parça parça iner, içerik birebir aynı")
    func multiConnection() async throws {
        let name = "buyuk-\(UUID().uuidString.prefix(6)).bin"
        let content = Data.pattern(size: 12_000_000, seed: 3)
        server.route("/\(name)", .file(content))
        store.add(links: server.url("/\(name)"))
        let item = try #require(store.items.first)

        #expect(await finished(item, within: 60))
        #expect(item.status == .completed)
        #expect(item.totalBytes == 12_000_000)
        #expect(try Data(contentsOf: folder.appendingPathComponent(name)) == content)
        // Range ile birden çok istek geldi.
        #expect(server.requests(to: "/\(name)").filter { $0.headers["range"] != nil }.count > 1)
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent(name + ".aria2").path))
    }

    @Test("Sunucuda olmayan dosya: anlaşılır hata")
    func notFound() async throws {
        store.add(links: server.url("/olmayan-\(UUID().uuidString).zip"))
        let item = try #require(store.items.first)
        #expect(await finished(item))
        #expect(item.status == .failed("Dosya sunucuda bulunamadı (404)"))
    }

    @Test("Duraklat → ilerleme durur → devam → tamamlanır")
    func pauseResume() async throws {
        let name = "yavas-\(UUID().uuidString.prefix(6)).bin"
        let content = Data.pattern(size: 1_500_000, seed: 9)
        server.route("/\(name)", .file(content, chunkDelay: 0.03))
        store.add(links: server.url("/\(name)"))
        let item = try #require(store.items.first)

        #expect(await TestEnvironment.wait(timeout: 15) { item.downloadedBytes > 0 })
        store.togglePause(item)
        #expect(item.status == .paused)
        try await Task.sleep(for: .seconds(1.5))
        let frozen = item.downloadedBytes
        try await Task.sleep(for: .seconds(1.5))
        #expect(item.downloadedBytes == frozen)
        #expect(item.status == .paused)

        store.togglePause(item)
        #expect(await finished(item, within: 60))
        #expect(item.status == .completed)
        #expect(try Data(contentsOf: folder.appendingPathComponent(name)) == content)
    }

    @Test("İptal: yarım dosya ve kontrol dosyası silinir")
    func cancelRemovesPartial() async throws {
        let name = "iptal-\(UUID().uuidString.prefix(6)).bin"
        server.route("/\(name)", .file(.pattern(size: 3_000_000), chunkDelay: 0.05))
        store.add(links: server.url("/\(name)"))
        let item = try #require(store.items.first)
        #expect(await TestEnvironment.wait(timeout: 15) { item.downloadedBytes > 0 })

        store.cancel(item)
        #expect(store.items.isEmpty)
        let gone = await TestEnvironment.wait(timeout: 10) {
            !FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path)
                && !FileManager.default.fileExists(atPath: folder.appendingPathComponent(name + ".aria2").path)
        }
        #expect(gone)
    }

    @Test("Uzantısız inen dosyaya türüne göre uzantı eklenir")
    func addsMissingExtension() async throws {
        let name = "galata-\(UUID().uuidString.prefix(6))"
        var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        png.append(.pattern(size: 4_000))
        server.route("/\(name)", .file(png))
        store.add(links: server.url("/\(name)"))
        let item = try #require(store.items.first)
        #expect(await finished(item))
        #expect(await TestEnvironment.wait(timeout: 5) { item.fileName == name + ".png" })
        #expect(item.category == .image)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(name + ".png").path))
    }

    @Test("Dosya yerine HTML hata sayfası inerse başarısız sayılır")
    func htmlInsteadOfFile() async throws {
        let name = "giris-\(UUID().uuidString.prefix(6)).zip"
        server.route("/\(name)", .file(Data("<!DOCTYPE html><html><body>Giriş yapın</body></html>".utf8),
                                       headers: ["Content-Type": "text/html"]))
        store.add(links: server.url("/\(name)"))
        let item = try #require(store.items.first)
        #expect(await TestEnvironment.wait(timeout: 30) { item.isFailed })
    }
}
