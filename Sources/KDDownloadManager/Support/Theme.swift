import SwiftUI
import AppKit

enum Theme {
    /// Kullanıcının seçtiği vurgu rengi (Ayarlar > Görünüm). Seçim değişince panel `PanelView`'daki
    /// `.id` sayesinde yeniden çizilir.
    static var accent: Color { AccentChoice.current.color }
    static let background = Color(light: 0xF3F3F3, dark: 0x1E1E1E)
    static let surface = Color(light: 0xFFFFFF, dark: 0x2A2A2A)
    static let track = Color(light: 0xEDEDED, dark: 0x3A3A3A)
    static let mutedFill = Color(light: 0xEFEFEF, dark: 0x353535)
    static let primaryText = Color(light: 0x111111, dark: 0xF2F2F2)
    static let secondaryText = Color(light: 0x6B6B6B, dark: 0x9A9A9A)

    static let panelWidth: CGFloat = 480
    static let panelHeight: CGFloat = {
        #if DEBUG
        // Ekran görüntüsü aracında uzun ekranların (Ayarlar) tamamını çizebilmek için.
        if let value = ProcessInfo.processInfo.environment["KD_PANEL_HEIGHT"].flatMap(Double.init) {
            return CGFloat(value)
        }
        #endif
        return 600
    }()
    static let cornerRadius: CGFloat = 16
}

/// Uygulamanın teması: macOS'u izler ya da sabit açık/koyu.
enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "Sistem"
        case .light: "Açık"
        case .dark: "Koyu"
        }
    }

    static var current: AppTheme {
        UserDefaults.standard.string(forKey: SettingsKey.appTheme).flatMap(AppTheme.init) ?? .system
    }

    /// Tüm pencerelere (panel, dosya seçme pencereleri) uygular; nil = sistemi izle.
    @MainActor
    static func apply() {
        NSApp.appearance = switch current {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// Vurgu rengi seçenekleri.
enum AccentChoice: String, CaseIterable, Identifiable {
    case orange, system, blue, purple, pink, red, green, teal

    var id: Self { self }

    var title: String {
        switch self {
        case .orange: "Turuncu"
        case .system: "Sistem vurgu rengi"
        case .blue: "Mavi"
        case .purple: "Mor"
        case .pink: "Pembe"
        case .red: "Kırmızı"
        case .green: "Yeşil"
        case .teal: "Turkuaz"
        }
    }

    var color: Color {
        switch self {
        case .orange: Color(hex: 0xFF8500)
        // macOS Ayarlar > Görünüm'deki vurgu rengi; orada değişince burada da değişir.
        case .system: Color(nsColor: .controlAccentColor)
        case .blue: Color(hex: 0x0A84FF)
        case .purple: Color(hex: 0x8E5CF7)
        case .pink: Color(hex: 0xFF2D78)
        case .red: Color(hex: 0xFF3B30)
        case .green: Color(hex: 0x30B350)
        case .teal: Color(hex: 0x14B8C4)
        }
    }

    static var current: AccentChoice {
        UserDefaults.standard.string(forKey: SettingsKey.accentColor).flatMap(AccentChoice.init) ?? .orange
    }

    /// Tarayıcı eklentisinin de aynı rengi kullanması için "#RRGGBB" (sRGB).
    @MainActor
    var hex: String {
        let color = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(srgbRed: 1, green: 0.52, blue: 0, alpha: 1)
        let rgb = [color.redComponent, color.greenComponent, color.blueComponent].map { Int(($0 * 255).rounded()) }
        return String(format: "#%02X%02X%02X", rgb[0], rgb[1], rgb[2])
    }
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
