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
        // Performans ölçümü için çok sayıda örnek indirme: yarısı iniyor, çeyreği duraklatılmış, çeyreği bitmiş.
        if let count = ProcessInfo.processInfo.environment["KD_DEMO_COUNT"].flatMap(Int.init), count > 0 {
            let names = ["Rapor", "Sunum", "Kayit", "Yedek", "Kurulum", "Albüm", "Film"]
            let extensions = ["pdf", "key", "mp4", "zip", "dmg", "mp3", "mkv"]
            store.add((0..<count).map { index in
                DownloadRequest(url: "https://files.example.com/\(names[index % 7])_\(index).\(extensions[index % 7])")
            })
            for (index, item) in store.items.enumerated() where index < count {
                item.totalBytes = Int64(20 + index % 40) * 1_073_741_824
                switch index % 4 {
                case 2: store.togglePause(item)
                case 3:
                    item.downloadedBytes = item.totalBytes
                    item.status = .completed
                    item.speed = 0
                default: break
                }
            }
            store.route = .list
        }
        // Eklentiden yeni bir sinyal gelmiş gibi (geliştirme ayarlarına yazılır, uygulamanınkine değil).
        if let browser = ProcessInfo.processInfo.environment["KD_DEMO_HELLO"] {
            store.extensionDidConnect(browser)
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
            if screen == "deleted", let first = store?.items.first {
                store?.delete(first)
            }
            if let panel, ProcessInfo.processInfo.environment["KD_DEMO_KEYS"] == nil {
                report(after: "açılış", panel: panel)
            }
            if let keys = ProcessInfo.processInfo.environment["KD_DEMO_KEYS"], let panel {
                try? await Task.sleep(for: .seconds(0.5))
                for key in keys.split(separator: ",") {
                    if key == "items" {
                        // Tüm indirmelerin son durumu: ad, durum, boyut ve diskteki dosya.
                        for item in store?.items ?? [] {
                            let path = item.destination?.path ?? item.folder.appendingPathComponent(item.fileName).path
                            let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int64
                            let line = "KD_DEMO_ITEM \(item.url) | ad=\(item.fileName) | \(item.status) | "
                                + "toplam=\(item.totalBytes) inen=\(item.downloadedBytes) | disk=\(size.map(String.init) ?? "yok")\n"
                            FileHandle.standardError.write(Data(line.utf8))
                        }
                        continue
                    }
                    if key.hasPrefix("scroll") {
                        // "scroll-down" / "scroll-up": trackpad'e benzer sürekli kaydırma, kare süreleri ölçülür.
                        await scroll(down: key == "scroll-down", in: panel)
                        continue
                    }
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
        let extensionStates = BrowserExtension.installedBrowsers.map { browser in
            "\(browser.name)=\(store.map { String(describing: $0.extensionStatus(for: browser)) } ?? "-")"
        }
        let line = "KD_DEMO_STATE \(key): eklenti=\(extensionStates) panel=\(panel.isVisible ? "açık" : "kapalı") anahtar=\(panel.isKeyWindow) "
            + "ekran=\(String(describing: store?.route ?? .list)) sekme=\(String(describing: store?.tab ?? .active)) "
            + "liste=\(store?.items.count ?? 0) ilk=\(store?.items.first.map { String(describing: $0.status) } ?? "-") seçili=\(item?.fileName ?? "-") önizleme=\(previewing) "
            + "pencereler=\(NSApp.windows.filter(\.isVisible).map { String(describing: type(of: $0)) })\n"
        FileHandle.standardError.write(Data(line.utf8))
    }

    /// Trackpad hareketine benzer 1,5 sn'lik kaydırma; bu sırada ekran yenileme geri çağrılarının
    /// arasındaki boşluklar ölçülür. Ana iş parçacığı bir karede işini bitiremezse boşluk büyür (takılma).
    private static func scroll(down: Bool, in panel: NSWindow) async {
        guard let view = panel.contentView, let screen = panel.screen else { return }
        func find(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView, scroll.documentView?.frame.height ?? 0 > scroll.frame.height + 50 { return scroll }
            for subview in view.subviews { if let found = find(subview) { return found } }
            return nil
        }
        guard let scrollView = find(view) else { return }
        func scrollOffset() -> CGFloat { scrollView.contentView.bounds.origin.y }
        let startOffset = scrollOffset()

        let counter = FrameCounter()
        let link = view.displayLink(target: counter, selector: #selector(FrameCounter.tick(_:)))
        link.add(to: .main, forMode: .common)
        let point = CGPoint(x: panel.frame.midX, y: screen.frame.maxY - panel.frame.midY + 60)
        let steps = 180
        for step in 0..<steps {
            guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                      wheel1: Int32(down ? -9 : 9), wheel2: 0, wheel3: 0) else { continue }
            event.location = point
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: step == 0 ? 1 : step == steps - 1 ? 4 : 2)
            event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(panel.windowNumber))
            event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(panel.windowNumber))
            if let nsEvent = NSEvent(cgEvent: event) { scrollView.scrollWheel(with: nsEvent) }
            try? await Task.sleep(for: .milliseconds(8))
        }
        try? await Task.sleep(for: .milliseconds(100))
        link.invalidate()
        let gaps = zip(counter.stamps.dropFirst(), counter.stamps).map { ($0 - $1) * 1000 }.sorted()
        guard let median = gaps.dropFirst(gaps.count / 2).first, let longest = gaps.last else { return }
        let hitches = gaps.filter { $0 > median * 1.6 }.count
        let line = String(format: "KD_DEMO_SCROLL %@: kare=%d ortanca=%.1f ms en uzun=%.1f ms takılma=%d konum %.0f→%.0f\n",
                          down ? "aşağı" : "yukarı", gaps.count, median, longest, hitches, startOffset, scrollOffset())
        FileHandle.standardError.write(Data(line.utf8))
    }

    private final class FrameCounter: NSObject {
        var stamps: [CFTimeInterval] = []
        @objc func tick(_ link: CADisplayLink) { stamps.append(link.timestamp) }
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
