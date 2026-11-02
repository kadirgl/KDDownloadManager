import SwiftUI
import AppKit

/// Listedeki tek indirme: solda kategori ikonu, ortada ad / yüzde / çubuk / durum, sağda cam butonlar.
/// Her zaman görünen tek buton duraklat / devam ettir (hatada tekrar dene); hız sınırı ve sil, fare
/// satırın üstüne gelince görünür. Özel hız sınırı varsa ibre turuncu olarak hep görünür.
struct DownloadRow: View {
    @Environment(DownloadStore.self) private var store
    let item: DownloadItem
    @State private var hovering = false
    @State private var showingLimit = false

    private var isCompleted: Bool { item.status == .completed }

    var body: some View {
        HStack(spacing: 14) {
            CategoryIcon(category: item.category)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.fileName)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(item.fileName)
                    Spacer(minLength: 0)
                    if !isCompleted {
                        Text("%\(Int(item.progress * 100))")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.secondaryText)
                            .monospacedDigit()
                            .fixedSize()
                    }
                }
                ProgressBar(value: isCompleted ? 1 : item.progress, tint: barTint, glows: item.status == .downloading)
                statusLine
            }

            actions
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .padding(.vertical, 12)
        .background {
            if item.isFailed {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(Theme.error.opacity(0.08))
            }
        }
        .glassCard()
        .overlay {
            if item.isFailed {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Theme.error.opacity(0.55), lineWidth: 1)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .onHover { hovering = $0 }
        // Çift tık: tamamlanan dosyayı aç (butonların tek tıklamasını geciktirmesin diye eşzamanlı).
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            if isCompleted, let destination = item.destination {
                NSWorkspace.shared.open(destination)
            }
        })
        // Tamamlanan dosya Finder'a ya da başka bir uygulamaya sürüklenebilir.
        .onDrag {
            guard isCompleted, let destination = item.destination else { return NSItemProvider() }
            return NSItemProvider(contentsOf: destination) ?? NSItemProvider()
        }
        .contextMenu { contextMenu }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.fileName), \(accessibilityStatus)")
    }

    // MARK: - Durum satırı

    @ViewBuilder
    private var statusLine: some View {
        HStack(spacing: 8) {
            switch item.status {
            case .downloading:
                if item.speed > 0 {
                    Text([ByteFormat.speed(item.speed), item.remainingSeconds.map(ByteFormat.remaining)]
                        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .fontWeight(.semibold)
                } else {
                    Text("Bağlanıyor…").foregroundStyle(Theme.secondaryText)
                }
                totalSize
            case .queued:
                Text("Sırada").foregroundStyle(Theme.secondaryText)
                totalSize
            case .processing:
                Text("Birleştiriliyor…").foregroundStyle(Theme.secondaryText)
                totalSize
            case .paused:
                Text("Duraklatıldı").foregroundStyle(Theme.secondaryText)
                Text(item.totalBytes > 0
                     ? "\(ByteFormat.size(item.downloadedBytes)) / \(ByteFormat.size(item.totalBytes))"
                     : ByteFormat.size(item.downloadedBytes))
                    .fontWeight(.semibold)
            case .completed:
                Text(ByteFormat.size(item.totalBytes)).fontWeight(.semibold)
                if let site = URL(string: item.url)?.host() {
                    Text(site.replacingOccurrences(of: "www.", with: "")).foregroundStyle(Theme.secondaryText)
                }
            case .failed(let message):
                Text(message)
                    .foregroundStyle(Theme.errorText)
                    .help(message)
            }
            if let limit = item.speedLimit, !isCompleted {
                Label(ByteFormat.speed(limit), systemImage: "gauge.with.dots.needle.33percent")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.accentText)
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(Capsule().fill(Theme.accent.opacity(0.14)))
                    .help("Bu indirmeye özel hız sınırı")
            }
        }
        .font(.system(size: 12))
        .monospacedDigit()
        .lineLimit(1)
    }

    @ViewBuilder
    private var totalSize: some View {
        if item.totalBytes > 0 {
            Text(ByteFormat.size(item.totalBytes)).foregroundStyle(Theme.secondaryText)
        }
    }

    private var barTint: Color {
        switch item.status {
        case .paused, .queued: Theme.doneBar.opacity(0.8)
        case .failed: Theme.error
        case .completed: Theme.doneBar
        default: Theme.accent
        }
    }

    private var accessibilityStatus: String {
        switch item.status {
        case .downloading: "indiriliyor, yüzde \(Int(item.progress * 100))"
        case .queued: "sırada"
        case .processing: "birleştiriliyor"
        case .paused: "duraklatıldı, yüzde \(Int(item.progress * 100))"
        case .completed: "tamamlandı"
        case .failed(let message): "başarısız: \(message)"
        }
    }

    // MARK: - Butonlar

    @ViewBuilder
    private var actions: some View {
        let showSecondary = hovering || showingLimit
        HStack(spacing: 6) {
            if isCompleted {
                if showSecondary {
                    iconButton("folder", help: "Klasörde göster") { store.revealInFinder(item) }
                    iconButton("xmark", help: "Listeden kaldır (dosya diskte kalır)") { store.cancel(item) }
                }
            } else {
                if showSecondary || item.speedLimit != nil, !item.isFailed {
                    Button { showingLimit.toggle() } label: {
                        Image(systemName: "gauge.with.dots.needle.33percent")
                    }
                    .buttonStyle(GlassIconButtonStyle(size: 36, tint: item.speedLimit == nil ? nil : Theme.accentText))
                    .help(item.speedLimit.map { "Hız sınırı: \(ByteFormat.speed($0))" } ?? "Hız sınırı")
                    .accessibilityLabel("Hız sınırı")
                    .popover(isPresented: $showingLimit, arrowEdge: .bottom) {
                        SpeedLimitMenu(current: item.speedLimit) { limit in
                            store.setSpeedLimit(limit, for: item)
                            showingLimit = false
                        }
                    }
                }
                if showSecondary {
                    iconButton("trash", help: "İndirmeyi sil") { store.cancel(item) }
                }
                iconButton(pauseSymbol, help: pauseHelp) { store.togglePause(item) }
            }
        }
        .animation(.easeOut(duration: 0.15), value: showSecondary)
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
        }
        .buttonStyle(GlassIconButtonStyle(size: 36))
        .help(help)
        .accessibilityLabel(help)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    private var pauseSymbol: String {
        switch item.status {
        case .paused: "play.fill"
        case .failed: "arrow.clockwise"
        default: "pause.fill"
        }
    }

    private var pauseHelp: String {
        switch item.status {
        case .paused: "Devam et"
        case .failed: "Tekrar dene"
        default: "Duraklat"
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        if !isCompleted {
            Button(pauseHelp) { store.togglePause(item) }
            Menu("Hız sınırı") {
                ForEach(SpeedLimitMenu.options, id: \.title) { option in
                    Toggle(option.title, isOn: Binding(
                        get: { item.speedLimit == option.limit },
                        set: { _ in store.setSpeedLimit(option.limit, for: item) }
                    ))
                }
            }
        }
        Button("Klasörde göster") { store.revealInFinder(item) }
        Button("Linki kopyala") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.url, forType: .string)
        }
        Divider()
        Button(isCompleted ? "Listeden kaldır" : "İndirmeyi sil", role: .destructive) {
            store.cancel(item)
        }
    }
}

/// Hız sınırı butonunun açtığı cam menü.
struct SpeedLimitMenu: View {
    let current: Int64?
    let onSelect: (Int64?) -> Void
    @AppStorage(SettingsKey.globalLimitEnabled) private var limitEnabled = false
    @AppStorage(SettingsKey.globalLimitMB) private var limitMB = SettingsKey.defaultGlobalLimitMB

    static let options: [(title: String, limit: Int64?)] =
        [("Sınırsız", nil)] + [1, 2, 5, 10, 25, 50].map { ("\($0) MB/sn", Int64($0) * 1_048_576) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel(title: "Bu indirme için hız sınırı")
                .padding(.horizontal, 6)
                .padding(.bottom, 4)
            ForEach(Self.options, id: \.title) { option in
                let selected = current == option.limit
                Button { onSelect(option.limit) } label: {
                    HStack {
                        Text(option.title)
                            .font(.system(size: 13, weight: selected ? .semibold : .regular))
                        Spacer()
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.accentText)
                        }
                    }
                }
                .buttonStyle(MenuRowButtonStyle(selected: selected))
            }
            if limitEnabled {
                Text("Genel sınır \(Int(limitMB)) MB/sn; daha yüksek değerler bununla kısıtlanır.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
                    .padding(.top, 6)
            }
        }
        .padding(10)
        .frame(width: 230)
    }
}
