#if DEBUG
import Foundation

/// Geliştirme aracı: `KD_ENGINE_TEST` ayarlıysa gerçek motorlarla (aria2 + yt-dlp) bir senaryo çalıştırır
/// (ekle → hız sınırı → duraklat → iptal → devam), her adımı stdout'a yazar ve çıkar.
/// İlk link duraklat/devam, ikincisi iptal için kullanılır; gerisi sadece indirilir.
///
///     KD_ENGINE_TEST="url1 url2 url3" .build/debug/KDDownloadManager -downloadFolder /tmp/kd
@MainActor
enum DebugEngineTest {
    static func runIfRequested() {
        guard let links = ProcessInfo.processInfo.environment["KD_ENGINE_TEST"] else { return }
        let store = DownloadStore(engine: RoutingEngine(files: Aria2Engine(), videos: YtDlpEngine()))

        Task {
            store.add(links: links.split(separator: " ").joined(separator: "\n"))
            // `add` en yeniyi başa koyuyor; linklerin yazıldığı sıraya çevir.
            let items = Array(store.items.reversed())
            let first = items[0]
            store.setSpeedLimit(1_048_576, for: first)
            // İkincisi iptal edilecek; küçük dosyalar iptalden önce bitmesin diye çok yavaş.
            if items.count > 1 { store.setSpeedLimit(50 * 1024, for: items[1]) }

            await step("başladı (ilk link 1 MB/S sınırlı)", store, after: 4)

            store.togglePause(first)
            var cancelledFiles: [String] = []
            if items.count > 1 {
                cancelledFiles = files(in: store.downloadFolder)
                store.cancel(items[1])
            }
            await step("ilki duraklatıldı, ikincisi iptal edildi", store, after: 2)
            await step("duraklatılmış ilk link ilerlememeli", store, after: 2)
            print("iptal öncesi klasör: \(cancelledFiles)")
            print("iptal sonrası klasör: \(files(in: store.downloadFolder))")

            store.setSpeedLimit(nil, for: first)
            store.togglePause(first)
            for _ in 0..<45 {
                await step("devam", store, after: 2)
                if store.items.allSatisfy({ if case .completed = $0.status { true } else if case .failed = $0.status { true } else { false } }) {
                    break
                }
            }
            print("son klasör: \(files(in: store.downloadFolder))")
            exit(0)
        }
    }

    private static func step(_ title: String, _ store: DownloadStore, after seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
        print("— \(title)")
        for item in store.items.reversed() {
            let limit = item.speedLimit.map(ByteFormat.speed) ?? "sınırsız"
            print("  \(item.fileName) [\(item.category.title)] \(item.status) "
                + "\(ByteFormat.size(item.downloadedBytes))/\(ByteFormat.size(item.totalBytes)) "
                + "%\(Int(item.progress * 100)) \(ByteFormat.speed(item.speed)) sınır: \(limit) "
                + "hedef: \(item.destination?.path ?? "-")")
        }
        fflush(stdout)
    }

    private static func files(in folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }
}
#endif
