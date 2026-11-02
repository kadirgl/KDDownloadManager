import Foundation
import AppKit
import Observation

/// Uygulamanın tek durum kaynağı: liste, filtreler, ekran yönlendirmesi.
@MainActor
@Observable
final class DownloadStore {
    enum Route {
        case list, addLink, settings, onboarding
    }

    var items: [DownloadItem] = []
    var category: DownloadCategory = .all
    var tab: ListTab = .active
    var route: Route = .list
    /// Ayarlar'da "Kur"a basılan tarayıcı; kurulum ekranı onun için açılır (nil: Chrome ya da ilk bulunan).
    var onboardingBrowser: String?
    /// Tarayıcı eklentilerinin en son ne zaman bağlandığı (Ayarlar'daki durum için); kalıcı.
    private(set) var extensionSeen: [String: Date] =
        UserDefaults.standard.dictionary(forKey: SettingsKey.extensionSeen) as? [String: Date] ?? [:]

    @ObservationIgnored private let engine: any DownloadEngine
    @ObservationIgnored private let archive: DownloadArchive?
    @ObservationIgnored private var lastSaved: Data?
    @ObservationIgnored private var autosave: Task<Void, Never>?
    /// "Devam eden vardı → kalmadı" geçişini yakalamak için.
    @ObservationIgnored private var hadActive = false
    /// Son kayıttan beri bir indirmenin durumu değişti mi (otomatik kayıt için).
    @ObservationIgnored private var statusChangedSinceSave = false
    @ObservationIgnored private var speedTicker: Task<Void, Never>?
    /// Bildirimler için her indirmenin son bilinen durumu (tamamlandı/başarısız geçişlerini yakalamak).
    @ObservationIgnored private var lastStatuses: [UUID: DownloadStatus] = [:]

    /// Menü çubuğunda ve alt şeritte gösterilen toplam hız: saniyede bir güncellenen, yumuşatılmış
    /// değer. Ham değer yarım saniyede bir zıplayıp durduğu için kullanıcıya "bir sorun var" hissi veriyordu.
    private(set) var displaySpeed: Int64 = 0
    /// Yeni ölçümün ağırlığı (üstel hareketli ortalama).
    private static let speedSmoothing = 0.35

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
            // Devam eden bir şey yoksa liste tamamlananlarla açılsın.
            showCompletedIfIdle()
            NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.save() }
            }
        }
        hadActive = hasActive
        lastStatuses = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.status) })
        watchActivity()
        startSpeedTicker()
    }

    private func startSpeedTicker() {
        speedTicker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.updateDisplaySpeed()
            }
        }
    }

    private func updateDisplaySpeed() {
        let raw = totalSpeed
        // İndirme yokken (ya da hepsi duraklatılınca) hemen sıfırla; yavaşça sönmesin.
        let next = raw == 0 ? 0 : Int64(Double(displaySpeed) * (1 - Self.speedSmoothing) + Double(raw) * Self.speedSmoothing)
        if next != displaySpeed { displaySpeed = next }
    }

    private var hasActive: Bool { items.contains { ListTab.active.includes($0.status) } }

    /// İlk açılış: hiçbir tarayıcı eklentisi bağlanmadıysa ve "Şimdilik geç" denmediyse kurulum ekranı.
    var needsOnboarding: Bool {
        extensionSeen.isEmpty && !UserDefaults.standard.bool(forKey: SettingsKey.onboardingSkipped)
    }

    /// Panel açılırken: gerekiyorsa eklenti kurulumu, değilse boştayken "Tamamlanan".
    func panelWillOpen() {
        if route == .list, needsOnboarding, !Self.isHarness {
            route = .onboarding
        }
        showCompletedIfIdle()
    }

    func skipOnboarding() {
        UserDefaults.standard.set(true, forKey: SettingsKey.onboardingSkipped)
        route = .list
    }

    /// Geliştirme senaryolarında kurulum ekranı kendiliğinden açılmasın.
    private static var isHarness: Bool {
        #if DEBUG
        return DebugHarness.isActive
        #else
        return false
        #endif
    }

    /// Devam eden indirme yoksa ve tamamlanan varsa "Tamamlanan" sekmesine geçer (panel açılırken).
    func showCompletedIfIdle() {
        guard route == .list, !hasActive, items.contains(where: { $0.status == .completed }) else { return }
        tab = .completed
    }

    /// Devam eden son indirme bitince (ya da iptal edilince) "Tamamlanan" sekmesine geçer.
    /// Sadece geçiş anında; kullanıcı sonra "Devam Eden"e dönerse zorla geri götürülmez.
    private func watchActivity() {
        withObservationTracking {
            _ = items.map(\.status)
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                let active = self.hasActive
                if self.hadActive, !active {
                    self.showCompletedIfIdle()
                }
                self.hadActive = active
                self.statusChangedSinceSave = true
                self.notifyStatusChanges()
                self.watchActivity()
            }
        }
    }

    /// Tamamlanan ve (otomatik denemeler bittikten sonra) başarısız olan indirmeler için bildirim.
    private func notifyStatusChanges() {
        var current: [UUID: DownloadStatus] = [:]
        for item in items {
            current[item.id] = item.status
            guard let previous = lastStatuses[item.id], previous != item.status else { continue }
            switch item.status {
            case .completed:
                Notifier.shared.downloadFinished(item)
            case .failed(let message):
                if case .failed = previous { break }
                Notifier.shared.downloadFailed(item, message: message)
            default:
                break
            }
        }
        lastStatuses = current
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

    /// Her satırdaki linki ayrı bir indirme olarak ekler; video linkleri `quality` kalitesinde iner.
    /// `speedLimit` indirme başına sınır; `startPaused` ise ("Hemen başlat" kapalı) duraklatılmış eklenir.
    func add(links text: String, quality: VideoQuality = .auto, speedLimit: Int64? = nil, startPaused: Bool = false) {
        let requests = Self.parseLinks(text).map { DownloadRequest(url: $0, quality: quality) }
        insert(requests.filter { DownloadSource.looksLikeLink($0.url) }, speedLimit: speedLimit, startPaused: startPaused)
    }

    /// Panelden ya da Chrome eklentisinden gelen istekleri ekler; link olmayanları atlar.
    func add(_ requests: [DownloadRequest]) {
        insert(requests.filter { DownloadSource.looksLikeLink($0.url) })
    }

    /// Finder'dan açılan, panele sürüklenen ya da tarayıcıdan gelen (magnet:) adresleri ekler.
    func open(_ urls: [URL]) {
        let torrents = urls.filter { $0.isFileURL && $0.pathExtension.lowercased() == "torrent" }
        addTorrentFiles(torrents)
        add(urls.filter { !$0.isFileURL }.map { DownloadRequest(url: $0.absoluteString) })
    }

    /// Diskteki .torrent dosyalarını ekler. Dosya uygulamanın klasörüne kopyalanır; asıl dosya
    /// silinse ya da taşınsa da indirme (uygulama yeniden açıldıktan sonra da) devam ettirilebilsin.
    func addTorrentFiles(_ files: [URL]) {
        let requests = files.compactMap { file -> DownloadRequest? in
            let copy = AppFolders.torrents.appendingPathComponent(UUID().uuidString + ".torrent")
            guard (try? FileManager.default.copyItem(at: file, to: copy)) != nil else { return nil }
            return DownloadRequest(url: copy.absoluteString, filename: file.deletingPathExtension().lastPathComponent)
        }
        insert(requests)
    }

    private func insert(_ requests: [DownloadRequest], speedLimit: Int64? = nil, startPaused: Bool = false) {
        guard !requests.isEmpty else { return }
        var names: [String] = []
        for request in requests {
            let saveAs = request.saveAs.map(Self.sanitizedFileName).flatMap { $0.isEmpty ? nil : $0 }
            let name = saveAs ?? request.filename.flatMap { $0.isEmpty ? nil : $0 }
            let item = DownloadItem(url: request.url.trimmingCharacters(in: .whitespacesAndNewlines), fileName: name,
                                    forceVideo: request.video == true)
            item.preferredName = saveAs
            item.referrer = request.referrer
            item.userAgent = request.userAgent
            item.cookies = request.cookies
            item.quality = request.quality ?? .auto
            if let jar = request.cookieJar, let site = CookieVault.site(of: item.url) {
                CookieVault.shared.store(jar, for: site)
            }
            item.speedLimit = speedLimit
            items.insert(item, at: 0)
            if startPaused {
                // Motor duraklatılmış ve hiç başlamamış indirmeyi "devam et"te sıfırdan ekliyor.
                item.status = .paused
            } else {
                engine.start(item)
            }
            names.append(item.fileName)
        }
        Notifier.shared.downloadsAdded(names)
        tab = .active
        category = .all
        route = .list
        save()
    }

    /// "Tümünü duraklat" / "Tümünü devam ettir".
    var allActivePaused: Bool {
        let active = items.filter { ListTab.active.includes($0.status) && !$0.isFailed }
        return !active.isEmpty && active.allSatisfy { $0.status == .paused }
    }

    func pauseAll() {
        for item in items where [.downloading, .queued, .processing].contains(item.status) {
            engine.pause(item)
        }
    }

    func resumeAll() {
        for item in items where item.status == .paused {
            engine.resume(item)
        }
    }

    func retryFailed() {
        for item in items where item.isFailed {
            engine.resume(item)
        }
    }

    /// Tamamlananları listeden kaldırır; dosyalar diskte kalır.
    func clearCompleted() {
        items.removeAll { $0.status == .completed }
        save()
    }

    func togglePause(_ item: DownloadItem) {
        switch item.status {
        case .downloading, .queued, .processing: engine.pause(item)
        case .paused, .failed: engine.resume(item)
        case .completed: break
        }
    }

    func cancel(_ item: DownloadItem) {
        engine.cancel(item)
        items.removeAll { $0.id == item.id }
        // Diskten eklenmiş torrent'in bizim kopyamızı da sil (kullanıcının asıl dosyasına dokunulmaz).
        if let file = URL(string: item.url), file.isFileURL,
           file.deletingLastPathComponent().standardizedFileURL == AppFolders.torrents.standardizedFileURL {
            try? FileManager.default.removeItem(at: file)
        }
        save()
    }

    func setSpeedLimit(_ limit: Int64?, for item: DownloadItem) {
        engine.setSpeedLimit(limit, for: item)
        // Duraklatılmış bir indirmenin sınırı değişince de kaydedilsin (otomatik kayıt boşta çalışmıyor).
        save()
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

    /// Eklenti kendini bildirdi (açılışta ve dakikada bir).
    func extensionDidConnect(_ browser: String) {
        extensionSeen[browser] = Date()
        UserDefaults.standard.set(extensionSeen, forKey: SettingsKey.extensionSeen)
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
                guard let self else { return }
                // Boşta (inen yok, durum değişmedi) listeyi her 2 sn'de JSON'a çevirmeye gerek yok.
                guard self.hasActive || self.statusChangedSinceSave else { continue }
                self.statusChangedSinceSave = false
                self.save()
            }
        }
    }

    // MARK: - Yardımcılar

    /// Dosya adında olamayacak karakterleri (/ : ve kontrol karakterleri) temizler, boyu sınırlar.
    static func sanitizedFileName(_ name: String) -> String {
        let cleaned = name.unicodeScalars.map { scalar -> String in
            if scalar == "/" || scalar == ":" || CharacterSet.controlCharacters.contains(scalar) { return "-" }
            return String(scalar)
        }.joined()
        return String(cleaned.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "."))).prefix(150))
    }

    static func parseLinks(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter(DownloadSource.looksLikeLink)
    }

    private static var savedGlobalLimit: Int64? {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: SettingsKey.globalLimitEnabled) else { return nil }
        let mb = defaults.object(forKey: SettingsKey.globalLimitMB) as? Double ?? SettingsKey.defaultGlobalLimitMB
        return Int64(mb * 1_048_576)
    }

    private static var savedMaxConcurrent: Int {
        UserDefaults.standard.object(forKey: SettingsKey.maxConcurrent) as? Int ?? SettingsKey.defaultMaxConcurrent
    }
}
