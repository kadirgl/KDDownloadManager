import Foundation
import Observation

/// İndirmenin hangi motorla yapılacağını belirler.
enum DownloadSource: Equatable {
    case direct   // HTTP/HTTPS/FTP → aria2
    case video    // YouTube vb. → yt-dlp
    case torrent  // magnet / .torrent → aria2

    static let videoHostList: [String] = {
        let hosts = [
            "youtube.com", "youtu.be", "vimeo.com", "dailymotion.com", "twitch.tv",
            "twitter.com", "x.com", "instagram.com", "tiktok.com", "facebook.com"
        ]
        #if DEBUG
        // Denemelerde video yolunu (yt-dlp) YouTube'a gitmeden çalıştırmak için ek siteler.
        if let extra = ProcessInfo.processInfo.environment["KD_VIDEO_HOSTS"] {
            return hosts + extra.split(separator: ",").map(String.init)
        }
        #endif
        return hosts
    }()

    static func detect(_ link: String) -> DownloadSource {
        let lower = link.lowercased()
        if lower.hasPrefix("magnet:") || lower.hasSuffix(".torrent") {
            return .torrent
        }
        if let host = URL(string: lower)?.host,
           videoHostList.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
            return .video
        }
        // HLS/DASH akışları (eklentinin sayfalarda yakaladığı .m3u8/.mpd) parça parça iner; yt-dlp birleştirir.
        if let path = URL(string: lower)?.path, path.hasSuffix(".m3u8") || path.hasSuffix(".mpd") {
            return .video
        }
        return .direct
    }

    /// yt-dlp'nin özel olarak tanıdığı siteler (YouTube vb.); diğer sitelerde yt-dlp'ye referrer ve
    /// tarayıcı kimliği de verilir.
    static func isKnownVideoSite(_ link: String) -> Bool {
        guard let host = URL(string: link.lowercased())?.host else { return false }
        return videoHostList.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    static func looksLikeLink(_ text: String) -> Bool {
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["http://", "https://", "ftp://", "magnet:"].contains { lower.hasPrefix($0) }
    }
}

enum DownloadStatus: Equatable {
    case queued
    case downloading
    /// İndirme bitti, dosya işleniyor (video ile sesi birleştirme, MP3'e dönüştürme). Bu sırada
    /// ilerleme bilgisi gelmiyor; hız 0 göründüğü için ayrı gösteriliyor.
    case processing
    case paused
    case completed
    case failed(String)
}

@MainActor
@Observable
final class DownloadItem: Identifiable {
    /// Kalıcı kimlik; uygulama yeniden açıldığında da aynı kalır (yt-dlp geçici klasörü buna bağlı).
    let id: UUID
    let url: String
    let source: DownloadSource
    /// İndirme sırasında değişebilir (sunucunun verdiği gerçek ad, uzantısı sonradan anlaşılan dosya);
    /// kategori de ona göre güncellenir. Videoda kategoriyi kalite belirliyor (video ya da sadece ses).
    var fileName: String {
        didSet {
            if source != .video, fileName != oldValue { category = DownloadCategory.forFile(named: fileName) }
        }
    }
    var category: DownloadCategory
    var totalBytes: Int64
    var downloadedBytes: Int64
    /// Anlık hız (bayt/sn).
    var speed: Int64 = 0
    /// Bu indirmeye özel hız sınırı (bayt/sn). nil = sınırsız.
    var speedLimit: Int64?
    var status: DownloadStatus
    /// İndirme bittiğinde dosyanın diskteki yeri.
    var destination: URL?
    /// İndirmenin yapıldığı klasör. Ayarlardaki klasör sonradan değişse de yarım dosya burada
    /// kaldığı için devam ederken bu kullanılır.
    var folder: URL
    /// Tarayıcıdan gelen istek bilgileri; giriş gerektiren indirmelerde sunucu bunları bekliyor.
    var referrer: String?
    var userAgent: String?
    /// Çerezler güvenlik için diske yazılmaz; uygulama yeniden açılınca kaybolur.
    var cookies: String?
    /// Dosyaya verilecek ad: akış adresleri anlamsız ("index.m3u8", karma kod) olduğunda eklenti sayfanın
    /// başlığını gönderiyor. Normal dosyada uzantılı tam ad, videoda (yt-dlp) uzantısız.
    var preferredName: String?
    /// İndirmenin bittiği an (Tamamlanan'daki "Bugün 14:32" ve sıralama için).
    var completedAt: Date?
    /// Video sitelerinde indirilecek kalite.
    var quality: VideoQuality = .auto {
        didSet {
            if source == .video { category = quality == .audio ? .music : .video }
        }
    }

    var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return min(Double(downloadedBytes) / Double(totalBytes), 1)
    }

    var isFailed: Bool {
        if case .failed = status { true } else { false }
    }

    /// Kalan süre (sn); hız ya da boyut bilinmiyorsa nil.
    var remainingSeconds: Double? {
        guard speed > 0, totalBytes > downloadedBytes else { return nil }
        return Double(totalBytes - downloadedBytes) / Double(speed)
    }

    init(
        id: UUID = UUID(),
        url: String,
        fileName: String? = nil,
        folder: URL = SettingsKey.downloadFolderURL,
        totalBytes: Int64 = 0,
        downloadedBytes: Int64 = 0,
        status: DownloadStatus = .queued,
        forceVideo: Bool = false
    ) {
        // Eklenti, yt-dlp'nin herhangi bir sitede video bulduğu sayfaları "video" olarak işaretleyebiliyor.
        let source = forceVideo ? .video : DownloadSource.detect(url)
        let name = fileName ?? Self.suggestedName(for: url, source: source)
        self.id = id
        self.folder = folder
        self.url = url
        self.source = source
        self.fileName = name
        self.category = source == .video ? .video : DownloadCategory.forFile(named: name)
        self.totalBytes = totalBytes
        self.downloadedBytes = downloadedBytes
        self.status = status
    }

    private static func suggestedName(for url: String, source: DownloadSource) -> String {
        switch source {
        case .torrent:
            if let name = URLComponents(string: url)?.queryItems?.first(where: { $0.name == "dn" })?.value {
                return name
            }
            return URL(string: url)?.lastPathComponent ?? "Torrent"
        case .video:
            // Gerçek başlık yt-dlp'den gelecek.
            return "\(Self.siteName(for: url)) videosu"
        case .direct:
            let name = URL(string: url)?.lastPathComponent ?? ""
            guard !name.isEmpty, name != "/" else { return "İndirme" }
            return name.removingPercentEncoding ?? name
        }
    }

    /// "www.youtube.com" yerine "YouTube" gibi okunur site adı (bildirimde ve listede, başlık gelene kadar).
    private static func siteName(for url: String) -> String {
        let host = (URL(string: url)?.host ?? "").replacingOccurrences(of: "www.", with: "")
        let names = [
            "youtube.com": "YouTube", "youtu.be": "YouTube", "m.youtube.com": "YouTube",
            "vimeo.com": "Vimeo", "dailymotion.com": "Dailymotion", "twitch.tv": "Twitch",
            "twitter.com": "X", "x.com": "X", "instagram.com": "Instagram",
            "tiktok.com": "TikTok", "facebook.com": "Facebook"
        ]
        return names[host] ?? (host.isEmpty ? "Video" : host)
    }
}
