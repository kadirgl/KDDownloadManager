import Foundation

/// Uygulamayla gelen yt-dlp. Yalnızca uygulamanın kendi güncellemesiyle (imzalı, noter onaylı paket) yenilenir;
/// uygulama içinden ayrıca indirilmez. 1.9.5 ve öncesi ayrı güncelleme indirebiliyordu; o kopyalar açılışta silinir.
enum YtDlp {
    /// Paketteki yt-dlp (Contents/Resources/yt-dlp/yt-dlp_macos); `swift run` ile çalışırken yok, o zaman
    /// Executables arama yolundaki (Homebrew) yt-dlp'yi kullanır.
    nonisolated static var bundledBinary: URL? {
        guard let folder = Bundle.main.url(forResource: "yt-dlp", withExtension: nil) else { return nil }
        let binary = folder.appendingPathComponent("yt-dlp_macos")
        return FileManager.default.isExecutableFile(atPath: binary.path) ? binary : nil
    }

    /// Eski sürümlerin uygulama içinden indirdiği yt-dlp kopyalarını siler (~/Library/Application Support/
    /// KDDownloadManager/Tools). Artık kullanılmıyorlar; yer kaplamasınlar.
    nonisolated static func removeDownloadedCopies() {
        let folder = AppFolders.support.appendingPathComponent("Tools", isDirectory: true)
        let manager = FileManager.default
        for name in (try? manager.contentsOfDirectory(atPath: folder.path)) ?? [] where name.hasPrefix("yt-dlp") {
            try? manager.removeItem(at: folder.appendingPathComponent(name))
        }
        if (try? manager.contentsOfDirectory(atPath: folder.path))?.isEmpty == true {
            try? manager.removeItem(at: folder)
        }
    }
}
