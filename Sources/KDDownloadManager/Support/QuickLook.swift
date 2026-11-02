import AppKit
import QuickLookUI

/// Tamamlanan dosyanın Boşluk tuşuyla Quick Look önizlemesi. Finder'daki gibi: Boşluk açar ve kapatır,
/// ↑/↓ önizlemedeyken listede bir sonraki dosyaya geçer, kapanınca klavye yeniden panele döner.
@MainActor
final class QuickLook: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLook()
    private var url: URL?
    /// ↑/↓: listede seçimi kaydırır ve yeni seçili dosyayı döndürür (tamamlanmamışsa nil).
    var onMove: ((Int) -> URL?)?

    private var panelIfOpen: QLPreviewPanel? {
        guard QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(), panel.isVisible else { return nil }
        return panel
    }

    /// Aynı dosya için açıksa kapatır.
    func toggle(_ url: URL) {
        if let open = panelIfOpen, self.url == url {
            open.orderOut(nil)
            returnFocus()
            return
        }
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
        panel.makeKeyAndOrderFront(nil)
    }

    /// Menü çubuğu paneli kapanırken önizleme de kapanır.
    func close() {
        panelIfOpen?.orderOut(nil)
    }

    /// Önizleme kapanınca klavye panele dönsün (yoksa ok tuşları ve Boşluk hiçbir yere gitmiyor).
    private func returnFocus() {
        NSApp.windows.first { $0 is PanelWindow && $0.isVisible }?.makeKey()
    }

    private func move(_ offset: Int, in panel: QLPreviewPanel) {
        guard let next = onMove?(offset) else { return }
        url = next
        panel.reloadData()
    }

    // MARK: - QLPreviewPanelDataSource

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        1
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated { url as NSURL? }
    }

    // MARK: - QLPreviewPanelDelegate

    /// Önizleme öndeyken tuşlar ona gidiyor; Boşluk ve ok tuşlarını burada karşılıyoruz.
    nonisolated func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard let event, event.type == .keyDown else { return false }
        let keyCode = event.keyCode
        // Önizlemeyi açan Boşluk basılı tutulursa tekrar olayları buraya geliyor; kapatmasın.
        if event.isARepeat, keyCode == 49 { return true }
        return MainActor.assumeIsolated {
            switch keyCode {
            case 49: // Boşluk
                panel.orderOut(nil)
                returnFocus()
                return true
            case 125, 126: // ↓, ↑
                move(keyCode == 125 ? 1 : -1, in: panel)
                return true
            default:
                return false
            }
        }
    }

    /// Esc ya da kapat düğmesiyle kapanınca da klavye panele dönsün.
    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in self.returnFocus() }
    }
}
