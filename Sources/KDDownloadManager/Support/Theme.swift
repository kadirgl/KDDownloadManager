import SwiftUI
import AppKit

enum Theme {
    static let accent = Color(hex: 0xFF8500)
    static let background = Color(light: 0xF3F3F3, dark: 0x1E1E1E)
    static let surface = Color(light: 0xFFFFFF, dark: 0x2A2A2A)
    static let track = Color(light: 0xEDEDED, dark: 0x3A3A3A)
    static let mutedFill = Color(light: 0xEFEFEF, dark: 0x353535)
    static let primaryText = Color(light: 0x111111, dark: 0xF2F2F2)
    static let secondaryText = Color(light: 0x6B6B6B, dark: 0x9A9A9A)

    static let panelWidth: CGFloat = 480
    static let panelHeight: CGFloat = 600
    static let cornerRadius: CGFloat = 16
}

extension Color {
    init(hex: UInt32) {
        self.init(nsColor: NSColor(hex: hex))
    }

    /// Açık/koyu moda göre otomatik değişen renk.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(hex: dark)
                : NSColor(hex: light)
        })
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
