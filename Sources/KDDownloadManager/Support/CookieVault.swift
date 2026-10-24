import Foundation

/// Tarayıcı eklentisinin gönderdiği bir çerez (chrome.cookies alanları).
struct BrowserCookie: Codable, Sendable, Equatable {
    var domain: String
    var path: String
    var name: String
    var value: String
    var secure: Bool
    var httpOnly: Bool?
    var hostOnly: Bool?
    /// Unix zamanı; oturum çerezlerinde yok.
    var expirationDate: Double?
}

/// Video sitelerinin (YouTube vb.) tarayıcıdan gelen çerezleri. YouTube çerezsiz isteklere sık sık
/// "robot olmadığınızı doğrulayın" diyor; yt-dlp tarayıcıdaki oturumun çerezleriyle bunu aşıyor.
///
/// Çerezler güvenlik için yalnızca bellekte tutulur. yt-dlp'ye verilirken indirmenin geçici klasörüne
/// sadece kullanıcının okuyabildiği bir dosya yazılır ve iş bitince silinir.
@MainActor
final class CookieVault {
    static let shared = CookieVault()

    private var jars: [String: (date: Date, cookies: [BrowserCookie])] = [:]
    /// Çerezi olmadığı için bekleyen siteler; eklenti dakikalık sinyalinin cevabında bunları görüp gönderir.
    private var wanted: Set<String> = []
    private var observers: [(String) -> Void] = []

    /// Bundan eski çerezler kullanılmaya devam eder ama eklentiden yenisi istenir.
    private static let freshness: TimeInterval = 20 * 60

    /// Çerezleri saklar. İçerik öncekinden farklıysa (örn. kullanıcı YouTube'a giriş yaptıysa)
    /// bekleyenlere haber verilir; aynı çerezlerle tekrar tekrar denenmesin.
    func store(_ cookies: [BrowserCookie], for site: String) {
        guard !cookies.isEmpty else { return }
        let sorted = cookies.sorted { ($0.domain, $0.path, $0.name) < ($1.domain, $1.path, $1.name) }
        let changed = jars[site]?.cookies != sorted
        jars[site] = (Date(), sorted)
        wanted.remove(site)
        if changed {
            observers.forEach { $0(site) }
        }
    }

    func cookies(for url: String) -> [BrowserCookie]? {
        Self.site(of: url).flatMap { jars[$0]?.cookies }
    }

    /// Çerez yoksa ya da eskidiyse eklentiden ister (bir sonraki dakikalık sinyalin cevabında).
    /// Eklenti dakikalık sinyalde sadece bilinen video sitelerinin çerezlerini gönderiyor; diğer
    /// sitelerin çerezleri zaten indirme isteğiyle birlikte geliyor.
    func requestIfNeeded(for url: String) {
        guard DownloadSource.isKnownVideoSite(url), let site = Self.site(of: url) else { return }
        if let jar = jars[site], Date().timeIntervalSince(jar.date) < Self.freshness { return }
        wanted.insert(site)
    }

    /// Eklentiden istenecek siteler.
    var wantedSites: [String] { wanted.sorted() }

    /// Çerezler eski olmasa da eklentiden yenisini iste (örn. çerezlerle bile robot doğrulaması çıktıysa).
    func requestFresh(for url: String) {
        guard DownloadSource.isKnownVideoSite(url), let site = Self.site(of: url) else { return }
        wanted.insert(site)
    }

    /// Bir site için çerez geldiğinde haber verir (bekleyen indirmeleri yeniden denemek için).
    func observe(_ handler: @escaping (String) -> Void) {
        observers.append(handler)
    }

    /// www.youtube.com → youtube.com gibi; bilinen video siteleri eklentideki VIDEO_HOSTS ile aynı,
    /// diğer sitelerde adresin alan adı (www. olmadan).
    static func site(of url: String) -> String? {
        guard let host = URL(string: url)?.host?.lowercased() else { return nil }
        if let known = DownloadSource.videoHostList.first(where: { host == $0 || host.hasSuffix("." + $0) }) {
            // youtu.be kısa linklerinin çerezleri youtube.com'da.
            return known == "youtu.be" ? "youtube.com" : known
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// yt-dlp'nin okuduğu Netscape biçiminde çerez dosyası yazar (izinler 0600).
    nonisolated static func writeNetscapeFile(_ cookies: [BrowserCookie], to url: URL) throws {
        var lines = ["# Netscape HTTP Cookie File"]
        for cookie in cookies {
            // Alan adı noktayla başlıyorsa alt alan adlarında da geçerli.
            let includeSubdomains = cookie.hostOnly == false || cookie.domain.hasPrefix(".")
            let domain = (cookie.httpOnly == true ? "#HttpOnly_" : "") + cookie.domain
            let expiry = cookie.expirationDate.map { String(Int($0)) } ?? "0"
            let fields = [domain, includeSubdomains ? "TRUE" : "FALSE", cookie.path,
                          cookie.secure ? "TRUE" : "FALSE", expiry, cookie.name, cookie.value]
            // Sekme ya da satır sonu içeren değerler dosyayı bozar; öyle bir çerez varsa atla.
            guard !fields.contains(where: { $0.contains("\t") || $0.contains("\n") }) else { continue }
            lines.append(fields.joined(separator: "\t"))
        }
        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        manager.createFile(atPath: url.path, contents: Data((lines.joined(separator: "\n") + "\n").utf8),
                           attributes: [.posixPermissions: 0o600])
    }
}
