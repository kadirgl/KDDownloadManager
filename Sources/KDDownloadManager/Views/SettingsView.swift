import SwiftUI
import AppKit

/// Ayarlar ekranı; değerler @AppStorage ile UserDefaults'a yazılır.
struct SettingsView: View {
    @Environment(DownloadStore.self) private var store
    @AppStorage(SettingsKey.downloadFolder) private var downloadFolder = SettingsKey.defaultDownloadFolder
    @AppStorage(SettingsKey.globalLimitEnabled) private var limitEnabled = false
    @AppStorage(SettingsKey.globalLimitMB) private var limitMB = 5.0
    @AppStorage(SettingsKey.maxConcurrent) private var maxConcurrent = SettingsKey.defaultMaxConcurrent
    @AppStorage(SettingsKey.showSpeedInMenuBar) private var showSpeed = true
    @AppStorage(SettingsKey.appTheme) private var theme = AppTheme.system.rawValue
    @AppStorage(SettingsKey.accentColor) private var accent = AccentChoice.orange.rawValue
    @AppStorage(SettingsKey.notifyOnAdd) private var notifyOnAdd = true
    @AppStorage(SettingsKey.notifyOnFinish) private var notifyOnFinish = true
    @AppStorage(SettingsKey.notifyOnFail) private var notifyOnFail = true
    // Kaynak macOS; burada sadece gösterim için tutuluyor.
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchAtLoginError: String?
    /// Kaydırıcı sürüklenirken her adımda uygulamamak için (video indirmeleri yeniden başlatılıyor).
    @State private var pendingLimit: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Ayarlar", onBack: { store.route = .list })

            ScrollView {
                VStack(spacing: 12) {
                    SettingsSection(title: "İndirme klasörü") {
                        HStack(spacing: 10) {
                            PhIcon(.folder, weight: .fill, size: 18)
                                .foregroundStyle(Theme.accent)
                            Text((downloadFolder as NSString).abbreviatingWithTildeInPath)
                                .font(.system(size: 13))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(downloadFolder)
                            Spacer(minLength: 8)
                            Button("Değiştir", action: chooseFolder)
                                .buttonStyle(PillButtonStyle(prominent: false))
                        }
                    }

                    SettingsSection(title: "Görünüm") {
                        HStack {
                            Text("Tema")
                            Spacer()
                            Picker("Tema", selection: $theme) {
                                ForEach(AppTheme.allCases) { Text($0.title).tag($0.rawValue) }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .fixedSize()
                        }
                        HStack {
                            Text("Vurgu rengi")
                            Spacer()
                            AccentPicker(selection: $accent)
                        }
                    }

                    SettingsSection(title: "Hız") {
                        SettingsToggle(title: "Genel hız sınırı", isOn: $limitEnabled)
                        if limitEnabled {
                            HStack(spacing: 10) {
                                Slider(value: $limitMB, in: 1...100, step: 1)
                                Text("\(Int(limitMB)) MB/S")
                                    .font(.system(size: 12, weight: .medium))
                                    .monospacedDigit()
                                    .frame(width: 64, alignment: .trailing)
                            }
                        }
                        HStack {
                            Text("Aynı anda en fazla")
                            Spacer()
                            Text("\(maxConcurrent) indirme")
                                .monospacedDigit()
                            Stepper("Aynı anda en fazla", value: $maxConcurrent, in: 1...10)
                                .labelsHidden()
                        }
                    }

                    ExtensionSettings()

                    TorrentSettings()

                    SettingsSection(title: "Bildirimler") {
                        SettingsToggle(title: "İndirme eklendiğinde", isOn: $notifyOnAdd)
                        SettingsToggle(title: "İndirme tamamlandığında", isOn: $notifyOnFinish)
                        SettingsToggle(title: "Hata olduğunda", isOn: $notifyOnFail)
                        if !Notifier.isAvailable {
                            Text("Uygulama .app olarak paketlenip açıldığında çalışır.")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }

                    SettingsSection(title: "Menü çubuğu") {
                        SettingsToggle(title: "Toplam hızı göster", isOn: $showSpeed)
                    }

                    SettingsSection(title: "Başlangıç") {
                        SettingsToggle(title: "Oturum açınca başlat", isOn: $launchAtLogin)
                            .disabled(!LaunchAtLogin.isAvailable)
                        if let note = launchAtLoginError ?? launchAtLoginNote {
                            Text(note)
                                .font(.system(size: 11))
                                .foregroundStyle(launchAtLoginError == nil ? Theme.secondaryText : .red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .toggleStyle(.switch)
                .tint(Theme.accent)
                .padding(16)
            }

            PanelFooter {
                Text(versionText)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                Button { NSApp.terminate(nil) } label: {
                    HStack(spacing: 6) {
                        PhIcon(.power, weight: .bold, size: 14)
                        Text("Çıkış")
                    }
                }
                .buttonStyle(PillButtonStyle(prominent: false))
                .keyboardShortcut("q")
            }
        }
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
        HStack(spacing: 6) {
            ForEach(AccentChoice.allCases) { choice in
                Button { selection = choice.rawValue } label: {
                    Circle()
                        .fill(choice.color)
                        .frame(width: 16, height: 16)
                        .overlay {
                            if choice == .system {
                                // Sistem rengini diğerlerinden ayırmak için ortasında küçük bir nokta.
                                Circle().fill(.white.opacity(0.85)).frame(width: 5, height: 5)
                            }
                        }
                        .padding(3)
                        .overlay(
                            Circle().strokeBorder(
                                selection == choice.rawValue ? Theme.primaryText.opacity(0.6) : .clear,
                                lineWidth: 1.5
                            )
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(choice.title)
                .accessibilityLabel(choice.title)
                .accessibilityAddTraits(selection == choice.rawValue ? .isSelected : [])
            }
        }
    }
}

/// Etiket solda, anahtar satırın sağında.
private struct SettingsToggle: View {
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

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
                .textCase(.uppercase)
                .padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .font(.system(size: 13))
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Theme.surface)
            )
        }
    }
}
