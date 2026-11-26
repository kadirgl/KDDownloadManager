import Foundation
import Testing
@testable import KDDownloadManager

@Suite("Dosya imzası")
@MainActor
struct FileTypeTests {
    private func sniff(_ bytes: [UInt8]) -> String? {
        let file = TestEnvironment.scratch().appendingPathComponent("adsız")
        FileManager.default.createFile(atPath: file.path, contents: Data(bytes) + Data(count: 32))
        return FileType.sniffExtension(of: file)
    }

    private func ascii(_ text: String, at offset: Int = 0) -> [UInt8] { [UInt8](repeating: 0, count: offset) + Array(text.utf8) }

    @Test("Bilinen imzalar")
    func signatures() {
        #expect(sniff([0xFF, 0xD8, 0xFF, 0xE0]) == "jpg")
        #expect(sniff([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]) == "png")
        #expect(sniff(ascii("GIF89a")) == "gif")
        #expect(sniff(ascii("RIFF") + [0, 0, 0, 0] + ascii("WEBP")) == "webp")
        #expect(sniff(ascii("RIFF") + [0, 0, 0, 0] + ascii("WAVE")) == "wav")
        #expect(sniff([0, 0, 0, 0x18] + ascii("ftypisom")) == "mp4")
        #expect(sniff([0, 0, 0, 0x18] + ascii("ftypqt  ")) == "mov")
        #expect(sniff([0, 0, 0, 0x18] + ascii("ftypheic")) == "heic")
        #expect(sniff([0, 0, 0, 0x18] + ascii("ftypM4A ")) == "m4a")
        #expect(sniff(ascii("%PDF-1.7")) == "pdf")
        #expect(sniff([0x50, 0x4B, 0x03, 0x04]) == "zip")
        #expect(sniff(ascii("Rar!")) == "rar")
        #expect(sniff([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]) == "7z")
        #expect(sniff([0x1F, 0x8B, 0x08, 0x00]) == "gz")
        #expect(sniff(ascii("ID3")) == "mp3")
        #expect(sniff(ascii("fLaC")) == "flac")
        #expect(sniff(ascii("OggS")) == "ogg")
        #expect(sniff(ascii("<svg xmlns")) == "svg")
        #expect(sniff(ascii("<?xml version=\"1.0\"?><svg>")) == "svg")
    }

    @Test("Tanınmayan, kısa ya da olmayan dosya")
    func unknown() {
        #expect(sniff(ascii("merhaba dünya")) == nil)
        let tiny = TestEnvironment.scratch().appendingPathComponent("kısa")
        FileManager.default.createFile(atPath: tiny.path, contents: Data([1, 2]))
        #expect(FileType.sniffExtension(of: tiny) == nil)
        #expect(FileType.sniffExtension(of: URL(fileURLWithPath: "/yok/böyle/bir/dosya")) == nil)
    }
}

@Suite("Çerezler")
@MainActor
struct CookieTests {
    @Test("Site adı: www atılır, video sitelerinde ana alan adı")
    func site() {
        #expect(CookieVault.site(of: "https://www.youtube.com/watch?v=1") == "youtube.com")
        #expect(CookieVault.site(of: "https://m.youtube.com/watch?v=1") == "youtube.com")
        #expect(CookieVault.site(of: "https://youtu.be/x") == "youtube.com")
        #expect(CookieVault.site(of: "https://WWW.Example.com/a") == "example.com")
        #expect(CookieVault.site(of: "https://cdn.example.com/a") == "cdn.example.com")
        #expect(CookieVault.site(of: "bozuk") == nil)
    }

    @Test("Netscape dosyası: biçim, yalnızca sahibin okuyabildiği izin, bozuk değerler atlanır")
    func netscapeFile() throws {
        let file = TestEnvironment.scratch().appendingPathComponent("a/cookies.txt")
        try CookieVault.writeNetscapeFile([
            BrowserCookie(domain: ".youtube.com", path: "/", name: "SID", value: "abc", secure: true,
                          httpOnly: true, hostOnly: false, expirationDate: 1_900_000_000.7),
            BrowserCookie(domain: "www.youtube.com", path: "/", name: "PREF", value: "x", secure: false,
                          httpOnly: false, hostOnly: true, expirationDate: nil),
            BrowserCookie(domain: ".youtube.com", path: "/", name: "BAD", value: "a\tb", secure: false),
        ], to: file)
        let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n").map(String.init)
        #expect(lines == [
            "# Netscape HTTP Cookie File",
            "#HttpOnly_.youtube.com\tTRUE\t/\tTRUE\t1900000000\tSID\tabc",
            "www.youtube.com\tFALSE\t/\tFALSE\t0\tPREF\tx",
        ])
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
    }

    @Test("Saklanan çerez site adına göre geri gelir")
    func vault() {
        let vault = CookieVault.shared
        let cookie = BrowserCookie(domain: ".vimeo.com", path: "/", name: "n", value: "v", secure: true)
        vault.store([cookie], for: "vimeo.com")
        #expect(vault.cookies(for: "https://player.vimeo.com/video/1") == [cookie])
        #expect(vault.cookies(for: "https://example.org/") == nil)
    }
}

@Suite("Liste kaydı")
@MainActor
struct ArchiveTests {
    init() { TestEnvironment.prepare() }

    private func archive() -> DownloadArchive {
        DownloadArchive(url: TestEnvironment.scratch().appendingPathComponent("downloads.json"))
    }

    @Test("Kaydedip geri yükleme: durumlar, ayarlar ve adlar korunur; çerezler yazılmaz")
    func roundTrip() throws {
        let archive = archive()
        let folder = TestEnvironment.scratch()
        let active = DownloadItem(url: "https://a.example/big.iso", folder: folder, totalBytes: 100, downloadedBytes: 40,
                                  status: .downloading)
        active.speedLimit = 1_048_576
        active.referrer = "https://a.example/"
        active.userAgent = "Mozilla/5.0"
        active.cookies = "session=GİZLİ"
        active.preferredName = "big.iso"
        let paused = DownloadItem(url: "https://a.example/p.zip", folder: folder, status: .paused)
        let failed = DownloadItem(url: "https://a.example/f.zip", folder: folder, status: .failed("Sunucu hatası (503)"))
        let done = DownloadItem(url: "https://a.example/d.pdf", folder: folder, status: .completed)
        done.destination = folder.appendingPathComponent("d.pdf")
        done.completedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let video = DownloadItem(url: "https://www.youtube.com/watch?v=1", status: .processing)
        video.quality = .audio
        let pageVideo = DownloadItem(url: "https://news.example/sayfa", status: .queued, forceVideo: true)

        let data = archive.encode([active, paused, failed, done, video, pageVideo])
        #expect(!String(decoding: data, as: UTF8.self).contains("GİZLİ"))
        archive.write(data)

        let loaded = archive.load()
        #expect(loaded.map(\.id) == [active, paused, failed, done, video, pageVideo].map(\.id))
        // İnmekte/işlenmekte olanlar açılışta sıraya girer.
        #expect(loaded.map(\.status) == [.queued, .paused, .failed("Sunucu hatası (503)"), .completed, .queued, .queued])
        #expect(loaded[0].speedLimit == 1_048_576)
        #expect(loaded[0].referrer == "https://a.example/")
        #expect(loaded[0].userAgent == "Mozilla/5.0")
        #expect(loaded[0].cookies == nil)
        #expect(loaded[0].preferredName == "big.iso")
        #expect(loaded[0].downloadedBytes == 40 && loaded[0].totalBytes == 100)
        #expect(loaded[0].folder.standardizedFileURL == folder.standardizedFileURL)
        #expect(loaded[3].destination?.lastPathComponent == "d.pdf")
        #expect(loaded[3].completedAt == done.completedAt)
        #expect(loaded[4].quality == .audio && loaded[4].category == .music)
        #expect(loaded[5].source == .video)
        // Aynı liste aynı veriyi üretir (gereksiz yazma olmaz).
        #expect(archive.encode(loaded) == archive.encode(loaded))
    }

    @Test("Okunamayan kayıt atlanır, dosyanın yedeği alınır")
    func lossy() throws {
        let archive = archive()
        let good = DownloadItem(url: "https://a.example/ok.zip", status: .completed)
        var records = try JSONSerialization.jsonObject(with: archive.encode([good])) as! [[String: Any]]
        records.append(["id": "bozuk", "state": "uçuyor"])
        archive.write(try JSONSerialization.data(withJSONObject: records))

        let loaded = archive.load()
        #expect(loaded.map(\.url) == ["https://a.example/ok.zip"])
        let backups = try FileManager.default.contentsOfDirectory(atPath: archive.url.deletingLastPathComponent().path)
            .filter { $0.contains("bozuk-") }
        #expect(backups.count == 1)
    }

    @Test("Dosya yoksa ya da tamamen bozuksa boş liste")
    func missingOrBroken() {
        let archive = archive()
        #expect(archive.load().isEmpty)
        archive.write(Data("{bu json değil".utf8))
        #expect(archive.load().isEmpty)
    }
}
