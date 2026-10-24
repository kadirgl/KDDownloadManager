import SwiftUI
import AppKit

@main
struct KDDownloadManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = DownloadStore(
        engine: RoutingEngine(files: Aria2Engine(), videos: YtDlpEngine()),
        archive: KDDownloadManagerApp.archive
    )

    private static var archive: DownloadArchive? {
        #if DEBUG
        // Geliştirme senaryoları kendi listeleriyle çalışır; gerçek listeye dokunmasınlar.
        if DebugHarness.isActive { return nil }
        #endif
        return .standard
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environment(store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // .app paketinde Info.plist'teki LSUIElement bunu zaten sağlıyor;
        // `swift run` ile çalışırken de Dock ikonu çıkmasın diye burada da ayarlıyoruz.
        NSApp.setActivationPolicy(.accessory)
        #if DEBUG
        DebugSnapshot.runIfRequested()
        DebugEngineTest.runIfRequested()
        DebugPersistenceTest.runIfRequested()
        #endif
    }
}
