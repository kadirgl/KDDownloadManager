import SwiftUI
import AppKit

/// Menü çubuğunda görünen ikon (+ isteğe bağlı anlık toplam hız).
struct MenuBarLabel: View {
    let store: DownloadStore
    @AppStorage(SettingsKey.showSpeedInMenuBar) private var showSpeed = true

    var body: some View {
        Image(nsImage: Self.icon)
        if showSpeed, store.displaySpeed > 0 {
            Text(Self.fixedWidth(ByteFormat.speed(store.displaySpeed)))
                .monospacedDigit()
        }
    }

    /// Menü çubuğu etiketi frame kabul etmediği için genişliği rakam genişliğindeki boşlukla
    /// (U+2007) sabitliyoruz; hız değiştikçe yanındaki ikonlar kaymasın.
    private static func fixedWidth(_ text: String) -> String {
        String(repeating: "\u{2007}", count: max(0, 8 - text.count)) + text
    }

    /// MenuBarExtra etiketi SwiftUI frame'lerini yok saydığı için
    /// Phosphor ikonunu sabit boyutlu bir template NSImage'a çeviriyoruz.
    private static let icon: NSImage = {
        let renderer = ImageRenderer(content: Ph.arrowCircleDown.weight(.bold).frame(width: 16, height: 16))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage()
        image.size = NSSize(width: 16, height: 16)
        image.isTemplate = true
        return image
    }()
}
