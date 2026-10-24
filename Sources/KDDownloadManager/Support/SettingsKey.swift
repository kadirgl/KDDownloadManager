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
}
