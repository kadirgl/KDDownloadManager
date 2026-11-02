import SwiftUI

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
