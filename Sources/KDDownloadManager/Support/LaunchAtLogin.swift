import Foundation
import ServiceManagement

/// "Oturum açınca başlat" ayarı. Chrome eklentisinin çalışması için uygulamanın açık olması gerektiğinden
/// önemli. macOS bunu Ayarlar > Genel > Giriş Öğeleri'nde de gösterir; durum her zaman sistemden okunur.
@MainActor
enum LaunchAtLogin {
    /// Sadece .app paketinden çalışırken kullanılabilir (`swift run` ile değil).
    static var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
