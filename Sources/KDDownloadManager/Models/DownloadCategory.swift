import SwiftUI

/// Üstteki filtre çipleri.
enum DownloadCategory: CaseIterable, Identifiable {
    case all, video, music, image, app, archive, document, other

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "Tümü"
        case .video: "Video"
        case .music: "Müzik"
        case .image: "Resim"
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
        case .image: "photo.fill"
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
        case .image: Color(hex: 0x4FD1C5)
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
        case .image: Color(hex: 0x1A9C93)
        case .app: Color(hex: 0x2C6FE0)
        case .archive: Color(hex: 0xA67840)
        case .document: Color(hex: 0x2E9E5C)
        case .all, .other: Color(hex: 0x6B7280)
        }
    }

    /// Uzantı → kategori. Uzantı birden çok listede olmamalı.
    private static let extensions: [DownloadCategory: Set<String>] = [
        .video: ["mp4", "m4v", "mov", "mkv", "avi", "webm", "flv", "f4v", "wmv", "asf", "mpg", "mpeg", "mpe",
                 "m2v", "m2ts", "mts", "ts", "3gp", "3g2", "ogv", "vob", "rm", "rmvb", "divx", "xvid", "hevc",
                 "h264", "h265", "mxf", "dv"],
        .music: ["mp3", "m4a", "m4b", "m4p", "aac", "flac", "alac", "wav", "wave", "aif", "aiff", "aifc", "ogg",
                 "oga", "opus", "wma", "mid", "midi", "amr", "ape", "wv", "caf", "dsf", "dff", "mka", "ac3", "dts"],
        .image: ["jpg", "jpeg", "jpe", "jfif", "pjpeg", "png", "apng", "gif", "webp", "avif", "heic", "heif",
                 "jxl", "bmp", "dib", "tif", "tiff", "svg", "svgz", "ico", "icns", "psd", "ai", "eps", "raw",
                 "dng", "cr2", "cr3", "nef", "nrw", "arw", "orf", "rw2", "raf", "srw", "pef", "xcf", "tga",
                 "exr", "hdr"],
        .app: ["dmg", "pkg", "mpkg", "app", "exe", "msi", "msix", "appx", "ipa", "apk", "aab", "xapk", "apkm",
               "deb", "rpm", "appimage", "snap", "flatpak", "jar", "iso", "img", "vhd", "vhdx", "vmdk", "ova"],
        .archive: ["zip", "zipx", "rar", "7z", "tar", "gz", "tgz", "bz2", "tbz", "tbz2", "xz", "txz", "zst",
                   "tzst", "lz", "lzma", "lz4", "z", "cab", "arj", "lzh", "sit", "sitx", "cpio", "xar", "sea"],
        .document: ["pdf", "doc", "docx", "docm", "dot", "dotx", "xls", "xlsx", "xlsm", "xlsb", "ppt", "pptx",
                    "pps", "ppsx", "odt", "ods", "odp", "odg", "rtf", "txt", "text", "md", "markdown", "csv",
                    "tsv", "epub", "mobi", "azw", "azw3", "fb2", "djvu", "xps", "oxps", "pages", "numbers",
                    "key", "tex", "log", "json", "xml", "yaml", "yml", "html", "htm", "srt", "vtt", "ass", "ssa",
                    "sub"]
    ]

    static func forFile(named name: String) -> DownloadCategory {
        let ext = (name as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return .other }
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
