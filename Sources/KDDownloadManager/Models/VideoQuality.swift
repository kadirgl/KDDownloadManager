import Foundation

/// Video sitelerinden (yt-dlp) indirirken istenen kalite.
enum VideoQuality: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Mac'te her yerde oynayan H.264/AAC'nin en iyisi (YouTube'da genelde 1080p).
    case auto
    case p2160 = "2160"
    case p1440 = "1440"
    case p1080 = "1080"
    case p720 = "720"
    case p480 = "480"
    case p360 = "360"
    /// Sadece ses, MP3 olarak.
    case audio

    var id: Self { self }

    var title: String {
        switch self {
        case .auto: "Otomatik"
        case .p2160: "2160p (4K)"
        case .p1440: "1440p"
        case .audio: "Sadece ses (MP3)"
        default: "\(rawValue)p"
        }
    }

    /// Seçilen en yüksek çözünürlük; nil ise sınırsız ya da video değil.
    var maxHeight: Int? {
        switch self {
        case .auto, .audio: nil
        default: Int(rawValue)
        }
    }
}
