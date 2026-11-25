import AppKit
import UniformTypeIdentifiers

/// Tarayıcı eklentisinin kurulumu: Chromium tabanlı tarayıcılar (Chrome, Edge, Brave, Arc…) aynı eklentiyi
/// kullanır. Eklenti Chrome Web Mağazası'ndan kurulur; mağazayı kullanamayanlar için uygulamayla gelen kopya
/// geliştirici modundan ("paketlenmemiş öğe") yüklenebilir. İki kopyanın kimliği farklıdır, ikisi de kabul edilir.
@MainActor
enum BrowserExtension {
    struct Browser: Identifiable {
        let name: String
        let appURL: URL
        let bundleID: String
        /// O tarayıcının uzantılar sayfası (chrome://extensions vb.).
        let extensionsPage: String
        /// Profil klasörlerinin bulunduğu yer (~/Library/Application Support altında).
        let dataFolder: URL
        var id: String { name }

        var isRunning: Bool {
            !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
        }
    }

    /// Chrome Web Mağazası'nın eklentiye verdiği kimlik (Geliştirici Panosu > öğe > Paket). Mağazada öğe
    /// oluşturulunca buraya yazılır (`scripts/chrome-store.sh set-id <kimlik>` Windows'takini de doldurur).
    /// Boşken kurulum ekranları geliştirici modundan yüklemeyi gösterir.
    nonisolated static let storeExtensionID = "cfpaffdmeoohjngkkfabjdcjhlgjaedd"

    /// Uygulamayla gelen paketlenmemiş kopyanın kimliği; depodaki manifest'in "key" alanı sayesinde her
    /// tarayıcıda aynı. Bu kopyayı kullananlar mağazaya geçene kadar çalışmaya devam etsin diye kabul ediliyor.
    nonisolated static let unpackedExtensionID = "necbfaijhfnnoikbppjdjcpfjekefdbk"

    /// Uygulamanın istek kabul ettiği eklenti kimlikleri (ExtensionBridge.allowedOrigins).
    nonisolated static var extensionIDs: [String] {
        [storeExtensionID, unpackedExtensionID].filter { !$0.isEmpty }
    }

    /// Mağaza kaydı incelemeden geçip yayımlandı mı? Yayımlanana kadar kurulum ekranları uygulamayla gelen
    /// kopyayı (geliştirici modu) gösterir; mağaza kimliği yine de kabul edilir. Onaydan sonra true yapılır
    /// (`scripts/chrome-store.sh live` Windows'takini de değiştirir).
    nonisolated static let storeListingLive = false

    /// Eklentinin Chrome Web Mağazası sayfası; mağaza kaydı yayımlanmadıysa nil.
    static var storeURL: URL? {
        guard storeListingLive, !storeExtensionID.isEmpty else { return nil }
        return URL(string: "https://chromewebstore.google.com/detail/\(storeExtensionID)")
    }

    /// Mağaza sayfasını o tarayıcıda açar (Edge ve Opera da Chrome Web Mağazası'ndan eklenti kurabiliyor).
    static func openStorePage(in browser: Browser) -> Bool {
        guard let storeURL else { return false }
        NSWorkspace.shared.open([storeURL], withApplicationAt: browser.appURL, configuration: NSWorkspace.OpenConfiguration())
        return true
    }

    private static let candidates: [(name: String, bundleID: String, page: String, data: String)] = [
        ("Google Chrome", "com.google.Chrome", "chrome://extensions", "Google/Chrome"),
        ("Microsoft Edge", "com.microsoft.edgemac", "edge://extensions", "Microsoft Edge"),
        ("Brave", "com.brave.Browser", "brave://extensions", "BraveSoftware/Brave-Browser"),
        ("Arc", "company.thebrowser.Browser", "chrome://extensions", "Arc/User Data"),
        ("Vivaldi", "com.vivaldi.Vivaldi", "vivaldi://extensions", "Vivaldi"),
        ("Opera", "com.operasoftware.Opera", "opera://extensions", "com.operasoftware.Opera"),
        ("Chromium", "org.chromium.Chromium", "chrome://extensions", "Chromium")
    ]

    private static var browserDataRoot: URL {
        #if DEBUG
        // Denemelerde gerçek tarayıcı profillerine bakılmasın diye sahte bir klasör verilebilir.
        if let path = ProcessInfo.processInfo.environment["KD_BROWSER_DATA"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        #endif
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    /// Kurulu tarayıcılar; durum bandı birkaç saniyede bir sorduğu için yarım dakika önbellekte tutulur.
    static var installedBrowsers: [Browser] {
        if let cached = browserCache, Date().timeIntervalSince(cached.date) < 30 { return cached.browsers }
        let browsers = findInstalledBrowsers()
        browserCache = (Date(), browsers)
        return browsers
    }

    private static var browserCache: (date: Date, browsers: [Browser])?

    private static func findInstalledBrowsers() -> [Browser] {
        candidates.compactMap { candidate in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: candidate.bundleID).map {
                Browser(name: candidate.name, appURL: $0, bundleID: candidate.bundleID, extensionsPage: candidate.page,
                        dataFolder: browserDataRoot.appendingPathComponent(candidate.data, isDirectory: true))
            }
        }
    }

    // MARK: - Kurulu mu?

    enum InstallState {
        case installed, disabled, notInstalled
        /// Profil ayarları okunamadı; eklentinin sinyaline bakılır.
        case unknown
    }

    struct InstallInfo {
        var state: InstallState
        /// Tarayıcının bu bilgiyi diske en son yazdığı an.
        var written: Date?
        /// Mağaza kopyası kurulu ve açık.
        var fromStore = false
        /// Geliştirici modunda yüklenen kopya kurulu ve açık.
        var unpacked = false
    }

    /// Tarayıcının profil ayarlarında (Preferences / Secure Preferences) eklentinin kaydı var mı. Eklenti
    /// kaldırılınca kayıt hemen silindiği için "kurulu" görünmeye devam etmiyor. Yalnızca eklentinin
    /// kimliklerine bakılır; dosyalar değiştikçe yeniden okunur.
    static func installState(in browser: Browser) -> InstallState {
        installInfo(in: browser).state
    }

    /// Kurulum durumu ve tarayıcının bu bilgiyi diske en son ne zaman yazdığı. Chrome ayarları kurulumdan
    /// birkaç saniye sonra yazıyor; o arada gelen eklenti sinyali dosyadan daha yeni bilgi sayılır.
    static func installInfo(in browser: Browser) -> InstallInfo {
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(atPath: browser.dataFolder.path) else { return InstallInfo(state: .unknown) }
        // Opera'da profil klasörün kendisi; diğerlerinde "Default", "Profile 1"…
        let profiles = [browser.dataFolder] + entries
            .filter { $0 == "Default" || $0.hasPrefix("Profile ") }
            .map { browser.dataFolder.appendingPathComponent($0, isDirectory: true) }
        var readAny = false
        var disabled = false
        var info = InstallInfo(state: .notInstalled)
        for profile in profiles {
            for file in ["Secure Preferences", "Preferences"] {
                guard let (settings, modified) = extensionSettings(at: profile.appendingPathComponent(file)) else { continue }
                readAny = true
                info.written = max(info.written ?? modified, modified)
                for id in extensionIDs {
                    // Chrome eklenti kaldırılınca kaydı silmiyor, içi boş bırakıyor; klasörü ya da konumu olmayan
                    // kayıt kurulu sayılmaz.
                    guard let entry = settings[id] as? [String: Any],
                          entry["path"] != nil || entry["location"] != nil else { continue }
                    if isDisabled(entry) {
                        disabled = true
                    } else if id == unpackedExtensionID {
                        info.unpacked = true
                    } else {
                        info.fromStore = true
                    }
                }
            }
        }
        info.state = if info.fromStore || info.unpacked { .installed } else if disabled { .disabled } else if readAny { .notInstalled } else { .unknown }
        return info
    }

    private static func isDisabled(_ entry: [String: Any]) -> Bool {
        if let state = entry["state"] as? Int, state == 0 { return true }
        if let reasons = entry["disable_reasons"] as? Int { return reasons != 0 }
        if let reasons = entry["disable_reasons"] as? [Any] { return !reasons.isEmpty }
        return false
    }

    /// Dosya değişmedikçe yeniden ayrıştırılmasın (birkaç MB olabiliyor).
    private static var cache: [URL: (modified: Date, settings: [String: Any])] = [:]

    private static func extensionSettings(at file: URL) -> (settings: [String: Any], modified: Date)? {
        guard let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else {
            return nil
        }
        if let cached = cache[file], cached.modified == modified { return (cached.settings, modified) }
        guard let data = try? Data(contentsOf: file),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let settings = (root["extensions"] as? [String: Any])?["settings"] as? [String: Any] ?? [:]
        cache[file] = (modified, settings)
        return (settings, modified)
    }

    /// Kendini markasıyla bildiremeyen tarayıcılar (Arc, Vivaldi, Chromium) eklentide bu adla görünüyor.
    static let unnamedBrowser = "Chromium tabanlı tarayıcı"
    static let unnamedBrowsers: Set<String> = ["Arc", "Vivaldi", "Chromium"]

    // MARK: - Geliştirici modundan kurulum (mağazayı kullanamayanlar için)

    /// Tarayıcıya "paketlenmemiş öğe" olarak yüklenen klasör. Uygulama güncellenince yeni sürüm
    /// buraya kopyalanır; tarayıcı bir sonraki açılışında (ya da uzantılar sayfasında yenileyince) alır.
    static var folder: URL {
        AppFolders.support.appendingPathComponent("BrowserExtension", isDirectory: true)
    }

    /// Eklentinin uygulamayla gelen kaynağı: .app içinde Resources/BrowserExtension,
    /// `swift run` ile çalışırken depodaki ChromeExtension klasörü.
    private static var source: URL? {
        if let bundled = Bundle.main.url(forResource: "BrowserExtension", withExtension: nil) {
            return bundled
        }
        #if DEBUG
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let folder = repository.appendingPathComponent("ChromeExtension")
        return FileManager.default.fileExists(atPath: folder.path) ? folder : nil
        #else
        return nil
        #endif
    }

    /// Kurulum klasörü yoksa ya da sürümü uygulamanınkinden farklıysa günceller.
    /// Uygulama açılışında da çağrılır; kurulu eklenti böylece uygulamayla birlikte güncellenir.
    @discardableResult
    static func refreshFolder() -> Bool {
        guard let source else { return false }
        let manager = FileManager.default
        if version(at: folder) == version(at: source), version(at: source) != nil {
            return true
        }
        let staging = folder.deletingLastPathComponent().appendingPathComponent("BrowserExtension.new", isDirectory: true)
        try? manager.removeItem(at: staging)
        guard (try? manager.copyItem(at: source, to: staging)) != nil else { return false }
        if manager.fileExists(atPath: folder.path) {
            return (try? manager.replaceItemAt(folder, withItemAt: staging)) != nil
        }
        return (try? manager.moveItem(at: staging, to: folder)) != nil
    }

    /// Tarayıcının yüklediği klasördeki eklentinin sürümü; eklenti kendi sürümü bundan eskiyse kendini
    /// yeniden yükler (uygulama güncellenince klasör de yenileniyor).
    static var installedVersion: String? { version(at: folder) }

    private static func version(at folder: URL) -> String? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")),
              let manifest = try? JSONDecoder().decode(JSONValue.self, from: data) else { return nil }
        return manifest["version"]?.stringValue
    }

    /// Kurulumu başlatır: klasörü hazırlar, yolunu panoya kopyalar, Finder'da gösterir ve
    /// tarayıcının uzantılar sayfasını açar. Son adımı (Geliştirici modu + "Paketlenmemiş öğe yükle")
    /// tarayıcılar güvenlik gereği kullanıcıya bırakıyor.
    static func beginInstall(in browser: Browser) -> Bool {
        guard refreshFolder() else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(folder.path, forType: .string)
        NSWorkspace.shared.activateFileViewerSelecting([folder])
        if let page = URL(string: browser.extensionsPage) {
            NSWorkspace.shared.open([page], withApplicationAt: browser.appURL, configuration: NSWorkspace.OpenConfiguration())
        }
        return true
    }
}

/// Magnet linkleri ve .torrent dosyaları için varsayılan uygulama ayarı. Eklentisi olmayan
/// tarayıcılarda (Safari) magnet linklerinin uygulamaya gelmesini bu sağlar.
@MainActor
enum TorrentHandler {
    private static let probe = URL(string: "magnet:?xt=urn:btih:0")!

    /// Sadece .app paketinden çalışırken kullanılabilir; macOS dosya/adres kayıtlarını paketten okur.
    static var isAvailable: Bool { LaunchAtLogin.isAvailable }

    /// Şu an magnet linklerini açan uygulamanın adı (yoksa nil).
    static var currentHandlerName: String? {
        NSWorkspace.shared.urlForApplication(toOpen: probe).map {
            FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "")
        }
    }

    static var isDefault: Bool {
        NSWorkspace.shared.urlForApplication(toOpen: probe)?.standardizedFileURL
            == Bundle.main.bundleURL.standardizedFileURL
    }

    static func makeDefault() async throws {
        let app = Bundle.main.bundleURL
        try await NSWorkspace.shared.setDefaultApplication(at: app, toOpenURLsWithScheme: "magnet")
        if let torrent = UTType(filenameExtension: "torrent") {
            try await NSWorkspace.shared.setDefaultApplication(at: app, toOpen: torrent)
        }
    }
}
