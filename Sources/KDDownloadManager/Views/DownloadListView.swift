import SwiftUI
import AppKit

/// Ana ekran: başlık, kategori rayı, indirme kartları ve altta yüzen iki cam kapsül.
/// Alttaki Devam Eden / Tamamlanan listeyi duruma göre, kategori rayı o durumun içinde süzer.
struct DownloadListView: View {
    @Environment(DownloadStore.self) private var store

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            PanelHeader(title: "KD Download Manager") {
                Button { store.route = .addLink } label: {
                    Image(systemName: "link")
                }
                .buttonStyle(GlassIconButtonStyle(size: 40))
                .keyboardShortcut("n")
                .help("Link ekle (⌘N)")
                .accessibilityLabel("Link ekle")

                Button { store.route = .settings } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(GlassIconButtonStyle(size: 40))
                .keyboardShortcut(",")
                .help("Ayarlar (⌘,)")
                .accessibilityLabel("Ayarlar")
            }

            ExtensionBanner()
            FailedBanner()

            if store.items.contains(where: { store.tab.includes($0.status) }) {
                CategoryRail(selection: $store.category)
                ListSummary()
                if store.visibleItems.isEmpty {
                    EmptyCategoryView()
                } else {
                    ScrollView {
                        LazyVStack(spacing: Theme.cardSpacing) {
                            ForEach(store.visibleItems) { item in
                                DownloadRow(item: item)
                            }
                        }
                        .padding(.horizontal, Theme.margin)
                        .padding(.top, 2)
                        // Son satır yüzen barın arkasında kalmasın.
                        .padding(.bottom, Theme.bottomBarClearance)
                    }
                    .scrollIndicators(.never)
                }
            } else {
                EmptyListView()
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .bottom) { BottomBar() }
        .background { ListShortcuts() }
    }
}

// MARK: - Kategori rayı

/// Tek cam ray; yalnızca o görünümde dosyası olan kategoriler sayısıyla görünür.
private struct CategoryRail: View {
    @Environment(DownloadStore.self) private var store
    @Binding var selection: DownloadCategory
    @Namespace private var namespace

    var body: some View {
        let counts = Dictionary(grouping: store.items.filter { store.tab.includes($0.status) }, by: \.category)
            .mapValues(\.count)
        let total = counts.values.reduce(0, +)
        let categories = DownloadCategory.allCases.filter {
            $0 == .all || (counts[$0] ?? 0) > 0 || $0 == selection
        }

        ScrollView(.horizontal) {
            HStack(spacing: 2) {
                ForEach(categories) { category in
                    let count = category == .all ? total : counts[category] ?? 0
                    let selected = selection == category
                    Button { selection = category } label: {
                        HStack(spacing: 5) {
                            Text(category.title)
                                .font(.system(size: 12.5, weight: selected ? .semibold : .medium))
                            Text("\(count)")
                                .font(.system(size: 11, weight: .medium))
                                .monospacedDigit()
                                .opacity(selected ? 0.8 : 0.6)
                        }
                        .foregroundStyle(selected ? Theme.onAccent : Theme.primaryText)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(Theme.accent)
                                    .shadow(color: Theme.accentGlow, radius: 6, y: 3)
                                    .matchedGeometryEffect(id: "chip", in: namespace)
                            }
                        }
                        .opacity(count == 0 && !selected ? 0.4 : 1)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(category.title), \(count) dosya")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(3)
        }
        .scrollIndicators(.never)
        // Taşarsa sağ kenarda solma.
        .mask(
            HStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 18)
            }
        )
        .glassCard(radius: 18)
        .padding(.horizontal, Theme.margin)
        .padding(.bottom, 12)
        .animation(.snappy(duration: 0.25), value: selection)
    }
}

// MARK: - Liste üstü özet ve toplu işlemler

private struct ListSummary: View {
    @Environment(DownloadStore.self) private var store

    var body: some View {
        HStack {
            Text(summary)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
                .monospacedDigit()
            Spacer()
            switch store.tab {
            case .active:
                if store.items.contains(where: { ListTab.active.includes($0.status) && !$0.isFailed }) {
                    let paused = store.allActivePaused
                    Button {
                        paused ? store.resumeAll() : store.pauseAll()
                    } label: {
                        Label(paused ? "Tümünü devam ettir" : "Tümünü duraklat",
                              systemImage: paused ? "play.fill" : "pause.fill")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(GlassCapsuleButtonStyle(height: 26, fontSize: 11.5))
                }
            case .completed:
                Menu {
                    Button("İndirme klasörünü aç") { NSWorkspace.shared.open(store.downloadFolder) }
                    Divider()
                    Button("Listeyi temizle (dosyalar diskte kalır)") { store.clearCompleted() }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 30, height: 26)
                        .strongGlass(Capsule())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Diğer işlemler")
                .accessibilityLabel("Diğer işlemler")
            }
        }
        .padding(.horizontal, Theme.margin + 2)
        .padding(.bottom, 10)
    }

    private var summary: String {
        let items = store.items.filter { store.tab.includes($0.status) }
        switch store.tab {
        case .active:
            var parts: [String] = []
            func add(_ count: Int, _ word: String) { if count > 0 { parts.append("\(count) \(word)") } }
            add(items.filter { $0.status == .downloading || $0.status == .processing }.count, "iniyor")
            add(items.filter { $0.status == .queued }.count, "sırada")
            add(items.filter { $0.status == .paused }.count, "duraklatıldı")
            add(items.filter(\.isFailed).count, "hata")
            return parts.joined(separator: " · ")
        case .completed:
            let size = items.reduce(Int64(0)) { $0 + $1.totalBytes }
            return "\(items.count) dosya · \(ByteFormat.size(size))"
        }
    }
}

// MARK: - Alt bar

/// Pencerenin içinde yüzen iki cam kapsül: solda Devam Eden / Tamamlanan, sağda toplam hız.
private struct BottomBar: View {
    @Environment(DownloadStore.self) private var store
    @AppStorage(SettingsKey.globalLimitEnabled) private var limitEnabled = false
    @AppStorage(SettingsKey.globalLimitMB) private var limitMB = SettingsKey.defaultGlobalLimitMB
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                ForEach(ListTab.allCases) { tab in
                    tabButton(tab)
                }
            }
            .padding(4)
            .strongGlass(Capsule())

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 1) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 11, weight: .bold))
                    Text(ByteFormat.speed(store.displaySpeed))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .font(.system(size: 13, weight: .semibold))
                .opacity(store.displaySpeed > 0 ? 1 : 0.55)
                if limitEnabled {
                    Label("Sınır \(Int(limitMB)) MB/sn", systemImage: "gauge.with.dots.needle.33percent")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 46)
            .strongGlass(Capsule())
            .help("Toplam indirme hızı")
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, Theme.margin - 4)
        .padding(.bottom, 14)
        .animation(.snappy(duration: 0.25), value: store.tab)
    }

    private func tabButton(_ tab: ListTab) -> some View {
        let selected = store.tab == tab
        let count = store.items.filter { tab.includes($0.status) }.count
        return Button { store.tab = tab } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 10, weight: .bold))
                Text(tab.title)
                    .font(.system(size: 13, weight: .semibold))
                if count > 0 {
                    CountBadge(count: count, onAccent: selected)
                }
            }
            .foregroundStyle(selected ? Theme.onAccent : Theme.primaryText)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background {
                if selected {
                    Capsule()
                        .fill(Theme.accent)
                        .shadow(color: Theme.accentGlow, radius: 8, y: 4)
                        .matchedGeometryEffect(id: "tab", in: namespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(tab == .active ? "Devam Eden (⌘1)" : "Tamamlanan (⌘2)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Boş durumlar

/// Seçili sekmede hiç indirme yok.
private struct EmptyListView: View {
    @Environment(DownloadStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle()
                    .strokeBorder(Theme.glassEdge, lineWidth: 1)
                    .background(Circle().fill(Theme.glass.opacity(0.5)))
                    .frame(width: 124, height: 124)
                Image(systemName: store.tab == .active ? "arrow.down.to.line" : "checkmark")
                    .font(.system(size: 30, weight: .semibold))
                    .frame(width: 92, height: 92)
                    .strongGlass(Circle())
            }
            .padding(.bottom, 26)
            .accessibilityHidden(true)

            Text(store.tab == .active ? "Devam eden indirme yok" : "Henüz tamamlanan indirme yok")
                .font(.system(size: 17, weight: .semibold))
                .padding(.bottom, 6)

            switch store.tab {
            case .active:
                Text("Bir link ekle ya da Chrome'da bir dosya indir, burada görünür.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
                    .padding(.bottom, 20)
                Button { store.route = .addLink } label: {
                    Label("Link ekle", systemImage: "link")
                }
                .buttonStyle(AccentButtonStyle(height: 38, fontSize: 14))
                .padding(.bottom, 14)
                HStack(spacing: 4) {
                    Text("ya da linki kopyalayıp")
                    KeyCap(key: "⌘")
                    KeyCap(key: "V")
                    Text("yap")
                }
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.secondaryText)
            case .completed:
                let active = store.items.filter { ListTab.active.includes($0.status) }.count
                Text(active > 0 ? "\(active) indirme devam ediyor." : "Biten indirmeler burada görünür.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.bottom, 20)
                if active > 0 {
                    Button("Devam edenlere git") { store.tab = .active }
                        .buttonStyle(GlassCapsuleButtonStyle(height: 34, fontSize: 13))
                }
            }
            Spacer()
            Spacer().frame(height: Theme.bottomBarClearance - 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.margin)
    }
}

/// Sekmede indirme var ama seçili kategoride kalmadı.
private struct EmptyCategoryView: View {
    @Environment(DownloadStore.self) private var store

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            CategoryIcon(category: store.category, size: 52)
                .opacity(0.6)
            Text("Bu kategoride dosya kalmadı")
                .font(.system(size: 15, weight: .semibold))
            Button("Tümünü göster") { store.category = .all }
                .buttonStyle(GlassCapsuleButtonStyle(height: 32, fontSize: 12.5))
            Spacer()
            Spacer().frame(height: Theme.bottomBarClearance - 20)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Eklenti bandı

/// "Şimdilik geç" denip eklenti hiç bağlanmadıysa listenin üstünde sarı band; kapatılırsa 7 gün sonra yeniden çıkar.
private struct ExtensionBanner: View {
    @Environment(DownloadStore.self) private var store
    @AppStorage(SettingsKey.onboardingSkipped) private var skipped = false
    @AppStorage(SettingsKey.extensionBannerDismissed) private var dismissed = 0.0

    var body: some View {
        if skipped, store.extensionSeen.isEmpty, Date().timeIntervalSince1970 - dismissed > 7 * 86_400 {
            HStack(spacing: 10) {
                Image(systemName: "puzzlepiece.extension.fill")
                    .foregroundStyle(Theme.warning)
                Text("Chrome eklentisi bağlı değil")
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
                Button("Kur") { store.route = .onboarding }
                    .buttonStyle(GlassCapsuleButtonStyle(height: 26, fontSize: 12))
                Button {
                    dismissed = Date().timeIntervalSince1970
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("7 gün sonra yeniden hatırlat")
                .accessibilityLabel("Kapat")
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.warning.opacity(0.14))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.warning.opacity(0.35)))
            )
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, 12)
        }
    }
}

/// Birden fazla indirme başarısız olduysa listenin üstünde kırmızı band ve "Tümünü tekrar dene".
private struct FailedBanner: View {
    @Environment(DownloadStore.self) private var store

    var body: some View {
        let failed = store.items.filter(\.isFailed).count
        if store.tab == .active, failed > 1 {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.error)
                Text("\(failed) indirme tamamlanamadı")
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
                Button("Tümünü tekrar dene") { store.retryFailed() }
                    .buttonStyle(GlassCapsuleButtonStyle(height: 26, fontSize: 12))
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.error.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.error.opacity(0.35)))
            )
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, 12)
        }
    }
}

// MARK: - Kısayollar

/// ⌘V: panodaki link ya da magnet ile Link ekle'yi açar; ⌘1 / ⌘2: sekmeler.
private struct ListShortcuts: View {
    @Environment(DownloadStore.self) private var store

    var body: some View {
        ZStack {
            Button("") {
                guard let text = NSPasteboard.general.string(forType: .string),
                      !DownloadStore.parseLinks(text).isEmpty else { return }
                store.route = .addLink
            }
            .keyboardShortcut("v")
            Button("") { store.tab = .active }
                .keyboardShortcut("1")
            Button("") { store.tab = .completed }
                .keyboardShortcut("2")
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}
