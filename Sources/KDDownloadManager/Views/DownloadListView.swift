import SwiftUI
import PhosphorSwift

/// Ana ekran: başlık, kategori çipleri, indirme listesi ve alt sekmeler.
struct DownloadListView: View {
    @Environment(DownloadStore.self) private var store

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            PanelHeader(title: "KD Download Manager") {
                Button { store.route = .addLink } label: {
                    PhIcon(.link, size: 20)
                }
                .buttonStyle(IconButtonStyle())
                .keyboardShortcut("n")
                .help("Link ekle (⌘N)")

                Button { store.route = .settings } label: {
                    PhIcon(.gear, size: 20)
                }
                .buttonStyle(IconButtonStyle())
                .keyboardShortcut(",")
                .help("Ayarlar (⌘,)")
            }

            CategoryBar(selection: $store.category)

            if store.visibleItems.isEmpty {
                EmptyListView()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(store.visibleItems) { item in
                            DownloadRow(item: item)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }

            BottomBar()
        }
    }
}

private struct CategoryBar: View {
    @Binding var selection: DownloadCategory

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(DownloadCategory.allCases) { category in
                    Button(category.title) { selection = category }
                        .buttonStyle(PillButtonStyle(
                            prominent: selection == category,
                            inactiveFill: Theme.surface,
                            horizontalPadding: 9,
                            fontSize: 12
                        ))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .scrollClipDisabled()
    }
}

private struct BottomBar: View {
    @Environment(DownloadStore.self) private var store

    var body: some View {
        PanelFooter {
            ForEach(ListTab.allCases) { tab in
                Button { store.tab = tab } label: {
                    HStack(spacing: 6) {
                        PhIcon(tab.icon, weight: .fill, size: 14)
                        Text(tab.title)
                    }
                }
                .buttonStyle(PillButtonStyle(prominent: store.tab == tab))
            }
            Spacer()
            HStack(spacing: 4) {
                PhIcon(.arrowDown, weight: .bold, size: 14)
                Text(ByteFormat.speed(store.totalSpeed))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .font(.system(size: 13, weight: .medium))
            .help("Toplam indirme hızı")
        }
    }
}

private struct EmptyListView: View {
    @Environment(DownloadStore.self) private var store

    var body: some View {
        VStack(spacing: 12) {
            PhIcon(store.tab == .active ? .downloadSimple : .flag, weight: .light, size: 44)
                .foregroundStyle(Theme.secondaryText)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)
            if store.tab == .active {
                Button { store.route = .addLink } label: {
                    HStack(spacing: 6) {
                        PhIcon(.link, weight: .bold, size: 14)
                        Text("Link ekle")
                    }
                }
                .buttonStyle(PillButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var message: String {
        let scope = store.category == .all ? "" : "\(store.category.title) kategorisinde "
        switch store.tab {
        case .active: return "\(scope)devam eden indirme yok"
        case .completed: return "\(scope)tamamlanan indirme yok"
        }
    }
}
