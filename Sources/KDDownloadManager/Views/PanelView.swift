import SwiftUI
import PhosphorSwift

/// Menü çubuğundan açılan panelin kökü; `store.route`'a göre ekran değiştirir.
struct PanelView: View {
    @Environment(DownloadStore.self) private var store

    var body: some View {
        Group {
            switch store.route {
            case .list: DownloadListView()
            case .addLink: AddLinkView()
            case .settings: SettingsView()
            }
        }
        .frame(width: Theme.panelWidth, height: Theme.panelHeight)
        .background(Theme.background)
        .foregroundStyle(Theme.primaryText)
        .onAppear { store.showCompletedIfIdle() }
        // .torrent dosyası ya da tarayıcıdan link sürükleyip bırakmak.
        .dropDestination(for: URL.self) { urls, _ in
            store.open(urls)
            return !urls.isEmpty
        }
    }
}

/// Beyaz üst şerit: başlık, isteğe bağlı geri butonu ve sağdaki ikonlar.
struct PanelHeader<Trailing: View>: View {
    let title: String
    var onBack: (() -> Void)?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 6) {
            if let onBack {
                Button(action: onBack) {
                    PhIcon(.caretLeft, weight: .bold, size: 16)
                }
                .buttonStyle(IconButtonStyle())
                .keyboardShortcut(.cancelAction)
                .help("Geri")
            }
            Text(title)
                .font(.system(size: 16))
            Spacer()
            trailing
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(Theme.surface)
    }
}

extension PanelHeader where Trailing == EmptyView {
    init(title: String, onBack: (() -> Void)? = nil) {
        self.init(title: title, onBack: onBack) { EmptyView() }
    }
}

/// Beyaz alt şerit (sekme butonları, "İndir" vb.).
struct PanelFooter<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 8) { content }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(Theme.surface)
    }
}
