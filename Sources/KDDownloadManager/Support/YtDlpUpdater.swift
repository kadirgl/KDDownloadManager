import Foundation
import CryptoKit
import Observation

/// Gömülü yt-dlp'yi güncel tutar. YouTube sık değiştiği için yt-dlp birkaç haftada bir güncellenmezse
/// video indirmeleri bozulabiliyor.
///
/// Yeni sürüm imzalı uygulama paketine değil, Application Support/KDDownloadManager/Tools'a indirilir
/// (paketin içi değişirse imza bozulur). `Executables`, paketteki ile indirilmiş olandan hangisi
/// yeniyse onu kullanır. İndirme yalnızca resmi GitHub sürümünden yapılır ve aynı sürümdeki
/// SHA2-256SUMS ile doğrulanır; dosya çalıştırılıp sürümü kontrol edildikten sonra yerine konur.
/// Çalışan indirmeler etkilenmez (eski dosya, süreç bitene kadar diskte kalır).
@MainActor
@Observable
final class YtDlpUpdater {
    enum State: Equatable {
        case idle
        case checking
        case downloading(String)
        case upToDate
        case updated(String)
        case failed(String)
    }

    static let shared = YtDlpUpdater()

    private(set) var state: State = .idle
    /// Şu an kullanılan sürüm ve nereden geldiği (Ayarlar'da gösterilir).
    private(set) var current = YtDlpUpdater.installed()
    private(set) var lastCheck: Date? = UserDefaults.standard.object(forKey: SettingsKey.ytDlpLastCheck) as? Date

    private static let release = "https://github.com/yt-dlp/yt-dlp/releases"
    private static let latestAPI = URL(string: "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest")!
    /// Otomatik denetim en fazla bu sıklıkta.
    private static let automaticInterval: TimeInterval = 24 * 3600

    // MARK: - Hangi yt-dlp kullanılıyor

    struct Installed: Equatable {
        enum Origin { case bundled, downloaded, system }
        let version: String?
        let origin: Origin
    }

    /// İndirilen güncellemelerin klasörü.
    nonisolated static var folder: URL {
        #if DEBUG
        // Denemelerde gerçek klasöre dokunmamak için.
        if let path = ProcessInfo.processInfo.environment["KD_TOOLS_DIR"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        #endif
        return AppFolders.support.appendingPathComponent("Tools", isDirectory: true)
    }

    nonisolated private static var downloadedBinary: URL { folder.appendingPathComponent("yt-dlp") }
    nonisolated private static var downloadedVersionFile: URL { folder.appendingPathComponent("yt-dlp.version") }

    /// Paketteki yt-dlp'nin sürümü (package-app.sh, Contents/Resources/yt-dlp.version'a yazar).
    nonisolated private static var bundledVersion: String? {
        guard Executables.bundledFolder != nil,
              let file = Bundle.main.url(forResource: "yt-dlp", withExtension: "version") else { return nil }
        return readVersion(file)
    }

    nonisolated private static func readVersion(_ file: URL) -> String? {
        (try? String(contentsOf: file, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// İndirilmiş güncelleme, paketteki sürümden yeniyse onun yolu; değilse nil (paketteki kullanılır).
    nonisolated static func preferredBinary() -> URL? {
        guard FileManager.default.isExecutableFile(atPath: downloadedBinary.path),
              let downloaded = readVersion(downloadedVersionFile) else { return nil }
        if let bundled = bundledVersion, !isNewer(downloaded, than: bundled) { return nil }
        return downloadedBinary
    }

    nonisolated static func installed() -> Installed {
        if preferredBinary() != nil {
            return Installed(version: readVersion(downloadedVersionFile), origin: .downloaded)
        }
        if let bundled = bundledVersion {
            return Installed(version: bundled, origin: .bundled)
        }
        return Installed(version: nil, origin: .system)
    }

    /// yt-dlp sürümleri "2026.10.21" ya da "2026.10.21.1" biçiminde; parça parça sayı olarak karşılaştırılır.
    nonisolated static func isNewer(_ candidate: String, than other: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = other.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: - Güncelleme

    var isBusy: Bool {
        switch state {
        case .checking, .downloading: true
        default: false
        }
    }

    /// Açılışta: ayar açıksa ve son denetimden beri bir gün geçtiyse sessizce denetler.
    func checkAutomaticallyIfDue() {
        let enabled = UserDefaults.standard.object(forKey: SettingsKey.ytDlpAutoUpdate) as? Bool ?? true
        guard enabled, current.origin != .system else { return }
        if let lastCheck, Date().timeIntervalSince(lastCheck) < Self.automaticInterval { return }
        Task { await update() }
    }

    func update() async {
        guard !isBusy else { return }
        state = .checking
        do {
            let latest = try await Self.latestVersion()
            lastCheck = Date()
            UserDefaults.standard.set(lastCheck, forKey: SettingsKey.ytDlpLastCheck)
            if let version = current.version, !Self.isNewer(latest, than: version) {
                state = .upToDate
                return
            }
            state = .downloading(latest)
            try await Self.install(latest)
            current = Self.installed()
            state = .updated(latest)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private struct UpdateError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private static func latestVersion() async throws -> String {
        var request = URLRequest(url: latestAPI, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let tag = try JSONDecoder().decode(JSONValue.self, from: data)["tag_name"]?.stringValue,
              tag.range(of: #"^\d{4}\.\d{2}\.\d{2}(\.\d+)?$"#, options: .regularExpression) != nil else {
            throw UpdateError(message: "Güncel sürüm bilgisi alınamadı")
        }
        return tag
    }

    /// İndirir, doğrular, çalıştırıp sürümünü kontrol eder ve eskisinin yerine koyar.
    private static func install(_ version: String) async throws {
        let base = URL(string: "\(release)/download/\(version)")!
        let (sums, _) = try await URLSession.shared.data(from: base.appendingPathComponent("SHA2-256SUMS"))
        guard let expected = String(decoding: sums, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map({ $0.split(separator: " ", omittingEmptySubsequences: true) })
            .first(where: { $0.count == 2 && $0[1] == "yt-dlp_macos" })?[0] else {
            throw UpdateError(message: "Doğrulama listesi okunamadı")
        }

        let (temporary, response) = try await URLSession.shared.download(from: base.appendingPathComponent("yt-dlp_macos"))
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw UpdateError(message: "yt-dlp indirilemedi")
        }
        let binary = corruptedForTesting(try Data(contentsOf: temporary))
        let actual = SHA256.hash(data: binary).map { String(format: "%02x", $0) }.joined()
        guard actual == String(expected) else {
            throw UpdateError(message: "İndirilen dosya doğrulanamadı (SHA-256 uyuşmuyor); kurulmadı")
        }

        let manager = FileManager.default
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let staged = folder.appendingPathComponent("yt-dlp.new")
        try? manager.removeItem(at: staged)
        try binary.write(to: staged)
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staged.path)

        guard try await reportedVersion(of: staged) == version else {
            try? manager.removeItem(at: staged)
            throw UpdateError(message: "İndirilen yt-dlp çalıştırılamadı; kurulmadı")
        }
        // Yerine koyma tek adımda; çalışan yt-dlp süreçleri eski dosyayla bitirir.
        if manager.fileExists(atPath: downloadedBinary.path) {
            _ = try manager.replaceItemAt(downloadedBinary, withItemAt: staged)
        } else {
            try manager.moveItem(at: staged, to: downloadedBinary)
        }
        try version.write(to: downloadedVersionFile, atomically: true, encoding: .utf8)
    }

    /// DEBUG'da `KD_UPDATE_CORRUPT` ile dosyayı bozar; doğrulamanın bozuk dosyayı reddettiğini denemek için.
    private static func corruptedForTesting(_ data: Data) -> Data {
        #if DEBUG
        if ProcessInfo.processInfo.environment["KD_UPDATE_CORRUPT"] != nil, !data.isEmpty {
            var corrupted = data
            corrupted[corrupted.count / 2] ^= 0xFF
            return corrupted
        }
        #endif
        return data
    }

    private static func reportedVersion(of binary: URL) async throws -> String {
        try await Task.detached {
            let process = Process()
            process.executableURL = binary
            process.arguments = ["--version"]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
    }
}
