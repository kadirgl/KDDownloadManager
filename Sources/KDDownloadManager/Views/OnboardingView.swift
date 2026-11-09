import SwiftUI
import AppKit

/// İlk açılış: tarayıcı eklentisinin kurulumu. Eklenti ilk kez bağlanınca kısa bir onay gösterip
/// İndirmeler'e geçer; "Şimdilik geç" denirse bir daha kendiliğinden açılmaz.
struct OnboardingView: View {
    @Environment(DownloadStore.self) private var store
    @State private var copied = false
    @State private var installFailed = false
    @State private var connected = false

    /// Ayarlar'da "Kur"a basılan tarayıcı; yoksa Chrome, o da yoksa ilk bulunan Chromium tarayıcı.
    private var browser: BrowserExtension.Browser? {
        let browsers = BrowserExtension.installedBrowsers
        return browsers.first { $0.name == store.onboardingBrowser }
            ?? browsers.first { $0.name == "Google Chrome" }
            ?? browsers.first
    }

    private var shortName: String {
        browser?.name.replacingOccurrences(of: "Google ", with: "") ?? "Chrome"
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    AppBadge()
                        .padding(.top, 30)
                        .padding(.bottom, 16)
                    Text("\(shortName) eklentisini kur")
                        .font(.system(size: 22, weight: .semibold))
                        .padding(.bottom, 8)
                    Text("İndirmeleri, videoları ve magnet linklerini \(shortName)'dan tek tıkla uygulamaya gönderir. Eklenti henüz Chrome Web Mağazası'nda olmadığı için geliştirici modundan yüklenir, 1 dakika sürer.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 18)

                    if let browser {
                        steps(for: browser)
                    } else {
                        SettingsNote("Desteklenen bir tarayıcı bulunamadı (Chrome, Edge, Brave, Arc, Vivaldi, Opera).")
                            .padding(16)
                            .glassCard()
                    }

                    Label("Kısayol: Finder'daki klasörü sürükleyip eklentiler sayfasına bırakabilirsin.", systemImage: "info.circle")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 6)
                        .padding(.top, 10)
                    if installFailed {
                        SettingsNote("Eklenti dosyaları hazırlanamadı.", isError: true)
                            .padding(.top, 6)
                    }

                    waitingIndicator
                        .padding(.top, 14)
                }
                .padding(.horizontal, Theme.margin)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.never)

            VStack(spacing: 6) {
                Button(action: beginInstall) {
                    Label("Kurulumu başlat", systemImage: "puzzlepiece.extension.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AccentButtonStyle(height: 46, fontSize: 14))
                .disabled(browser == nil)
                .keyboardShortcut(.defaultAction)

                Button("Şimdilik geç") { store.skipOnboarding() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(height: 30)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, 12)
        }
        .onChange(of: browser.flatMap { store.lastSignal(from: $0) }) { _, seen in
            guard seen != nil, !connected else { return }
            withAnimation(.snappy) { connected = true }
            Task {
                try? await Task.sleep(for: .seconds(1.4))
                store.onboardingBrowser = nil
                store.route = .list
            }
        }
    }

    private func steps(for browser: BrowserExtension.Browser) -> some View {
        VStack(spacing: 0) {
            step(1, title: "Eklentiler sayfasını aç") {
                HStack(spacing: 4) {
                    Text("\(shortName)'da")
                    Text(browser.extensionsPage)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Theme.badge))
                }
            } trailing: {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(browser.extensionsPage, forType: .string)
                    copied = true
                } label: {
                    Label(copied ? "Kopyalandı" : "Kopyala", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .fixedSize()
                }
                .buttonStyle(GlassCapsuleButtonStyle(height: 28, fontSize: 12))
                .help("Tarayıcılar chrome:// adreslerinin dışarıdan açılmasını engelleyebiliyor; adres çubuğuna yapıştırın.")
            }
            GlassDivider().padding(.leading, 50)
            step(2, title: "Geliştirici modunu aç") {
                Text("Sayfanın sağ üst köşesindeki anahtar")
            } trailing: {
                // Sadece gösterim: tarayıcıdaki anahtarın neye benzediği.
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: 34, height: 20)
                    .overlay(alignment: .trailing) {
                        Circle().fill(.white).frame(width: 16, height: 16).padding(2)
                    }
                    .accessibilityHidden(true)
            }
            GlassDivider().padding(.leading, 50)
            step(3, title: "\u{201C}Paketlenmemiş öğe yükle\u{201D}ye tıkla") {
                Text("Sol üstte, geliştirici modu açılınca çıkar")
            } trailing: {
                EmptyView()
            }
            GlassDivider().padding(.leading, 50)
            step(4, title: "Eklenti klasörünü seç") {
                Label((BrowserExtension.folder.path as NSString).abbreviatingWithTildeInPath, systemImage: "folder.fill")
                    .lineLimit(1)
                    .truncationMode(.head)
                    .help(BrowserExtension.folder.path)
            } trailing: {
                Button("Finder'da göster") {
                    guard BrowserExtension.refreshFolder() else {
                        installFailed = true
                        return
                    }
                    NSWorkspace.shared.activateFileViewerSelecting([BrowserExtension.folder])
                }
                .buttonStyle(GlassCapsuleButtonStyle(height: 28, fontSize: 12))
            }
        }
        .glassCard()
    }

    private func step<Detail: View, Trailing: View>(
        _ number: Int, title: String,
        @ViewBuilder detail: () -> Detail,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Theme.badge))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                detail()
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 6)
            trailing()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
    }

    private var waitingIndicator: some View {
        HStack(spacing: 8) {
            if connected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.success)
                    .transition(.scale.combined(with: .opacity))
                Text("Eklenti bağlandı")
            } else {
                ProgressView().controlSize(.small)
                Text("Eklenti bekleniyor…")
            }
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 14)
        .frame(height: 30)
        .strongGlass(Capsule())
        .accessibilityElement(children: .combine)
    }

    private func beginInstall() {
        guard let browser else { return }
        installFailed = !BrowserExtension.beginInstall(in: browser)
    }
}

/// Turuncu uygulama ikonu, köşesinde cam yapboz rozeti.
private struct AppBadge: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(LinearGradient(colors: [Theme.accent.opacity(0.85), Theme.accent], startPoint: .top, endPoint: .bottom))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .clear], startPoint: .top, endPoint: .center))
            )
            .overlay(
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Theme.onAccent)
            )
            .frame(width: 80, height: 80)
            .shadow(color: Theme.accentGlow, radius: 14, y: 8)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .strongGlass(Circle())
                    .offset(x: 9, y: 9)
            }
            .accessibilityHidden(true)
    }
}
