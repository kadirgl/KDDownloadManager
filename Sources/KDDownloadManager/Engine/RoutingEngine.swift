import Foundation

/// Her indirmeyi kaynağına göre doğru motora yollar: video siteleri → yt-dlp, gerisi → aria2.
/// Genel ayarlar (toplam hız sınırı, eşzamanlı indirme sayısı) iki motora da ayrı ayrı uygulanır.
@MainActor
final class RoutingEngine: DownloadEngine {
    private let files: any DownloadEngine
    private let videos: any DownloadEngine

    init(files: any DownloadEngine, videos: any DownloadEngine) {
        self.files = files
        self.videos = videos
    }

    private func engine(for item: DownloadItem) -> any DownloadEngine {
        item.source == .video ? videos : files
    }

    func start(_ item: DownloadItem) {
        engine(for: item).start(item)
    }

    func pause(_ item: DownloadItem) {
        engine(for: item).pause(item)
    }

    func resume(_ item: DownloadItem) {
        engine(for: item).resume(item)
    }

    func cancel(_ item: DownloadItem) {
        engine(for: item).cancel(item)
    }

    func setSpeedLimit(_ limit: Int64?, for item: DownloadItem) {
        engine(for: item).setSpeedLimit(limit, for: item)
    }

    func setGlobalSpeedLimit(_ limit: Int64?) {
        files.setGlobalSpeedLimit(limit)
        videos.setGlobalSpeedLimit(limit)
    }

    func setMaxConcurrent(_ count: Int) {
        files.setMaxConcurrent(count)
        videos.setMaxConcurrent(count)
    }
}
