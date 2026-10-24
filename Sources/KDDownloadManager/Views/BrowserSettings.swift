import SwiftUI

/// Ayarlar > Tarayıcı eklentisi: kurulu tarayıcılar, bağlantı durumları ve kurulum adımları.
struct ExtensionSettings: View {
    @Environment(DownloadStore.self) private var store
    @State private var browsers = BrowserExtension.installedBrowsers
    /// Kurulumu başlatılan tarayıcı; adımlar onun için gösterilir.
    @State private var installing: BrowserExtension.Browser?
    @State private var installFailed = false

    /// Eklenti dakikada bir sinyal gönderiyor; biraz pay bırakarak "bağlı" sayılma süresi.
    private static let connectedWindow: TimeInterval = 150

    var body: some View {
        SettingsSection(title: "Tarayıcı eklentisi") {
            Text("Eklenti tarayıcıdaki indirmeleri, magnet linklerini ve videoları (kalite seçerek) uygulamaya gönderir.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            // Göreli zamanlar ("2 dk önce") ve bağlantı durumu güncel kalsın.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(alignment: .leading, spacing: 10) {
                    if browsers.isEmpty {
                        Text("Desteklenen bir tarayıcı bulunamadı (Chrome, Edge, Brave, Arc, Vivaldi, Opera).")
                            .font(.system(size: 12))
                    }
                    ForEach(browsers) { browser in
                        row(for: browser, now: context.date)
                    }
                    ForEach(otherConnections(now: context.date), id: \.name) { connection in
                        statusLine(name: connection.name, seen: connection.date, now: context.date)
                    }
                }
            }

            if let installing {
                steps(for: installing)
            }
            if installFailed {
                Text("Eklenti dosyaları hazırlanamadı.")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
            Text("Safari için eklenti yok; magnet linkleri aşağıdaki Torrent ayarıyla Safari'de de çalışır.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(for browser: BrowserExtension.Browser, now: Date) -> some View {
        let seen = store.extensionSeen[browser.name]
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(browser.name)
                status(seen: seen, now: now)
            }
            Spacer()
            Button(seen == nil ? "Kur" : "Yeniden kur") {
                installFailed = !BrowserExtension.beginInstall(in: browser)
                installing = installFailed ? nil : browser
            }
            .buttonStyle(PillButtonStyle(prominent: seen == nil))
        }
    }

    /// Kurulu tarayıcı listesinde olmayan ama bağlanmış olanlar (örn. adını bildiremeyen Chromium türevleri).
    private func otherConnections(now: Date) -> [(name: String, date: Date)] {
        let known = Set(browsers.map(\.name))
        return store.extensionSeen
            .filter { !known.contains($0.key) }
            .map { (name: $0.key, date: $0.value) }
            .sorted { $0.date > $1.date }
    }

    private func statusLine(name: String, seen: Date, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
            status(seen: seen, now: now)
        }
    }

    private func status(seen: Date?, now: Date) -> some View {
        let connected = seen.map { now.timeIntervalSince($0) < Self.connectedWindow } ?? false
        let text: String
        if connected {
            text = "Bağlı"
        } else if let seen {
            text = "Son bağlantı \(seen.formatted(.relative(presentation: .named, unitsStyle: .wide).locale(Locale(identifier: "tr_TR"))))"
        } else {
            text = "Eklenti kurulu değil"
        }
        return HStack(spacing: 5) {
            Circle()
                .fill(connected ? Color.green : Theme.secondaryText.opacity(0.5))
                .frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
        }
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
            .font(.system(size: 11))
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.background))
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
                VStack(alignment: .leading, spacing: 2) {
                    Text("Magnet linkleri ve .torrent dosyaları")
                    Text(statusText)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
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
                    .buttonStyle(PillButtonStyle())
                    .disabled(!TorrentHandler.isAvailable)
                }
            }
            if let error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
            Text("Diskteki .torrent dosyalarını panele sürükleyip bırakabilir ya da Link Ekle ekranından seçebilirsiniz.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusText: String {
        if !TorrentHandler.isAvailable { return "Uygulama .app olarak paketlenip açıldığında ayarlanabilir." }
        if isDefault { return "KD Download Manager ile açılıyor" }
        return handlerName.map { "Şu an \($0) ile açılıyor" } ?? "Şu an bunları açan bir uygulama yok"
    }
}
