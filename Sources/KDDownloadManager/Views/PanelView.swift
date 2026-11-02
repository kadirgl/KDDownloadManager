import SwiftUI

/// Menü çubuğundan açılan panelin kökü; `store.route`'a göre ekran değiştirir. Arkasındaki bulanıklığı
/// pencere (StatusItemController) çiziyor; burada cama renk, kenar ve üst ışık ekleniyor.
struct PanelView: View {
    @Environment(DownloadStore.self) private var store
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    /// Vurgu rengi değişince tüm paneli yeniden çizmek için.
    @AppStorage(SettingsKey.accentColor) private var accent = AccentChoice.orange.rawValue

    private let shape = RoundedRectangle(cornerRadius: Theme.windowRadius, style: .continuous)

    var body: some View {
        Group {
            switch store.route {
            case .list: DownloadListView()
            case .addLink: AddLinkView()
            case .settings: SettingsView()
            case .onboarding: OnboardingView()
            }
        }
        .frame(width: Theme.panelWidth, height: Theme.panelHeight)
        .background {
            if reduceTransparency {
                shape.fill(Theme.windowSolid)
            } else {
                ZStack {
                    if #available(macOS 26, *) {
                        Color.clear.glassEffect(.regular, in: shape)
                    }
                    shape.fill(Theme.windowTint)
                }
            }
        }
        .overlay(shape.strokeBorder(Theme.windowEdge, lineWidth: 1))
        .overlay(
            shape.strokeBorder(
                LinearGradient(colors: [Theme.windowHighlight, .clear], startPoint: .top, endPoint: .init(x: 0.5, y: 0.08)),
                lineWidth: 1
            )
        )
        .clipShape(shape)
        .foregroundStyle(Theme.primaryText)
        .tint(Theme.accent)
        .id(accent)
        .animation(.snappy(duration: 0.25), value: store.route)
        // .torrent dosyası ya da tarayıcıdan link sürükleyip bırakmak.
        .dropDestination(for: URL.self) { urls, _ in
            store.open(urls)
            return !urls.isEmpty
        }
    }
}
