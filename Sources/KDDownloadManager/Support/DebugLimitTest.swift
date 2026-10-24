#if DEBUG
import Foundation

/// Geliştirme aracı: hız sınırlarının gerçekte ne kadar tuttuğunu ölçer (ekrandaki hıza değil,
/// inen bayta bakarak). Her aşamada 4 sn ısınma + 12 sn ölçüm yapar, sonra çıkar.
///
///     KD_LIMIT_TEST=1 .build/debug/KDDownloadManager -downloadFolder /tmp/kd
@MainActor
enum DebugLimitTest {
    private static let fileA = "https://fsn1-speed.hetzner.com/1GB.bin"
    private static let fileB = "https://ash-speed.hetzner.com/1GB.bin"
    private static let video = "https://www.youtube.com/watch?v=aqz-KE-bpKQ"

    static func runIfRequested() {
        guard ProcessInfo.processInfo.environment["KD_LIMIT_TEST"] != nil else { return }
        let store = DownloadStore(engine: RoutingEngine(files: Aria2Engine(), videos: YtDlpEngine()))
        let mb: Int64 = 1_048_576

        Task {
            // 1) Tek dosya, indirmeye özel 1 MB/S
            store.add(links: fileA)
            let a = store.items[0]
            store.setSpeedLimit(mb, for: a)
            await measure("Dosya, kendi sınırı 1 MB/S", [a], store)

            // 2) Tek video, indirmeye özel 1 MB/S
            store.togglePause(a)
            store.add(links: video)
            let v = store.items[0]
            store.setSpeedLimit(mb, for: v)
            await measure("Video, kendi sınırı 1 MB/S", [v], store, warmup: 10)

            // 3) Genel sınır 3 MB/S: iki dosya + video aynı anda, kendi sınırları yok
            store.setSpeedLimit(nil, for: a)
            store.setSpeedLimit(nil, for: v)
            store.togglePause(a)
            store.add(links: fileB)
            let b = store.items[0]
            let defaults = UserDefaults.standard
            let saved = [SettingsKey.globalLimitEnabled, SettingsKey.globalLimitMB].map { ($0, defaults.object(forKey: $0)) }
            UserDefaults.standard.set(true, forKey: SettingsKey.globalLimitEnabled)
            UserDefaults.standard.set(3.0, forKey: SettingsKey.globalLimitMB)
            store.applyGlobalSpeedLimit()
            await measure("Genel sınır 3 MB/S (2 dosya + video)", [a, b, v], store, warmup: 10)

            for (key, value) in saved {
                defaults.set(value, forKey: key)
            }
            for item in store.items { store.cancel(item) }
            try? await Task.sleep(for: .seconds(2))
            exit(0)
        }
    }

    private static func measure(_ title: String, _ items: [DownloadItem], _ store: DownloadStore, warmup: Double = 4) async {
        try? await Task.sleep(for: .seconds(warmup))
        let start = items.map(\.downloadedBytes)
        let began = Date()
        try? await Task.sleep(for: .seconds(12))
        let elapsed = Date().timeIntervalSince(began)
        print("— \(title)")
        var total: Int64 = 0
        for (item, before) in zip(items, start) {
            let rate = Int64(Double(item.downloadedBytes - before) / elapsed)
            total += rate
            print("  \(item.fileName.prefix(40)): gerçek \(ByteFormat.speed(rate)), ekranda \(ByteFormat.speed(item.speed)), \(item.status)")
        }
        if items.count > 1 { print("  toplam: \(ByteFormat.speed(total))") }
        fflush(stdout)
    }
}
#endif
