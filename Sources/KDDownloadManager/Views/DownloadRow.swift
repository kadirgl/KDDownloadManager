import SwiftUI
import AppKit

/// Listedeki tek indirme kartı.
struct DownloadRow: View {
    @Environment(DownloadStore.self) private var store
    let item: DownloadItem
    @State private var showingLimit = false

    var body: some View {
        HStack(spacing: 14) {
            FileTile(icon: item.category.icon)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.fileName)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(item.fileName)
                    Spacer(minLength: 0)
                    Text("%\(Int(item.progress * 100))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .monospacedDigit()
                }
                ProgressBar(value: item.progress, tint: barTint)
                HStack(spacing: 18) {
                    statusText
                    Text(item.totalBytes > 0 ? ByteFormat.size(item.totalBytes) : "—")
                }
                .font(.system(size: 12))
                .monospacedDigit()
                .lineLimit(1)
            }

            actions
        }
        .padding(8)
        .padding(.trailing, 6)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(Theme.surface)
        )
        .contextMenu { contextMenu }
    }

    // MARK: - Parçalar

    @ViewBuilder
    private var statusText: some View {
        switch item.status {
        case .downloading:
            Text(ByteFormat.speed(item.speed))
        case .queued:
            Text("Sırada").foregroundStyle(Theme.secondaryText)
        case .paused:
            Text("Duraklatıldı").foregroundStyle(Theme.secondaryText)
        case .completed:
            Text("Tamamlandı").foregroundStyle(Theme.secondaryText)
        case .failed(let message):
            Text(message).foregroundStyle(.red).help(message)
        }
    }

    private var barTint: Color {
        switch item.status {
        case .paused, .queued: Theme.secondaryText.opacity(0.5)
        case .failed: .red
        default: Theme.accent
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 4) {
            if item.status == .completed {
                Button { store.revealInFinder(item) } label: {
                    PhIcon(.folderOpen, size: 22)
                }
                .help("Finder'da göster")
            } else {
                Button { showingLimit.toggle() } label: {
                    PhIcon(.gauge, size: 22)
                        .foregroundStyle(item.speedLimit == nil ? Theme.primaryText : Theme.accent)
                }
                .help(item.speedLimit.map { "Hız sınırı: \(ByteFormat.speed($0))" } ?? "Hız sınırı")
                .popover(isPresented: $showingLimit, arrowEdge: .bottom) {
                    SpeedLimitPicker(current: item.speedLimit) { limit in
                        store.setSpeedLimit(limit, for: item)
                        showingLimit = false
                    }
                }

                Button { store.togglePause(item) } label: {
                    PhIcon(pauseIcon, size: 22)
                }
                .help(pauseHelp)
            }

            Button { store.cancel(item) } label: {
                PhIcon(.xCircle, size: 22)
            }
            .help(item.status == .completed ? "Listeden kaldır" : "İptal et")
        }
        .buttonStyle(IconButtonStyle())
    }

    private var pauseIcon: Ph {
        switch item.status {
        case .paused: .playCircle
        case .failed: .arrowClockwise
        default: .pauseCircle
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
        Button("Linki kopyala") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.url, forType: .string)
        }
        if item.status == .completed {
            Button("Finder'da göster") { store.revealInFinder(item) }
        } else {
            Button(pauseHelp) { store.togglePause(item) }
        }
        Divider()
        Button(item.status == .completed ? "Listeden kaldır" : "İptal et", role: .destructive) {
            store.cancel(item)
        }
    }
}

/// Hız sınırı butonunun açtığı küçük seçim listesi.
private struct SpeedLimitPicker: View {
    let current: Int64?
    let onSelect: (Int64?) -> Void

    private static let presetsMB: [Int64] = [1, 2, 5, 10, 25, 50]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Hız sınırı")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            option("Sınırsız", limit: nil)
            ForEach(Self.presetsMB, id: \.self) { mb in
                option("\(mb) MB/S", limit: mb * 1_048_576)
            }
        }
        .padding(8)
        .frame(width: 150)
    }

    private func option(_ title: String, limit: Int64?) -> some View {
        Button { onSelect(limit) } label: {
            HStack {
                Text(title)
                Spacer()
                if current == limit {
                    PhIcon(.check, weight: .bold, size: 12)
                        .foregroundStyle(Theme.accent)
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowButtonStyle())
    }
}

private struct MenuRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MenuRowBody(configuration: configuration)
    }

    private struct MenuRowBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.mutedFill.opacity(hovering ? 1 : 0))
                )
                .opacity(configuration.isPressed ? 0.6 : 1)
                .onHover { hovering = $0 }
        }
    }
}
