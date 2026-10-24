import Foundation

/// Uygulamaya dışarıdan (panel ya da Chrome eklentisi) gelen indirme isteği.
/// Tarayıcıdan gelenlerde, giriş gerektiren indirmeler için istek bilgileri de bulunur.
struct DownloadRequest: Decodable, Sendable {
    var url: String
    /// Chrome'un sunucudan öğrendiği dosya adı; sadece aria2 kendi adını bulana kadar gösterilir.
    var filename: String?
    var referrer: String?
    var userAgent: String?
    /// "ad=değer; ad2=değer2" biçiminde çerez başlığı.
    var cookies: String?
    /// Video sitelerinde istenen kalite; yoksa otomatik.
    var quality: VideoQuality?
    /// Video sitelerinde (YouTube vb.) o sitenin tüm çerezleri; yt-dlp'ye verilir.
    var cookieJar: [BrowserCookie]?

    init(url: String, filename: String? = nil, referrer: String? = nil, userAgent: String? = nil,
         cookies: String? = nil, quality: VideoQuality? = nil) {
        self.url = url
        self.filename = filename
        self.referrer = referrer
        self.userAgent = userAgent
        self.cookies = cookies
        self.quality = quality
    }

    private enum CodingKeys: String, CodingKey {
        case url, filename, referrer, userAgent, cookies, quality, cookieJar
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(String.self, forKey: .url)
        filename = try container.decodeIfPresent(String.self, forKey: .filename)
        referrer = try container.decodeIfPresent(String.self, forKey: .referrer)
        userAgent = try container.decodeIfPresent(String.self, forKey: .userAgent)
        cookies = try container.decodeIfPresent(String.self, forKey: .cookies)
        // Tanınmayan kalite (eklentinin daha yeni bir sürümü) bütün isteği bozmasın; otomatik sayılır.
        quality = try? container.decodeIfPresent(VideoQuality.self, forKey: .quality)
        cookieJar = try? container.decodeIfPresent([BrowserCookie].self, forKey: .cookieJar)
    }
}
