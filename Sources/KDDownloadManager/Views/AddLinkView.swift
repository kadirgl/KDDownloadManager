import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Link yapıştırıp indirme başlatma ekranı. Tek link girilince önce denetlenir (ad, boyut, kaliteler);
/// açılamayan link, daha önce indirilmiş dosya ve diskte yer kalmaması ayrıca gösterilir.
struct AddLinkView: View {
    @Environment(DownloadStore.self) private var store
    @AppStorage(SettingsKey.downloadFolder) private var downloadFolder = SettingsKey.defaultDownloadFolder
    @AppStorage(SettingsKey.connections) private var connections = SettingsKey.defaultConnections
    @State private var text = ""
    @State private var quality: VideoQuality = .auto
    @State private var speedLimit: Int64?
    @State private var startNow = true
    /// Alan açılışta panodan dolduruldu ("Panodaki link otomatik eklendi").
    @State private var filledFromClipboard = false
    @State private var probe: Probe = .idle
    /// Denetim 10 sn'yi geçti: "Sunucu yanıt vermiyor · Tekrar dene"; indirme yine de başlatılabilir.
    @State private var slow = false
    @State private var retry = 0
    /// Tek dosyada kaydedilecek ad (denetimden ya da daha önce indirilmişse "(1)" ekli).
    @State private var name = ""
    @FocusState private var editorFocused: Bool

    enum Probe {
        case idle
        case checking
        case done(LinkProbe.Outcome)
    }

    private var links: [String] { DownloadStore.parseLinks(text) }
    private var single: String? { links.count == 1 ? links[0] : nil }
    private var singleSource: DownloadSource? { single.map(DownloadSource.detect) }
    private var hasVideoLinks: Bool { links.contains { DownloadSource.detect($0) == .video } }
    private var duplicate: DownloadItem? { single.flatMap(store.existingItem) }
    /// Yazılan metinden hiç link çıkmadı (örn. "https//site.com").
    private var textIsInvalid: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && links.isEmpty }

    private var invalidReason: String? {
        if textIsInvalid { return "Adres eksik ya da hatalı görünüyor. \"https://\" ile başladığını kontrol edip tekrar dene." }
        if case .done(.invalid(let reason)) = probe, duplicate == nil { return reason }
        return nil
    }

    private var isChecking: Bool {
        if case .checking = probe, !slow { true } else { false }
    }

    /// Bilinen indirme boyutu (yer kontrolü ve İndir butonu için).
    private var expectedSize: Int64? {
        if let duplicate { return duplicate.totalBytes > 0 ? duplicate.totalBytes : nil }
        switch probe {
        case .done(.file(let info)): return info.size
        case .done(.video(let formats)): return formats.options.first { $0.quality == quality }?.size
        default: return nil
        }
    }

    private var freeSpace: Int64? {
        let values = try? URL(fileURLWithPath: downloadFolder).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    private var missingSpace: Int64? {
        guard let size = expectedSize, let free = freeSpace, size > free else { return nil }
        return size - free
    }

    /// Ad alanı: tek dosya linkinde ve daha önce indirilmiş her linkte.
    private var showsNameField: Bool {
        duplicate != nil || singleSource == .direct
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Link ekle", onBack: { store.route = .list })

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(title: "Bağlantı")
                        editor
                        if invalidReason == nil {
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
                    }

                    linkSection

                    if duplicate != nil, invalidReason == nil {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel(title: "Yine de indirilirse")
                            VStack(alignment: .leading, spacing: 12) {
                                nameRow
                                SettingsNote("Eski dosyanın üzerine yazılmaz, yeni kopya bu adla kaydedilir.")
                                GlassDivider()
                                saveRow
                            }
                            .optionsCard(warning: missingSpace != nil)
                        }
                    } else if invalidReason == nil, !links.isEmpty {
                        if hasVideoLinks {
                            VStack(alignment: .leading, spacing: 8) {
                                SectionLabel(title: "Kalite")
                                QualityRail(selection: $quality, formats: videoFormats)
                            }
                        }
                        if showsNameField {
                            VStack(alignment: .leading, spacing: 8) {
                                SectionLabel(title: "Dosya")
                                VStack(alignment: .leading, spacing: 12) {
                                    nameRow
                                    GlassDivider()
                                    saveRow
                                }
                                .optionsCard(warning: missingSpace != nil)
                            }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel(title: "Seçenekler")
                            VStack(alignment: .leading, spacing: 12) {
                                if !showsNameField {
                                    saveRow
                                    GlassDivider()
                                }
                                limitRow
                                GlassDivider()
                                SettingsToggle(title: "Hemen başlat", isOn: $startNow)
                            }
                            .optionsCard(warning: !showsNameField && missingSpace != nil)
                        }
                    }

                    if invalidReason == nil {
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
            #if DEBUG
            if let demo = DebugPanel.addLinkText {
                text = demo
                return
            }
            #endif
            if text.isEmpty, let clip = clipboardLinks {
                text = clip
                filledFromClipboard = true
            }
            editorFocused = true
        }
        // Tek link yazılınca (kısa bir bekleyişten sonra) denetle; link değişirse eski denetim iptal olur.
        .task(id: "\(single ?? "")#\(retry)") {
            await check()
        }
    }

    // MARK: - Bağlantı alanı

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
                .strokeBorder(
                    invalidReason != nil ? Theme.error : Theme.accent.opacity(editorFocused ? 0.7 : 0),
                    lineWidth: 1.5
                )
        )
        .animation(.easeOut(duration: 0.15), value: editorFocused)
    }

    // MARK: - Bulunan link(ler)

    @ViewBuilder
    private var linkSection: some View {
        if let reason = invalidReason {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(Theme.error)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Bu link açılamadı")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(Theme.errorText)
                        SettingsNote(reason)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .tintedCard(Theme.error)
                SettingsNote("Desteklenenler: doğrudan dosya linkleri, magnet linkleri ve YouTube gibi video sayfaları.")
                    .padding(.horizontal, 4)
            }
        } else if let duplicate {
            DuplicateCard(item: duplicate)
        } else if let single {
            switch probe {
            case .idle, .checking:
                CheckingCard(slow: slow) { retry += 1 }
            case .done(let outcome):
                FoundCard(link: single, outcome: outcome, quality: quality, connections: connections) { retry += 1 }
            }
        } else if !links.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(links.prefix(20).enumerated()), id: \.offset) { index, link in
                    if index > 0 { GlassDivider().padding(.horizontal, 14) }
                    LinkPreviewRow(link: link, quality: quality, alreadyListed: store.existingItem(for: link) != nil)
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
    }

    private var videoFormats: VideoFormats? {
        if case .done(.video(let formats)) = probe { formats } else { nil }
    }

    // MARK: - Seçenek satırları

    private var nameRow: some View {
        HStack(spacing: 10) {
            Text("Ad")
            TextField("Dosya adı", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .multilineTextAlignment(.trailing)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.badge.opacity(0.7)))
        }
    }

    private var saveRow: some View {
        VStack(alignment: .leading, spacing: 6) {
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
                            .font(.system(size: 11.5, weight: missingSpace == nil ? .regular : .semibold))
                            .foregroundStyle(missingSpace == nil ? Theme.secondaryText : Theme.errorText)
                            .fixedSize()
                    }
                    Button("Değiştir", action: chooseFolder)
                        .buttonStyle(GlassCapsuleButtonStyle(height: 26, fontSize: 11.5))
                }
            }
            if let missing = missingSpace {
                Text("\(ByteFormat.size(missing)) daha yer gerekiyor. Başka bir disk seç ya da yer aç.")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.errorText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var limitRow: some View {
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
    }

    // MARK: - Alt butonlar

    private var footer: some View {
        HStack(spacing: 8) {
            Button("İptal") { store.route = .list }
                .buttonStyle(GlassCapsuleButtonStyle(height: 46, fontSize: 14, floating: true))
            if missingSpace != nil {
                Button(action: chooseFolder) {
                    Label("Başka klasör seç", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AccentButtonStyle(height: 46, fontSize: 14))
            } else {
                Button(action: download) {
                    Label(downloadTitle, systemImage: "arrow.down.to.line")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AccentButtonStyle(height: 46, fontSize: 14))
                .disabled(links.isEmpty || invalidReason != nil || isChecking)
                .keyboardShortcut(.return, modifiers: .command)
                .help("İndir (⌘↩)")
            }
        }
        .padding(.horizontal, Theme.margin - 4)
        .padding(.bottom, 14)
    }

    private var downloadTitle: String {
        if duplicate != nil { return "Yine de indir" }
        if links.count > 1 { return "\(links.count) dosyayı indir" }
        return ["İndir", expectedSize.map { "~\(ByteFormat.size($0))" }].compactMap { $0 }.joined(separator: " · ")
    }

    private func download() {
        let saveAs = showsNameField ? DownloadStore.sanitizedFileName(name) : nil
        store.add(links: text, quality: quality, speedLimit: speedLimit, startPaused: !startNow, saveAs: saveAs)
    }

    // MARK: - Denetim

    private func check() async {
        slow = false
        name = ""
        if let duplicate {
            name = duplicateName(for: duplicate)
            probe = .idle
            return
        }
        guard let link = single else {
            probe = .idle
            return
        }
        probe = .checking
        // Yazarken her harfte istek atılmasın.
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }
        let timer = Task {
            try? await Task.sleep(for: .seconds(LinkProbe.timeout))
            if !Task.isCancelled { slow = true }
        }
        let outcome = await LinkProbe.check(link)
        timer.cancel()
        guard !Task.isCancelled else { return }
        slow = false
        withAnimation(.snappy(duration: 0.25)) { probe = .done(outcome) }
        // Kullanıcı bu arada adı değiştirdiyse dokunma.
        guard singleSource == .direct, name.isEmpty else { return }
        if case .file(let info) = outcome, let found = info.name {
            name = found
        } else {
            name = DownloadItem(url: link).fileName
        }
    }

    /// Daha önce indirilmiş dosyanın yeni kopyası için "(1)" ekli ad; videoda uzantısız (yt-dlp ekliyor).
    private func duplicateName(for item: DownloadItem) -> String {
        store.freshName(for: item.fileName, in: item.folder, keepExtension: item.source != .video)
    }

    // MARK: - Dosya seçimleri ve pano

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

private extension View {
    /// Seçenek kartı; yer yetmiyorsa kırmızı.
    @ViewBuilder
    func optionsCard(warning: Bool) -> some View {
        let card = font(.system(size: 14))
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
        if warning {
            card.tintedCard(Theme.error)
        } else {
            card.glassCard()
        }
    }

    /// Renkli uyarı kartı (hata kırmızı, "zaten indirildi" sarı).
    func tintedCard(_ color: Color) -> some View {
        background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(color.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(color.opacity(0.4)))
        )
    }
}

// MARK: - Kartlar

/// Denetim sürerken: dönen halka, iki iskelet çizgi; 10 sn geçerse "Tekrar dene".
private struct CheckingCard: View {
    let slow: Bool
    let onRetry: () -> Void
    @State private var spinning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                if slow {
                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.warning)
                        .frame(width: 40, height: 40)
                } else {
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 26, height: 26)
                        .rotationEffect(.degrees(spinning ? 360 : 0))
                        .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: spinning)
                        .frame(width: 40, height: 40)
                        .onAppear { spinning = true }
                }
                VStack(alignment: .leading, spacing: 7) {
                    if slow {
                        HStack(spacing: 6) {
                            Text("Sunucu yanıt vermiyor")
                                .font(.system(size: 13.5, weight: .semibold))
                            Text("·").foregroundStyle(Theme.secondaryText)
                            Button("Tekrar dene", action: onRetry)
                                .buttonStyle(.plain)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.accentText)
                        }
                    } else {
                        Text("Bağlantı kontrol ediliyor…")
                            .font(.system(size: 13.5, weight: .semibold))
                        Capsule().fill(Theme.track).frame(width: 200, height: 7)
                        Capsule().fill(Theme.track).frame(width: 130, height: 7)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .glassCard()
            SettingsNote(slow
                ? "İstersen beklemeden indirebilirsin; ad ve boyut indirme başlayınca öğrenilir."
                : "Dosya adı ve boyutu birkaç saniye içinde görünür. İstersen beklemeden İptal'e basabilirsin.")
                .padding(.horizontal, 4)
        }
    }
}

/// Denetlenen tek link: kategori ikonu, ad, site · tür · boyut ve "Bulundu".
private struct FoundCard: View {
    let link: String
    let outcome: LinkProbe.Outcome
    let quality: VideoQuality
    let connections: Int
    let onRetry: () -> Void

    var body: some View {
        let source = DownloadSource.detect(link)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                CategoryIcon(category: category(source), size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(source))
                        .font(.system(size: 13.5, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(details(source))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                status
            }
            .padding(12)
            if case .file(let info) = outcome, source == .direct, info.resumable {
                GlassDivider()
                HStack(spacing: 14) {
                    Label("Parçalı indirme: \(connections) bağlantı", systemImage: "line.3.horizontal")
                    Label("Kaldığı yerden devam eder", systemImage: "arrow.clockwise")
                }
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
            }
            if case .warning(let message) = outcome {
                GlassDivider()
                HStack(spacing: 8) {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button("Tekrar dene", action: onRetry)
                        .buttonStyle(GlassCapsuleButtonStyle(height: 24, fontSize: 11))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            if case .videoUnknown = outcome {
                GlassDivider()
                SettingsNote("Video bilgisi şimdi alınamadı; indirme sırasında yeniden denenecek.")
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
            }
        }
        .glassCard()
    }

    @ViewBuilder
    private var status: some View {
        switch outcome {
        case .file, .video:
            Label("Bulundu", systemImage: "checkmark")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Theme.success)
                .fixedSize()
        default:
            EmptyView()
        }
    }

    private func category(_ source: DownloadSource) -> DownloadCategory {
        switch source {
        case .video: quality == .audio ? .music : .video
        case .torrent: .other
        case .direct: DownloadCategory.forFile(named: title(source))
        }
    }

    private func title(_ source: DownloadSource) -> String {
        switch outcome {
        case .video(let formats): return formats.title + (quality == .audio ? ".mp3" : ".mp4")
        case .file(let info): if let name = info.name { return name }
        default: break
        }
        return DownloadItem(url: link).fileName
    }

    private func details(_ source: DownloadSource) -> String {
        let host = URL(string: link)?.host()?.replacingOccurrences(of: "www.", with: "")
        var parts = [host]
        switch outcome {
        case .video(let formats):
            parts.append(quality == .audio ? "Ses" : "Video")
            if let duration = formats.duration {
                parts.append(Duration.seconds(duration).formatted(.time(pattern: duration >= 3600 ? .hourMinuteSecond : .minuteSecond)))
            }
        case .file(let info):
            let category = DownloadCategory.forFile(named: title(source))
            parts.append(source == .torrent ? "Torrent" : category == .other ? "Dosya" : category.title)
            parts.append(info.size.map(ByteFormat.size))
        default:
            parts.append(source == .video ? "Video" : "Dosya")
        }
        return parts.compactMap { $0 }.joined(separator: " · ")
    }
}

/// Aynı link daha önce eklenmiş: tamamlandıysa ne zaman ve nerede, açma ve Finder'da gösterme.
private struct DuplicateCard: View {
    @Environment(DownloadStore.self) private var store
    let item: DownloadItem

    var body: some View {
        let completed = item.status == .completed
        HStack(alignment: .top, spacing: 12) {
            CategoryIcon(category: item.category, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Label(completed ? "Bu dosya zaten indirildi" : "Bu link zaten listede",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.warning)
                Text([item.fileName, item.totalBytes > 0 ? ByteFormat.size(item.totalBytes) : nil].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(details(completed: completed))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if completed, let file = item.destination, FileManager.default.fileExists(atPath: file.path) {
                        Button("Dosyayı aç") { NSWorkspace.shared.open(file) }
                            .buttonStyle(GlassCapsuleButtonStyle(height: 26, fontSize: 11.5))
                        Button("Finder'da göster") { store.revealInFinder(item) }
                            .buttonStyle(GlassCapsuleButtonStyle(height: 26, fontSize: 11.5))
                    } else if !completed {
                        Button("Listede göster") {
                            store.tab = .active
                            store.category = .all
                            store.selection = item.id
                            store.route = .list
                        }
                        .buttonStyle(GlassCapsuleButtonStyle(height: 26, fontSize: 11.5))
                    }
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .tintedCard(Theme.warning)
    }

    private func details(completed: Bool) -> String {
        let folder = (item.folder.path as NSString).abbreviatingWithTildeInPath
        guard completed else { return "%\(Int(item.progress * 100)) indi · \(folder)" }
        guard let date = item.completedAt else { return folder }
        let ago = date.formatted(.relative(presentation: .named, unitsStyle: .wide).locale(Locale(identifier: "tr_TR")))
        return "\(ago) · \(folder)"
    }
}

/// Birden çok linkte bir satır: kategori ikonu, dosya adı, site ve tür.
private struct LinkPreviewRow: View {
    let link: String
    let quality: VideoQuality
    let alreadyListed: Bool

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
            if alreadyListed {
                Text("Zaten listede")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.warning)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(Capsule().fill(Theme.warning.opacity(0.14)))
            }
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

/// Video kalitesi çipleri; tek cam rayda, seçili olan vurgu renginde. Video denetlendiyse yalnızca
/// sunulan kaliteler gösterilir.
private struct QualityRail: View {
    @Binding var selection: VideoQuality
    let formats: VideoFormats?
    @Namespace private var namespace

    private var qualities: [VideoQuality] {
        guard let formats else { return VideoQuality.allCases }
        let offered = Set(formats.options.map(\.quality))
        return VideoQuality.allCases.filter { offered.contains($0) || $0 == .auto }
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 2) {
                ForEach(qualities) { quality in
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
        .onChange(of: qualities) { _, offered in
            if !offered.contains(selection) { selection = .auto }
        }
    }

    private func title(_ quality: VideoQuality) -> String {
        switch quality {
        case .p2160: "4K"
        case .audio: "Sadece ses"
        default: quality.title
        }
    }
}
