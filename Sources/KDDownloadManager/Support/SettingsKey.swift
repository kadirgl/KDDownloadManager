import Foundation

/// UserDefaults / @AppStorage anahtarları.
enum SettingsKey {
    static let showSpeedInMenuBar = "showSpeedInMenuBar"
    static let globalLimitEnabled = "globalLimitEnabled"
    static let globalLimitMB = "globalLimitMB"
    static let maxConcurrent = "maxConcurrent"
    static let downloadFolder = "downloadFolder"

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
