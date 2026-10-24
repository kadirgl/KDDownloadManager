import SwiftUI
import AppKit
import PhosphorSwift

/// Ayarlar ekranı; değerler @AppStorage ile UserDefaults'a yazılır.
struct SettingsView: View {
    @Environment(DownloadStore.self) private var store
    @AppStorage(SettingsKey.downloadFolder) private var downloadFolder = SettingsKey.defaultDownloadFolder
    @AppStorage(SettingsKey.globalLimitEnabled) private var limitEnabled = false
    @AppStorage(SettingsKey.globalLimitMB) private var limitMB = 5.0
    @AppStorage(SettingsKey.maxConcurrent) private var maxConcurrent = SettingsKey.defaultMaxConcurrent
    @AppStorage(SettingsKey.showSpeedInMenuBar) private var showSpeed = true

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

                    SettingsSection(title: "Menü çubuğu") {
                        SettingsToggle(title: "Toplam hızı göster", isOn: $showSpeed)
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
        .onChange(of: limitMB) { store.applyGlobalSpeedLimit() }
        .onChange(of: maxConcurrent) { store.applyMaxConcurrent() }
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

private struct SettingsSection<Content: View>: View {
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
