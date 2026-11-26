import Foundation
@testable import KDDownloadManager

/// Mağazanın motora ne söylediğini kaydeden sahte motor; ağ ya da süreç yok.
@MainActor
final class RecordingEngine: DownloadEngine {
    enum Call: Equatable {
        case start(UUID), pause(UUID), resume(UUID), cancel(UUID)
        case speedLimit(UUID, Int64?), globalLimit(Int64?), maxConcurrent(Int)
    }

    private(set) var calls: [Call] = []

    func start(_ item: DownloadItem) {
        calls.append(.start(item.id))
        item.setStatus(.downloading)
    }

    func pause(_ item: DownloadItem) {
        calls.append(.pause(item.id))
        item.setStatus(.paused)
    }

    func resume(_ item: DownloadItem) {
        calls.append(.resume(item.id))
        item.setStatus(.downloading)
    }

    func cancel(_ item: DownloadItem) { calls.append(.cancel(item.id)) }

    func setSpeedLimit(_ limit: Int64?, for item: DownloadItem) {
        calls.append(.speedLimit(item.id, limit))
        item.speedLimit = limit
    }

    func setGlobalSpeedLimit(_ limit: Int64?) { calls.append(.globalLimit(limit)) }
    func setMaxConcurrent(_ count: Int) { calls.append(.maxConcurrent(count)) }

    func count(_ match: (Call) -> Bool) -> Int { calls.filter(match).count }
}
