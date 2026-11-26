import SwiftUI
import AppKit

/// Ayarlar > Uygulama güncellemesi: sürüm, denetim, yeni sürümün notları ve kurulumu.
struct AppUpdateSettings: View {
    @AppStorage(SettingsKey.appAutoUpdateCheck) private var autoCheck = true
    @Environment(DownloadStore.self) private var store
    private let updater = AppUpdater.shared

    var body: some View {
        SettingsSection(title: String(localized: "Uygulama güncellemesi")) {
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
            SettingsToggle(title: String(localized: "Günde bir denetle"), isOn: $autoCheck)
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
                    SettingsNote(String(localized: "Süren indirmeler uygulama yeniden açılınca kaldıkları yerden devam eder."))
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
        case .checking: return String(localized: "Denetleniyor…")
        case .upToDate: return String(localized: "Güncel")
        case .available(let release): return String(localized: "Yeni sürüm: \(release.version)")
        case .downloading(let release, let progress):
            return String(localized: "\(release.version) indiriliyor… \(AppLanguage.percent(progress))")
        case .installing(let release): return String(localized: "\(release.version) kuruluyor…")
        case .failed(let message): return message
        case .idle: break
        }
        guard AppUpdater.isAvailable else { return String(localized: "Paketli uygulamada kullanılabilir") }
        guard let lastCheck = updater.lastCheck else { return String(localized: "Henüz denetlenmedi") }
        let ago = AppLanguage.relative(lastCheck)
        return String(localized: "Son denetim \(ago)")
    }

    private var note: String {
        if AppUpdater.isAvailable, let problem = AppUpdater.installProblem { return problem }
        if BrowserExtension.storeURL != nil {
            return String(localized: "Yeni sürümler GitHub'dan indirilir ve kurulmadan önce imzası doğrulanır. Mağazadan kurulan tarayıcı eklentisini tarayıcı kendisi günceller.")
        }
        return String(localized: "Yeni sürümler GitHub'dan indirilir ve kurulmadan önce imzası doğrulanır. Tarayıcı eklentisi de uygulamayla birlikte güncellenir.")
    }
}
