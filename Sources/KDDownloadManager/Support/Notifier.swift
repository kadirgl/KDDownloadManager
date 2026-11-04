import AppKit
import UserNotifications

/// İndirme eklendi / tamamlandı / başarısız oldu bildirimleri.
/// Tamamlanan indirmenin bildirimine tıklanınca dosya Finder'da gösterilir.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    /// Bildirim merkezi yalnızca .app paketinden çalışırken kullanılabilir; paketsiz çalıştırılabilir
    /// dosyada (swift run, geliştirme senaryoları) çağrıldığında süreç çöküyor.
    static var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    private nonisolated static let fileKey = "file"

    func setUp() {
        guard Self.isAvailable else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func downloadsAdded(_ names: [String]) {
        guard Self.enabled(SettingsKey.notifyOnAdd), !names.isEmpty else { return }
        let title = names.count == 1 ? "İndirme eklendi" : "\(names.count) indirme eklendi"
        post(title: title, body: names.prefix(3).joined(separator: ", ") + (names.count > 3 ? "…" : ""), sound: false)
    }

    func downloadFinished(_ item: DownloadItem) {
        guard Self.enabled(SettingsKey.notifyOnFinish) else { return }
        post(title: "İndirme tamamlandı", body: item.fileName, file: item.destination, sound: true)
    }

    func downloadFailed(_ item: DownloadItem, message: String) {
        guard Self.enabled(SettingsKey.notifyOnFail) else { return }
        post(title: "İndirme başarısız", body: "\(item.fileName)\n\(message)", sound: true)
    }

    func updateAvailable(_ version: String) {
        post(title: "Yeni sürüm: \(version)", body: "KD Download Manager'ı güncellemek için tıklayın.", sound: false)
    }

    /// Ayarlanmamışsa açık sayılır.
    private static func enabled(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }

    private func post(title: String, body: String, file: URL? = nil, sound: Bool) {
        #if DEBUG
        // Geliştirme sürümünde bildirim merkezi yok; ne gönderileceği görülebilsin.
        if !Self.isAvailable { print("[bildirim] \(title): \(body.replacingOccurrences(of: "\n", with: " — "))") }
        #endif
        guard Self.isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.threadIdentifier = "downloads"
        if sound { content.sound = .default }
        if let file { content.userInfo = [Self.fileKey: file.path] }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Menü çubuğu uygulaması çoğu zaman "ön planda" sayıldığı için bildirimler yine de gösterilsin.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let path = response.notification.request.content.userInfo[Self.fileKey] as? String
        await MainActor.run {
            // Biten dosyanın bildirimi dosyayı Finder'da gösterir; diğerleri (eklendi, hata) paneli açar.
            if let path, FileManager.default.fileExists(atPath: path) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            } else {
                NotificationCenter.default.post(name: StatusItemController.openPanelNotification, object: nil)
            }
        }
    }
}
