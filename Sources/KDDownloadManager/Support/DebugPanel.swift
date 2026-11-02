#if DEBUG
import SwiftUI
import AppKit
import QuickLookUI

/// Geliştirme aracı: menü çubuğu panelini örnek verilerle açar. Cam efektleri ancak gerçek
/// pencerede çizildiği için tasarım bu şekilde, ekran görüntüsüyle karşılaştırılıyor.
///
///     KD_DEMO=list .build/debug/KDDownloadManager
///
/// KD_DEMO: list, completed, empty, empty-completed, add-link, settings, onboarding, failed
/// KD_DEMO_THEME: light / dark (isteğe bağlı)
/// KD_DEMO_BACKDROP=1: panelin arkasına tasarımdaki renkli zemini koyar.
/// KD_DEMO_LINK: Link ekle alanına yazılacak metin (panoya dokunmadan); KD_DEMO_SEARCH: Tamamlanan'da arama.
/// KD_DEMO=deleted: ilk indirmeyi silip "Geri al" bildirimini gösterir.
/// KD_DEMO_KEYS: panel açılınca sırayla basılacak tuşlar, örn. "down,down,space" ya da "down,cmd-delete,cmd-z".
/// Gerçek listeye, ayarlara ve eklenti portuna dokunmaz (DebugHarness.isActive).
@MainActor
enum DebugPanel {
    static var screen: String? { ProcessInfo.processInfo.environment["KD_DEMO"] }
    static var addLinkText: String? { ProcessInfo.processInfo.environment["KD_DEMO_LINK"] }

    private static weak var store: DownloadStore?

    static func configure(_ store: DownloadStore) {
        guard let screen else { return }
        self.store = store
        switch screen {
        case "empty":
            store.items.removeAll { $0.status != .completed }
        case "empty-completed":
            store.items.removeAll()
        case "failed":
            store.items.first { $0.status != .completed }?.status = .failed("Bağlantının süresi doldu")
            store.items.dropFirst().first { $0.status != .completed }?.status = .failed("Diskte yer kalmadı")
        default:
            break
        }
        // Tamamlananlara örnek bitiş zamanları.
        for (index, item) in store.items.filter({ $0.status == .completed }).enumerated() {
            item.completedAt = Date().addingTimeInterval(-Double(index) * 30_000 - 600)
            // Quick Look ve "Dosyayı aç" denenebilsin diye geçici bir örnek dosya.
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("kd-demo-\(index).txt")
            try? "KD Download Manager örnek dosyası: \(item.fileName)".write(to: file, atomically: true, encoding: .utf8)
            item.destination = file
        }
        store.searchText = ProcessInfo.processInfo.environment["KD_DEMO_SEARCH"] ?? ""
        switch screen {
        case "completed", "empty-completed": store.tab = .completed
        case "add-link": store.route = .addLink
        case "settings": store.route = .settings
        case "onboarding": store.route = .onboarding
        default: store.tab = .active
        }
    }

    private static var backdrop: NSWindow?

    static func runIfRequested(open: @escaping () -> Void) {
        guard screen != nil else { return }
        switch ProcessInfo.processInfo.environment["KD_DEMO_THEME"] {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
        Task {
            try? await Task.sleep(for: .seconds(0.6))
            open()
            let panel = NSApp.windows.first { $0 is PanelWindow }
            if ProcessInfo.processInfo.environment["KD_DEMO_BACKDROP"] != nil {
                showBackdrop(behind: panel)
            }
            // Ekran görüntüsü için panelin ekrandaki yeri (sol üst köşe orijinli, nokta).
            if screen == "deleted", let first = store?.items.first {
                store?.delete(first)
            }
            if let keys = ProcessInfo.processInfo.environment["KD_DEMO_KEYS"], let panel {
                try? await Task.sleep(for: .seconds(0.5))
                for key in keys.split(separator: ",") {
                    press(String(key), in: NSApp.keyWindow ?? panel)
                    try? await Task.sleep(for: .seconds(0.6))
                    report(after: String(key), panel: panel)
                }
            }
            if screen == "empty" {
                // Liste boşalınca "Tamamlanan"a otomatik geçiş bir sonraki döngüde geliyor.
                try? await Task.sleep(for: .seconds(0.3))
                store?.tab = .active
            }
            if let panel, let screen = panel.screen {
                let frame = (backdrop?.frame ?? panel.frame).intersection(screen.visibleFrame)
                let top = screen.frame.maxY - frame.maxY
                FileHandle.standardError.write(Data("KD_DEMO_REGION \(Int(frame.minX)),\(Int(top)),\(Int(frame.width)),\(Int(frame.height))\n".utf8))
            }
        }
    }

    /// Tuştan sonraki durum: ekran görüntüsü almadan doğrulamak için.
    private static func report(after key: String, panel: NSWindow) {
        let preview = QLPreviewPanel.sharedPreviewPanelExists() ? QLPreviewPanel.shared() : nil
        let item = store?.items.first { $0.id == store?.selection }
        let previewing = preview?.isVisible == true ? (preview?.currentPreviewItem?.previewItemURL?.lastPathComponent ?? "?") : "kapalı"
        let line = "KD_DEMO_STATE \(key): panel=\(panel.isVisible ? "açık" : "kapalı") anahtar=\(panel.isKeyWindow) "
            + "ekran=\(String(describing: store?.route ?? .list)) sekme=\(String(describing: store?.tab ?? .active)) "
            + "liste=\(store?.items.count ?? 0) seçili=\(item?.fileName ?? "-") önizleme=\(previewing) "
            + "pencereler=\(NSApp.windows.filter(\.isVisible).map { String(describing: type(of: $0)) })\n"
        FileHandle.standardError.write(Data(line.utf8))
    }

    private static func press(_ key: String, in window: NSWindow) {
        let table: [String: (code: UInt16, characters: String)] = [
            "down": (125, "\u{F701}"), "up": (126, "\u{F700}"), "space": (49, " "), "return": (36, "\r"),
            "delete": (51, "\u{7F}"), "z": (6, "z"), "f": (3, "f"), "r": (15, "r"), "escape": (53, "\u{1B}"), "comma": (43, ","), "w": (13, "w"), "n": (45, "n"), "v": (9, "v"), "c": (8, "c"), "one": (18, "1"), "two": (19, "2")
        ]
        let command = key.hasPrefix("cmd-")
        guard let entry = table[command ? String(key.dropFirst(4)) : key] else { return }
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: command ? .command : [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                characters: entry.characters, charactersIgnoringModifiers: entry.characters, isARepeat: false,
                keyCode: entry.code
            ) else { continue }
            NSApp.sendEvent(event)
        }
    }

    /// Tasarım panolarındaki gibi turuncu, mor, turkuaz ve pembe ışıklı zemin.
    private static func showBackdrop(behind panel: NSWindow?) {
        guard let panel else { return }
        let frame = panel.frame.insetBy(dx: -140, dy: -60)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.contentView = NSHostingView(rootView: Backdrop(dark: NSApp.effectiveAppearance.isDark))
        window.orderFront(nil)
        backdrop = window
    }

    private struct Backdrop: View {
        let dark: Bool

        var body: some View {
            ZStack {
                (dark ? Color(hex: 0x15121C) : Color(hex: 0xF3EEF4))
                blob(0xF08A2E, x: 0.12, y: 0.18, size: 380)
                blob(0x6C5CF5, x: 0.92, y: 0.25, size: 420)
                blob(0x3FB8C9, x: 0.08, y: 0.85, size: 380)
                blob(0xD83A72, x: 0.62, y: 0.92, size: 420)
            }
            .ignoresSafeArea()
        }

        private func blob(_ hex: UInt32, x: CGFloat, y: CGFloat, size: CGFloat) -> some View {
            GeometryReader { geo in
                Circle()
                    .fill(Color(hex: hex).opacity(dark ? 0.75 : 0.35))
                    .frame(width: size, height: size)
                    .blur(radius: 90)
                    .position(x: geo.size.width * x, y: geo.size.height * y)
            }
        }
    }
}
#endif
