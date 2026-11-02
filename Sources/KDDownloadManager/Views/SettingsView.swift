import SwiftUI
import AppKit

/// Ayarlar ekranı; değerler @AppStorage ile UserDefaults'a yazılır. Her bölüm bir cam kart, satırlar
/// arasında ince ayırıcı; sürüm ve Çıkış alt köşelerde yüzen cam kapsüller.
struct SettingsView: View {
    @Environment(DownloadStore.self) private var store
    @AppStorage(SettingsKey.downloadFolder) private var downloadFolder = SettingsKey.defaultDownloadFolder
    @AppStorage(SettingsKey.globalLimitEnabled) private var limitEnabled = false
    @AppStorage(SettingsKey.globalLimitMB) private var limitMB = SettingsKey.defaultGlobalLimitMB
    @AppStorage(SettingsKey.maxConcurrent) private var maxConcurrent = SettingsKey.defaultMaxConcurrent
    @AppStorage(SettingsKey.connections) private var connections = SettingsKey.defaultConnections
    @AppStorage(SettingsKey.showSpeedInMenuBar) private var showSpeed = true
    @AppStorage(SettingsKey.appTheme) private var theme = AppTheme.system.rawValue
    @AppStorage(SettingsKey.accentColor) private var accent = AccentChoice.orange.rawValue
    @AppStorage(SettingsKey.notifyOnAdd) private var notifyOnAdd = true
    @AppStorage(SettingsKey.notifyOnFinish) private var notifyOnFinish = true
    @AppStorage(SettingsKey.notifyOnFail) private var notifyOnFail = true
    // Kaynak macOS; burada sadece gösterim için tutuluyor.
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchAtLoginError: String?
    /// Sınır art arda değiştirilirken her adımda uygulamamak için (video indirmeleri yeniden başlatılıyor).
    @State private var pendingLimit: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Ayarlar", onBack: { store.route = .list })

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    SettingsSection(title: "İndirme klasörü") {
                        HStack(spacing: 10) {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(Theme.accent)
                            Text((downloadFolder as NSString).abbreviatingWithTildeInPath)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(downloadFolder)
                            Spacer(minLength: 8)
                            Button("Değiştir", action: chooseFolder)
                                .buttonStyle(GlassCapsuleButtonStyle())
                        }
                    }

                    SettingsSection(title: "Görünüm") {
                        SettingsRow("Tema") {
                            GlassSegmented(
                                options: AppTheme.allCases.map { ($0.rawValue, $0.title) },
                                selection: $theme
                            )
                        }
                        GlassDivider()
                        SettingsRow("Vurgu rengi") {
                            AccentPicker(selection: $accent)
                        }
                    }

                    SettingsSection(title: "Hız") {
                        SettingsToggle(title: "Genel hız sınırı", isOn: $limitEnabled)
                        if limitEnabled {
                            SettingsRow("Sınır", note: "Tüm indirmelerin toplamı bunu geçmez; indirmeye özel daha yüksek sınırlar da buna göre kısıtlanır.") {
                                GlassStepper(
                                    label: "Sınır",
                                    value: Binding(get: { Int(limitMB) }, set: { limitMB = Double($0) }),
                                    range: 1...100,
                                    format: { "\($0) MB/sn" }
                                )
                            }
                        }
                        GlassDivider()
                        SettingsRow("Aynı anda en fazla") {
                            GlassStepper(label: "Aynı anda en fazla", value: $maxConcurrent, range: 1...10,
                                         format: { "\($0) indirme" })
                        }
                        GlassDivider()
                        SettingsRow("Bağlantı sayısı", note: "Parçalı indirme: her dosya ve video bu kadar paralel bağlantıyla iner. Sunucu izin vermezse o indirme tek bağlantıya düşer.") {
                            GlassStepper(label: "Bağlantı sayısı", value: $connections, range: 1...16)
                        }
                    }

                    ExtensionSettings()

                    TorrentSettings()

                    YtDlpSettings()

                    SettingsSection(title: "Bildirimler") {
                        SettingsToggle(title: "İndirme eklendiğinde", isOn: $notifyOnAdd)
                        GlassDivider()
                        SettingsToggle(title: "İndirme tamamlandığında", isOn: $notifyOnFinish)
                        GlassDivider()
                        SettingsToggle(title: "Hata olduğunda", isOn: $notifyOnFail)
                        if !Notifier.isAvailable {
                            SettingsNote("Uygulama .app olarak paketlenip açıldığında çalışır.")
                        }
                    }

                    SettingsSection(title: "Menü çubuğu") {
                        SettingsToggle(title: "Toplam hızı göster", isOn: $showSpeed)
                    }

                    SettingsSection(title: "Başlangıç") {
                        SettingsToggle(title: "Oturum açınca başlat", isOn: $launchAtLogin)
                            .disabled(!LaunchAtLogin.isAvailable)
                        if let note = launchAtLoginError ?? launchAtLoginNote {
                            SettingsNote(note, isError: launchAtLoginError != nil)
                        }
                    }
                }
                .padding(.horizontal, Theme.margin)
                .padding(.top, 4)
                .padding(.bottom, Theme.bottomBarClearance)
            }
            .scrollIndicators(.never)
        }
        .overlay(alignment: .bottom) { footer }
        .toggleStyle(.switch)
        .tint(Theme.accent)
        .onChange(of: limitEnabled) { store.applyGlobalSpeedLimit() }
        .onChange(of: limitMB) {
            pendingLimit?.cancel()
            pendingLimit = Task {
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                store.applyGlobalSpeedLimit()
            }
        }
        .onChange(of: maxConcurrent) { store.applyMaxConcurrent() }
        .onChange(of: theme) { AppTheme.apply() }
        .onChange(of: launchAtLogin) { _, enabled in
            guard enabled != LaunchAtLogin.isEnabled else { return }
            do {
                try LaunchAtLogin.set(enabled)
                launchAtLoginError = nil
            } catch {
                launchAtLoginError = "Ayarlanamadı: \(error.localizedDescription)"
                launchAtLogin = LaunchAtLogin.isEnabled
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(versionText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .strongGlass(Capsule())
            Spacer()
            Button { NSApp.terminate(nil) } label: {
                Label("Çıkış", systemImage: "power")
            }
            .buttonStyle(GlassCapsuleButtonStyle(height: 40, fontSize: 13))
            .keyboardShortcut("q")
        }
        .padding(.horizontal, Theme.margin - 4)
        .padding(.bottom, 14)
    }

    private var launchAtLoginNote: String? {
        LaunchAtLogin.isAvailable
            ? "Chrome eklentisinin çalışması için uygulamanın açık olması gerekir."
            : "Uygulama .app olarak paketlenip açıldığında kullanılabilir."
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "KD Download Manager" + (version.map { " \($0)" } ?? "")
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: downloadFolder, isDirectory: true)
        panel.prompt = "Seç"
        NSApp.activate()
        if panel.runModal() == .OK, let url = panel.url {
            downloadFolder = url.path
        }
    }
}

/// Vurgu rengi seçimi: renk yuvarlakları, seçili olanın çevresinde halka.
private struct AccentPicker: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 5) {
            ForEach(AccentChoice.allCases) { choice in
                let selected = selection == choice.rawValue
                Button { selection = choice.rawValue } label: {
                    Circle()
                        .fill(choice.color)
                        .frame(width: 18, height: 18)
                        .overlay {
                            if choice == .system {
                                // Sistem rengini diğerlerinden ayırmak için ortasında küçük bir nokta.
                                Circle().fill(.white.opacity(0.85)).frame(width: 6, height: 6)
                            }
                        }
                        .padding(3)
                        .overlay(Circle().strokeBorder(selected ? Theme.primaryText.opacity(0.8) : .clear, lineWidth: 1.5))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(choice.title)
                .accessibilityLabel(choice.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// Bölüm: üstte etiket, altında cam kart.
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title: title)
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .font(.system(size: 14))
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
    }
}

/// Etiket solda, denetim sağda; isteğe bağlı açıklama altta.
struct SettingsRow<Control: View>: View {
    let title: String
    var note: String?
    @ViewBuilder var control: Control

    init(_ title: String, note: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.note = note
        self.control = control()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer(minLength: 8)
                control
            }
            if let note {
                SettingsNote(note)
            }
        }
    }
}

/// Etiket solda, anahtar satırın sağında.
struct SettingsToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Toggle(title, isOn: $isOn)
                .labelsHidden()
        }
    }
}

/// Kartın içindeki küçük açıklama metni.
struct SettingsNote: View {
    let text: String
    var isError = false

    init(_ text: String, isError: Bool = false) {
        self.text = text
        self.isError = isError
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(isError ? Theme.errorText : Theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// "Bağlı" / "Güncel" gibi durum satırı: yeşil nokta ya da onay işaretiyle.
struct StatusLine: View {
    enum Kind { case connected, success, neutral, error }

    let text: String
    var kind: Kind = .neutral

    var body: some View {
        HStack(spacing: 5) {
            switch kind {
            case .connected:
                Circle().fill(Theme.success).frame(width: 7, height: 7)
            case .success:
                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.success)
            case .error:
                Circle().fill(Theme.error).frame(width: 7, height: 7)
            case .neutral:
                EmptyView()
            }
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(kind == .error ? Theme.errorText : Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
