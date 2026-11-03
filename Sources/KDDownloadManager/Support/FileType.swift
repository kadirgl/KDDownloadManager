import Foundation

/// Uzantısız inen dosyanın gerçek türü, ilk baytlarından (dosya imzası). Sunucu adı uzantısız verdiğinde
/// (örn. "things-to-do-in-istanbul" adlı bir WebP) dosya doğru uzantı ve kategoriyle kaydedilsin diye.
enum FileType {
    static func sniffExtension(of file: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 64), data.count >= 4 else { return nil }
        let bytes = [UInt8](data)
        func starts(_ prefix: [UInt8], at offset: Int = 0) -> Bool {
            bytes.count >= offset + prefix.count && Array(bytes[offset..<offset + prefix.count]) == prefix
        }
        func ascii(_ text: String, at offset: Int = 0) -> Bool { starts(Array(text.utf8), at: offset) }

        if starts([0xFF, 0xD8, 0xFF]) { return "jpg" }
        if starts([0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if ascii("GIF8") { return "gif" }
        if ascii("RIFF"), ascii("WEBP", at: 8) { return "webp" }
        if ascii("RIFF"), ascii("WAVE", at: 8) { return "wav" }
        if ascii("RIFF"), ascii("AVI ", at: 8) { return "avi" }
        if ascii("ftyp", at: 4), bytes.count >= 12 {
            let brand = String(decoding: bytes[8..<12], as: UTF8.self)
            switch brand {
            case "avif", "avis": return "avif"
            case "heic", "heix", "mif1", "msf1": return "heic"
            case "qt  ": return "mov"
            case "M4A ", "M4B ": return "m4a"
            default: return "mp4"
            }
        }
        if ascii("%PDF") { return "pdf" }
        if starts([0x50, 0x4B, 0x03, 0x04]) { return "zip" }
        if ascii("Rar!") { return "rar" }
        if starts([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]) { return "7z" }
        if starts([0x1F, 0x8B]) { return "gz" }
        if starts([0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]) { return "xz" }
        if ascii("BZh") { return "bz2" }
        if ascii("ID3") || starts([0xFF, 0xFB]) || starts([0xFF, 0xF3]) || starts([0xFF, 0xF2]) { return "mp3" }
        if ascii("fLaC") { return "flac" }
        if ascii("OggS") { return "ogg" }
        if starts([0x1A, 0x45, 0xDF, 0xA3]) {
            return String(decoding: bytes, as: UTF8.self).contains("webm") ? "webm" : "mkv"
        }
        if ascii("BM") { return "bmp" }
        if starts([0x49, 0x49, 0x2A, 0x00]) || starts([0x4D, 0x4D, 0x00, 0x2A]) { return "tiff" }
        let text = String(decoding: bytes, as: UTF8.self).lowercased()
        if text.hasPrefix("<svg") || (text.hasPrefix("<?xml") && text.contains("<svg")) { return "svg" }
        return nil
    }
}
