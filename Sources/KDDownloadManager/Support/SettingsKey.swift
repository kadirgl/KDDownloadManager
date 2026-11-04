import Foundation

/// UserDefaults / @AppStorage anahtarları.
enum SettingsKey {
    static let showSpeedInMenuBar = "showSpeedInMenuBar"
    static let globalLimitEnabled = "globalLimitEnabled"
    static let globalLimitMB = "globalLimitMB"
    static let defaultGlobalLimitMB = 10.0
    static let maxConcurrent = "maxConcurrent"
    static let downloadFolder = "downloadFolder"
    static let extensionSeen = "extensionSeen"
    static let notifyOnAdd = "notifyOnAdd"
    static let notifyOnFinish = "notifyOnFinish"
    static let notifyOnFail = "notifyOnFail"
    static let appTheme = "appTheme"
    static let accentColor = "accentColor"
    static let ytDlpAutoUpdate = "ytDlpAutoUpdate"
    static let ytDlpLastCheck = "ytDlpLastCheck"
    static let appAutoUpdateCheck = "appAutoUpdateCheck"
    static let appUpdateLastCheck = "appUpdateLastCheck"
    /// Bildirimi gönderilen son sürüm (her yeni sürüm için bir kez bildirilir).
    static let appUpdateAnnounced = "appUpdateAnnounced"
    /// Listedeki güncelleme bandının kapatıldığı sürüm.
    static let appUpdateBannerDismissed = "appUpdateBannerDismissed"
    /// İlk açılıştaki eklenti kurulumunda "Şimdilik geç" seçildi; kurulum ekranı bir daha zorla açılmaz.
    static let onboardingSkipped = "onboardingSkipped"
    /// Bir tarayıcı eklentisi en az bir kez bağlandı (sonradan kaldırılsa da kurulum ekranı zorla açılmaz).
    static let extensionEverConnected = "extensionEverConnected"
    /// "Chrome eklentisi bağlı değil" bandının kapatıldığı an (7 gün sonra yeniden çıkar).
    static let extensionBannerDismissed = "extensionBannerDismissed"
    /// Tamamlanan listesinin sırası (CompletedSort).
    static let completedSort = "completedSort"

    static var defaultDownloadFolder: String {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
            ?? NSHomeDirectory() + "/Downloads"
    }

    /// Ayarlardaki indirme klasörü (seçilmediyse ~/Downloads).
    static var downloadFolderURL: URL {
        let path = UserDefaults.standard.string(forKey: downloadFolder) ?? defaultDownloadFolder
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static let defaultMaxConcurrent = 3

    /// Parçalı indirme: bir dosya/video bu kadar paralel bağlantıyla indirilir (aria2 en fazla 16).
    static let connections = "connections"
    static let defaultConnections = 8

    static var connectionCount: Int {
        let value = UserDefaults.standard.object(forKey: connections) as? Int ?? defaultConnections
        return min(max(value, 1), 16)
    }

    private static let importedDevelopmentSettings = "importedDevelopmentSettings"

    /// `swift run` ile çalışırken ayarlar "KDDownloadManager" alanına yazılıyor, .app ise paket kimliğini
    /// kullanıyor. Paketli uygulama ilk açıldığında oradaki ayarları bir kereliğine taşır.
    static func importDevelopmentSettings() {
        let defaults = UserDefaults.standard
        guard Bundle.main.bundleIdentifier != nil,
              defaults.object(forKey: importedDevelopmentSettings) == nil else { return }
        defaults.set(true, forKey: importedDevelopmentSettings)
        guard let development = UserDefaults(suiteName: "KDDownloadManager") else { return }
        for key in [showSpeedInMenuBar, globalLimitEnabled, globalLimitMB, maxConcurrent, downloadFolder]
        where defaults.object(forKey: key) == nil {
            if let value = development.object(forKey: key) {
                defaults.set(value, forKey: key)
            }
        }
    }
}
