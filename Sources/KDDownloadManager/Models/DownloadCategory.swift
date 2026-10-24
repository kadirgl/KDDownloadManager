import Foundation

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

    var icon: Ph {
        switch self {
        case .all, .other: .file
        case .video: .filmStrip
        case .music: .musicNotes
        case .app: .appWindow
        case .archive: .fileZip
        case .document: .file
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

    var icon: Ph {
        switch self {
        case .active: .play
        case .completed: .flag
        }
    }

    func includes(_ status: DownloadStatus) -> Bool {
        switch self {
        case .active: status != .completed
        case .completed: status == .completed
        }
    }
}
