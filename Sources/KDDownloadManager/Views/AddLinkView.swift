import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Link yapıştırıp indirme başlatma ekranı: bağlantı alanı, bulunan linkler, video kalitesi ve seçenekler.
struct AddLinkView: View {
    @Environment(DownloadStore.self) private var store
    @AppStorage(SettingsKey.downloadFolder) private var downloadFolder = SettingsKey.defaultDownloadFolder
    @State private var text = ""
    @State private var quality: VideoQuality = .auto
    @State private var speedLimit: Int64?
    @State private var startNow = true
    /// Alan açılışta panodan dolduruldu ("Panodaki link otomatik eklendi").
    @State private var filledFromClipboard = false
    @FocusState private var editorFocused: Bool

    private var links: [String] { DownloadStore.parseLinks(text) }
    private var hasVideoLinks: Bool { links.contains { DownloadSource.detect($0) == .video } }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Link ekle", onBack: { store.route = .list })

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(title: "Bağlantı")
                        editor
                        Label(
                            filledFromClipboard
                                ? "Panodaki link otomatik eklendi · dosya, video ve magnet desteklenir"
                                : "Her satıra bir link · dosya, video ve magnet desteklenir",
                            systemImage: filledFromClipboard ? "doc.on.clipboard" : "info.circle"
                        )
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.horizontal, 4)
                    }

                    if !links.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(links.prefix(20).enumerated()), id: \.offset) { index, link in
                                if index > 0 { GlassDivider().padding(.horizontal, 14) }
                                LinkPreviewRow(link: link, quality: quality)
                            }
                            if links.count > 20 {
                                Text("ve \(links.count - 20) link daha")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.secondaryText)
                                    .padding(.vertical, 10)
                            }
                        }
                        .glassCard()
                    }

                    if hasVideoLinks {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel(title: "Kalite")
                            QualityRail(selection: $quality)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(title: "Seçenekler")
                        VStack(alignment: .leading, spacing: 12) {
                            SettingsRow("Kaydet") {
                                HStack(spacing: 6) {
                                    Image(systemName: "folder.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Theme.accent)
                                    Text((downloadFolder as NSString).abbreviatingWithTildeInPath)
                                        .font(.system(size: 12.5, weight: .medium))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    if let free = freeSpace {
                                        Text("· \(ByteFormat.size(free)) boş")
                                            .font(.system(size: 11.5))
                                            .foregroundStyle(Theme.secondaryText)
                                            .fixedSize()
                                    }
                                    Button("Değiştir", action: chooseFolder)
                                        .buttonStyle(GlassCapsuleButtonStyle(height: 26, fontSize: 11.5))
                                }
                            }
                            GlassDivider()
                            SettingsRow("Hız sınırı") {
                                Menu {
                                    ForEach(SpeedLimitMenu.options, id: \.title) { option in
                                        Button(option.title) { speedLimit = option.limit }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(speedLimit.map(ByteFormat.speed) ?? "Sınırsız")
                                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                                    }
                                    .font(.system(size: 12, weight: .semibold))
                                    .padding(.horizontal, 12)
                                    .frame(height: 26)
                                    .strongGlass(Capsule())
                                }
                                .menuStyle(.button)
                                .buttonStyle(.plain)
                                .menuIndicator(.hidden)
                                .fixedSize()
                            }
                            GlassDivider()
                            SettingsToggle(title: "Hemen başlat", isOn: $startNow)
                        }
                        .font(.system(size: 14))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 13)
                        .glassCard()
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                        Text(".torrent dosyasını pencereye sürükle ya da")
                        Button("dosya seç", action: chooseTorrentFiles)
                            .buttonStyle(.plain)
                            .fontWeight(.semibold)
                            .underline()
                            .foregroundStyle(Theme.accentText)
                    }
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, Theme.margin)
                .padding(.top, 4)
                .padding(.bottom, Theme.bottomBarClearance)
            }
            .scrollIndicators(.never)
        }
        .toggleStyle(.switch)
        .overlay(alignment: .bottom) { footer }
        .onAppear {
            if text.isEmpty, let clip = clipboardLinks {
                text = clip
                filledFromClipboard = true
            }
            editorFocused = true
        }
    }

    private var editor: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "link")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 9)
            TextEditor(text: $text)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .focused($editorFocused)
                .frame(minHeight: 30, maxHeight: links.count > 1 ? 96 : 34)
                .padding(.top, 2)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("https://… ya da magnet:?…")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.tertiaryText)
                            .padding(.leading, 5)
                            .padding(.top, 9)
                            .allowsHitTesting(false)
                    }
                }
            Button(action: pasteFromClipboard) {
                Label("Yapıştır", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(GlassCapsuleButtonStyle(height: 28, fontSize: 12))
            .padding(.top, 3)
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .glassCard(radius: 18)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.accent.opacity(editorFocused ? 0.7 : 0), lineWidth: 1.5)
        )
        .animation(.easeOut(duration: 0.15), value: editorFocused)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("İptal") { store.route = .list }
                .buttonStyle(GlassCapsuleButtonStyle(height: 46, fontSize: 14))
            Button {
                store.add(links: text, quality: quality, speedLimit: speedLimit, startPaused: !startNow)
            } label: {
                Label(downloadTitle, systemImage: "arrow.down.to.line")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AccentButtonStyle(height: 46, fontSize: 14))
            .disabled(links.isEmpty)
            .keyboardShortcut(.return, modifiers: .command)
            .help("İndir (⌘↩)")
        }
        .padding(.horizontal, Theme.margin - 4)
        .padding(.bottom, 14)
    }

    private var downloadTitle: String {
        links.count > 1 ? "\(links.count) dosyayı indir" : "İndir"
    }

    /// İndirme klasörünün bulunduğu diskteki boş alan.
    private var freeSpace: Int64? {
        let values = try? URL(fileURLWithPath: downloadFolder).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: downloadFolder, isDirectory: true)
        panel.prompt = "Seç"
        NSApp.activate()
        if panel.runModal() == .OK, let url = panel.url {
            downloadFolder = url.path
        }
    }

    private func chooseTorrentFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "torrent") ?? .data]
        panel.allowsMultipleSelection = true
        panel.prompt = "Ekle"
        NSApp.activate()
        if panel.runModal() == .OK {
            store.addTorrentFiles(panel.urls)
        }
    }

    /// Panodaki metinden çıkan linkler (yoksa nil).
    private var clipboardLinks: String? {
        guard let string = NSPasteboard.general.string(forType: .string) else { return nil }
        let found = DownloadStore.parseLinks(string)
        return found.isEmpty ? nil : found.joined(separator: "\n")
    }

    private func pasteFromClipboard() {
        guard let clip = clipboardLinks else { return }
        let existing = Set(links)
        let new = clip.split(separator: "\n").map(String.init).filter { !existing.contains($0) }
        guard !new.isEmpty else { return }
        let base = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = ((base.isEmpty ? [] : [base]) + new).joined(separator: "\n")
    }
}

/// Bulunan bir link: kategori ikonu, dosya adı, site ve tür.
private struct LinkPreviewRow: View {
    let link: String
    let quality: VideoQuality

    var body: some View {
        let source = DownloadSource.detect(link)
        let name = DownloadItem(url: link).fileName
        let category: DownloadCategory = source == .video
            ? (quality == .audio ? .music : .video)
            : DownloadCategory.forFile(named: name)
        HStack(spacing: 12) {
            CategoryIcon(category: category, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text([host, kind(source, category)].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .help(link)
    }

    private var host: String? {
        URL(string: link)?.host()?.replacingOccurrences(of: "www.", with: "")
    }

    private func kind(_ source: DownloadSource, _ category: DownloadCategory) -> String {
        switch source {
        case .torrent: "Torrent"
        case .video: quality == .audio ? "Ses (MP3)" : "Video"
        case .direct: category == .other ? "Dosya" : category.title
        }
    }
}

/// Video kalitesi çipleri; tek cam rayda, seçili olan vurgu renginde.
private struct QualityRail: View {
    @Binding var selection: VideoQuality
    @Namespace private var namespace

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 2) {
                ForEach(VideoQuality.allCases) { quality in
                    let selected = selection == quality
                    Button { selection = quality } label: {
                        Text(title(quality))
                            .font(.system(size: 12.5, weight: selected ? .semibold : .medium))
                            .foregroundStyle(selected ? Theme.onAccent : Theme.primaryText)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background {
                                if selected {
                                    Capsule()
                                        .fill(Theme.accent)
                                        .shadow(color: Theme.accentGlow, radius: 6, y: 3)
                                        .matchedGeometryEffect(id: "quality", in: namespace)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(3)
        }
        .scrollIndicators(.never)
        .glassCard(radius: 18)
        .animation(.snappy(duration: 0.25), value: selection)
    }

    private func title(_ quality: VideoQuality) -> String {
        switch quality {
        case .p2160: "4K"
        case .audio: "Sadece ses"
        default: quality.title
        }
    }
}
