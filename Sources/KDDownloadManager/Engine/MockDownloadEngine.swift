import Foundation

/// Arayüzü denemek için sahte indirme motoru: gerçek ağ trafiği yok,
/// sadece ilerlemeyi ve hızı simüle eder.
@MainActor
final class MockDownloadEngine: DownloadEngine {
    private var items: [UUID: DownloadItem] = [:]
    /// Her indirmenin "hattının" kaldırabileceği hız.
    private var bandwidth: [UUID: Int64] = [:]
    private var globalLimit: Int64?
    private var ticker: Task<Void, Never>?

    private static let tickInterval = 0.5

    func start(_ item: DownloadItem) {
        items[item.id] = item
        bandwidth[item.id] = Int64.random(in: 4...30) * 1_048_576
        if item.totalBytes == 0 {
            item.totalBytes = Int64.random(in: 80...2_000) * 1_048_576
        }
        if item.status == .queued {
            item.status = .downloading
        }
        startTickerIfNeeded()
    }

    func pause(_ item: DownloadItem) {
        item.status = .paused
        item.speed = 0
    }

    func resume(_ item: DownloadItem) {
        item.status = .downloading
        startTickerIfNeeded()
    }

    func cancel(_ item: DownloadItem) {
        items[item.id] = nil
        bandwidth[item.id] = nil
    }

    func setSpeedLimit(_ limit: Int64?, for item: DownloadItem) {
        item.speedLimit = limit
    }

    func setGlobalSpeedLimit(_ limit: Int64?) {
        globalLimit = limit
    }

    /// Sahte motor sırayı simüle etmiyor; hepsini aynı anda indirir.
    func setMaxConcurrent(_ count: Int) {}

    private func startTickerIfNeeded() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.tickInterval))
                guard let self else { return }
                if !self.tick() {
                    self.ticker = nil
                    return
                }
            }
        }
    }

    /// Bir adım ilerletir; indirilen bir şey kalmadıysa false döner.
    private func tick() -> Bool {
        let active = items.values.filter { $0.status == .downloading }
        guard !active.isEmpty else { return false }

        var speeds: [UUID: Int64] = [:]
        for item in active {
            var speed = Int64(Double(bandwidth[item.id] ?? 0) * Double.random(in: 0.85...1.15))
            if let limit = item.speedLimit {
                speed = min(speed, limit)
            }
            speeds[item.id] = speed
        }

        // Genel sınır varsa toplam hızı orantılı olarak küçült.
        let total = speeds.values.reduce(0, +)
        if let globalLimit, total > globalLimit {
            let ratio = Double(globalLimit) / Double(total)
            speeds = speeds.mapValues { Int64(Double($0) * ratio) }
        }

        for item in active {
            let speed = speeds[item.id] ?? 0
            item.speed = speed
            item.downloadedBytes = min(item.totalBytes, item.downloadedBytes + Int64(Double(speed) * Self.tickInterval))
            if item.downloadedBytes >= item.totalBytes {
                item.status = .completed
                item.speed = 0
            }
        }
        return true
    }
}

extension DownloadStore {
    /// Tasarımdaki örnek satırlar + Tamamlanan sekmesi için birkaç kayıt.
    static func sampleItems() -> [DownloadItem] {
        let gb: Int64 = 1_073_741_824
        let mb: Int64 = 1_048_576
        return [
            DownloadItem(url: "https://example.com/Aşamaya%20müdahale.pdf", fileName: "Aşamaya müdahale.pdf",
                         totalBytes: 12 * gb, downloadedBytes: 12 * gb * 87 / 100),
            DownloadItem(url: "https://example.com/Aşamaya%20müdahale.mp3", fileName: "Aşamaya müdahale.mp3",
                         totalBytes: 12 * gb, downloadedBytes: 12 * gb * 67 / 100),
            DownloadItem(url: "https://example.com/rapor.pdf", fileName: "Aşamaya müdahale.pdf",
                         totalBytes: 12 * gb, downloadedBytes: 12 * gb * 27 / 100),
            DownloadItem(url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ", fileName: "Konser kaydı.mp4",
                         totalBytes: 640 * mb, downloadedBytes: 640 * mb, status: .completed),
            DownloadItem(url: "magnet:?xt=urn:btih:0000&dn=ubuntu-24.04-desktop-arm64.iso",
                         totalBytes: 3 * gb, downloadedBytes: 3 * gb, status: .completed),
            DownloadItem(url: "https://example.com/Proje.zip",
                         totalBytes: 220 * mb, downloadedBytes: 220 * mb, status: .completed)
        ]
    }
}
