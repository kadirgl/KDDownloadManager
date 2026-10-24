import Foundation

/// aria2c, yt-dlp, ffmpeg gibi yardımcı programları bulur.
/// Finder'dan açılan uygulamanın PATH'i kısıtlı olduğu için Homebrew klasörleri de aranır.
enum Executables {
    static let searchPath: [String] = {
        let inherited = (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin")
            .split(separator: ":").map(String.init)
        var seen = Set<String>()
        return (inherited + ["/opt/homebrew/bin", "/usr/local/bin"]).filter { seen.insert($0).inserted }
    }()

    /// Önce uygulama paketine (ileride gömülecek), sonra arama yoluna bakar.
    static func find(_ name: String) -> URL? {
        if let bundled = Bundle.main.url(forResource: name, withExtension: nil) {
            return bundled
        }
        return searchPath
            .map { URL(fileURLWithPath: $0).appendingPathComponent(name) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// Alt süreçler için ortam; yt-dlp'nin deno/ffmpeg'i bulabilmesi için PATH genişletilmiş.
    static var environment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = searchPath.joined(separator: ":")
        return environment
    }
}
