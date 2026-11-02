import SwiftUI

/// Üstteki filtre çipleri.
enum DownloadCategory: CaseIterable, Identifiable {
    case all, video, music, app, archive, document, other

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "Tümü"
        case .video: "Video"
        case .music: "Müzik"
        case .app: "Uygulama"
        case .archive: "Arşiv"
        case .document: "Döküman"
        case .other: "Diğer"
        }
    }

    /// Kategori ikonundaki SF Symbol (tasarım rehberindeki kategori tablosu).
    var symbol: String {
        switch self {
        case .all, .other: "ellipsis"
        case .video: "play.fill"
        case .music: "music.note"
        case .app: "square.grid.2x2.fill"
        case .archive: "archivebox.fill"
        case .document: "doc.text.fill"
        }
    }

    /// Kategori ikonunun üst ve alt renkleri.
    var topColor: Color {
        switch self {
        case .video: Color(hex: 0xB48CF0)
        case .music: Color(hex: 0xF57A9A)
        case .app: Color(hex: 0x5AA2F8)
        case .archive: Color(hex: 0xD6AE74)
        case .document: Color(hex: 0x5FCB8A)
        case .all, .other: Color(hex: 0xA7AEBB)
        }
    }

    var bottomColor: Color {
        switch self {
        case .video: Color(hex: 0x8150D6)
        case .music: Color(hex: 0xD4436A)
        case .app: Color(hex: 0x2C6FE0)
        case .archive: Color(hex: 0xA67840)
        case .document: Color(hex: 0x2E9E5C)
        case .all, .other: Color(hex: 0x6B7280)
        }
    }

    private static let extensions: [DownloadCategory: Set<String>] = [
        .video: ["mp4", "mkv", "mov", "avi", "webm", "m4v", "flv", "wmv"],
        .music: ["mp3", "m4a", "flac", "wav", "aac", "ogg", "opus", "aiff"],
        .app: ["dmg", "pkg", "app", "exe", "msi", "ipa", "apk"],
        .archive: ["zip", "rar", "7z", "tar", "gz", "bz2", "xz", "tgz"],
        .document: ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "rtf",
                    "epub", "pages", "numbers", "key", "csv", "md"]
    ]

    static func forFile(named name: String) -> DownloadCategory {
        let ext = (name as NSString).pathExtension.lowercased()
        return extensions.first { $0.value.contains(ext) }?.key ?? .other
    }
}

/// Tamamlanan listesinin sırası.
enum CompletedSort: String, CaseIterable, Identifiable {
    case newest, name, size

    var id: Self { self }

    var title: String {
        switch self {
        case .newest: "En yeni"
        case .name: "Ada göre"
        case .size: "Boyuta göre"
        }
    }
}

/// Alttaki "Devam Eden / Tamamlanan" sekmeleri.
enum ListTab: CaseIterable, Identifiable {
    case active, completed

    var id: Self { self }

    var title: String {
        switch self {
        case .active: "Devam Eden"
        case .completed: "Tamamlanan"
        }
    }

    var symbol: String {
        switch self {
        case .active: "play.fill"
        case .completed: "checkmark"
        }
    }

    func includes(_ status: DownloadStatus) -> Bool {
        switch self {
        case .active: status != .completed
        case .completed: status == .completed
        }
    }
}
