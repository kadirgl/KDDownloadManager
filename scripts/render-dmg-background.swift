// Kurulum diskinin (DMG) arka planını çizer: açık zemin, beyaz kart, uygulamadan Uygulamalar klasörüne giden
// el çizimi bir ok ve altta kısa bir yönerge.
//
//   swift scripts/render-dmg-background.swift <klasör>   → <klasör>/background.png (1x) ve background@2x.png
//
// Ölçüler scripts/make-dmg.sh'taki pencere ve ikon yerleriyle aynı olmalı (Layout).
import AppKit

enum Layout {
    static let size = NSSize(width: 640, height: 400)
    /// İkonların merkezleri (Finder koordinatı: sol üstten). make-dmg.sh de bunları kullanır.
    static let app = NSPoint(x: 170, y: 170)
    static let applications = NSPoint(x: 470, y: 170)
}

let accent = NSColor(srgbRed: 0xF0 / 255, green: 0x8A / 255, blue: 0x2E / 255, alpha: 1)

func render(scale: CGFloat, to url: URL) throws {
    let pixels = NSSize(width: Layout.size.width * scale, height: Layout.size.height * scale)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(pixels.width), pixelsHigh: Int(pixels.height), bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = Layout.size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    // AppKit'te başlangıç sol altta; çizim Finder'ın sol üst koordinatıyla yapılsın.
    let context = NSGraphicsContext.current!.cgContext
    context.translateBy(x: 0, y: Layout.size.height)
    context.scaleBy(x: 1, y: -1)
    let flipped = NSGraphicsContext(cgContext: context, flipped: true)
    NSGraphicsContext.current = flipped

    let bounds = NSRect(origin: .zero, size: Layout.size)

    // Zemin: sıcak, çok açık bir geçiş ve köşelerde markanın turuncusundan hafif ışık.
    NSGradient(colors: [
        NSColor(srgbRed: 0.985, green: 0.975, blue: 0.965, alpha: 1),
        NSColor(srgbRed: 0.955, green: 0.955, blue: 0.965, alpha: 1),
    ])!.draw(in: bounds, angle: -90)
    for (center, radius, alpha) in [(NSPoint(x: 40, y: 20), 260.0, 0.20), (NSPoint(x: 620, y: 390), 240.0, 0.14)] {
        NSGradient(colors: [accent.withAlphaComponent(alpha), accent.withAlphaComponent(0)])!
            .draw(fromCenter: center, radius: 0, toCenter: center, radius: radius, options: [])
    }

    // Kart: ikonlar ve yazılar bunun üstünde okunaklı dursun (Finder koyu modda da ikon adlarını koyu yazar).
    let card = bounds.insetBy(dx: 26, dy: 24)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.08)
    shadow.shadowOffset = NSSize(width: 0, height: 2)
    shadow.shadowBlurRadius = 14
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.white.withAlphaComponent(0.92).setFill()
    NSBezierPath(roundedRect: card, xRadius: 18, yRadius: 18).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSColor.black.withAlphaComponent(0.06).setStroke()
    let border = NSBezierPath(roundedRect: card.insetBy(dx: 0.5, dy: 0.5), xRadius: 18, yRadius: 18)
    border.lineWidth = 1
    border.stroke()

    // Ok: fırçayla çizilmiş gibi hafif kavisli, ucu açık. İkonların (128 pt) arasında kalır.
    let start = NSPoint(x: Layout.app.x + 88, y: Layout.app.y + 4)
    let end = NSPoint(x: Layout.applications.x - 92, y: Layout.applications.y - 2)
    let ink = NSColor(srgbRed: 0.74, green: 0.76, blue: 0.79, alpha: 1)
    ink.setStroke()
    let arrow = NSBezierPath()
    arrow.move(to: start)
    arrow.curve(to: end,
                controlPoint1: NSPoint(x: start.x + 40, y: start.y - 34),
                controlPoint2: NSPoint(x: end.x - 46, y: end.y - 30))  // = control2 aşağıda
    arrow.lineWidth = 5
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.stroke()
    // İkinci, ince bir iz: fırça dokusu.
    let trace = arrow.copy() as! NSBezierPath
    trace.transform(using: AffineTransform(translationByX: 0, byY: 2.2))
    trace.lineWidth = 1.6
    ink.withAlphaComponent(0.55).setStroke()
    trace.stroke()
    ink.setStroke()
    // Uç, eğrinin bittiği yöne bakar (son kontrol noktasından uca).
    let control2 = NSPoint(x: end.x - 46, y: end.y - 30)
    let direction = atan2(end.y - control2.y, end.x - control2.x)
    func barb(_ turn: CGFloat) -> NSPoint {
        let angle = direction + .pi + turn
        return NSPoint(x: end.x + 22 * cos(angle), y: end.y + 22 * sin(angle))
    }
    let head = NSBezierPath()
    head.move(to: barb(0.5))
    head.line(to: end)
    head.line(to: barb(-0.5))
    head.lineWidth = 5
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.stroke()

    // Yönerge: iki dilde, kartın altında.
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let caption = NSAttributedString(
        string: "Uygulamalar klasörüne sürükleyin  ·  Drag to Applications",
        attributes: [
            .font: NSFont.systemFont(ofSize: 12.5, weight: .medium),
            .foregroundColor: NSColor(srgbRed: 0.45, green: 0.47, blue: 0.5, alpha: 1),
            .paragraphStyle: paragraph,
        ]
    )
    caption.draw(in: NSRect(x: card.minX, y: card.maxY - 46, width: card.width, height: 20))

    guard let png = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
    try png.write(to: url)
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("Kullanım: swift scripts/render-dmg-background.swift <klasör>\n".utf8))
    exit(64)
}
let folder = URL(fileURLWithPath: arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
try render(scale: 1, to: folder.appendingPathComponent("background.png"))
try render(scale: 2, to: folder.appendingPathComponent("background@2x.png"))
