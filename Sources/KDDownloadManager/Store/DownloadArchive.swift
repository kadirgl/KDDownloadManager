import Foundation

/// İndirme listesini uygulama kapanıp açılınca kaybolmasın diye JSON olarak saklar.
/// Varsayılan yer: ~/Library/Application Support/KDDownloadManager/downloads.json
struct DownloadArchive {
    let url: URL

    static var standard: DownloadArchive {
        #if DEBUG
        // Denemelerde gerçek listeye dokunmamak için başka bir dosya verilebilir.
        if let path = ProcessInfo.processInfo.environment["KD_ARCHIVE"] {
            return DownloadArchive(url: URL(fileURLWithPath: path))
        }
        #endif
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return DownloadArchive(url: support.appendingPathComponent("KDDownloadManager/downloads.json"))
    }

    /// Diske yazılan biçim. Anlık hız gibi geçici bilgiler saklanmıyor.
    private struct Record: Codable {
        enum State: String, Codable {
            case active, paused, completed, failed
        }

        var id: UUID
        var url: String
        var fileName: String
        var folder: String
        var totalBytes: Int64
        var downloadedBytes: Int64
        var speedLimit: Int64?
        var state: State
        var error: String?
        var destination: String?
        // Çerezler bilerek saklanmıyor.
        var referrer: String?
        var userAgent: String?
        var quality: VideoQuality?
        /// Adresi video sitesi olmayan ama video olarak indirilen (eklentinin işaretlediği) kayıtlar.
        var video: Bool?
        var preferredName: String?
        var completedAt: Date?
    }

    @MainActor
    func load() -> [DownloadItem] {
        guard let data = try? Data(contentsOf: url),
              let records = try? JSONDecoder().decode([Record].self, from: data) else { return [] }
        return records.map { record in
            let status: DownloadStatus = switch record.state {
            // Kapanırken inmekte/sırada olanlar açılışta sıraya girip devam eder.
            case .active: .queued
            case .paused: .paused
            case .completed: .completed
            case .failed: .failed(record.error ?? "İndirme başarısız")
            }
            let item = DownloadItem(
                id: record.id,
                url: record.url,
                fileName: record.fileName,
                folder: URL(fileURLWithPath: record.folder, isDirectory: true),
                totalBytes: record.totalBytes,
                downloadedBytes: record.downloadedBytes,
                status: status,
                forceVideo: record.video == true
            )
            item.preferredName = record.preferredName
            item.completedAt = record.completedAt
            item.speedLimit = record.speedLimit
            item.destination = record.destination.map { URL(fileURLWithPath: $0) }
            item.referrer = record.referrer
            item.userAgent = record.userAgent
            item.quality = record.quality ?? .auto
            return item
        }
    }

    /// Listeyi JSON'a çevirir; değişip değişmediğini karşılaştırmak için ayrı tutuluyor.
    @MainActor
    func encode(_ items: [DownloadItem]) -> Data {
        let records = items.map { item in
            let (state, error): (Record.State, String?) = switch item.status {
            case .queued, .downloading, .processing: (.active, nil)
            case .paused: (.paused, nil)
            case .completed: (.completed, nil)
            case .failed(let message): (.failed, message)
            }
            return Record(
                id: item.id,
                url: item.url,
                fileName: item.fileName,
                folder: item.folder.path,
                totalBytes: item.totalBytes,
                downloadedBytes: item.downloadedBytes,
                speedLimit: item.speedLimit,
                state: state,
                error: error,
                destination: item.destination?.path,
                referrer: item.referrer,
                userAgent: item.userAgent,
                quality: item.quality == .auto ? nil : item.quality,
                video: item.source == .video && DownloadSource.detect(item.url) != .video ? true : nil,
                preferredName: item.preferredName,
                completedAt: item.completedAt
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(records)) ?? Data()
    }

    func write(_ data: Data) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
