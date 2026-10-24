import Foundation

/// Uygulamanın kendi dosyalarını tuttuğu klasörler (~/Library/Application Support/KDDownloadManager).
enum AppFolders {
    static var support: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return created(base.appendingPathComponent("KDDownloadManager", isDirectory: true))
    }

    /// Diskten eklenen .torrent dosyalarının kopyaları; asıl dosya silinse de indirme devam ettirilebilsin.
    static var torrents: URL {
        created(support.appendingPathComponent("Torrents", isDirectory: true))
    }

    private static func created(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
