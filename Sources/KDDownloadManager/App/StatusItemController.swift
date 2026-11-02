import SwiftUI
import AppKit
import QuickLookUI

/// Menü çubuğu ikonu ve tıklayınca açılan cam panel.
/// SwiftUI'nin MenuBarExtra'sı pencerenin zeminini, köşesini ve boyutunu değiştirmeye izin vermediği için
/// panel burada elle kuruluyor: 460 × 680, köşe 30, arkasındaki masaüstünü bulanıklaştıran cam.
@MainActor
final class StatusItemController: NSObject, NSWindowDelegate {
    private let store: DownloadStore
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private lazy var panel = makePanel()
    private var outsideClickMonitor: Any?
    private var iconState: IconState?
    private var doneTimer: Task<Void, Never>?

    /// Bildirime tıklanınca paneli açmak için.
    static let openPanelNotification = Notification.Name("KDOpenPanel")

    init(store: DownloadStore) {
        self.store = store
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(openFromNotification), name: Self.openPanelNotification, object: nil
        )
        // Başka bir uygulama öne geçince (⌘Tab, Dock, bildirim) panel kapansın. Panelin anahtar pencere
        // olmaktan çıkmasına bakılmıyor: önizleme, hız sınırı menüsü ve dosya seçme penceresi de
        // anahtar oluyor; macOS uygulamayı her zaman öne almadığı için "uygulama arka planda" kontrolü
        // önizlemeyi açılır açılmaz kapatıyordu.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(otherApplicationActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil
        )
        if let button = statusItem.button {
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(toggle)
            button.setAccessibilityLabel("KD Download Manager")
        }
        observeLabel()
        NotificationCenter.default.addObserver(
            self, selector: #selector(defaultsChanged), name: UserDefaults.didChangeNotification, object: nil
        )
    }

    var isOpen: Bool { panel.isVisible }

    @objc func toggle() {
        isOpen ? close() : open()
    }

    @objc private func otherApplicationActivated(_ notification: Notification) {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        guard !Self.keepsOpenForDemo, app?.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              NSApp.modalWindow == nil else { return }
        close()
    }

    /// Demo aracı çalışırken başka uygulamalar öne geçebiliyor; panel açık kalsın.
    private static var keepsOpenForDemo: Bool {
        #if DEBUG
        return DebugPanel.screen != nil
        #else
        return false
        #endif
    }

    @objc private func openFromNotification() {
        if !isOpen { open() }
    }

    func open() {
        guard !isOpen else { return }
        store.panelWillOpen()
        position()
        // Uygulama etkin değilken anahtarlar ve alanlar soluk (pasif) çiziliyor. Kapanırken gizlendiyse
        // önce görünür yapılmalı, yoksa panel ekrana gelmiyor.
        if NSApp.isHidden { NSApp.unhide(nil) }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        statusItem.button?.highlight(true)
        // Panelin dışına (başka bir uygulamaya ya da masaüstüne) tıklanınca kapansın.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    func close() {
        guard panel.isVisible else { return }
        QuickLook.shared.close()
        panel.orderOut(nil)
        statusItem.button?.highlight(false)
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        outsideClickMonitor = nil
        // Panel açılırken uygulama öne alınmıştı; kapanınca odağı önceki uygulamaya geri ver, yoksa
        // klavye girdisi penceresi olmayan bu uygulamaya gidiyor.
        if NSApp.isActive, NSApp.modalWindow == nil {
            NSApp.hide(nil)
        }
    }

    // MARK: - Panel

    private func makePanel() -> PanelWindow {
        let size = NSSize(width: Theme.panelWidth, height: Theme.panelHeight)
        let hosting = NSHostingView(rootView: PanelView().environment(store))
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]

        let content: NSView
        if #available(macOS 26, *) {
            // Cam, PanelView'da pencerenin şekliyle (.glassEffect) çiziliyor.
            content = hosting
        } else {
            let effect = NSVisualEffectView(frame: hosting.frame)
            effect.material = .hudWindow
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.maskImage = Self.roundedMask(radius: Theme.windowRadius)
            effect.addSubview(hosting)
            content = effect
        }

        let panel = PanelWindow(size: size)
        panel.contentView = content
        panel.delegate = self
        // Esc: alt ekranlarda (Link ekle, Ayarlar, kurulum) listeye döner, listede paneli kapatır. Yazı alanı
        // odaktayken Esc doğrudan pencereye geldiği için geri butonunun kısayoluna güvenilemiyor.
        panel.onCancel = { [weak self] in
            guard let self else { return }
            if QuickLook.shared.isVisible {
                QuickLook.shared.close()
            } else if store.route == .list {
                close()
            } else {
                store.route = .list
            }
        }
        panel.onClose = { [weak self] in self?.close() }
        return panel
    }

    /// Menü çubuğu ikonunun hemen altında, ekranın dışına taşmadan.
    private func position() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let size = panel.frame.size
        let x = min(max(buttonFrame.midX - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
        let y = max(buttonFrame.minY - size.height - 6, visible.minY + 8)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    // MARK: - Menü çubuğu ikonu

    /// Boşta sadece ikon; inerken etrafında toplam ilerleme halkası; hata varsa kırmızı nokta (tıklanınca
    /// liste açılır); son indirme bitince 3 sn onay işareti.
    private enum IconState: Equatable {
        case idle
        /// 0…36 arası adım; halka her %2,8'de bir yeniden çizilir.
        case progress(Int)
        case error
        case done
    }

    private static let iconSize = NSSize(width: 18, height: 18)
    private static let doneDuration: TimeInterval = 3

    private func currentIconState() -> IconState {
        if store.hasFailures { return .error }
        let running = store.items.filter { [.downloading, .queued, .processing].contains($0.status) }
        if !running.isEmpty {
            let sized = running.filter { $0.totalBytes > 0 }
            let total = sized.reduce(Int64(0)) { $0 + $1.totalBytes }
            let done = sized.reduce(Int64(0)) { $0 + min($1.downloadedBytes, $1.totalBytes) }
            return .progress(total > 0 ? Int((Double(done) / Double(total) * 36).rounded(.down)) : 0)
        }
        if let finished = store.finishedAt, Date().timeIntervalSince(finished) < Self.doneDuration {
            return .done
        }
        return .idle
    }

    private func updateIcon() {
        let state = currentIconState()
        if state == .done, let finished = store.finishedAt {
            // Onay işareti süresi dolunca boşta ikonuna dön.
            doneTimer?.cancel()
            doneTimer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(0, Self.doneDuration - Date().timeIntervalSince(finished)) + 0.05))
                guard !Task.isCancelled else { return }
                self?.updateIcon()
            }
        }
        guard state != iconState, let button = statusItem.button else { return }
        iconState = state
        button.image = Self.image(for: state)
    }

    private static func image(for state: IconState) -> NSImage {
        let size = iconSize
        let symbol = { (name: String, pointSize: CGFloat, weight: NSFont.Weight, colors: [NSColor]?) -> NSImage? in
            var configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
            if let colors { configuration = configuration.applying(.init(paletteColors: colors)) }
            return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
        }
        func drawCentered(_ image: NSImage?, in rect: NSRect) {
            guard let image else { return }
            let origin = NSPoint(x: rect.midX - image.size.width / 2, y: rect.midY - image.size.height / 2)
            image.draw(in: NSRect(origin: origin, size: image.size))
        }
        let image: NSImage
        switch state {
        case .idle, .done:
            image = NSImage(size: size, flipped: false) { rect in
                drawCentered(symbol(state == .done ? "checkmark.circle" : "arrow.down.circle", 15, .semibold, nil), in: rect)
                return true
            }
            image.isTemplate = true
        case .progress(let step):
            image = NSImage(size: size, flipped: false) { rect in
                let ring = rect.insetBy(dx: 1.8, dy: 1.8)
                let center = NSPoint(x: ring.midX, y: ring.midY)
                let track = NSBezierPath(ovalIn: ring)
                track.lineWidth = 1.6
                NSColor.black.withAlphaComponent(0.3).setStroke()
                track.stroke()
                let fraction = CGFloat(step) / 36
                if fraction > 0 {
                    let arc = NSBezierPath()
                    arc.appendArc(withCenter: center, radius: ring.width / 2, startAngle: 90, endAngle: 90 - 360 * fraction, clockwise: true)
                    arc.lineWidth = 2
                    arc.lineCapStyle = .round
                    NSColor.black.setStroke()
                    arc.stroke()
                }
                drawCentered(symbol("arrow.down", 8, .bold, nil), in: rect)
                return true
            }
            image.isTemplate = true
        case .error:
            // Kırmızı nokta tek renkli (template) ikonda çizilemediği için menü çubuğunun yazı rengiyle çiziliyor.
            image = NSImage(size: size, flipped: false) { rect in
                drawCentered(symbol("arrow.down.circle", 15, .semibold, [.labelColor]), in: rect)
                let dot = NSRect(x: rect.maxX - 6.5, y: rect.maxY - 6.5, width: 6.5, height: 6.5)
                NSColor.systemRed.setFill()
                NSBezierPath(ovalIn: dot).fill()
                return true
            }
        }
        image.accessibilityDescription = switch state {
        case .idle: "KD Download Manager"
        case .progress(let step): "KD Download Manager, yüzde \(step * 100 / 36) indi"
        case .error: "KD Download Manager, indirme hatası var"
        case .done: "KD Download Manager, indirmeler tamamlandı"
        }
        return image
    }

    /// İkonun yanındaki anlık toplam hız ("Toplam hızı göster" açıksa ve bir şey iniyorsa).
    private func observeLabel() {
        withObservationTracking {
            updateLabel()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeLabel() }
        }
    }

    @objc private func defaultsChanged() {
        updateLabel()
    }

    private func updateLabel() {
        updateIcon()
        guard let button = statusItem.button else { return }
        let showSpeed = UserDefaults.standard.object(forKey: SettingsKey.showSpeedInMenuBar) as? Bool ?? true
        let speed = store.displaySpeed
        guard showSpeed, speed > 0 else {
            if !button.title.isEmpty { button.title = "" }
            return
        }
        // Genişlik rakam genişliğindeki boşlukla (U+2007) sabitleniyor; hız değiştikçe yandaki ikonlar kaymasın.
        let text = ByteFormat.speed(speed)
        let padded = " " + String(repeating: "\u{2007}", count: max(0, 10 - text.count)) + text
        button.attributedTitle = NSAttributedString(string: padded, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        ])
    }
}

/// Kenarlıksız, saydam panel. Uygulamayı öne getirmeden klavye girdisi alabiliyor (Link ekle alanı).
final class PanelWindow: NSPanel {
    var onCancel: (() -> Void)?
    var onClose: (() -> Void)?

    init(size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Quick Look paneli denetimi isterken yanıtlayıcı zincirine soruyor; biz veriyoruz.
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = QuickLook.shared
            panel.delegate = QuickLook.shared
        }
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {}

    /// Esc: açık bir menü yakalamadıysa geri gider ya da paneli kapatır (bkz. StatusItemController).
    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    /// ⌘W: menüde Kapat öğesi olmadığı ve kenarlıksız pencerenin kapat düğmesi bulunmadığı için elle.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "w" {
            onClose?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
