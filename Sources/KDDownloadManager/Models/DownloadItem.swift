import Foundation
import Observation

/// İndirmenin hangi motorla yapılacağını belirler.
enum DownloadSource: Equatable {
    case direct   // HTTP/HTTPS/FTP → aria2
    case video    // YouTube vb. → yt-dlp
    case torrent  // magnet / .torrent → aria2

    private static let videoHosts = [
        "youtube.com", "youtu.be", "vimeo.com", "dailymotion.com", "twitch.tv",
        "twitter.com", "x.com", "instagram.com", "tiktok.com", "facebook.com"
    ]

    static func detect(_ link: String) -> DownloadSource {
        let lower = link.lowercased()
        if lower.hasPrefix("magnet:") || lower.hasSuffix(".torrent") {
            return .torrent
        }
        if let host = URL(string: lower)?.host,
           videoHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
            return .video
        }
        return .direct
    }

    static func looksLikeLink(_ text: String) -> Bool {
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["http://", "https://", "ftp://", "magnet:"].contains { lower.hasPrefix($0) }
    }
}

enum DownloadStatus: Equatable {
    case queued
    case downloading
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
    var fileName: String
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

    var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return min(Double(downloadedBytes) / Double(totalBytes), 1)
    }

    init(
        id: UUID = UUID(),
        url: String,
        fileName: String? = nil,
        folder: URL = SettingsKey.downloadFolderURL,
        totalBytes: Int64 = 0,
        downloadedBytes: Int64 = 0,
        status: DownloadStatus = .queued
    ) {
        let source = DownloadSource.detect(url)
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
            return URL(string: url)?.host.map { "\($0) videosu" } ?? "Video"
        case .direct:
            let name = URL(string: url)?.lastPathComponent ?? ""
            guard !name.isEmpty, name != "/" else { return "İndirme" }
            return name.removingPercentEncoding ?? name
        }
    }
}
