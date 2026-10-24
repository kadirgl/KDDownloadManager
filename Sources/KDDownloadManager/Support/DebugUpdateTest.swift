#if DEBUG
import Foundation

/// Geliştirme aracı: yt-dlp güncelleyicisini dener (indir → doğrula → kur, ikinci denetimde "güncel",
/// sürüm karşılaştırması). `KD_TOOLS_DIR` ile gerçek klasöre dokunmadan çalıştırın;
/// `KD_UPDATE_CORRUPT=1` ile bozuk dosyanın reddedildiğini görün.
///
///     KD_UPDATE_TEST=1 KD_TOOLS_DIR=/tmp/kd-tools .build/debug/KDDownloadManager
@MainActor
enum DebugUpdateTest {
    static func runIfRequested() {
        guard ProcessInfo.processInfo.environment["KD_UPDATE_TEST"] != nil else { return }
        let updater = YtDlpUpdater.shared

        Task {
            let cases = [("2026.10.21.1", "2026.10.21", true), ("2026.10.21", "2026.10.21", false),
                         ("2026.9.30", "2026.10.21", false), ("2027.01.02", "2026.12.31", true)]
            for (a, b, expected) in cases {
                let result = YtDlpUpdater.isNewer(a, than: b)
                print("isNewer(\(a), \(b)) = \(result) \(result == expected ? "✓" : "✗ beklenen \(expected)")")
            }

            print("önce: \(updater.current), yt-dlp → \(Executables.find("yt-dlp")?.path ?? "-")")
            await updater.update()
            print("1. denetim: \(updater.state)")
            print("sonra: \(updater.current), yt-dlp → \(Executables.find("yt-dlp")?.path ?? "-")")
            await updater.update()
            print("2. denetim: \(updater.state)")
            let files = (try? FileManager.default.contentsOfDirectory(atPath: YtDlpUpdater.folder.path)) ?? []
            print("klasör: \(files.sorted())")
            fflush(stdout)
            exit(0)
        }
    }
}
#endif
