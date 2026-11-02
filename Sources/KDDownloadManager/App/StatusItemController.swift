import SwiftUI
import AppKit

/// Menü çubuğu ikonu ve tıklayınca açılan cam panel.
/// SwiftUI'nin MenuBarExtra'sı pencerenin zeminini, köşesini ve boyutunu değiştirmeye izin vermediği için
/// panel burada elle kuruluyor: 460 × 680, köşe 30, arkasındaki masaüstünü bulanıklaştıran cam.
@MainActor
final class StatusItemController: NSObject, NSWindowDelegate {
    private let store: DownloadStore
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private lazy var panel = makePanel()
    private var outsideClickMonitor: Any?

    init(store: DownloadStore) {
        self.store = store
        super.init()
        if let button = statusItem.button {
            button.image = Self.icon
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

    func open() {
        store.panelWillOpen()
        position()
        // Uygulama etkin değilken anahtarlar ve alanlar soluk (pasif) çiziliyor.
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
        panel.orderOut(nil)
        statusItem.button?.highlight(false)
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        outsideClickMonitor = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        // Odak uygulamadan çıktıysa kapan; hız sınırı menüsü (popover) ya da dosya seçme penceresi gibi
        // kendi pencerelerimize geçtiyse açık kalsın. Yeni anahtar pencere bir sonraki döngüde belli oluyor.
        DispatchQueue.main.async { [weak self] in
            guard NSApp.modalWindow == nil, !NSApp.isActive || NSApp.keyWindow == nil else { return }
            self?.close()
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
        panel.onCancel = { [weak self] in self?.close() }
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

    // MARK: - Menü çubuğu etiketi

    private static let icon: NSImage = {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        let image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: "KD Download Manager")?
            .withSymbolConfiguration(configuration) ?? NSImage()
        image.isTemplate = true
        return image
    }()

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

    /// Esc: açık bir menü ya da geri butonu yakalamadıysa paneli kapatır.
    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
