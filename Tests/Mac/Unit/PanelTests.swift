import AppKit
import Testing
@testable import KDDownloadManager

/// Menü çubuğu paneli: dışarı tıklanınca kapanır, ama Quick Look önizlemesinin içine tıklamak "dışarı" değildir.
@Suite("Panel")
@MainActor
struct PanelTests {
    let button = NSRect(x: 1000, y: 870, width: 30, height: 24)
    let preview = NSRect(x: 100, y: 100, width: 800, height: 500)

    @Test("Önizlemedeki oynatıcıya tıklamak (ileri sarma) paneli kapatmaz")
    func clickInPreview() {
        // Oynatma çubuğu ve 15 sn ileri düğmesi önizlemenin alt kısmında.
        #expect(!StatusItemController.isOutsideClick(at: NSPoint(x: 500, y: 120), statusButton: button, preview: preview))
        #expect(!StatusItemController.isOutsideClick(at: NSPoint(x: 101, y: 599), statusButton: button, preview: preview))
    }

    @Test("Menü çubuğu ikonuna tıklamak kapatmayı ikonun kendisine bırakır")
    func clickOnStatusButton() {
        #expect(!StatusItemController.isOutsideClick(at: NSPoint(x: 1015, y: 880), statusButton: button, preview: nil))
        // İkonun hemen kenarı da (2 pt pay).
        #expect(!StatusItemController.isOutsideClick(at: NSPoint(x: 999, y: 880), statusButton: button, preview: nil))
    }

    @Test("Başka bir yere tıklamak paneli kapatır; önizleme kapalıyken onun yeri de dışarıdır")
    func clickOutside() {
        #expect(StatusItemController.isOutsideClick(at: NSPoint(x: 950, y: 300), statusButton: button, preview: preview))
        #expect(StatusItemController.isOutsideClick(at: NSPoint(x: 500, y: 300), statusButton: button, preview: nil))
        #expect(StatusItemController.isOutsideClick(at: NSPoint(x: 500, y: 300), statusButton: nil, preview: nil))
    }
}
