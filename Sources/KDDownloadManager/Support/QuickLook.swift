import AppKit
import QuickLookUI

/// Tamamlanan dosyanın Boşluk tuşuyla Quick Look önizlemesi.
///
/// Önizleme klavyeyi almadan gösteriliyor: menü çubuğu paneli uygulamayı öne almadan klavye alabiliyor ama
/// Quick Look penceresi alamıyor; anahtar pencere olunca Boşluk ve ok tuşları öndeki başka bir uygulamaya
/// gidiyordu. Klavye panelde kalıyor: Boşluk kapatır, ↑/↓ listede gezer ve önizleme seçili dosyaya geçer,
/// Esc kapatır. Önizlemeye tıklanıp anahtar olursa aynı tuşlar orada da çalışır.
@MainActor
final class QuickLook: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLook()
    private var url: URL?
    /// Önizleme anahtar penceredeyken ↑/↓: listede seçimi kaydırır ve yeni seçili dosyayı döndürür.
    var onMove: ((Int) -> URL?)?

    private var openPanel: QLPreviewPanel? {
        guard QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(), panel.isVisible else { return nil }
        return panel
    }

    var isVisible: Bool { openPanel != nil }

    /// Aynı dosya için açıksa kapatır, değilse gösterir.
    func toggle(_ url: URL) {
        if isVisible, self.url == url {
            close()
        } else {
            show(url)
        }
    }

    /// Önizlemeyi bu dosyaya geçirir; kapalıysa açar.
    func show(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            NSSound.beep()
            return
        }
        guard let panel = QLPreviewPanel.shared() else { return }
        self.url = url
        panel.dataSource = self
        panel.delegate = self
        // Menü çubuğu panelinin (durum çubuğu seviyesinde) altında kalmasın.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.reloadData()
        if keyObserver == nil {
            // Quick Look açılış animasyonu bitince kendini anahtar pencere yapıyor; her seferinde klavye
            // panele geri verilir (önizlemede kaydırma ve tıklama anahtar olmadan da çalışıyor).
            keyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: panel, queue: .main
            ) { _ in
                // Quick Look işini bitirsin diye bir sonraki döngüde.
                DispatchQueue.main.async { QuickLook.shared.returnFocus() }
            }
        }
        panel.becomesKeyOnlyIfNeeded = true
        if !panel.isVisible {
            panel.orderFront(nil)
        }
        returnFocus()
        // Açılış animasyonu sırasında anahtar olmayı birkaç kez deniyor; ilk saniye boyunca geri al.
        for delay in [0.15, 0.4, 0.8] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, isVisible else { return }
                returnFocus()
            }
        }
    }

    private var keyObserver: (any NSObjectProtocol)?

    /// Önizleme açıkken seçilen satır değişti: tamamlanmış bir dosyaysa önizleme ona geçer.
    func follow(_ url: URL?) {
        guard isVisible, let url, url != self.url else { return }
        show(url)
    }

    func close() {
        openPanel?.orderOut(nil)
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
        keyObserver = nil
        returnFocus()
    }

    /// Önizlemeye tıklanıp anahtar olduysa klavye panele dönsün.
    private func returnFocus() {
        NSApp.windows.first { $0 is PanelWindow && $0.isVisible }?.makeKey()
    }

    // MARK: - QLPreviewPanelDataSource

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        1
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated { url as NSURL? }
    }

    // MARK: - QLPreviewPanelDelegate

    /// Önizleme anahtar penceredeyse (üstüne tıklandıysa) tuşlar ona gidiyor.
    nonisolated func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard let event, event.type == .keyDown else { return false }
        let keyCode = event.keyCode
        let isRepeat = event.isARepeat
        return MainActor.assumeIsolated {
            switch keyCode {
            case 49: // Boşluk; basılı tutulunca gelen tekrarlar kapatmasın.
                if !isRepeat { close() }
                return true
            case 53: // Esc
                close()
                return true
            case 125, 126: // ↓, ↑
                if let next = onMove?(keyCode == 125 ? 1 : -1) { show(next) }
                return true
            default:
                return false
            }
        }
    }

    /// Kapat düğmesiyle kapanınca da klavye panele dönsün.
    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in self.returnFocus() }
    }
}
