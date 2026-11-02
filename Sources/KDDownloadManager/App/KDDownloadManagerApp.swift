import SwiftUI
import AppKit

@main
struct KDDownloadManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Menü çubuğu ikonu ve paneli AppDelegate'teki StatusItemController kuruyor. SwiftUI bir sahne
    /// istediği için menü çubuğuna hiç eklenmeyen boş bir sahne veriliyor. (Boş bir Settings sahnesi
    /// ⌘, ile, bildirime tıklanınca ya da uygulama yeniden açılınca boş bir "Ayarlar" penceresi açıyordu.)
    var body: some Scene {
        MenuBarExtra("KD Download Manager", isInserted: .constant(false)) {
            EmptyView()
        }
    }
}

/// Liste ve Chrome köprüsü burada yaşıyor: panel hiç açılmasa da uygulama açılır açılmaz çalışmalılar.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// SwiftUI sahneyi açılış bildiriminden önce de kurabildiği için ayar taşıma burada, ilk erişimde yapılıyor.
    lazy var store: DownloadStore = {
        SettingsKey.importDevelopmentSettings()
        #if DEBUG
        if DebugPanel.screen != nil {
            let store = DownloadStore(engine: MockDownloadEngine(), seedSamples: true)
            DebugPanel.configure(store)
            return store
        }
        #endif
        return DownloadStore(
            engine: RoutingEngine(files: Aria2Engine(), videos: YtDlpEngine()),
            archive: AppDelegate.archive
        )
    }()
    private var bridge: ExtensionBridge?
    private var statusController: StatusItemController?

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
        Notifier.shared.setUp()
        AppTheme.apply()
        let statusController = StatusItemController(store: store)
        self.statusController = statusController
        #if DEBUG
        DebugPanel.runIfRequested { statusController.open() }
        DebugSnapshot.runIfRequested()
        DebugEngineTest.runIfRequested()
        DebugPersistenceTest.runIfRequested()
        DebugLimitTest.runIfRequested()
        DebugTorrentTest.runIfRequested()
        DebugUpdateTest.runIfRequested()
        // Senaryolar çalışırken asıl uygulamanın portunu işgal etmesinler.
        if DebugHarness.isActive { return }
        #endif

        let bridge = ExtensionBridge(
            onAdd: { [store] requests in store.add(requests) },
            onHello: { [store] browser in store.extensionDidConnect(browser) }
        )
        bridge.start()
        self.bridge = bridge
        // Gömülü yt-dlp'yi günde en fazla bir kez sessizce denetle (Ayarlar'dan kapatılabilir).
        YtDlpUpdater.removeOldVersions()
        YtDlpUpdater.shared.checkAutomaticallyIfDue()
        // Kurulu tarayıcı eklentisi uygulamayla birlikte güncellensin (tarayıcı yeniden açılınca alır).
        if FileManager.default.fileExists(atPath: BrowserExtension.folder.path) {
            BrowserExtension.refreshFolder()
        }
    }

    /// Uygulama zaten açıkken yeniden açılırsa (Finder, Launchpad, Spotlight) paneli göster.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusController?.open()
        return false
    }

    /// Finder'dan açılan .torrent dosyaları ve tarayıcılardan gelen magnet: linkleri
    /// (Info.plist'teki dosya türü ve adres şeması kayıtları sayesinde).
    func application(_ application: NSApplication, open urls: [URL]) {
        store.open(urls)
    }
}
