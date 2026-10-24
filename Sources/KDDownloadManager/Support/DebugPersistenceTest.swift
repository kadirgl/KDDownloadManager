#if DEBUG
import Foundation
import AppKit

/// Geliştirme senaryoları çalışırken uygulamanın gerçek listesi yüklenmesin/kaydedilmesin.
enum DebugHarness {
    static var isActive: Bool {
        let environment = ProcessInfo.processInfo.environment
        return ["KD_SNAPSHOT_DIR", "KD_ENGINE_TEST", "KD_PERSIST_TEST", "KD_LIMIT_TEST", "KD_TORRENT_TEST", "KD_UPDATE_TEST"].contains { environment[$0] != nil }
    }
}

/// Geliştirme aracı: listenin uygulama kapanıp açılınca korunmasını iki çalıştırmada dener.
///
///     KD_PERSIST_TEST=1 KD_ARCHIVE=/tmp/kd.json .build/debug/KDDownloadManager -downloadFolder /tmp/kd
///     KD_PERSIST_TEST=2 KD_ARCHIVE=/tmp/kd.json .build/debug/KDDownloadManager -downloadFolder /tmp/kd
///
/// 1. aşama: inen dosya + video, duraklatılmış dosya + video ve tamamlanan bir dosya bırakıp
/// uygulamayı gerçekten kapatır. 2. aşama: listeyi yükler, inenlerin kaldığı yerden sürdüğünü,
/// duraklatılanların iptalinde yarım dosyaların silindiğini kontrol eder.
@MainActor
enum DebugPersistenceTest {
    private static let activeFile = "https://fsn1-speed.hetzner.com/100MB.bin"
    private static let activeVideo = "https://www.youtube.com/watch?v=aqz-KE-bpKQ"
    private static let pausedFile = "https://fsn1-speed.hetzner.com/1GB.bin"
    private static let pausedVideo = "https://www.youtube.com/watch?v=jNQXAC9IVRw"
    private static let finishedFile = "https://github.com/aria2/aria2/releases/download/release-1.37.0/aria2-1.37.0.tar.xz"

    static func runIfRequested() {
        let environment = ProcessInfo.processInfo.environment
        guard let phase = environment["KD_PERSIST_TEST"], let archivePath = environment["KD_ARCHIVE"] else { return }
        let store = DownloadStore(
            engine: RoutingEngine(files: Aria2Engine(), videos: YtDlpEngine()),
            archive: DownloadArchive(url: URL(fileURLWithPath: archivePath))
        )
        func item(_ url: String) -> DownloadItem? { store.items.first { $0.url == url } }

        Task {
            if phase == "1" {
                store.add(links: [activeFile, activeVideo, pausedFile, pausedVideo, finishedFile].joined(separator: "\n"))
                for url in [activeFile, activeVideo, pausedFile] {
                    item(url).map { store.setSpeedLimit(1_048_576, for: $0) }
                }
                item(pausedVideo).map { store.setSpeedLimit(30 * 1024, for: $0) }
                await report("1: indiriliyor", store, after: 7)

                [pausedFile, pausedVideo].compactMap(item).forEach(store.togglePause)
                await report("1: ikisi duraklatıldı, uygulama kapatılıyor", store, after: 2)
                NSApp.terminate(nil)
            } else {
                await report("2: açılışta yüklenen liste", store, after: 0)
                await report("2: inenler kaldığı yerden sürmeli", store, after: 5)

                [pausedFile, pausedVideo].compactMap(item).forEach(store.cancel)
                [activeFile, activeVideo].compactMap(item).forEach { store.setSpeedLimit(nil, for: $0) }
                await report("2: duraklatılanlar iptal edildi, sınırlar kaldırıldı", store, after: 2)

                for _ in 0..<60 {
                    if store.items.allSatisfy({ $0.status == .completed }) { break }
                    try? await Task.sleep(for: .seconds(2))
                }
                await report("2: son durum", store, after: 0)
                NSApp.terminate(nil)
            }
        }
    }

    private static func report(_ title: String, _ store: DownloadStore, after seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
        print("— \(title)")
        for item in store.items.reversed() {
            print("  \(item.fileName) \(item.status) \(ByteFormat.size(item.downloadedBytes))/\(ByteFormat.size(item.totalBytes)) "
                + "\(ByteFormat.speed(item.speed)) sınır: \(item.speedLimit.map(ByteFormat.speed) ?? "yok")")
        }
        let manager = FileManager.default
        let folder = (try? manager.contentsOfDirectory(atPath: store.downloadFolder.path)) ?? []
        let caches = manager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KDDownloadManager/yt-dlp").path
        let temporary = (try? manager.subpathsOfDirectory(atPath: caches)) ?? []
        print("  klasör: \(folder.sorted())")
        print("  yt-dlp geçici: \(temporary.sorted())")
        fflush(stdout)
    }
}
#endif
