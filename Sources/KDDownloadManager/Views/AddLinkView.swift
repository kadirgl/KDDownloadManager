import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PhosphorSwift

/// Link yapıştırıp indirme başlatma ekranı.
struct AddLinkView: View {
    @Environment(DownloadStore.self) private var store
    @State private var text = ""
    @State private var quality: VideoQuality = .auto
    @FocusState private var editorFocused: Bool

    private var links: [String] { DownloadStore.parseLinks(text) }
    private var hasVideoLinks: Bool { links.contains { DownloadSource.detect($0) == .video } }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Link Ekle", onBack: { store.route = .list })

            VStack(alignment: .leading, spacing: 12) {
                Text("Her satıra bir link yazın. HTTP/FTP dosyaları, YouTube vb. videolar ve magnet/torrent linkleri desteklenir.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                editor

                if hasVideoLinks {
                    HStack {
                        Text("Video kalitesi")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Picker("Video kalitesi", selection: $quality) {
                            ForEach(VideoQuality.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surface))
                }

                if !links.isEmpty {
                    Text("\(links.count) link bulundu")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                                LinkPreviewRow(link: link)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)

            PanelFooter {
                Button(action: pasteFromClipboard) {
                    HStack(spacing: 6) {
                        PhIcon(.clipboard, weight: .bold, size: 14)
                        Text("Panodan yapıştır")
                    }
                }
                .buttonStyle(PillButtonStyle(prominent: false))

                Button(action: chooseTorrentFiles) {
                    HStack(spacing: 6) {
                        PhIcon(.magnet, weight: .bold, size: 14)
                        Text("Torrent dosyası")
                    }
                }
                .buttonStyle(PillButtonStyle(prominent: false))
                .help("Bilgisayardaki .torrent dosyalarını ekle (panele sürükleyip bırakmak da olur)")

                Spacer()

                Button { store.add(links: text, quality: quality) } label: {
                    HStack(spacing: 6) {
                        PhIcon(.downloadSimple, weight: .bold, size: 14)
                        Text(links.count > 1 ? "\(links.count) dosyayı indir" : "İndir")
                    }
                }
                .buttonStyle(PillButtonStyle())
                .disabled(links.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
                .help("İndir (⌘↩)")
            }
        }
        .onAppear {
            if text.isEmpty, let clip = clipboardLinks {
                text = clip
            }
            editorFocused = true
        }
    }

    private var editor: some View {
        TextEditor(text: $text)
            .font(.system(size: 12, design: .monospaced))
            .scrollContentBackground(.hidden)
            .focused($editorFocused)
            .padding(10)
            .frame(height: 140)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text("https://…")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
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

private struct LinkPreviewRow: View {
    let link: String

    var body: some View {
        HStack(spacing: 8) {
            SourceBadge(source: DownloadSource.detect(link))
            Text(link)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.surface)
        )
    }
}
