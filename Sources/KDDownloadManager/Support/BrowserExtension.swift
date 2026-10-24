import AppKit
import UniformTypeIdentifiers

/// Tarayıcı eklentisinin kurulumu: Chromium tabanlı tarayıcılar (Chrome, Edge, Brave, Arc…) aynı
/// eklentiyi kullanır ve eklenti kimliği (manifest'teki "key") hepsinde aynıdır.
@MainActor
enum BrowserExtension {
    struct Browser: Identifiable {
        let name: String
        let appURL: URL
        /// O tarayıcının uzantılar sayfası (chrome://extensions vb.).
        let extensionsPage: String
        var id: String { name }
    }

    private static let candidates: [(name: String, bundleID: String, page: String)] = [
        ("Google Chrome", "com.google.Chrome", "chrome://extensions"),
        ("Microsoft Edge", "com.microsoft.edgemac", "edge://extensions"),
        ("Brave", "com.brave.Browser", "brave://extensions"),
        ("Arc", "company.thebrowser.Browser", "chrome://extensions"),
        ("Vivaldi", "com.vivaldi.Vivaldi", "vivaldi://extensions"),
        ("Opera", "com.operasoftware.Opera", "opera://extensions"),
        ("Chromium", "org.chromium.Chromium", "chrome://extensions")
    ]

    static var installedBrowsers: [Browser] {
        candidates.compactMap { candidate in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: candidate.bundleID).map {
                Browser(name: candidate.name, appURL: $0, extensionsPage: candidate.page)
            }
        }
    }

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
