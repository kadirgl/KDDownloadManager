#if DEBUG
import SwiftUI
import AppKit

/// Geliştirme aracı: menü çubuğu panelini örnek verilerle açar. Cam efektleri ancak gerçek
/// pencerede çizildiği için tasarım bu şekilde, ekran görüntüsüyle karşılaştırılıyor.
///
///     KD_DEMO=list .build/debug/KDDownloadManager
///
/// KD_DEMO: list, completed, empty, empty-completed, add-link, settings, onboarding, failed
/// KD_DEMO_THEME: light / dark (isteğe bağlı)
/// KD_DEMO_BACKDROP=1: panelin arkasına tasarımdaki renkli zemini koyar.
/// Gerçek listeye, ayarlara ve eklenti portuna dokunmaz (DebugHarness.isActive).
@MainActor
enum DebugPanel {
    static var screen: String? { ProcessInfo.processInfo.environment["KD_DEMO"] }

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
        default:
            break
        }
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
