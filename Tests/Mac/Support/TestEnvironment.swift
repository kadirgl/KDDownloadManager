import Foundation
@testable import KDDownloadManager

/// Testler gerçek listeye, ayarlara, indirme klasörüne ve uygulama klasörüne dokunmasın diye her şey
/// geçici bir klasöre yönlendirilir. Ortam değişkenleri uygulama kodu ilk okumadan önce ayarlanmalı;
/// bu yüzden her test `TestEnvironment.prepare()` ile başlar (yalnızca ilk çağrı iş yapar).
enum TestEnvironment {
    /// Bu test çalıştırmasının kök klasörü; `scripts/test.sh` bitince siler.
    static let root: URL = {
        let base = ProcessInfo.processInfo.environment["KD_TEST_ROOT"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("KDDownloadManagerTests-\(getpid())")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    /// Köprü testlerinin portu; kurulu uygulamanın 47615'iyle çakışmaz.
    static let bridgePort: UInt16 = 47_690

    private static let once: Void = {
        setenv("KD_SUPPORT_DIR", root.appendingPathComponent("Support").path, 1)
        setenv("KD_BRIDGE_PORT", String(bridgePort), 1)
        // Ayarlar diske yazılmayan (argüman) alanında: test süreci bittiğinde kaybolur.
        UserDefaults.standard.setVolatileDomain([
            SettingsKey.downloadFolder: root.appendingPathComponent("Downloads").path,
            SettingsKey.notifyOnAdd: false,
            SettingsKey.notifyOnFinish: false,
            SettingsKey.notifyOnFail: false,
        ], forName: UserDefaults.argumentDomain)
        try? FileManager.default.createDirectory(at: root.appendingPathComponent("Downloads"), withIntermediateDirectories: true)
    }()

    static func prepare() { _ = once }

    /// Her teste ayrı, boş bir klasör.
    static func scratch(_ name: String = #function) -> URL {
        prepare()
        let safe = name.filter { $0.isLetter || $0.isNumber }
        let folder = root.appendingPathComponent("scratch/\(safe)-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Depo kökü (Package.swift'in klasörü); tutarlılık testleri eklenti ve Windows dosyalarını okur.
    static let repository: URL = {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) { return url }
        }
        fatalError("Package.swift bulunamadı")
    }()

    /// Belirtilen koşul sağlanana kadar bekler (en fazla `timeout` sn); sağlandıysa true.
    @MainActor
    static func wait(timeout: Double, poll: Double = 0.1, until condition: @MainActor () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .seconds(poll))
        }
        return condition()
    }
}
