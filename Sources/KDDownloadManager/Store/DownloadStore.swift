import Foundation
import AppKit
import Observation

/// Uygulamanın tek durum kaynağı: liste, filtreler, ekran yönlendirmesi.
@MainActor
@Observable
final class DownloadStore {
    enum Route {
        case list, addLink, settings
    }

    var items: [DownloadItem] = []
    var category: DownloadCategory = .all
    var tab: ListTab = .active
    var route: Route = .list

    @ObservationIgnored private let engine: any DownloadEngine
    @ObservationIgnored private let archive: DownloadArchive?
    @ObservationIgnored private var lastSaved: Data?
    @ObservationIgnored private var autosave: Task<Void, Never>?

    /// Liste değişikliklerini (ilerleme dahil) bu aralıkla diske yazar; değişmediyse yazmaz.
    private static let autosaveInterval = 2.0

    /// `archive` verilirse liste oradan yüklenir ve otomatik kaydedilir.
    init(engine: any DownloadEngine, seedSamples: Bool = false, archive: DownloadArchive? = nil) {
        self.engine = engine
        self.archive = archive
        engine.setGlobalSpeedLimit(Self.savedGlobalLimit)
        engine.setMaxConcurrent(Self.savedMaxConcurrent)
        if seedSamples {
            items = Self.sampleItems()
            items.filter { $0.status != .completed }.forEach(engine.start)
        }
        if let archive {
            items = archive.load()
            lastSaved = archive.encode(items)
            // Kapanırken inmekte olanlar kaldığı yerden devam etsin; duraklatılan ve hatalılar beklesin.
            items.filter { $0.status == .queued }.forEach(engine.start)
            startAutosave()
            NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.save() }
            }
        }
    }

    var visibleItems: [DownloadItem] {
        items.filter { tab.includes($0.status) && (category == .all || $0.category == category) }
    }

    var totalSpeed: Int64 {
        items.reduce(0) { $0 + $1.speed }
    }

    var downloadFolder: URL {
        SettingsKey.downloadFolderURL
    }

    // MARK: - İşlemler

    /// Her satırdaki linki ayrı bir indirme olarak ekler.
    func add(links text: String) {
        for link in Self.parseLinks(text) {
            let item = DownloadItem(url: link)
            items.insert(item, at: 0)
            engine.start(item)
        }
        tab = .active
        category = .all
        route = .list
        save()
    }

    func togglePause(_ item: DownloadItem) {
        switch item.status {
        case .downloading, .queued: engine.pause(item)
        case .paused, .failed: engine.resume(item)
        case .completed: break
        }
    }

    func cancel(_ item: DownloadItem) {
        engine.cancel(item)
        items.removeAll { $0.id == item.id }
        save()
    }

    func setSpeedLimit(_ limit: Int64?, for item: DownloadItem) {
        engine.setSpeedLimit(limit, for: item)
    }

    func applyGlobalSpeedLimit() {
        engine.setGlobalSpeedLimit(Self.savedGlobalLimit)
    }

    func applyMaxConcurrent() {
        engine.setMaxConcurrent(Self.savedMaxConcurrent)
    }

    func revealInFinder(_ item: DownloadItem) {
        if let destination = item.destination {
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } else {
            NSWorkspace.shared.open(item.folder)
        }
    }

    // MARK: - Kayıt

    /// Liste değiştiyse diske yazar.
    func save() {
        guard let archive else { return }
        let data = archive.encode(items)
        guard data != lastSaved else { return }
        archive.write(data)
        lastSaved = data
    }

    private func startAutosave() {
        autosave = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.autosaveInterval))
                self?.save()
            }
        }
    }

    // MARK: - Yardımcılar

    static func parseLinks(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter(DownloadSource.looksLikeLink)
    }

    private static var savedGlobalLimit: Int64? {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: SettingsKey.globalLimitEnabled) else { return nil }
        let mb = defaults.object(forKey: SettingsKey.globalLimitMB) as? Double ?? 5
        return Int64(mb * 1_048_576)
    }

    private static var savedMaxConcurrent: Int {
        UserDefaults.standard.object(forKey: SettingsKey.maxConcurrent) as? Int ?? SettingsKey.defaultMaxConcurrent
    }
}
