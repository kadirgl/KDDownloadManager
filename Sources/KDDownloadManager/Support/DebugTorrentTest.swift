#if DEBUG
import Foundation

/// Geliştirme aracı: torrent'in üç yolunu dener — diskteki .torrent dosyası, takipçisiz (sadece DHT)
/// magnet ve .torrent linki. Bir süre indirip durumu yazar, sonra hepsini iptal edip artık dosya
/// kalmadığını kontrol eder.
///
///     KD_TORRENT_TEST=1 KD_TORRENT_FILE=/yol/x.torrent KD_MAGNET='magnet:?...' KD_TORRENT_URL=https://.../y.torrent \
///         .build/debug/KDDownloadManager -downloadFolder /tmp/kd
@MainActor
enum DebugTorrentTest {
    static func runIfRequested() {
        let environment = ProcessInfo.processInfo.environment
        guard environment["KD_TORRENT_TEST"] != nil else { return }
        let store = DownloadStore(engine: RoutingEngine(files: Aria2Engine(), videos: YtDlpEngine()))

        Task {
            if let file = environment["KD_TORRENT_FILE"] {
                store.addTorrentFiles([URL(fileURLWithPath: file)])
            }
            let links = [environment["KD_MAGNET"], environment["KD_TORRENT_URL"]].compactMap { $0 }
            store.add(links: links.joined(separator: "\n"))
            // Sunuculara yüklenmemek için her birini sınırla.
            store.items.forEach { store.setSpeedLimit(2 * 1_048_576, for: $0) }

            for second in stride(from: 10, through: 60, by: 10) {
                try? await Task.sleep(for: .seconds(10))
                print("— \(second). saniye")
                for item in store.items.reversed() {
                    print("  [\(item.source)] \(item.fileName.prefix(45)) \(item.status) "
                        + "\(ByteFormat.size(item.downloadedBytes))/\(ByteFormat.size(item.totalBytes)) \(ByteFormat.speed(item.speed))")
                }
                fflush(stdout)
            }

            store.items.forEach(store.cancel)
            try? await Task.sleep(for: .seconds(2))
            let manager = FileManager.default
            print("iptal sonrası klasör: \((try? manager.contentsOfDirectory(atPath: store.downloadFolder.path)) ?? [])")
            print("torrent kopyaları: \((try? manager.contentsOfDirectory(atPath: AppFolders.torrents.path)) ?? [])")
            fflush(stdout)
            exit(0)
        }
    }
}
#endif
