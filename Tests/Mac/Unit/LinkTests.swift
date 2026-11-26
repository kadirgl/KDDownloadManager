import Foundation
import Testing
@testable import KDDownloadManager

/// Linkin hangi motora gideceği ve indirme satırının ilk adı.
@Suite("Link tanıma")
@MainActor
struct DownloadSourceTests {
    @Test("Video siteleri ve alt alan adları yt-dlp'ye gider", arguments: [
        "https://www.youtube.com/watch?v=abc", "https://youtu.be/abc", "https://m.youtube.com/watch?v=1",
        "https://vimeo.com/1234", "https://x.com/user/status/1", "https://www.instagram.com/reel/x",
        "https://www.tiktok.com/@a/video/1", "https://www.twitch.tv/videos/1", "HTTPS://WWW.YOUTUBE.COM/watch?v=CAPS",
    ])
    func videoSites(_ link: String) {
        #expect(DownloadSource.detect(link) == .video)
        #expect(DownloadSource.isKnownVideoSite(link))
    }

    @Test("Akışlar (.m3u8, .mpd) her sitede video sayılır")
    func streams() {
        #expect(DownloadSource.detect("https://cdn.example.com/live/master.m3u8?token=1") == .video)
        #expect(DownloadSource.detect("https://cdn.example.com/a/manifest.mpd") == .video)
        // Bilinen site değil: yt-dlp'ye referrer da verilmeli.
        #expect(!DownloadSource.isKnownVideoSite("https://cdn.example.com/live/master.m3u8"))
    }

    @Test("magnet ve .torrent aria2'ye torrent olarak gider")
    func torrents() {
        #expect(DownloadSource.detect("magnet:?xt=urn:btih:abc&dn=ubuntu.iso") == .torrent)
        #expect(DownloadSource.detect("https://releases.ubuntu.com/ubuntu.iso.torrent") == .torrent)
        #expect(DownloadSource.detect("file:///Users/x/a.torrent") == .torrent)
    }

    @Test("Diğer her şey doğrudan dosya")
    func direct() {
        #expect(DownloadSource.detect("https://example.com/file.zip") == .direct)
        // Adında "youtube" geçen başka bir site video değildir.
        #expect(DownloadSource.detect("https://notyoutube.com/a.mp4") == .direct)
        #expect(DownloadSource.detect("https://youtube.com.evil.example/a") == .direct)
        #expect(DownloadSource.detect("ftp://ftp.example.com/a.iso") == .direct)
    }

    @Test("Link gibi görünen metinler")
    func looksLikeLink() {
        for link in ["http://a.b", "https://a.b/c", "  https://a.b  ", "FTP://x/y", "magnet:?xt=1"] {
            #expect(DownloadSource.looksLikeLink(link), "\(link)")
        }
        for text in ["", "www.example.com", "javascript:alert(1)", "file:///etc/passwd", "merhaba"] {
            #expect(!DownloadSource.looksLikeLink(text), "\(text)")
        }
    }
}

@Suite("İndirme satırı")
@MainActor
struct DownloadItemTests {
    init() { TestEnvironment.prepare() }

    @Test("Ad adresten çıkarılır; yüzde kodlaması çözülür")
    func nameFromURL() {
        #expect(DownloadItem(url: "https://example.com/files/Yillik%20Rapor.pdf").fileName == "Yillik Rapor.pdf")
        #expect(DownloadItem(url: "https://example.com/files/a.zip?x=1").fileName == "a.zip")
    }

    @Test("Adressiz yol (\"/\", boş) 'İndirme' olur — Broadcom'un /?file= adresleri")
    func emptyPath() {
        #expect(DownloadItem(url: "https://example.com/").fileName == "İndirme")
        #expect(DownloadItem(url: "https://example.com/?file=VMware-Fusion.dmg").fileName == "İndirme")
    }

    @Test("Torrent adı magnet'in dn alanından")
    func torrentName() {
        let item = DownloadItem(url: "magnet:?xt=urn:btih:0000&dn=ubuntu-24.04.iso")
        #expect(item.fileName == "ubuntu-24.04.iso")
        #expect(item.category == .app)
        #expect(item.source == .torrent)
    }

    @Test("Video, başlık gelene kadar site adıyla görünür")
    func videoPlaceholder() {
        #expect(DownloadItem(url: "https://www.youtube.com/watch?v=x").fileName == "YouTube videosu")
        #expect(DownloadItem(url: "https://vimeo.com/1").fileName == "Vimeo videosu")
        #expect(DownloadItem(url: "https://www.youtube.com/watch?v=x").category == .video)
    }

    @Test("Eklentinin işaretlediği sayfa video olarak iner")
    func forcedVideo() {
        let item = DownloadItem(url: "https://news.example.com/article", forceVideo: true)
        #expect(item.source == .video)
        #expect(item.category == .video)
    }

    @Test("Ad değişince kategori de değişir (dosya); videoda kaliteye bağlı")
    func categoryFollowsName() {
        let file = DownloadItem(url: "https://example.com/download")
        #expect(file.category == .other)
        file.fileName = "kurulum.dmg"
        #expect(file.category == .app)

        let video = DownloadItem(url: "https://www.youtube.com/watch?v=x")
        video.fileName = "şarkı.mp3"
        #expect(video.category == .video)
        video.quality = .audio
        #expect(video.category == .music)
        video.quality = .p720
        #expect(video.category == .video)
    }

    @Test("İlerleme ve kalan süre")
    func progress() {
        let item = DownloadItem(url: "https://example.com/a.bin", totalBytes: 1_000, downloadedBytes: 250)
        #expect(item.progress == 0.25)
        #expect(item.remainingSeconds == nil)
        item.speed = 75
        #expect(item.remainingSeconds == 10)
        item.downloadedBytes = 5_000
        #expect(item.progress == 1)

        let empty = DownloadItem(url: "https://example.com/empty.txt", status: .completed)
        #expect(empty.progress == 1)
        #expect(DownloadItem(url: "https://example.com/unknown").progress == 0)
    }

    @Test("Durum güncellemesi aynı değeri yeniden yazmaz")
    func setStatus() {
        let item = DownloadItem(url: "https://example.com/a.bin")
        item.setStatus(.downloading, speed: 10)
        #expect(item.status == .downloading && item.speed == 10)
        item.setStatus(.failed("x"))
        #expect(item.isFailed && item.speed == 0)
    }
}

@Suite("Kategoriler")
@MainActor
struct CategoryTests {
    @Test("Uzantı → kategori", arguments: [
        ("film.MKV", DownloadCategory.video), ("a.mp4", .video), ("klip.webm", .video),
        ("şarkı.mp3", .music), ("a.flac", .music), ("a.opus", .music),
        ("foto.HEIC", .image), ("a.webp", .image), ("a.svg", .image),
        ("Kurulum.dmg", .app), ("setup.exe", .app), ("a.apk", .app), ("ubuntu.iso", .app),
        ("a.zip", .archive), ("a.tar", .archive), ("a.7z", .archive), ("a.tgz", .archive),
        ("rapor.pdf", .document), ("a.docx", .document), ("a.srt", .document), ("a.epub", .document),
        ("adsız", .other), ("a.xyz", .other), (".gizli", .other),
    ])
    func mapping(name: String, category: DownloadCategory) {
        #expect(DownloadCategory.forFile(named: name) == category)
    }

    @Test("Çift uzantıda sondaki geçerli")
    func doubleExtension() {
        #expect(DownloadCategory.forFile(named: "yedek.tar.gz") == .archive)
        #expect(DownloadCategory.forFile(named: "video.mp4.part") == .other)
    }

    @Test("Sekmeler: tamamlanan ayrı, hatalılar devam edenlerde")
    func tabs() {
        #expect(ListTab.completed.includes(.completed))
        #expect(!ListTab.active.includes(.completed))
        for status: DownloadStatus in [.queued, .downloading, .processing, .paused, .failed("x")] {
            #expect(ListTab.active.includes(status))
            #expect(!ListTab.completed.includes(status))
        }
    }
}
