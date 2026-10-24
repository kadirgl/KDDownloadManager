import Foundation

/// Arayüzün indirme motorundan beklediği her şey.
///
/// - `Aria2Engine`: aria2c'yi JSON-RPC ile yönetir (HTTP, çoklu bağlantı, torrent/magnet, hız sınırı)
/// - `YtDlpEngine`: YouTube vb. siteler için yt-dlp + ffmpeg
/// - `RoutingEngine`: her indirmeyi kaynağına göre bu ikisinden birine yollar
/// - `MockDownloadEngine`: arayüz denemeleri ve ekran görüntüleri için sahte motor
@MainActor
protocol DownloadEngine: AnyObject {
    func start(_ item: DownloadItem)
    func pause(_ item: DownloadItem)
    func resume(_ item: DownloadItem)
    func cancel(_ item: DownloadItem)
    func setSpeedLimit(_ limit: Int64?, for item: DownloadItem)
    func setGlobalSpeedLimit(_ limit: Int64?)
    func setMaxConcurrent(_ count: Int)
}

extension DownloadItem {
    /// Motorların durum güncellemesi; değişmeyen değerleri yeniden yazıp arayüzü boşuna tetiklemez.
    func setStatus(_ status: DownloadStatus, speed: Int64 = 0) {
        if self.status != status { self.status = status }
        if self.speed != speed { self.speed = speed }
    }
}
