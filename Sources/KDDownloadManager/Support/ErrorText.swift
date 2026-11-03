import Foundation

/// aria2 ve yt-dlp'nin İngilizce hata metinlerini satırda ve bildirimde gösterilecek Türkçe, kısa
/// açıklamalara çevirir. Tanınmayan hata olduğu gibi gösterilir (bilgi kaybolmasın).
enum ErrorText {
    /// aria2'nin hata kodu (https://aria2.github.io/manual/en/html/aria2c.html#exit-status) ve metni.
    static func aria2(code: String?, message: String?, remaining: Int64?) -> String {
        let message = message ?? ""
        if code == "9" || message.localizedCaseInsensitiveContains("No space left")
            || message.localizedCaseInsensitiveContains("not enough disk space") {
            return diskFull(remaining: remaining)
        }
        if let status = httpStatus(in: message) {
            return http(status)
        }
        switch code {
        case "2": return "Bağlantı zaman aşımına uğradı"
        case "3": return "Dosya sunucuda bulunamadı (404)"
        case "5": return "Sunucu çok yavaş yanıt verdi"
        case "6": return "Ağ bağlantısı koptu"
        case "8": return "Sunucu kaldığı yerden devam etmeyi desteklemiyor"
        case "13": return "Aynı adla bir dosya zaten var"
        case "15", "16", "17", "18": return "Dosya diske yazılamadı (klasör izni ya da disk sorunu)"
        case "19": return "Sunucu bulunamadı; internet bağlantınızı kontrol edin"
        case "22": return "Sunucu geçersiz bir yanıt verdi"
        case "23": return "Çok fazla yönlendirme"
        case "24": return "Giriş gerekiyor (yetkilendirme başarısız)"
        case "26", "27": return "Torrent dosyası ya da magnet linki bozuk"
        case "29": return "Sunucu şu an çok yoğun; biraz sonra tekrar deneyin"
        case "32": return "Dosya doğrulanamadı (sağlama toplamı tutmuyor)"
        default: return message.isEmpty ? "İndirme başarısız" : message
        }
    }

    /// yt-dlp'nin son "ERROR:" satırı.
    static func ytDlp(_ message: String?, exitCode: Int32) -> String {
        guard let message, !message.isEmpty else { return "Video indirilemedi (kod \(exitCode))" }
        let rules: [(needles: [String], text: String)] = [
            (["No space left"], diskFull(remaining: nil)),
            (["Unsupported URL"], "Bu sayfada indirilebilir video bulunamadı"),
            (["Private video"], "Video gizli; yalnızca sahibi izleyebilir"),
            (["members-only", "Join this channel"], "Video yalnızca kanal üyelerine açık"),
            (["Premieres in", "live event will begin", "This live event"], "Canlı yayın ya da gösterim henüz başlamadı"),
            (["not available in your country", "geo restrict", "geo-restricted"], "Video bu ülkede kullanılamıyor"),
            (["Video unavailable", "This video is unavailable", "has been removed", "no longer available"],
             "Video kullanılamıyor ya da kaldırılmış"),
            (["Requested format is not available"], "İstenen kalite bu videoda yok; Otomatik'i deneyin"),
            (["ffmpeg", "Postprocessing", "Conversion failed"], "Video birleştirilemedi (ffmpeg)"),
            (["Unable to download webpage", "Failed to resolve", "nodename nor servname", "Name or service not known",
              "Connection refused", "Network is unreachable"], "Siteye bağlanılamadı; internet bağlantınızı kontrol edin"),
            (["timed out"], "Bağlantı zaman aşımına uğradı"),
        ]
        for rule in rules where rule.needles.contains(where: { message.localizedCaseInsensitiveContains($0) }) {
            return rule.text
        }
        if let status = httpStatus(in: message) {
            return http(status)
        }
        // "[youtube] abc123: ..." önekini at.
        if let range = message.range(of: #"^\[[^\]]+\] [^:]+: "#, options: .regularExpression) {
            return String(message[range.upperBound...])
        }
        return message
    }

    static func diskFull(remaining: Int64?) -> String {
        guard let remaining, remaining > 0 else { return "Diskte yer kalmadı" }
        return "Diskte yer kalmadı · \(ByteFormat.size(remaining)) gerekli"
    }

    private static func http(_ status: Int) -> String {
        switch status {
        case 401: "Giriş gerekiyor (401)"
        case 403: "Sunucu erişime izin vermedi (403); bağlantının süresi dolmuş olabilir"
        case 404: "Dosya sunucuda bulunamadı (404)"
        case 410: "Dosya sunucudan kaldırılmış (410)"
        case 416: "Sunucu kaldığı yerden devam etmeyi kabul etmedi (416)"
        case 429: "Sunucu çok fazla istek dedi (429); biraz sonra tekrar deneyin"
        case 500..<600: "Sunucu hatası (\(status)); biraz sonra tekrar deneyin"
        default: "Sunucu isteği reddetti (\(status))"
        }
    }

    /// "status=404" (aria2) ya da "HTTP Error 404" (yt-dlp).
    private static func httpStatus(in message: String) -> Int? {
        for pattern in [#"status=(\d{3})"#, #"HTTP Error (\d{3})"#] {
            if let range = message.range(of: pattern, options: .regularExpression) {
                let digits = message[range].filter(\.isNumber)
                if let code = Int(digits.suffix(3)) { return code }
            }
        }
        return nil
    }
}
