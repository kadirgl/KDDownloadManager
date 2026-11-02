import SwiftUI

/// Ayarlar > Tarayıcı eklentisi: kurulu tarayıcılar, bağlantı durumları ve kurulum adımları.
struct ExtensionSettings: View {
    @Environment(DownloadStore.self) private var store
    @State private var browsers = BrowserExtension.installedBrowsers
    /// Kurulumu başlatılan tarayıcı; adımlar onun için gösterilir.
    @State private var installing: BrowserExtension.Browser?
    @State private var installFailed = false

    var body: some View {
        SettingsSection(title: "Tarayıcı eklentisi") {
            SettingsNote("Eklenti tarayıcıdaki indirmeleri, magnet linklerini ve videoları (kalite seçerek) uygulamaya gönderir.")

            // Göreli zamanlar ("2 dk önce") ve bağlantı durumu güncel kalsın.
            // Bağlantı durumu ve tarayıcı ayarları değiştikçe görünsün (kaldırma birkaç saniyede yansır).
            TimelineView(.periodic(from: .now, by: 5)) { context in
                VStack(alignment: .leading, spacing: 12) {
                    if browsers.isEmpty {
                        Text("Desteklenen bir tarayıcı bulunamadı (Chrome, Edge, Brave, Arc, Vivaldi, Opera).")
                            .font(.system(size: 12))
                    }
                    ForEach(browsers) { browser in
                        GlassDivider()
                        row(for: browser, now: context.date)
                    }
                    ForEach(otherConnections(now: context.date), id: \.name) { connection in
                        GlassDivider()
                        statusLine(name: connection.name, seen: connection.date, now: context.date)
                    }
                }
            }

            if let installing {
                steps(for: installing)
            }
            if installFailed {
                SettingsNote("Eklenti dosyaları hazırlanamadı.", isError: true)
            }
            GlassDivider()
            SettingsNote("Safari için eklenti yok; magnet linkleri aşağıdaki Torrent ayarıyla Safari'de de çalışır.")
        }
    }

    private func row(for browser: BrowserExtension.Browser, now: Date) -> some View {
        let status = store.extensionStatus(for: browser, now: now)
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(browser.name).fontWeight(.semibold)
                statusLine(status)
            }
            Spacer()
            switch status {
            case .notInstalled:
                // Kurulu değil: adım adım kurulum ekranı.
                Button("Kur") {
                    store.onboardingBrowser = browser.name
                    store.route = .onboarding
                }
                .buttonStyle(AccentButtonStyle(height: 30, fontSize: 12))
            case .disabled:
                Button("Aç") { openExtensionsPage(of: browser) }
                    .buttonStyle(AccentButtonStyle(height: 30, fontSize: 12))
                    .help("Uzantılar sayfasında KD Download Manager'ın anahtarını açın.")
            default:
                Button("Yeniden kur") {
                    installFailed = !BrowserExtension.beginInstall(in: browser)
                    installing = installFailed ? nil : browser
                }
                .buttonStyle(GlassCapsuleButtonStyle())
            }
        }
    }

    /// Kurulu tarayıcı listesinde olmayan ama son bir günde bağlanmış olanlar (örn. adını bildiremeyen
    /// Chromium türevleri).
    private func otherConnections(now: Date) -> [(name: String, date: Date)] {
        var known = Set(browsers.map(\.name))
        if browsers.contains(where: { BrowserExtension.unnamedBrowsers.contains($0.name) }) {
            known.insert(BrowserExtension.unnamedBrowser)
        }
        return store.extensionSeen
            .filter { !known.contains($0.key) && now.timeIntervalSince($0.value) < 86_400 }
            .map { (name: $0.key, date: $0.value) }
            .sorted { $0.date > $1.date }
    }

    private func statusLine(name: String, seen: Date, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name).fontWeight(.semibold)
            statusLine(now.timeIntervalSince(seen) < DownloadStore.extensionConnectedWindow ? .connected : .notConnected(seen))
        }
    }

    private func statusLine(_ status: DownloadStore.ExtensionStatus) -> StatusLine {
        func ago(_ date: Date?) -> String {
            guard let date else { return "" }
            return " · son bağlantı " + date.formatted(.relative(presentation: .named, unitsStyle: .wide).locale(Locale(identifier: "tr_TR")))
        }
        return switch status {
        case .connected: StatusLine(text: "Bağlı", kind: .connected)
        case .notInstalled: StatusLine(text: "Kurulu değil", kind: .error)
        case .disabled: StatusLine(text: "Eklenti kapalı (devre dışı)", kind: .error)
        case .browserClosed(let seen): StatusLine(text: "Tarayıcı kapalı" + ago(seen))
        case .notConnected(let seen): StatusLine(text: "Bağlı değil" + ago(seen), kind: .error)
        }
    }

    private func openExtensionsPage(of browser: BrowserExtension.Browser) {
        guard let page = URL(string: browser.extensionsPage) else { return }
        NSWorkspace.shared.open([page], withApplicationAt: browser.appURL, configuration: NSWorkspace.OpenConfiguration())
    }

    private func steps(for browser: BrowserExtension.Browser) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(browser.name)'da açılan Uzantılar sayfasında:")
                .font(.system(size: 12, weight: .semibold))
            Group {
                Text("1. Sağ üstten **Geliştirici modu**nu açın.")
                Text("2. **Paketlenmemiş öğe yükle**'ye tıklayın.")
                Text("3. Açılan pencerede ⌘⇧G'ye basıp yapıştırın (klasör yolu panoya kopyalandı) ve **Seç**'e basın.")
                Text("Eklenti bağlanınca burada \"Bağlı\" görünür. Eklentiyi önceden başka bir klasörden yüklediyseniz önce onu kaldırın.")
                    .foregroundStyle(Theme.secondaryText)
            }
            .font(.system(size: 11.5))
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 14)
    }
}

/// Ayarlar > Torrent: magnet linkleri ve .torrent dosyaları için varsayılan uygulama.
struct TorrentSettings: View {
    @State private var isDefault = TorrentHandler.isDefault
    @State private var handlerName = TorrentHandler.currentHandlerName
    @State private var error: String?

    var body: some View {
        SettingsSection(title: "Torrent") {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Magnet linkleri ve .torrent dosyaları").fontWeight(.semibold)
                    StatusLine(text: statusText, kind: isDefault ? .success : .neutral)
                }
                Spacer()
                if !isDefault {
                    Button("Bununla aç") {
                        Task {
                            do {
                                try await TorrentHandler.makeDefault()
                                error = nil
                            } catch {
                                self.error = "Ayarlanamadı: \(error.localizedDescription)"
                            }
                            isDefault = TorrentHandler.isDefault
                            handlerName = TorrentHandler.currentHandlerName
                        }
                    }
                    .buttonStyle(AccentButtonStyle(height: 30, fontSize: 12))
                    .disabled(!TorrentHandler.isAvailable)
                }
            }
            if let error {
                SettingsNote(error, isError: true)
            }
            GlassDivider()
            SettingsNote("Diskteki .torrent dosyalarını panele sürükleyip bırakabilir ya da Link ekle ekranından seçebilirsiniz.")
        }
    }

    private var statusText: String {
        if !TorrentHandler.isAvailable { return "Uygulama .app olarak paketlenip açıldığında ayarlanabilir." }
        if isDefault { return "KD Download Manager ile açılıyor" }
        return handlerName.map { "Şu an \($0) ile açılıyor" } ?? "Şu an bunları açan bir uygulama yok"
    }
}
