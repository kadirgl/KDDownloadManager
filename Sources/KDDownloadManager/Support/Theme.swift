import SwiftUI
import AppKit

/// Liquid Glass tasarım token'ları (tasarım rehberi: "Tasarım tokenları" ve "Açık tema").
/// Renkler açık/koyu temaya göre kendiliğinden değişir.
enum Theme {
    /// Kullanıcının seçtiği vurgu rengi (Ayarlar > Görünüm). Seçim değişince panel `PanelView`'daki
    /// `.id` sayesinde yeniden çizilir.
    static var accent: Color { AccentChoice.current.color }

    /// Vurgu zeminindeki yazı ve ikonlar: koyu (#1D1D1F) ve beyazdan hangisi vurguyla daha yüksek
    /// kontrast oranı (WCAG) veriyorsa o. Kullanıcı istediği rengi seçebildiği için sabit değil, hesaplanıyor.
    /// Örneğin turuncu üstünde koyu yazı 6,7:1, beyaz 2,5:1.
    static var onAccent: Color {
        let accent = AccentChoice.current.luminance
        let dark = AccentChoice.luminance(of: NSColor(hex: 0x1D1D1F))
        let darkContrast = (accent + 0.05) / (dark + 0.05)
        let whiteContrast = 1.05 / (accent + 0.05)
        return darkContrast >= whiteContrast ? Color(hex: 0x1D1D1F) : .white
    }

    /// Vurgu renginde yazı: koyu temada açılmış, açık temada koyulaştırılmış vurgu.
    static var accentText: Color {
        let base = NSColor(accent).usingColorSpace(.sRGB) ?? .orange
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.isDark
                ? base.blended(withFraction: 0.35, of: .white) ?? base
                : base.blended(withFraction: 0.38, of: .black) ?? base
        })
    }

    static var accentGlow: Color {
        let base = NSColor(accent)
        return Color(nsColor: NSColor(name: nil) { appearance in
            base.withAlphaComponent(appearance.isDark ? 0.45 : 0.35)
        })
    }

    static let primaryText = Color(light: .init(hex: 0x1D1D1F), dark: .white)
    static let secondaryText = Color(
        light: .black.withAlphaComponent(contrast(0.62)),
        dark: .white.withAlphaComponent(contrast(0.72))
    )
    static let tertiaryText = Color(light: .black.withAlphaComponent(0.55), dark: .white.withAlphaComponent(0.55))
    static let divider = Color(light: .black.withAlphaComponent(0.08), dark: .white.withAlphaComponent(0.08))
    static let track = Color(light: .black.withAlphaComponent(0.08), dark: .white.withAlphaComponent(0.12))
    static let doneBar = Color(light: .black.withAlphaComponent(0.28), dark: .white.withAlphaComponent(0.55))
    /// Rozet ve etiket zemini (sayı rozetleri, "HD", klavye tuşları).
    static let badge = Color(light: .black.withAlphaComponent(0.07), dark: .white.withAlphaComponent(0.18))
    static let switchOff = Color(light: .black.withAlphaComponent(0.12), dark: .white.withAlphaComponent(0.16))
    static let success = Color(light: .init(hex: 0x16A34A), dark: .init(hex: 0x4ADE80))
    static let error = Color(light: .init(hex: 0xE5484D), dark: .init(hex: 0xFF6B6B))
    static let errorText = Color(light: .init(hex: 0xB42318), dark: .init(hex: 0xFF8A8A))
    static let warning = Color(light: .init(hex: 0xB7791F), dark: .init(hex: 0xFACC15))
    /// Gölgeler açık temada saf siyah yerine mor-gri; yüzeyler daha yumuşak görünüyor.
    static let shadow = Color(light: NSColor(hex: 0x281E50).withAlphaComponent(0.14), dark: .black.withAlphaComponent(0.35))

    // Cam katmanları
    /// Pencere camının rengi: koyu temada #1C1A22 %58, açıkta beyaz %70 (okunabilirlik için
    /// rehberdeki ilk değerlerden — %42 / %55 — daha opak).
    static let windowTint = Color(
        light: .white.withAlphaComponent(0.70),
        dark: NSColor(hex: 0x1C1A22).withAlphaComponent(0.58)
    )
    /// "Şeffaflığı azalt" açıkken camın yerine düz zemin.
    static let windowSolid = Color(light: .init(hex: 0xF4F4F7), dark: .init(hex: 0x232129))
    static let windowEdge = Color(light: .black.withAlphaComponent(0.06), dark: .white.withAlphaComponent(0.10))
    static let windowHighlight = Color(light: .white.withAlphaComponent(0.95), dark: .white.withAlphaComponent(0.28))
    /// Kartlar, sekme rayı, ikon butonlar.
    static let glass = Color(light: .white.withAlphaComponent(0.55), dark: .white.withAlphaComponent(0.07))
    static let glassEdge = Color(light: .black.withAlphaComponent(0.05), dark: .white.withAlphaComponent(0.08))
    static let glassHighlight = Color(light: .white.withAlphaComponent(0.95), dark: .white.withAlphaComponent(0.22))
    /// Yüzen bar, küçük butonlar, stepper.
    static let strongGlass = Color(light: .white.withAlphaComponent(0.72), dark: .white.withAlphaComponent(0.12))
    static let strongGlassEdge = Color(light: .black.withAlphaComponent(0.06), dark: .white.withAlphaComponent(0.10))
    static let strongGlassHighlight = Color(light: .white, dark: .white.withAlphaComponent(0.35))
    /// Tema seçicinin seçili hapı.
    static let selectedPill = Color(light: .white, dark: .white.withAlphaComponent(0.22))

    static let panelWidth: CGFloat = 460
    static let panelHeight: CGFloat = {
        #if DEBUG
        // Ekran görüntüsü aracında uzun ekranların (Ayarlar) tamamını çizebilmek için.
        if let value = ProcessInfo.processInfo.environment["KD_PANEL_HEIGHT"].flatMap(Double.init) {
            return CGFloat(value)
        }
        #endif
        return 680
    }()
    static let windowRadius: CGFloat = 30
    static let cardRadius: CGFloat = 22
    static let iconRadius: CGFloat = 12
    /// Kenar boşluğu ve aralıklar.
    static let margin: CGFloat = 18
    static let cardSpacing: CGFloat = 10
    static let sectionSpacing: CGFloat = 18
    /// Listenin altında yüzen bar için bırakılan boşluk.
    static let bottomBarClearance: CGFloat = 96

    /// "Kontrastı artır" açıkken ikincil yazılar daha opak.
    private static func contrast(_ opacity: CGFloat) -> CGFloat {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 0.85 : opacity
    }
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

/// Vurgu rengi seçenekleri; `custom` kullanıcının renk panelinden seçtiği renk.
enum AccentChoice: String, CaseIterable, Identifiable {
    case orange, system, blue, purple, pink, red, green, teal, custom

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
        case .custom: "Özel renk"
        }
    }

    var color: Color {
        switch self {
        case .orange: Color(hex: 0xF08A2E)
        // macOS Ayarlar > Görünüm'deki vurgu rengi; orada değişince burada da değişir.
        case .system: Color(nsColor: .controlAccentColor)
        case .blue: Color(hex: 0x0A84FF)
        case .purple: Color(hex: 0x8E5CF7)
        case .pink: Color(hex: 0xFF2D78)
        case .red: Color(hex: 0xFF3B30)
        case .green: Color(hex: 0x30B350)
        case .teal: Color(hex: 0x14B8C4)
        // Henüz seçilmediyse turuncu (renk paneli de ondan başlar).
        case .custom: Color(nsColor: Self.customColor ?? NSColor(hex: 0xF08A2E))
        }
    }

    /// Renk panelinden seçilen renk ("#RRGGBB" olarak saklanıyor); seçilmediyse nil.
    static var customColor: NSColor? {
        guard let text = UserDefaults.standard.string(forKey: SettingsKey.accentCustomColor),
              text.hasPrefix("#"), text.count == 7, let value = UInt32(text.dropFirst(), radix: 16) else { return nil }
        return NSColor(hex: value)
    }

    /// Göreli parlaklık (WCAG); vurgu zeminindeki yazının rengini seçmek için.
    var luminance: CGFloat { Self.luminance(of: NSColor(color)) }

    static func luminance(of color: NSColor) -> CGFloat {
        guard let rgb = color.usingColorSpace(.sRGB) else { return 0.3 }
        func linear(_ value: CGFloat) -> CGFloat {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
    }

    static var current: AccentChoice {
        UserDefaults.standard.string(forKey: SettingsKey.accentColor).flatMap(AccentChoice.init) ?? .orange
    }

    /// Tarayıcı eklentisinin de aynı rengi kullanması için "#RRGGBB" (sRGB).
    @MainActor
    var hex: String { Self.hex(of: NSColor(color)) }

    static func hex(of color: NSColor) -> String {
        let color = color.usingColorSpace(.sRGB) ?? NSColor(srgbRed: 0.94, green: 0.54, blue: 0.18, alpha: 1)
        let rgb = [color.redComponent, color.greenComponent, color.blueComponent].map { Int((min(max($0, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", rgb[0], rgb[1], rgb[2])
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(nsColor: NSColor(hex: hex))
    }

    /// Açık/koyu moda göre otomatik değişen renk.
    init(light: UInt32, dark: UInt32) {
        self.init(light: NSColor(hex: light), dark: NSColor(hex: dark))
    }

    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { $0.isDark ? dark : light })
    }
}

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
