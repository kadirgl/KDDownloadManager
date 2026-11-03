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
    /// Panel ekranda mı. Kapalıyken içerik hiç çizilmiyor; gizli pencerede de her ilerlemede yeniden
    /// hesaplanıp çiziliyordu (açık panelden fazla işlemci).
    var panelVisible = false
    /// Liste kayarken satırlardaki hover butonları açılıp kapanmasın (imleç altından geçen her satırda
    /// düzen değişiyor, kaydırma takılıyordu).
    var isScrolling = false
    /// Ayarlar'da "Kur"a basılan tarayıcı; kurulum ekranı onun için açılır (nil: Chrome ya da ilk bulunan).
    var onboardingBrowser: String?
    /// Klavyeyle gezinme, Quick Look ve satır kısayolları için seçili satır.
    var selection: UUID?
    /// Tamamlanan'daki arama (dosya adı ve kaynak site).
    var searchText = ""
    var completedSort: CompletedSort =
        UserDefaults.standard.string(forKey: SettingsKey.completedSort).flatMap(CompletedSort.init) ?? .newest {
        didSet { UserDefaults.standard.set(completedSort.rawValue, forKey: SettingsKey.completedSort) }
    }
    /// Silinen ama "Geri al" süresi dolmamış indirme; süre bitince dosyası ve parçaları gerçekten silinir.
    private(set) var pendingDeletion: PendingDeletion?
    /// Devam eden son indirmenin bittiği an (menü çubuğundaki 3 sn'lik onay işareti için).
    private(set) var finishedAt: Date?

    struct PendingDeletion {
        let item: DownloadItem
        let index: Int
        /// Silinirken iniyordu; geri alınınca devam eder.
        let wasRunning: Bool
        /// Tamamlanmış dosya çöpe taşınacak (devam edenlerde yarım dosya silinir).
        let trashesFile: Bool
        let deadline: Date
    }

    static let undoWindow: TimeInterval = 5
    @ObservationIgnored private var deletionTask: Task<Void, Never>?
    /// Tarayıcı eklentilerinin en son ne zaman bağlandığı (Ayarlar'daki durum için); kalıcı.
    /// İki haftadır sinyal vermeyenler (eski sürümlerin adsız "Tarayıcı" kaydı gibi) unutulur.
    private(set) var extensionSeen: [String: Date] = {
        let saved = UserDefaults.standard.dictionary(forKey: SettingsKey.extensionSeen) as? [String: Date] ?? [:]
        return saved.filter { Date().timeIntervalSince($0.value) < 14 * 86_400 }
    }()

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
                MainActor.assumeIsolated {
                    self?.commitPendingDeletion(terminating: true)
                    self?.save()
                }
            }
        }
        hadActive = hasActive
        updateActivityAssertion()
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
        !extensionEverConnected && !UserDefaults.standard.bool(forKey: SettingsKey.onboardingSkipped)
    }

    var extensionEverConnected: Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.extensionEverConnected) || !extensionSeen.isEmpty
    }

    // MARK: - Tarayıcı eklentisi durumu

    enum ExtensionStatus: Equatable {
        case connected
        /// Tarayıcı kapalı; son sinyal zamanı.
        case browserClosed(Date?)
        /// Tarayıcı açık ama eklentiden sinyal gelmiyor.
        case notConnected(Date?)
        case disabled
        case notInstalled
    }

    /// Eklenti dakikada bir sinyal gönderiyor; biraz pay bırakarak "bağlı" sayılma süresi.
    static let extensionConnectedWindow: TimeInterval = 150

    /// Önce tarayıcının profil ayarlarına (kaldırılınca hemen yansır), sonra eklentinin sinyaline bakılır.
    func extensionStatus(for browser: BrowserExtension.Browser, now: Date = Date()) -> ExtensionStatus {
        let seen = lastSignal(from: browser)
        let recent = seen.map { now.timeIntervalSince($0) < Self.extensionConnectedWindow } ?? false
        let install = BrowserExtension.installInfo(in: browser)
        switch install.state {
        case .notInstalled, .disabled:
            // Yeni kurulmuş: tarayıcı ayarlarını henüz yazmadı ama eklenti sinyal verdi (dosyadan daha yeni).
            if recent, let seen, let written = install.written, seen > written { return .connected }
            return install.state == .disabled ? .disabled : .notInstalled
        case .unknown where seen == nil:
            return .notInstalled
        case .installed, .unknown:
            break
        }
        if recent { return .connected }
        return browser.isRunning ? .notConnected(seen) : .browserClosed(seen)
    }

    /// Tarayıcıdan gelen son sinyal; markasını bildiremeyenlerde ortak adla gelen sinyal.
    func lastSignal(from browser: BrowserExtension.Browser) -> Date? {
        if let seen = extensionSeen[browser.name] { return seen }
        guard BrowserExtension.unnamedBrowsers.contains(browser.name) else { return nil }
        return extensionSeen[BrowserExtension.unnamedBrowser]
    }

    enum ExtensionProblem {
        /// Hiçbir tarayıcıda kurulu (ya da açık) değil.
        case notInstalled
        /// Tarayıcı açık ama eklentiden sinyal gelmiyor.
        case notConnected
    }

    /// Listenin üstündeki hatırlatma bandı için. Bir tarayıcıda bağlıysa ya da tarayıcılar kapalıysa sorun yok.
    func extensionProblem(now: Date = Date()) -> ExtensionProblem? {
        let statuses = BrowserExtension.installedBrowsers.map { extensionStatus(for: $0, now: now) }
        guard !statuses.isEmpty, !statuses.contains(.connected) else { return nil }
        if statuses.allSatisfy({ $0 == .notInstalled || $0 == .disabled }) { return .notInstalled }
        if statuses.contains(where: { if case .notConnected = $0 { true } else { false } }) { return .notConnected }
        return nil
    }

    /// Panel açılırken: gerekiyorsa eklenti kurulumu, değilse boştayken "Tamamlanan".
    func panelWillOpen() {
        if route == .list, needsOnboarding, !Self.isHarness {
            route = .onboarding
        }
        // Menü çubuğundaki kırmızı nokta: tıklanınca hatalı indirmelerin olduğu liste açılır.
        if route == .list, hasFailures { tab = .active }
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
                self.updateActivityAssertion()
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

    /// İndirme sürerken macOS uygulamayı App Nap'e almasın: menü çubuğu uygulamasının penceresi
    /// görünmediğinde zamanlayıcılar (aria2'den ilerleme okuma, hız göstergesi) yavaşlatılıyor.
    @ObservationIgnored private var activity: NSObjectProtocol?

    private func updateActivityAssertion() {
        let running = items.contains { [.downloading, .queued, .processing].contains($0.status) }
        if running, activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiatedAllowingIdleSystemSleep], reason: "İndirmeler sürüyor"
            )
        } else if !running, let current = activity {
            ProcessInfo.processInfo.endActivity(current)
            activity = nil
        }
    }

    /// Tamamlanan ve (otomatik denemeler bittikten sonra) başarısız olan indirmeler için bildirim.
    private func notifyStatusChanges() {
        var current: [UUID: DownloadStatus] = [:]
        var finished = false
        for item in items {
            current[item.id] = item.status
            guard let previous = lastStatuses[item.id], previous != item.status else { continue }
            switch item.status {
            case .completed:
                if item.completedAt == nil { item.completedAt = Date() }
                finished = true
                Notifier.shared.downloadFinished(item)
            case .failed(let message):
                if case .failed = previous { break }
                Notifier.shared.downloadFailed(item, message: message)
            default:
                break
            }
        }
        lastStatuses = current
        // Son indirme de bitti (iptal edilmedi, hata yok): menü çubuğunda kısa bir onay işareti.
        if finished, !hasActive, !hasFailures { finishedAt = Date() }
    }

    var visibleItems: [DownloadItem] {
        let filtered = items.filter { tab.includes($0.status) && (category == .all || $0.category == category) }
        guard tab == .completed else { return filtered }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let found = query.isEmpty ? filtered : filtered.filter {
            $0.fileName.localizedStandardContains(query) || (URL(string: $0.url)?.host() ?? "").localizedStandardContains(query)
        }
        switch completedSort {
        // Liste en yeni eklenen başta tutuluyor; bitiş anı bilinmeyenler o sırada kalır.
        case .newest: return found.enumerated().sorted {
            ($0.element.completedAt ?? .distantPast, -$0.offset) > ($1.element.completedAt ?? .distantPast, -$1.offset)
        }.map(\.element)
        case .name: return found.sorted { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
        case .size: return found.sorted { $0.totalBytes > $1.totalBytes }
        }
    }

    var hasFailures: Bool { items.contains(where: \.isFailed) }

    var totalSpeed: Int64 {
        items.reduce(0) { $0 + $1.speed }
    }

    var downloadFolder: URL {
        SettingsKey.downloadFolderURL
    }

    // MARK: - İşlemler

    /// Her satırdaki linki ayrı bir indirme olarak ekler; video linkleri `quality` kalitesinde iner.
    /// `speedLimit` indirme başına sınır; `startPaused` ise ("Hemen başlat" kapalı) duraklatılmış eklenir.
    /// `saveAs` tek link eklenirken kullanıcının verdiği ad (Link ekle'deki "Ad" alanı).
    func add(links text: String, quality: VideoQuality = .auto, speedLimit: Int64? = nil, startPaused: Bool = false,
             saveAs: String? = nil) {
        var requests = Self.parseLinks(text).map { DownloadRequest(url: $0, quality: quality) }
        if requests.count == 1, let saveAs, !saveAs.isEmpty {
            requests[0].saveAs = saveAs
        }
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
        // Link ekle'den eklendiyse listeye dön; tarayıcıdan gelen indirme kullanıcıyı Ayarlar'dan ya da
        // kurulum ekranından zorla çıkarmasın.
        if route == .addLink { route = .list }
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
        for item in items where item.status == .completed {
            engine.cancel(item)
        }
        items.removeAll { $0.status == .completed }
        selection = nil
        save()
    }

    /// Aynı adresten daha önce eklenmiş indirme (listeden silinmişler sayılmaz).
    func existingItem(for url: String) -> DownloadItem? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.first { $0.url == trimmed }
    }

    /// Klasörde ve listede olmayan bir ad: "Rapor.pdf" → "Rapor (1).pdf". `keepExtension` false ise
    /// (video, yt-dlp uzantıyı kendisi ekliyor) uzantısız döner.
    func freshName(for name: String, in folder: URL, keepExtension: Bool = true) -> String {
        let ext = (name as NSString).pathExtension
        let base = ext.isEmpty ? name : (name as NSString).deletingPathExtension
        let taken = Set(items.map(\.fileName))
        for number in 1...999 {
            let candidate = "\(base) (\(number))" + (ext.isEmpty ? "" : ".\(ext)")
            let exists = FileManager.default.fileExists(atPath: folder.appendingPathComponent(candidate).path)
            if !exists, !taken.contains(candidate) {
                return keepExtension ? candidate : (candidate as NSString).deletingPathExtension
            }
        }
        return name
    }

    func togglePause(_ item: DownloadItem) {
        switch item.status {
        case .downloading, .queued, .processing: engine.pause(item)
        case .paused, .failed: engine.resume(item)
        case .completed: break
        }
    }

    // MARK: - Silme ve geri alma

    /// Çöp kutusu / ⌘⌫: indirme listeden hemen kalkar; dosyası (devam edende yarım dosya, tamamlananda
    /// indirilen dosya) "Geri al" süresi dolunca silinir. Süre içinde ⌘Z ya da Geri al ile geri gelir.
    func delete(_ item: DownloadItem) {
        commitPendingDeletion()
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let wasRunning = [.downloading, .queued, .processing].contains(item.status)
        if wasRunning { engine.pause(item) }
        items.remove(at: index)
        if selection == item.id { selection = nil }
        pendingDeletion = PendingDeletion(
            item: item, index: index, wasRunning: wasRunning,
            trashesFile: item.status == .completed, deadline: Date().addingTimeInterval(Self.undoWindow)
        )
        deletionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.undoWindow))
            guard !Task.isCancelled else { return }
            self?.commitPendingDeletion()
        }
        save()
    }

    func undoDelete() {
        guard let pending = pendingDeletion else { return }
        deletionTask?.cancel()
        pendingDeletion = nil
        items.insert(pending.item, at: min(pending.index, items.count))
        // Son devam eden silinince liste "Tamamlanan"a geçmiş olabilir; geri gelen görünsün.
        tab = ListTab.active.includes(pending.item.status) ? .active : .completed
        if category != .all, category != pending.item.category { category = .all }
        selection = pending.item.id
        if pending.wasRunning { engine.resume(pending.item) }
        save()
    }

    /// Bekleyen silmeyi hemen uygular (süre doldu, yeni bir silme geldi ya da uygulama kapanıyor).
    func commitPendingDeletion(terminating: Bool = false) {
        guard let pending = pendingDeletion else { return }
        deletionTask?.cancel()
        pendingDeletion = nil
        let item = pending.item
        if pending.trashesFile {
            engine.cancel(item)
            if let file = item.destination {
                try? FileManager.default.trashItem(at: file, resultingItemURL: nil)
            }
            return
        }
        cancel(item)
        // aria2 yarım dosyayı arka planda siliyor; uygulama kapanıyorsa o iş hiç çalışmaz. Yarım dosyayı
        // kontrol dosyası (.aria2) varsa hemen sil; yoksa aynı adlı bitmiş bir dosyaya dokunulmaz.
        if terminating, item.source == .direct {
            let file = item.folder.appendingPathComponent(item.fileName)
            let control = file.appendingPathExtension("aria2")
            if FileManager.default.fileExists(atPath: control.path) {
                try? FileManager.default.removeItem(at: file)
                try? FileManager.default.removeItem(at: control)
            }
        }
    }

    /// ✕: tamamlanan dosyayı sadece listeden kaldırır; dosya diskte kalır.
    func removeFromList(_ item: DownloadItem) {
        if selection == item.id { selection = nil }
        cancel(item)
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
        // Panel kapalıyken kurulum ekranı görünmediği için geçişi burada yap (açıkken ekran kendisi
        // kısa bir onay gösterip geçiyor).
        if route == .onboarding, !panelVisible {
            route = .list
            onboardingBrowser = nil
        }
        extensionSeen[browser] = Date()
        UserDefaults.standard.set(extensionSeen, forKey: SettingsKey.extensionSeen)
        UserDefaults.standard.set(true, forKey: SettingsKey.extensionEverConnected)
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
