#if DEBUG
import SwiftUI
import AppKit

/// Geliştirme aracı: `KD_SNAPSHOT_DIR` ayarlıysa paneli her ekran için
/// açık/koyu PNG olarak bu klasöre çizer ve uygulamadan çıkar.
/// Ekran kaydı izni gerektirmez; tasarımla karşılaştırmak için kullanılıyor.
///
///     KD_SNAPSHOT_DIR=/tmp/kd .build/debug/KDDownloadManager
///
/// `KD_SNAPSHOT_STORE=1`: Chrome Web Mağazası görselleri için marka ve kişi adı geçmeyen örnek liste
/// (ChromeExtension/store/make-assets.sh).
@MainActor
enum DebugSnapshot {
    static func runIfRequested() {
        guard let dir = ProcessInfo.processInfo.environment["KD_SNAPSHOT_DIR"] else { return }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let forStore = ProcessInfo.processInfo.environment["KD_SNAPSHOT_STORE"] != nil
        let engine = MockDownloadEngine()
        let store = DownloadStore(engine: engine, seedSamples: !forStore)
        if forStore {
            store.items = storeSamples()
            store.items.filter { $0.status != .completed }.forEach(engine.start)
        }
        store.panelVisible = true

        Task {
            // Sahte motor birkaç adım ilerlesin ki hızlar dolu görünsün.
            try? await Task.sleep(for: .seconds(1.2))
            // KD_UPDATE_API verildiyse yeni sürüm bulunmuş hali (listedeki band ve Ayarlar'daki bölüm).
            if ProcessInfo.processInfo.environment["KD_UPDATE_API"] != nil {
                await AppUpdater.shared.check()
                for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                    let section = AppUpdateSettings().padding(Theme.margin).toggleStyle(.switch).environment(store)
                    await render(section, appearance: appearance, height: 330,
                                 to: folder.appendingPathComponent("update-\(suffix).png"))
                }
            }
            let screens: [(String, DownloadStore.Route, ListTab)] = [
                ("list", .list, .active),
                ("completed", .list, .completed),
                ("add-link", .addLink, .active),
                ("settings", .settings, .active),
                ("onboarding", .onboarding, .active)
            ]
            for (name, route, tab) in screens {
                store.route = route
                store.tab = tab
                for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                    await render(store, appearance: appearance, to: folder.appendingPathComponent("\(name)-\(suffix).png"))
                }
            }
            // Ayarların tamamı (kaydırmadan görünmeyen bölümler dahil); uzun metinlerin taşmasını denetlemek için.
            store.route = .settings
            for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                await render(SettingsView().environment(store), appearance: appearance, height: 2600,
                             to: folder.appendingPathComponent("settings-all-\(suffix).png"))
            }
            exit(0)
        }
    }

    /// Mağaza görselleri için örnek indirmeler; arayüzün dilinde.
    private static func storeSamples() -> [DownloadItem] {
        let mb: Int64 = 1_048_576
        let english = AppLanguage.current == "en"
        func item(_ name: String, _ trName: String, _ size: Int64, _ percent: Int64, _ status: DownloadStatus = .downloading,
                  host: String = "files.example.com") -> DownloadItem {
            DownloadItem(url: "https://\(host)/\(english ? name : trName)", totalBytes: size * mb,
                         downloadedBytes: size * mb * percent / 100, status: status)
        }
        return [
            item("Mountain_Timelapse_4K.mp4", "Dag_Manzarasi_4K.mp4", 2_150, 58, host: "videos.example.com"),
            item("Photo_Library_2026.zip", "Fotograf_Arsivi_2026.zip", 3_400, 31),
            item("Podcast_Episode_42.mp3", "Podcast_Bolum_42.mp3", 64, 12, .paused),
            item("Annual_Report_2026.pdf", "Yillik_Rapor_2026.pdf", 18, 100, .completed),
            item("City_Skyline.webp", "Sehir_Silueti.webp", 2, 100, .completed),
            item("Project_Files_v2.zip", "Proje_Dosyalari_v2.zip", 220, 100, .completed),
            item("Conference_Talk.mp4", "Konferans_Konusmasi.mp4", 860, 100, .completed, host: "videos.example.com")
        ]
    }

    private static func render(_ store: DownloadStore, appearance: NSAppearance.Name, to url: URL) async {
        await render(PanelView().environment(store), appearance: appearance, height: Theme.panelHeight, to: url)
    }

    private static func render(_ view: some View, appearance: NSAppearance.Name, height: CGFloat, to url: URL) async {
        let size = CGSize(width: Theme.panelWidth, height: height)
        let hosting = NSHostingView(rootView: view.background(Theme.windowSolid))
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.appearance = NSAppearance(named: appearance)

        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        // SwiftUI'nin ilk çizimi bir sonraki döngüde tamamlanıyor.
        try? await Task.sleep(for: .milliseconds(300))

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.close()
    }
}
#endif
