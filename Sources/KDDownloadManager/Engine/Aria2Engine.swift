import Foundation
import AppKit

/// aria2c üzerinden gerçek indirme motoru: HTTP/HTTPS/FTP (çoklu bağlantı), magnet ve .torrent.
/// aria2c ilk indirmede başlatılır; durum yarım saniyede bir `system.multicall` ile sorgulanır.
/// YouTube vb. video linkleri `RoutingEngine` tarafından `YtDlpEngine`'e yollanır.
@MainActor
final class Aria2Engine: DownloadEngine {
    private let daemon = Aria2Daemon()
    private var client: Aria2Client?
    private var startup: Task<Aria2Client, Error>?
    private var poller: Task<Void, Never>?

    private var items: [UUID: DownloadItem] = [:]
    /// aria2'nin indirme kimliği (gid). Magnet/torrent'te meta veri inince yenisiyle değişir.
    private var gids: [UUID: String] = [:]
    /// İptal edilince silinecek dosyalar: aria2'nin bildirdiği yollar + kontrol dosyası.
    private var partialFiles: [UUID: [String]] = [:]
    /// Kullanıcının duraklattıkları. aria2 komutları ve durum sorguları birbirini geçebildiği için
    /// "duraklatıldı" bilgisini aria2'nin anlık cevabından değil buradan alıyoruz.
    private var pausedByUser: Set<UUID> = []
    /// Bağlantı hatasıyla düşüp tek bağlantıyla devam edenler. Bazı sunucular aynı IP'den
    /// birkaç bağlantıdan fazlasına 429/503 dönüyor; aria2 o zaman indirmeyi tamamen bırakıyor.
    private var singleConnection: Set<UUID> = []
    /// Kendiliğinden yapılan yeniden deneme sayısı; kullanıcı elle devam ettirince sıfırlanır.
    private var autoRetries: [UUID: Int] = [:]
    /// Yeniden denemeden önceki bekleme (sn). 429 gibi geçici engellerde sunucuya zaman tanır.
    private static let retryDelays: [Double] = [0, 5, 15, 30, 60]

    /// aria2 hata kodları: 1 bilinmeyen, 2 zaman aşımı, 6 ağ sorunu, 22 sunucu HTTP hatası (429/503 vb.).
    /// "Bulunamadı", disk ve yetki hataları tek bağlantıyla da düzelmeyeceği için listede yok.
    private static let connectionErrorCodes: Set<String> = ["1", "2", "6", "22"]

    private var maxConcurrent = 3
    private var globalLimit: Int64?

    private static let pollInterval = 0.5
    /// Her sorguda istenen hafif alanlar.
    private static let statusKeys: JSONValue = [
        "status", "totalLength", "completedLength", "downloadSpeed", "errorMessage", "errorCode", "followedBy"
    ]
    /// Dosya listesi ve torrent bilgisi: binlerce dosyalı bir torrentte yüzlerce KB tutuyor. Sadece dosya
    /// adı ve yolu öğrenilene kadar istenir, sonra her yarım saniyede tekrar çekilmez.
    private static let detailedStatusKeys: JSONValue = [
        "status", "totalLength", "completedLength", "downloadSpeed", "errorMessage", "errorCode", "followedBy",
        "files", "bittorrent", "dir"
    ]
    /// Dosya adı/yolu öğrenilmiş indirmeler (gid); ayrıntılı sorgu artık gerekmiyor.
    private var detailsKnown: Set<String> = []
    /// Tamamlanınca gösterilecek yer: tek dosyada dosya, çok dosyalı torrent'te klasör.
    private var roots: [UUID: String] = [:]

    init() {
        // --stop-with-process birkaç saniye geç fark ediyor; uygulama hemen yeniden açılırsa
        // eski ve yeni aria2c aynı dosyaya yazmasın diye kapanırken hemen durdur.
        // (SIGTERM'de aria2 .aria2 kontrol dosyasını kaydedip kapanıyor.)
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.daemon.stop() }
        }
    }

    // MARK: - DownloadEngine

    func start(_ item: DownloadItem) {
        items[item.id] = item
        add(item)
    }

    func pause(_ item: DownloadItem) {
        pausedByUser.insert(item.id)
        item.setStatus(.paused)
        if let gid = gids[item.id] {
            send("aria2.forcePause", [.string(gid)])
        }
    }

    func resume(_ item: DownloadItem) {
        // Önceki oturumdan kalıp bu oturumda hiç başlatılmamış olabilir.
        items[item.id] = item
        pausedByUser.remove(item.id)
        autoRetries[item.id] = nil
        guard item.status == .paused, let gid = gids[item.id] else {
            // Hata almış ya da önceki oturumdan kalmış: yeniden ekle;
            // --continue ve .aria2 kontrol dosyası sayesinde kaldığı yerden devam eder.
            if let old = gids.removeValue(forKey: item.id) {
                send("aria2.removeDownloadResult", [.string(old)])
            }
            add(item)
            return
        }
        item.setStatus(.queued)
        send("aria2.unpause", [.string(gid)])
        startPollingIfNeeded()
    }

    func cancel(_ item: DownloadItem) {
        items[item.id] = nil
        roots[item.id] = nil
        singleConnection.remove(item.id)
        autoRetries[item.id] = nil
        pausedByUser.remove(item.id)
        let files = partialFiles.removeValue(forKey: item.id) ?? []
        guard let gid = gids.removeValue(forKey: item.id) else {
            if item.status != .completed {
                Self.delete(Self.leftoverFiles(of: item))
            }
            return
        }

        if item.status == .completed {
            // Sadece listeden kaldırılıyor; dosyaya dokunma.
            send("aria2.removeDownloadResult", [.string(gid)])
            return
        }
        Task {
            guard let client = try? await connected() else { return }
            _ = try? await client.call("aria2.forceRemove", [.string(gid)])
            // aria2 dosyaları bırakana kadar kısa bir süre bekle.
            try? await Task.sleep(for: .milliseconds(500))
            _ = try? await client.call("aria2.removeDownloadResult", [.string(gid)])
            Self.delete(files)
        }
    }

    func setSpeedLimit(_ limit: Int64?, for item: DownloadItem) {
        item.speedLimit = limit
        if let gid = gids[item.id] {
            send("aria2.changeOption", [.string(gid), ["max-download-limit": .string(String(limit ?? 0))]])
        }
    }

    func setGlobalSpeedLimit(_ limit: Int64?) {
        globalLimit = limit
        // aria2c henüz çalışmıyorsa değer başlatılırken parametre olarak verilecek.
        if client != nil {
            send("aria2.changeGlobalOption", [["max-overall-download-limit": .string(String(limit ?? 0))]])
        }
    }

    func setMaxConcurrent(_ count: Int) {
        maxConcurrent = count
        if client != nil {
            send("aria2.changeGlobalOption", [["max-concurrent-downloads": .string(String(count))]])
        }
    }

    // MARK: - aria2 bağlantısı

    private func connected() async throws -> Aria2Client {
        if let client { return client }
        let startup = self.startup ?? Task { [daemon, maxConcurrent, globalLimit] in
            try await daemon.start(maxConcurrent: maxConcurrent, globalLimit: globalLimit)
        }
        self.startup = startup
        do {
            let client = try await startup.value
            if self.client == nil {
                self.client = client
                // aria2c başlarken genel ayarlar değiştiyse başlangıç değerleri eskidi; güncelini uygula.
                _ = try? await client.call("aria2.changeGlobalOption", [[
                    "max-overall-download-limit": .string(String(globalLimit ?? 0)),
                    "max-concurrent-downloads": .string(String(maxConcurrent))
                ]])
            }
            return client
        } catch {
            self.startup = nil
            throw error
        }
    }

    private func add(_ item: DownloadItem) {
        item.setStatus(.queued)
        let limitAtAdd = item.speedLimit
        var options: [String: JSONValue] = [
            "dir": .string(item.folder.path),
            "max-download-limit": .string(String(limitAtAdd ?? 0))
        ]
        if singleConnection.contains(item.id) {
            options["split"] = "1"
            options["max-connection-per-server"] = "1"
        }
        // Tarayıcıdan geldiyse aynı istek bilgileriyle indir; giriş gerektiren siteler bunları bekliyor.
        if let referrer = item.referrer { options["referer"] = .string(referrer) }
        if let userAgent = item.userAgent { options["user-agent"] = .string(userAgent) }
        if let cookies = item.cookies { options["header"] = [.string("Cookie: " + cookies)] }
        Task {
            do {
                let client = try await connected()
                let result: JSONValue
                if let file = URL(string: item.url), file.isFileURL {
                    // Diskteki .torrent dosyası: içeriği base64 olarak verilir.
                    guard let torrent = try? Data(contentsOf: file) else {
                        throw Aria2Error(message: "Torrent dosyası okunamadı")
                    }
                    if !Self.isPrivate(torrent) {
                        options["bt-tracker"] = .string(Self.publicTrackers.joined(separator: ","))
                    }
                    result = try await client.call("aria2.addTorrent", [.string(torrent.base64EncodedString()), [], .object(options)])
                } else {
                    if Self.isTrackerlessMagnet(item.url) {
                        options["bt-tracker"] = .string(Self.publicTrackers.joined(separator: ","))
                    }
                    result = try await client.call("aria2.addUri", [[.string(item.url)], .object(options)])
                }
                guard let gid = result.stringValue else {
                    throw Aria2Error(message: "aria2 indirme kimliği vermedi")
                }
                // Bu arada iptal edildiyse aria2'den de kaldır.
                guard items[item.id] != nil else {
                    _ = try? await client.call("aria2.forceRemove", [.string(gid)])
                    return
                }
                gids[item.id] = gid
                // Kimlik gelmeden yapılan değişiklikleri şimdi uygula.
                if item.speedLimit != limitAtAdd {
                    setSpeedLimit(item.speedLimit, for: item)
                }
                if pausedByUser.contains(item.id) {
                    send("aria2.forcePause", [.string(gid)])
                }
                startPollingIfNeeded()
            } catch {
                item.setStatus(.failed(error.localizedDescription))
            }
        }
    }

    /// Sonucu beklenmeyen komutlar; hatalar zaten bir sonraki durum sorgusunda görünür.
    private func send(_ method: String, _ params: [JSONValue]) {
        Task {
            guard let client = try? await connected() else { return }
            _ = try? await client.call(method, params)
        }
    }

    // MARK: - Durum sorgulama

    private func startPollingIfNeeded() {
        guard poller == nil else { return }
        poller = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, await self.poll() else { break }
                try? await Task.sleep(for: .seconds(Self.pollInterval))
            }
            self?.poller = nil
        }
    }

    /// Sırada/inen indirmelerin durumunu günceller; izlenecek bir şey kalmadıysa false döner.
    private func poll() async -> Bool {
        let tracked = gids.filter { id, _ in
            guard let status = items[id]?.status else { return false }
            return status == .queued || status == .downloading
        }
        guard let client, !tracked.isEmpty else { return false }

        let ids = Array(tracked.keys)
        let calls = ids.map { id -> (method: String, params: [JSONValue]) in
            let gid = tracked[id]!
            let keys = detailsKnown.contains(gid) ? Self.statusKeys : Self.detailedStatusKeys
            return (method: "aria2.tellStatus", params: [.string(gid), keys])
        }
        do {
            let results = try await client.multicall(calls)
            for (id, result) in zip(ids, results) {
                // Beklerken iptal edildiyse ya da kimliği değiştiyse atla.
                guard let item = items[id], let gid = tracked[id], gids[id] == gid,
                      case .success(let status) = result else { continue }
                apply(status, to: item, gid: gid)
            }
        } catch {
            if !daemon.isRunning {
                daemonStopped()
                return false
            }
        }
        return true
    }

    private func apply(_ status: JSONValue, to item: DownloadItem, gid: String) {
        // Ayrıntılar (dosya listesi) sadece istendiyse gelir.
        if let files = status["files"]?.arrayValue {
            let paths = files
                .compactMap { $0["path"]?.stringValue }
                .filter { !$0.isEmpty && !$0.hasPrefix("[METADATA]") }
            let torrentName = status["bittorrent"]?["info"]?["name"]?.stringValue
            // Tek dosyada dosyanın kendisi, çok dosyalı torrent'te "<dir>/<isim>" klasörü.
            let root = torrentName.flatMap { name in status["dir"]?.stringValue.map { "\($0)/\(name)" } }
                ?? paths.first

            if let name = torrentName ?? paths.first.map({ URL(fileURLWithPath: $0).lastPathComponent }),
               item.fileName != name {
                item.fileName = name
                item.category = DownloadCategory.forFile(named: name)
            }
            if let root, !paths.isEmpty {
                partialFiles[item.id] = paths + [root + ".aria2"]
                roots[item.id] = root
                detailsKnown.insert(gid)
            }
        }
        if let total = status["totalLength"]?.int64Value, total > 0, item.totalBytes != total {
            item.totalBytes = total
        }
        // Değişmeyen değeri yeniden yazmak ekranı boşuna yeniden çizdiriyor.
        if let done = status["completedLength"]?.int64Value, item.downloadedBytes != done {
            item.downloadedBytes = done
        }

        let state = status["status"]?.stringValue
        // Duraklatma komutu henüz işlenmediyse "active" görebiliriz; kullanıcının isteği geçerli.
        if pausedByUser.contains(item.id), state == "active" || state == "waiting" {
            return
        }

        switch state {
        case "active":
            item.setStatus(.downloading, speed: status["downloadSpeed"]?.int64Value ?? 0)
        case "waiting":
            item.setStatus(.queued)
        case "paused":
            // Devam komutu henüz işlenmediyse eski "paused" cevabı gelebilir; sırada say.
            item.setStatus(pausedByUser.contains(item.id) ? .paused : .queued)
        case "error":
            if retryWithSingleConnection(item, status: status) { return }
            item.setStatus(.failed(status["errorMessage"]?.stringValue ?? "İndirme başarısız"))
        case "complete":
            if let next = status["followedBy"]?[0]?.stringValue {
                // Magnet/.torrent: meta veri indi, asıl indirme yeni kimlikle sürüyor.
                gids[item.id] = next
                return
            }
            item.totalBytes = max(item.totalBytes, item.downloadedBytes)
            item.downloadedBytes = item.totalBytes
            item.destination = roots[item.id].map { URL(fileURLWithPath: $0) }
            detailsKnown.remove(gid)
            item.setStatus(.completed)
        default:
            break
        }
    }

    private func daemonStopped() {
        client = nil
        startup = nil
        for (id, _) in gids {
            if let item = items[id], item.status != .completed {
                item.setStatus(.failed("İndirme motoru (aria2c) durdu"))
            }
        }
        gids.removeAll()
    }

    /// Bağlantı kaynaklı hatayla düşen HTTP/FTP indirmesini tek bağlantıyla, artan aralıklarla
    /// kaldığı yerden yeniden başlatır (.aria2 kontrol dosyası korunuyor). Denemeler bitince false.
    private func retryWithSingleConnection(_ item: DownloadItem, status: JSONValue) -> Bool {
        let message = status["errorMessage"]?.stringValue ?? ""
        let code = status["errorCode"]?.stringValue ?? ""
        let attempt = autoRetries[item.id, default: 0]
        guard item.source == .direct, attempt < Self.retryDelays.count,
              Self.connectionErrorCodes.contains(code) || message.contains("No URI available"),
              !Self.isPermanentHTTPError(message) else { return false }
        autoRetries[item.id] = attempt + 1
        singleConnection.insert(item.id)
        if let old = gids.removeValue(forKey: item.id) {
            send("aria2.removeDownloadResult", [.string(old)])
        }
        item.setStatus(.queued)
        Task {
            try? await Task.sleep(for: .seconds(Self.retryDelays[attempt]))
            // Beklerken iptal edildiyse, duraklatıldıysa ya da elle devam ettirildiyse dokunma.
            guard items[item.id] != nil, gids[item.id] == nil, !pausedByUser.contains(item.id),
                  item.status == .queued else { return }
            add(item)
        }
        return true
    }

    /// "status=404" gibi 4xx hataları beklemekle düzelmez (dosya yok, yasak…); 408 ve 429 hariç.
    private static func isPermanentHTTPError(_ message: String) -> Bool {
        guard let range = message.range(of: #"status=(\d{3})"#, options: .regularExpression),
              let status = Int(message[range].dropFirst("status=".count)) else { return false }
        return (400..<500).contains(status) && status != 408 && status != 429
    }

    // MARK: - Torrent

    /// aria2'nin DHT'si çoğu zaman eş bulamadığından, kendi takipçisi olmayan magnet'lere ve
    /// herkese açık .torrent dosyalarına eklenen, yaygın kullanılan açık takipçiler.
    private static let publicTrackers = [
        "udp://tracker.opentrackr.org:1337/announce",
        "udp://open.stealth.si:80/announce",
        "udp://tracker.torrent.eu.org:451/announce",
        "udp://exodus.desync.com:6969/announce",
        "udp://open.demonii.com:1337/announce"
    ]

    private static func isTrackerlessMagnet(_ url: String) -> Bool {
        guard url.lowercased().hasPrefix("magnet:") else { return false }
        return !(URLComponents(string: url)?.queryItems ?? []).contains { $0.name == "tr" }
    }

    /// Özel (üyelik isteyen) sitelerin torrent'leri "private" işaretlidir; bunlara yabancı takipçi
    /// eklemek hesabın engellenmesine yol açabilir. Bencode'da anahtar "7:private", değer "i1e".
    private static func isPrivate(_ torrent: Data) -> Bool {
        torrent.firstRange(of: Data("7:privatei1e".utf8)) != nil
    }

    /// Önceki oturumdan kalmış, bu oturumda aria2'ye hiç verilmemiş bir indirmenin yarım dosyaları.
    /// Yanında aria2 kontrol dosyası (.aria2) yoksa dosya yarım değildir ya da bizim değildir; dokunmuyoruz.
    private static func leftoverFiles(of item: DownloadItem) -> [String] {
        let path = item.folder.appendingPathComponent(item.fileName).path
        let control = path + ".aria2"
        return FileManager.default.fileExists(atPath: control) ? [path, control] : []
    }

    /// Yalnızca aria2'nin bu indirme için bildirdiği dosyaları siler; klasörlere dokunmaz.
    private static func delete(_ files: [String]) {
        for path in files {
            try? FileManager.default.removeItem(atPath: path)
        }
    }
}
