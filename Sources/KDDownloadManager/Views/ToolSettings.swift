import SwiftUI
import AppKit

/// Ayarlar > Video indirici: yt-dlp sürümü, elle ve otomatik güncelleme.
struct YtDlpSettings: View {
    @AppStorage(SettingsKey.ytDlpAutoUpdate) private var autoUpdate = true
    private let updater = YtDlpUpdater.shared

    var body: some View {
        SettingsSection(title: "Video indirici (yt-dlp)") {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(updater.current.version.map { "yt-dlp \($0)" } ?? "yt-dlp").fontWeight(.semibold)
                    StatusLine(text: statusText, kind: isError ? .error : isUpToDate ? .success : .neutral)
                }
                Spacer()
                if updater.isBusy {
                    ProgressView().controlSize(.small)
                }
                Button("Denetle") {
                    Task { await updater.update() }
                }
                .buttonStyle(GlassCapsuleButtonStyle())
                .disabled(updater.isBusy || updater.current.origin == .system)
                .help("yt-dlp'nin yeni sürümü var mı denetle")
            }
            GlassDivider()
            SettingsToggle(title: "Otomatik güncelle", isOn: $autoUpdate)
                .disabled(updater.current.origin == .system)
            SettingsNote("YouTube sık değiştiği için yt-dlp güncel tutulmazsa video indirmeleri bozulabilir. Güncellemeler yt-dlp'nin resmi GitHub sürümünden alınır ve doğrulanır.")
        }
    }

    private var isUpToDate: Bool {
        switch updater.state {
        case .upToDate, .updated: true
        default: false
        }
    }

    private var isError: Bool {
        if case .failed = updater.state { true } else { false }
    }

    private var statusText: String {
        switch updater.state {
        case .checking: return "Denetleniyor…"
        case .downloading(let version): return "\(version) indiriliyor…"
        case .upToDate: return "Güncel"
        case .updated(let version): return "\(version) sürümüne güncellendi"
        case .failed(let message): return message
        case .idle: break
        }
        switch updater.current.origin {
        case .system:
            return "Sistemdeki (Homebrew) yt-dlp kullanılıyor; uygulama içinden güncellenmez."
        case .bundled, .downloaded:
            let origin = updater.current.origin == .bundled ? "Uygulamayla gelen" : "Güncellenmiş"
            guard let lastCheck = updater.lastCheck else { return "\(origin) · henüz denetlenmedi" }
            let ago = lastCheck.formatted(.relative(presentation: .named, unitsStyle: .wide).locale(Locale(identifier: "tr_TR")))
            return "\(origin) · son denetim \(ago)"
        }
    }
}

/// Ayarlar > Uygulama güncellemesi: sürüm, denetim, yeni sürümün notları ve kurulumu.
struct AppUpdateSettings: View {
    @AppStorage(SettingsKey.appAutoUpdateCheck) private var autoCheck = true
    @Environment(DownloadStore.self) private var store
    private let updater = AppUpdater.shared

    var body: some View {
        SettingsSection(title: "Uygulama güncellemesi") {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("KD Download Manager \(AppUpdater.currentVersion)").fontWeight(.semibold)
                    StatusLine(text: statusText, kind: statusKind)
                }
                Spacer()
                if case .checking = updater.state {
                    ProgressView().controlSize(.small)
                }
                if updater.availableRelease == nil {
                    Button("Denetle") {
                        Task { await updater.check() }
                    }
                    .buttonStyle(GlassCapsuleButtonStyle())
                    .disabled(updater.isBusy || !AppUpdater.isAvailable)
                    .help("Yeni sürüm var mı denetle")
                }
            }

            if let release = currentRelease {
                GlassDivider()
                releaseDetails(release)
            }

            GlassDivider()
            SettingsToggle(title: "Günde bir denetle", isOn: $autoCheck)
                .disabled(!AppUpdater.isAvailable)
            SettingsNote(note, isError: AppUpdater.isAvailable && AppUpdater.installProblem != nil)
        }
    }

    /// Bulunan ya da inmekte olan sürüm.
    private var currentRelease: AppUpdater.Release? {
        switch updater.state {
        case .available(let release), .downloading(let release, _), .installing(let release): release
        default: nil
        }
    }

    @ViewBuilder
    private func releaseDetails(_ release: AppUpdater.Release) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let notes = Self.displayNotes(release.notes) {
                let text = Text(notes)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                // Kısa notlar olduğu gibi; uzunlar kaydırılabilir bir kutuda.
                ViewThatFits(in: .vertical) {
                    text
                    ScrollView { text }
                }
                .frame(maxHeight: 120)
            }
            switch updater.state {
            case .downloading(_, let progress):
                HStack(spacing: 8) {
                    ProgressView(value: progress)
                        .tint(Theme.accent)
                    Button("Vazgeç") { updater.cancel() }
                        .buttonStyle(GlassCapsuleButtonStyle(height: 26))
                }
            case .installing:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Kuruluyor, uygulama yeniden açılacak…").font(.system(size: 12))
                }
            default:
                HStack(spacing: 8) {
                    Button {
                        updater.install()
                    } label: {
                        Label("Güncelle ve yeniden başlat", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(AccentButtonStyle(height: 32, fontSize: 12.5))
                    .disabled(AppUpdater.installProblem != nil)
                    if let page = release.page {
                        Button("GitHub'da gör") { NSWorkspace.shared.open(page) }
                            .buttonStyle(GlassCapsuleButtonStyle(height: 32))
                    }
                }
                if store.items.contains(where: { $0.status == .downloading }) {
                    SettingsNote("Süren indirmeler uygulama yeniden açılınca kaldıkları yerden devam eder.")
                }
            }
        }
    }

    /// GitHub'daki sürüm notları: kurulum açıklaması (--- sonrası) atılır, başlıklar kalın, maddeler • olur.
    static func displayNotes(_ notes: String) -> AttributedString? {
        let body = notes.components(separatedBy: "\n---").first ?? notes
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") { return "**" + trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces) + "**" }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") { return "•  " + trimmed.dropFirst(2) }
            return trimmed
        }
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    private var statusKind: StatusLine.Kind {
        switch updater.state {
        case .upToDate: .success
        case .failed: .error
        case .available: .connected
        default: .neutral
        }
    }

    private var statusText: String {
        switch updater.state {
        case .checking: return "Denetleniyor…"
        case .upToDate: return "Güncel"
        case .available(let release): return "Yeni sürüm: \(release.version)"
        case .downloading(let release, let progress): return "\(release.version) indiriliyor… %\(Int(progress * 100))"
        case .installing(let release): return "\(release.version) kuruluyor…"
        case .failed(let message): return message
        case .idle: break
        }
        guard AppUpdater.isAvailable else { return "Paketli uygulamada kullanılabilir" }
        guard let lastCheck = updater.lastCheck else { return "Henüz denetlenmedi" }
        let ago = lastCheck.formatted(.relative(presentation: .named, unitsStyle: .wide).locale(Locale(identifier: "tr_TR")))
        return "Son denetim \(ago)"
    }

    private var note: String {
        if AppUpdater.isAvailable, let problem = AppUpdater.installProblem { return problem }
        return "Yeni sürümler GitHub'dan indirilir ve kurulmadan önce imzası doğrulanır. Tarayıcı eklentisi de uygulamayla birlikte güncellenir."
    }
}
