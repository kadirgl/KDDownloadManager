import Foundation

/// Her indirmeyi kaynağına göre doğru motora yollar: video siteleri → yt-dlp, gerisi → aria2.
///
/// Genel hız sınırı iki motor arasında paylaştırılır: inmekte olan her indirmeye eşit pay düşer,
/// kendi sınırı payından düşük olanların artanı diğerlerine dağıtılır. aria2'ye kendi indirmelerinin
/// payları toplamı (kendi içinde bölüştürür), her yt-dlp sürecine de kendi payı verilir.
/// Paylar inen indirme sayısı değişince yeniden hesaplanır.
@MainActor
final class RoutingEngine: DownloadEngine {
    private let files: any DownloadEngine
    private let videos: any DownloadEngine

    /// Bu motor üzerinden başlatılmış indirmeler (paylaştırma için).
    private var items: [UUID: DownloadItem] = [:]
    private var globalLimit: Int64?
    private var applied: Plan?
    private var monitor: Task<Void, Never>?

    private struct Plan: Equatable {
        var files: Int64?
        var videos: Int64?
    }

    /// yt-dlp payı ancak bu orandan fazla değişirse uygulanır; her değişiklik süreci yeniden başlatıyor.
    private static let videoRestartThreshold = 0.15

    init(files: any DownloadEngine, videos: any DownloadEngine) {
        self.files = files
        self.videos = videos
    }

    private func engine(for item: DownloadItem) -> any DownloadEngine {
        item.source == .video ? videos : files
    }

    func start(_ item: DownloadItem) {
        items[item.id] = item
        engine(for: item).start(item)
    }

    func pause(_ item: DownloadItem) {
        engine(for: item).pause(item)
    }

    func resume(_ item: DownloadItem) {
        items[item.id] = item
        engine(for: item).resume(item)
    }

    func cancel(_ item: DownloadItem) {
        items[item.id] = nil
        engine(for: item).cancel(item)
    }

    func setSpeedLimit(_ limit: Int64?, for item: DownloadItem) {
        engine(for: item).setSpeedLimit(limit, for: item)
        rebalance()
    }

    func setGlobalSpeedLimit(_ limit: Int64?) {
        globalLimit = limit
        monitor?.cancel()
        monitor = nil
        guard limit != nil else {
            apply(Plan(files: nil, videos: nil))
            return
        }
        rebalance()
        // Durum değişiklikleri motorlardan geliyor; inen sayısını saniyede bir kontrol et.
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.rebalance()
            }
        }
    }

    func setMaxConcurrent(_ count: Int) {
        files.setMaxConcurrent(count)
        videos.setMaxConcurrent(count)
    }

    // MARK: - Paylaştırma

    private func rebalance() {
        guard let globalLimit else { return }
        let active = items.values.filter { $0.status == .downloading }
        let shares = Self.shares(of: globalLimit, caps: active.map(\.speedLimit))
        let fileShares = zip(active, shares).filter { $0.0.source != .video }.map(\.1)
        let videoShares = zip(active, shares).filter { $0.0.source == .video }.map(\.1)

        // Hiç inmeyen tarafa tüm bütçe verilir; yeni bir indirme başlayınca bir saniye içinde paylaşılır.
        var plan = Plan(
            files: fileShares.isEmpty ? globalLimit : fileShares.reduce(0, +),
            videos: videoShares.max() ?? globalLimit
        )
        if let old = applied?.videos, let new = plan.videos, old > 0,
           abs(Double(new - old)) / Double(old) < Self.videoRestartThreshold {
            plan.videos = old
        }
        apply(plan)
    }

    private func apply(_ plan: Plan) {
        guard plan != applied else { return }
        if plan.files != applied?.files { files.setGlobalSpeedLimit(plan.files) }
        if plan.videos != applied?.videos { videos.setGlobalSpeedLimit(plan.videos) }
        applied = plan
    }

    /// Bütçeyi eşit böler; kendi sınırı (cap) payından düşük olana sınırı kadar verip artanı
    /// diğerleri arasında yeniden böler.
    static func shares(of total: Int64, caps: [Int64?]) -> [Int64] {
        var result = [Int64](repeating: 0, count: caps.count)
        var open = Set(caps.indices)
        var remaining = total
        while !open.isEmpty {
            let equal = remaining / Int64(open.count)
            let capped = open.filter { caps[$0].map { $0 <= equal } ?? false }
            guard !capped.isEmpty else {
                open.forEach { result[$0] = equal }
                break
            }
            for index in capped {
                result[index] = caps[index]!
                remaining -= caps[index]!
                open.remove(index)
            }
        }
        return result
    }
}
