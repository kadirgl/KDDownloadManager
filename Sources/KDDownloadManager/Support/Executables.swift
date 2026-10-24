import Foundation

/// aria2c, yt-dlp, ffmpeg gibi yardımcı programları bulur.
/// Önce uygulamanın içine gömülenlere (Contents/Helpers/bin, scripts/bundle-tools.sh), sonra arama
/// yoluna bakar. Finder'dan açılan uygulamanın PATH'i kısıtlı olduğu için Homebrew klasörleri de aranır.
enum Executables {
    /// Paketli uygulamada gömülü araçların klasörü; `swift run` ile çalışırken yok.
    static let bundledFolder: URL? = {
        let folder = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/bin", isDirectory: true)
        return FileManager.default.fileExists(atPath: folder.path) ? folder : nil
    }()

    static let searchPath: [String] = {
        let inherited = (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin")
            .split(separator: ":").map(String.init)
        var seen = Set<String>()
        let all = ([bundledFolder?.path].compactMap { $0 } + inherited + ["/opt/homebrew/bin", "/usr/local/bin"])
            .filter { seen.insert($0).inserted }
        #if DEBUG
        // Homebrew'suz bir Mac'i denemek için: sadece gömülü araçlar ve sistem klasörleri.
        if ProcessInfo.processInfo.environment["KD_NO_HOMEBREW"] != nil {
            return all.filter { !$0.hasPrefix("/opt/homebrew") && !$0.hasPrefix("/usr/local") }
        }
        #endif
        return all
    }()

    static func find(_ name: String) -> URL? {
        // Uygulama içinden güncellenen yt-dlp, paketteki sürümden yeniyse o kullanılır.
        if name == "yt-dlp", let updated = YtDlpUpdater.preferredBinary() {
            return updated
        }
        return searchPath
            .map { URL(fileURLWithPath: $0).appendingPathComponent(name) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// Alt süreçler için ortam; gömülü araçlar ve Homebrew klasörleri PATH'in başında.
    static var environment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = searchPath.joined(separator: ":")
        return environment
    }

    /// yt-dlp'nin YouTube doğrulamasını çözmek için kullanacağı JavaScript motoru. Mac'te deno varsa
    /// (daha hızlı) yt-dlp onu kendisi bulur; yoksa uygulamaya gömülü QuickJS kullanılır.
    static var javaScriptRuntimeArguments: [String] {
        if find("deno") != nil { return [] }
        guard let quickjs = find("qjs") else { return [] }
        return ["--no-js-runtimes", "--js-runtimes", "quickjs:" + quickjs.path]
    }
}
