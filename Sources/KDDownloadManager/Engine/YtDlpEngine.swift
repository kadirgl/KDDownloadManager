import Foundation
import AppKit

/// YouTube vb. siteler için yt-dlp motoru. Her indirme ayrı bir yt-dlp süreci;
/// ilerleme `--progress-template` ile makinece okunur satırlar ("KDPROG {json}") olarak alınır.
/// Duraklatma süreci durdurur, devam etme yeniden başlatır (yt-dlp .part dosyasından sürdürür).
/// Hız sınırı değişince de süreç aynı şekilde yeni sınırla yeniden başlatılır.
/// Yarım dosyalar indirme başına ayrı bir geçici klasörde tutulur; indirme klasöründe
/// sadece bitmiş dosya görünür, iptalde de o klasörü silmek yeterli olur.
@MainActor
final class YtDlpEngine: DownloadEngine {
    private enum StopReason {
        case pause, cancel, restart
    }

    private final class Job {
        let process: Process
        /// Süreci biz durdurduysak nedeni; nil ise kendi kendine bitti.
        var stopReason: StopReason?

        init(process: Process) {
            self.process = process
        }
    }

    private var items: [UUID: DownloadItem] = [:]
    /// Başlamayı bekleyenler, ekleme sırasıyla.
    private var queue: [UUID] = []
    private var jobs: [UUID: Job] = [:]
    /// Parça dosyası → inen bayt. Video ve ses ayrı dosyalar olarak inip sonra birleşiyor.
    private var parts: [UUID: [String: Int64]] = [:]
    /// yt-dlp'nin indirme öncesi bildirdiği toplam boyut (tüm parçalar).
    private var expectedTotal: [UUID: Int64] = [:]

    private var maxConcurrent = SettingsKey.defaultMaxConcurrent
    private var globalLimit: Int64?

    init() {
        // Uygulama kapanırken yt-dlp süreçleri sahipsiz kalıp inmeye devam etmesin.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // Durumları değişmesin; liste "inmekte" olarak kaydedilip açılışta devam etsin.
                self?.jobs.values.forEach { job in
                    job.stopReason = .pause
                    job.process.terminate()
                }
            }
        }
    }

    // MARK: - DownloadEngine

    func start(_ item: DownloadItem) {
        items[item.id] = item
        enqueue(item)
    }

    func pause(_ item: DownloadItem) {
        queue.removeAll { $0 == item.id }
        item.setStatus(.paused)
        stop(item.id, reason: .pause)
    }

    func resume(_ item: DownloadItem) {
        // Önceki oturumdan kalıp bu oturumda hiç başlatılmamış olabilir.
        items[item.id] = item
        enqueue(item)
    }

    func cancel(_ item: DownloadItem) {
        items[item.id] = nil
        queue.removeAll { $0 == item.id }
        expectedTotal[item.id] = nil
        parts[item.id] = nil
        // Süreç çalışıyorsa geçici klasör süreç kapanınca silinir.
        if jobs[item.id] != nil {
            stop(item.id, reason: .cancel)
        } else {
            Self.removeTemporaryFolder(for: item.id)
        }
    }

    func setSpeedLimit(_ limit: Int64?, for item: DownloadItem) {
        item.speedLimit = limit
        stop(item.id, reason: .restart)
    }

    /// yt-dlp'de toplam sınır yok; her sürece ayrı ayrı uygulanıyor (indirmenin kendi sınırıyla en küçüğü).
    func setGlobalSpeedLimit(_ limit: Int64?) {
        guard globalLimit != limit else { return }
        globalLimit = limit
        jobs.keys.forEach { stop($0, reason: .restart) }
    }

    func setMaxConcurrent(_ count: Int) {
        maxConcurrent = count
        launchNext()
    }

    // MARK: - Süreç yönetimi

    private func enqueue(_ item: DownloadItem) {
        item.setStatus(.queued)
        if !queue.contains(item.id) {
            queue.append(item.id)
        }
        launchNext()
    }

    private func launchNext() {
        // Duraklatılıp hemen devam ettirilenin eski süreci kapanana kadar bekle; ikisi aynı dosyaya yazmasın.
        while jobs.count < maxConcurrent, let index = queue.firstIndex(where: { jobs[$0] == nil }) {
            let id = queue.remove(at: index)
            if let item = items[id] {
                launch(item)
            }
        }
    }

    private func stop(_ id: UUID, reason: StopReason) {
        guard let job = jobs[id] else { return }
        job.stopReason = reason
        job.process.terminate()
    }

    private func launch(_ item: DownloadItem) {
        guard let binary = Executables.find("yt-dlp") else {
            item.setStatus(.failed("yt-dlp bulunamadı (brew install yt-dlp)"))
            return
        }
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments(for: item)
        var environment = Executables.environment
        // Boruya yazarken Python çıktıyı tamponluyor; satırlar geç ve toplu gelmesin.
        environment["PYTHONUNBUFFERED"] = "1"
        process.environment = environment
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        let exitCode = AsyncStream<Int32> { continuation in
            process.terminationHandler = { process in
                continuation.yield(process.terminationStatus)
                continuation.finish()
            }
        }

        do {
            try process.run()
        } catch {
            item.setStatus(.failed(error.localizedDescription))
            return
        }
        let job = Job(process: process)
        jobs[item.id] = job
        item.setStatus(.downloading)

        // Hata mesajı stderr'de "ERROR: ..." satırı olarak geliyor; sonuncusunu sakla.
        let lastError = Task {
            var last: String?
            for await line in errors.lines where line.hasPrefix("ERROR:") {
                last = line.dropFirst("ERROR:".count).trimmingCharacters(in: .whitespaces)
            }
            return last
        }
        Task {
            for await line in output.lines {
                // Durdurulan sürecin son satırları duraklatılmış durumu ezmesin.
                if items[item.id] != nil, job.stopReason == nil {
                    handle(line, for: item)
                }
            }
            var status: Int32 = -1
            for await code in exitCode {
                status = code
            }
            finish(item, job: job, status: status, error: await lastError.value)
        }
    }

    private func finish(_ item: DownloadItem, job: Job, status: Int32, error: String?) {
        jobs[item.id] = nil
        defer { launchNext() }

        switch job.stopReason {
        case .cancel:
            Self.removeTemporaryFolder(for: item.id)
        case .pause:
            break
        case .restart:
            // Duraklatılmış ya da kaldırılmış değilse yeni ayarlarla kaldığı yerden sürdür.
            if items[item.id] != nil, item.status == .downloading {
                launch(item)
            }
        case nil:
            guard items[item.id] != nil else { return }
            guard status == 0 else {
                item.setStatus(.failed(error ?? "yt-dlp hata verdi (kod \(status))"))
                return
            }
            if let path = item.destination?.path,
               let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int64 {
                item.totalBytes = size
            }
            item.totalBytes = max(item.totalBytes, item.downloadedBytes)
            item.downloadedBytes = item.totalBytes
            parts[item.id] = nil
            expectedTotal[item.id] = nil
            Self.removeTemporaryFolder(for: item.id)
            item.setStatus(.completed)
        }
    }

    // MARK: - yt-dlp çıktısı

    private func arguments(for item: DownloadItem) -> [String] {
        var arguments = [
            "--no-playlist",
            "--newline",
            // --print sessiz moda geçiriyor; ilerleme satırlarını yine de istiyoruz.
            "--progress",
            "--no-simulate",
            "-P", item.folder.path,
            "-P", "temp:" + Self.temporaryFolder(for: item.id).path,
            "-o", "%(title)s.%(ext)s",
            "--print",
            "before_dl:KDINFO %(.{title,filesize,filesize_approx,requested_formats.:.filesize,requested_formats.:.filesize_approx})j",
            "--print", "after_move:KDFILE %(filepath)s",
            "--progress-template",
            "download:KDPROG %(progress.{status,downloaded_bytes,total_bytes,total_bytes_estimate,speed,filename})j"
        ]
        if let ffmpeg = Executables.find("ffmpeg") {
            // Mac'te QuickTime'ın açabildiği H.264/AAC tercih ediliyor; görüntü ve ses ayrı inip MP4'te birleşir.
            arguments += [
                "-f", "bv*+ba/b",
                "-S", "vcodec:h264,res,acodec:aac",
                "--merge-output-format", "mp4",
                "--ffmpeg-location", ffmpeg.path
            ]
        } else {
            // ffmpeg yoksa birleştirme gerektirmeyen tek dosyalık en iyi biçim.
            arguments += ["-f", "b"]
        }
        let limits = [item.speedLimit, globalLimit].compactMap { $0 }
        if let limit = limits.min() {
            arguments += ["--limit-rate", String(limit)]
        }
        return arguments + ["--", item.url]
    }

    private func handle(_ line: String, for item: DownloadItem) {
        guard let space = line.firstIndex(of: " ") else { return }
        let tag = line[..<space]
        let payload = String(line[line.index(after: space)...])

        switch tag {
        case "KDINFO":
            guard let info = Self.decode(payload) else { return }
            if let title = info["title"]?.stringValue, item.fileName != title {
                item.fileName = title
            }
            // Görüntü + ses ayrı biçimlerse boyutları ayrı geliyor; kesin boyut yoksa tahmini kullan.
            let exact = info["requested_formats.:.filesize"]?.arrayValue ?? []
            let approx = info["requested_formats.:.filesize_approx"]?.arrayValue ?? []
            let requested = (0..<max(exact.count, approx.count)).reduce(Int64(0)) { sum, index in
                sum + (exact[safe: index]?.int64Value ?? approx[safe: index]?.int64Value ?? 0)
            }
            let total = requested > 0
                ? requested
                : info["filesize"]?.int64Value ?? info["filesize_approx"]?.int64Value ?? 0
            if total > 0 {
                expectedTotal[item.id] = total
                item.totalBytes = total
            }

        case "KDPROG":
            guard let progress = Self.decode(payload),
                  let file = progress["filename"]?.stringValue else { return }
            var itemParts = parts[item.id, default: [:]]
            itemParts[file] = progress["downloaded_bytes"]?.int64Value ?? itemParts[file] ?? 0
            parts[item.id] = itemParts
            item.downloadedBytes = itemParts.values.reduce(0, +)

            if expectedTotal[item.id] == nil,
               let partTotal = progress["total_bytes"]?.int64Value ?? progress["total_bytes_estimate"]?.int64Value {
                // Toplam baştan bilinmiyorsa: biten parçalar + bu parçanın boyutu.
                item.totalBytes = item.downloadedBytes - (itemParts[file] ?? 0) + partTotal
            }
            let downloading = progress["status"]?.stringValue == "downloading"
            item.setStatus(.downloading, speed: downloading ? progress["speed"]?.int64Value ?? 0 : 0)

        case "KDFILE":
            let url = URL(fileURLWithPath: payload)
            item.destination = url
            item.fileName = url.lastPathComponent

        default:
            break
        }
    }

    private static func decode(_ json: String) -> JSONValue? {
        try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    }

    /// Yarım parçaların (.part, .ytdl, "-Frag" dosyaları, birleştirilmemiş görüntü/ses) tutulduğu,
    /// bu indirmeye özel klasör. Bitince yt-dlp sonucu indirme klasörüne taşır.
    private static func temporaryFolder(for id: UUID) -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("KDDownloadManager/yt-dlp/\(id.uuidString)", isDirectory: true)
    }

    private static func removeTemporaryFolder(for id: UUID) {
        try? FileManager.default.removeItem(at: temporaryFolder(for: id))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
