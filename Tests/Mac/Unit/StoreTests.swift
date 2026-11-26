import Foundation
import Testing
@testable import KDDownloadManager

/// Listenin davranışı: ekleme, adlandırma, tekrarlar, duraklatma, silme/geri alma, filtreler.
/// Motor sahte (RecordingEngine); ağ yok.
@Suite("İndirme listesi")
@MainActor
struct StoreTests {
    let engine = RecordingEngine()
    let store: DownloadStore

    init() {
        TestEnvironment.prepare()
        store = DownloadStore(engine: engine)
    }

    @Test("Birden çok satır ayrı indirme olur; en yeni başta, link olmayanlar atlanır")
    func addLinks() {
        store.add(links: "https://a.example/1.zip\nmerhaba\nhttps://a.example/2.pdf")
        #expect(store.items.map(\.fileName) == ["2.pdf", "1.zip"])
        #expect(engine.count { if case .start = $0 { true } else { false } } == 2)
        #expect(store.tab == .active)
    }

    @Test("Link ekle'deki 'Ad' tek linkte kullanılır ve temizlenir")
    func saveAs() {
        store.add(links: "https://a.example/x", saveAs: "Yeni/Ad.pdf")
        #expect(store.items[0].fileName == "Yeni-Ad.pdf")
        #expect(store.items[0].preferredName == "Yeni-Ad.pdf")
        // İki linkte ad yok sayılır.
        store.add(links: "https://a.example/1\nhttps://a.example/2", saveAs: "Tek.pdf")
        #expect(!store.items.contains { $0.fileName == "Tek.pdf" && $0.url.hasSuffix("/1") })
    }

    @Test("Tarayıcının verdiği ad aria2'ye de verilir (Broadcom 'index.html' hatası)")
    func browserName() {
        var request = DownloadRequest(url: "https://download.example.com/?file=abc123", filename: "VMware-Fusion.dmg")
        request.fromBrowserDownload = true
        store.add([request])
        let item = store.items[0]
        #expect(item.fileName == "VMware-Fusion.dmg")
        #expect(item.preferredName == "VMware-Fusion.dmg")
        #expect(item.category == .app)
    }

    @Test("Videoda tarayıcının adı aria2 adı olmaz (yt-dlp kendi adını verir)")
    func videoNameNotForced() {
        store.add([DownloadRequest(url: "https://www.youtube.com/watch?v=1", filename: "watch")])
        #expect(store.items[0].preferredName == nil)
    }

    @Test("Aynı istek 10 sn içinde ikinci kez gelirse eklenmez")
    func duplicateRequest() {
        let request = DownloadRequest(url: "https://a.example/tekrar.zip")
        store.add([request])
        store.add([request])
        #expect(store.items.count == 1)
        // Farklı kalite ayrı bir istektir.
        store.add([DownloadRequest(url: "https://www.youtube.com/watch?v=1", quality: .p720),
                   DownloadRequest(url: "https://www.youtube.com/watch?v=1", quality: .audio)])
        #expect(store.items.count == 3)
    }

    @Test("Aynı klasörde aynı adlı ikinci dosya '(1)' alır")
    func uniqueNames() {
        store.add(links: "https://a.example/rapor.pdf")
        store.add(links: "https://b.example/rapor.pdf")
        store.add(links: "https://c.example/RAPOR.pdf")
        // Büyük/küçük harf farkı aynı dosya demek (APFS, NTFS): üçüncüsü "(2)" almalı.
        #expect(store.items.map(\.fileName) == ["RAPOR (2).pdf", "rapor (1).pdf", "rapor.pdf"])
        #expect(store.items[0].preferredName == "RAPOR (2).pdf")
    }

    @Test("Diskteki dosyanın adı da dolu sayılır")
    func freshNameChecksDisk() {
        let folder = TestEnvironment.scratch()
        FileManager.default.createFile(atPath: folder.appendingPathComponent("a (1).zip").path, contents: Data())
        #expect(store.freshName(for: "a.zip", in: folder) == "a (2).zip")
        #expect(store.freshName(for: "video", in: folder, keepExtension: false) == "video (1)")
        #expect(store.freshName(for: "film.mp4", in: folder, keepExtension: false) == "film (1)")
    }

    @Test("'Hemen başlat' kapalıyken duraklatılmış eklenir, motora gitmez")
    func startPaused() {
        store.add(links: "https://a.example/bekle.zip", startPaused: true)
        #expect(store.items[0].status == .paused)
        #expect(engine.calls.allSatisfy { if case .start = $0 { false } else { true } })
    }

    @Test("Hız sınırı motora iletilir")
    func speedLimit() {
        store.add(links: "https://a.example/s.zip", speedLimit: 512_000)
        let item = store.items[0]
        #expect(item.speedLimit == 512_000)
        store.setSpeedLimit(nil, for: item)
        #expect(engine.calls.last == .speedLimit(item.id, nil))
    }

    @Test("Duraklat / devam / hepsini duraklat / hatalıları yeniden dene")
    func pauseResume() {
        store.add(links: "https://a.example/1.zip\nhttps://a.example/2.zip")
        let first = store.items[0]
        store.togglePause(first)
        #expect(first.status == .paused)
        store.togglePause(first)
        #expect(first.status == .downloading)

        store.pauseAll()
        #expect(store.items.allSatisfy { $0.status == .paused })
        #expect(store.allActivePaused)
        store.resumeAll()
        #expect(store.items.allSatisfy { $0.status == .downloading })

        store.items[1].setStatus(.failed("x"))
        #expect(store.hasFailures)
        store.retryFailed()
        #expect(!store.hasFailures)

        // Tamamlanan duraklatılmaz.
        first.setStatus(.completed)
        let before = engine.calls.count
        store.togglePause(first)
        #expect(engine.calls.count == before)
    }

    @Test("Sil → geri al: aynı yerine döner, inen indirme devam eder")
    func deleteUndo() {
        store.add(links: "https://a.example/1.zip\nhttps://a.example/2.zip\nhttps://a.example/3.zip")
        let middle = store.items[1]
        store.delete(middle)
        #expect(!store.items.contains { $0.id == middle.id })
        #expect(store.pendingDeletion?.item.id == middle.id)
        #expect(engine.calls.contains(.pause(middle.id)))

        store.undoDelete()
        #expect(store.items[1].id == middle.id)
        #expect(store.pendingDeletion == nil)
        #expect(engine.calls.last == .resume(middle.id))
        #expect(store.selection == middle.id)
    }

    @Test("Yeni bir silme öncekini hemen uygular (motordan da kalkar)")
    func deleteCommits() {
        store.add(links: "https://a.example/1.zip\nhttps://a.example/2.zip")
        let (a, b) = (store.items[0], store.items[1])
        store.delete(a)
        store.delete(b)
        #expect(engine.calls.contains(.cancel(a.id)))
        #expect(store.pendingDeletion?.item.id == b.id)
        store.commitPendingDeletion()
        #expect(store.items.isEmpty)
        #expect(engine.calls.contains(.cancel(b.id)))
    }

    @Test("Tamamlananı silmek dosyayı çöpe taşır")
    func deleteCompletedTrashes() throws {
        let folder = TestEnvironment.scratch()
        let file = folder.appendingPathComponent("bitti.txt")
        FileManager.default.createFile(atPath: file.path, contents: Data("x".utf8))
        store.add(links: "https://a.example/bitti.txt")
        let item = store.items[0]
        item.setStatus(.completed)
        item.destination = file
        store.delete(item)
        #expect(FileManager.default.fileExists(atPath: file.path))
        store.commitPendingDeletion()
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test("Tamamlananları temizle: listeden kalkar, dosyalar kalır")
    func clearCompleted() {
        store.add(links: "https://a.example/1.zip\nhttps://a.example/2.zip")
        store.items[0].setStatus(.completed)
        store.clearCompleted()
        #expect(store.items.count == 1)
        #expect(store.items[0].status != .completed)
    }

    @Test("Görünen liste: sekme, kategori, arama ve sıralama")
    func visibleItems() {
        store.add(links: "https://a.example/b-film.mp4\nhttps://cdn.site.example/a-rapor.pdf\nhttps://a.example/c-sarki.mp3\nhttps://a.example/inen.zip")
        let byName = Dictionary(uniqueKeysWithValues: store.items.map { ($0.fileName, $0) })
        for (name, size, day) in [("b-film.mp4", 300, 1.0), ("a-rapor.pdf", 100, 3.0), ("c-sarki.mp3", 200, 2.0)] {
            let item = byName[name]!
            item.setStatus(.completed)
            item.totalBytes = Int64(size)
            item.completedAt = Date(timeIntervalSince1970: day * 86_400)
        }
        store.tab = .active
        #expect(store.visibleItems.map(\.fileName) == ["inen.zip"])

        store.tab = .completed
        store.completedSort = .newest
        #expect(store.visibleItems.map(\.fileName) == ["a-rapor.pdf", "c-sarki.mp3", "b-film.mp4"])
        store.completedSort = .name
        #expect(store.visibleItems.map(\.fileName) == ["a-rapor.pdf", "b-film.mp4", "c-sarki.mp3"])
        store.completedSort = .size
        #expect(store.visibleItems.map(\.fileName) == ["b-film.mp4", "c-sarki.mp3", "a-rapor.pdf"])

        store.category = .music
        #expect(store.visibleItems.map(\.fileName) == ["c-sarki.mp3"])
        store.category = .all
        store.searchText = "site.example"
        #expect(store.visibleItems.map(\.fileName) == ["a-rapor.pdf"])
        store.searchText = "film"
        #expect(store.visibleItems.map(\.fileName) == ["b-film.mp4"])
    }

    @Test("Aynı adresten önceki indirme bulunur")
    func existing() {
        store.add(links: "https://a.example/var.zip")
        #expect(store.existingItem(for: "  https://a.example/var.zip ") != nil)
        #expect(store.existingItem(for: "https://a.example/yok.zip") == nil)
    }

    @Test("Dosya yerine inen HTML sayfası (giriş/hata sayfası) yakalanır")
    func webPageInsteadOfFile() {
        let folder = TestEnvironment.scratch()
        func item(_ name: String, _ content: String) -> DownloadItem {
            let file = folder.appendingPathComponent(name)
            FileManager.default.createFile(atPath: file.path, contents: Data(content.utf8))
            let item = DownloadItem(url: "https://a.example/\(name)", folder: folder, status: .completed)
            item.destination = file
            return item
        }
        #expect(DownloadStore.webPageInsteadOfFile(item("setup.zip", "  <!DOCTYPE html><html>Giriş yapın")) != nil)
        #expect(DownloadStore.webPageInsteadOfFile(item("rapor.pdf", "<html><body>404")) != nil)
        #expect(DownloadStore.webPageInsteadOfFile(item("gercek.zip", "PK\u{3}\u{4}...")) == nil)
        // Zaten sayfa olan adlara ve uzantısızlara dokunulmaz.
        #expect(DownloadStore.webPageInsteadOfFile(item("sayfa.html", "<html>")) == nil)
        #expect(DownloadStore.webPageInsteadOfFile(item("adsız", "<html>")) == nil)
        #expect(DownloadStore.webPageInsteadOfFile(item("bos.zip", "")) == nil)
    }

    @Test("Kayıtlı liste açılışta yüklenir ve sıradakiler devam eder")
    func loadsArchive() {
        let archive = DownloadArchive(url: TestEnvironment.scratch().appendingPathComponent("downloads.json"))
        let queued = DownloadItem(url: "https://a.example/devam.zip", status: .downloading)
        let paused = DownloadItem(url: "https://a.example/bekle.zip", status: .paused)
        let done = DownloadItem(url: "https://a.example/bitti.zip", status: .completed)
        archive.write(archive.encode([queued, paused, done]))

        let engine = RecordingEngine()
        let store = DownloadStore(engine: engine, archive: archive)
        #expect(store.items.count == 3)
        #expect(engine.calls.contains(.start(queued.id)))
        #expect(!engine.calls.contains(.start(paused.id)))
        #expect(!engine.calls.contains(.start(done.id)))

        // Değişiklik diske yazılır.
        store.cancel(store.items[0])
        #expect(archive.load().count == 2)
    }
}
