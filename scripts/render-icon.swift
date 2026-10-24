// KD Download Manager ikonunu çizer: turuncu yuvarlak kare + beyaz indirme oku.
//
//   swift scripts/render-icon.swift app <klasör.iconset>   → macOS uygulama ikonu (iconutil için)
//   swift scripts/render-icon.swift extension <klasör>      → Chrome eklentisi ikonları (16/32/48/128)
//
// macOS ikonlarında şekil, Apple'ın ızgarasına göre kenarlardan boşluk bırakıp gölgeyle çizilir;
// eklenti ikonlarında tüm alanı kaplar.
import AppKit

let accent = NSColor(srgbRed: 1, green: 0x85 / 255, blue: 0, alpha: 1)

/// 1024×1024'lük tasarım alanında çizer; `pixels` boyutunda PNG yazar.
func render(pixels: Int, macStyle: Bool, to url: URL) throws {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(pixels) / 1024
    NSGraphicsContext.current!.cgContext.scaleBy(x: scale, y: scale)

    // Şekil: macOS'ta 824'lük gövde (ızgara), eklentide neredeyse tam alan.
    let body = macStyle ? NSRect(x: 100, y: 100, width: 824, height: 824) : NSRect(x: 32, y: 32, width: 960, height: 960)
    let radius = body.width * 0.2237
    if macStyle {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowOffset = NSSize(width: 0, height: -10)
        shadow.shadowBlurRadius = 24
        shadow.set()
    }
    accent.setFill()
    NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius).fill()
    NSShadow().set()

    // Ok: gövdeye göre ölçeklenmiş; küçük boyutlarda da okunsun diye kalın.
    let unit = body.width / 128
    func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: body.minX + x * unit, y: body.minY + y * unit)
    }
    NSColor.white.setStroke()
    let arrow = NSBezierPath()
    arrow.lineWidth = 12 * unit
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: point(64, 98))
    arrow.line(to: point(64, 44))
    arrow.move(to: point(40, 66))
    arrow.line(to: point(64, 42))
    arrow.line(to: point(88, 66))
    arrow.move(to: point(36, 28))
    arrow.line(to: point(92, 28))
    arrow.stroke()

    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

let arguments = CommandLine.arguments
guard arguments.count == 3, ["app", "extension"].contains(arguments[1]) else {
    FileHandle.standardError.write(Data("kullanım: render-icon.swift app|extension <klasör>\n".utf8))
    exit(1)
}
let folder = URL(fileURLWithPath: arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

if arguments[1] == "app" {
    // iconutil'in beklediği adlar: icon_<nokta>x<nokta>[@2x].png
    for points in [16, 32, 128, 256, 512] {
        try render(pixels: points, macStyle: true, to: folder.appendingPathComponent("icon_\(points)x\(points).png"))
        try render(pixels: points * 2, macStyle: true, to: folder.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
    }
} else {
    for pixels in [16, 32, 48, 128] {
        try render(pixels: pixels, macStyle: false, to: folder.appendingPathComponent("icon\(pixels).png"))
    }
}
