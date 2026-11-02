#if DEBUG
import SwiftUI
import AppKit

/// Geliştirme aracı: `KD_SNAPSHOT_DIR` ayarlıysa paneli her ekran için
/// açık/koyu PNG olarak bu klasöre çizer ve uygulamadan çıkar.
/// Ekran kaydı izni gerektirmez; tasarımla karşılaştırmak için kullanılıyor.
///
///     KD_SNAPSHOT_DIR=/tmp/kd .build/debug/KDDownloadManager
@MainActor
enum DebugSnapshot {
    static func runIfRequested() {
        guard let dir = ProcessInfo.processInfo.environment["KD_SNAPSHOT_DIR"] else { return }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = DownloadStore(engine: MockDownloadEngine(), seedSamples: true)
        store.panelVisible = true

        Task {
            // Sahte motor birkaç adım ilerlesin ki hızlar dolu görünsün.
            try? await Task.sleep(for: .seconds(1.2))
            let screens: [(String, DownloadStore.Route, ListTab)] = [
                ("list", .list, .active),
                ("completed", .list, .completed),
                ("add-link", .addLink, .active),
                ("settings", .settings, .active)
            ]
            for (name, route, tab) in screens {
                store.route = route
                store.tab = tab
                for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                    await render(store, appearance: appearance, to: folder.appendingPathComponent("\(name)-\(suffix).png"))
                }
            }
            exit(0)
        }
    }

    private static func render(_ store: DownloadStore, appearance: NSAppearance.Name, to url: URL) async {
        let size = CGSize(width: Theme.panelWidth, height: Theme.panelHeight)
        let hosting = NSHostingView(rootView: PanelView().environment(store))
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
