#if DEBUG
import Foundation

/// Geliştirme aracı: uygulama güncelleyicisini dener (denetle → indir → imzayı doğrula → paketi değiştir).
/// Kurulu uygulamaya dokunmamak için hedef bir kopya verilir; kurulan paket açılmaz.
///
///     KD_APP_UPDATE_TEST=1 KD_UPDATE_API=http://127.0.0.1:8797/latest KD_UPDATE_KEY=<açık anahtar> \
///     KD_UPDATE_TARGET=/tmp/hedef/KDDownloadManager.app .build/debug/KDDownloadManager
///
/// `KD_UPDATE_CORRUPT=1` ile imzası tutmayan paketin reddedildiğini görün.
@MainActor
enum DebugAppUpdateTest {
    static func runIfRequested() {
        guard ProcessInfo.processInfo.environment["KD_APP_UPDATE_TEST"] != nil else { return }
        let updater = AppUpdater.shared
        Task {
            for (a, b, expected) in [("1.5.10", "1.5.9", true), ("1.6.0", "1.6", false), ("1.5.5", "1.6.0", false)] {
                let result = AppUpdater.isNewer(a, than: b)
                print("isNewer(\(a), \(b)) = \(result) \(result == expected ? "✓" : "✗ beklenen \(expected)")")
            }
            print("kullanılabilir: \(AppUpdater.isAvailable), sorun: \(AppUpdater.installProblem ?? "-")")
            await updater.check()
            print("denetim: \(updater.state)")
            guard updater.availableRelease != nil else { exit(0) }
            updater.install()
            // Başarılı kurulum uygulamayı kapatır; buraya gelinirse hata vardır.
            while updater.isBusy { try? await Task.sleep(for: .milliseconds(200)) }
            print("kurulum: \(updater.state)")
            exit(0)
        }
    }
}
#endif
