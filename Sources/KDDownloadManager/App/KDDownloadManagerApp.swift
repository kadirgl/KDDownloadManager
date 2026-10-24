import SwiftUI
import AppKit

@main
struct KDDownloadManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environment(appDelegate.store)
        } label: {
            MenuBarLabel(store: appDelegate.store)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Liste ve Chrome köprüsü burada yaşıyor: panel hiç açılmasa da uygulama açılır açılmaz çalışmalılar.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// SwiftUI sahneyi açılış bildiriminden önce de kurabildiği için ayar taşıma burada, ilk erişimde yapılıyor.
    lazy var store: DownloadStore = {
        SettingsKey.importDevelopmentSettings()
        return DownloadStore(
            engine: RoutingEngine(files: Aria2Engine(), videos: YtDlpEngine()),
            archive: AppDelegate.archive
        )
    }()
    private var bridge: ExtensionBridge?

    private static var archive: DownloadArchive? {
        #if DEBUG
        // Geliştirme senaryoları kendi listeleriyle çalışır; gerçek listeye dokunmasınlar.
        if DebugHarness.isActive { return nil }
        #endif
        return .standard
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // .app paketinde Info.plist'teki LSUIElement bunu zaten sağlıyor;
        // `swift run` ile çalışırken de Dock ikonu çıkmasın diye burada da ayarlıyoruz.
        NSApp.setActivationPolicy(.accessory)
        #if DEBUG
        DebugSnapshot.runIfRequested()
        DebugEngineTest.runIfRequested()
        DebugPersistenceTest.runIfRequested()
        // Senaryolar çalışırken asıl uygulamanın portunu işgal etmesinler.
        if DebugHarness.isActive { return }
        #endif

        let bridge = ExtensionBridge { [store] requests in
            store.add(requests)
        }
        bridge.start()
        self.bridge = bridge
    }
}
