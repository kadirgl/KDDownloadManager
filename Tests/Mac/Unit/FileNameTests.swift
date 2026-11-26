import Foundation
import Testing
@testable import KDDownloadManager

@Suite("Dosya adları")
@MainActor
struct FileNameTests {
    @Test("Geçersiz karakterler temizlenir")
    func sanitize() {
        #expect(DownloadStore.sanitizedFileName("a/b:c.pdf") == "a-b-c.pdf")
        #expect(DownloadStore.sanitizedFileName("  Rapor.pdf  ") == "Rapor.pdf")
        #expect(DownloadStore.sanitizedFileName("satır\nsonu\t.txt") == "satır-sonu-.txt")
        // Baştaki noktalar dosyayı gizli yapardı.
        #expect(DownloadStore.sanitizedFileName("...gizli.txt") == "gizli.txt")
        #expect(DownloadStore.sanitizedFileName("   ") == "")
    }

    @Test("Uzun ad 200 baytı geçmez, uzantı korunur (Türkçe/emoji çok baytlı)")
    func limit() {
        let long = String(repeating: "ğ", count: 300) + ".mp4"
        let limited = DownloadStore.limitedFileName(long)
        #expect(limited.utf8.count <= 200)
        #expect(limited.hasSuffix(".mp4"))
        #expect(limited.hasPrefix("ğğğ"))

        let emoji = String(repeating: "🎬", count: 100)
        #expect(DownloadStore.limitedFileName(emoji).utf8.count <= 200)

        // Kısa ad dokunulmadan döner.
        #expect(DownloadStore.limitedFileName("kısa.pdf") == "kısa.pdf")
        // Çok uzun "uzantı" uzantı sayılmaz.
        let odd = String(repeating: "a", count: 190) + "." + String(repeating: "b", count: 30)
        #expect(DownloadStore.limitedFileName(odd).utf8.count <= 200)
    }

    @Test("Metinden linkler: her satır bir link, link olmayanlar atlanır")
    func parseLinks() {
        let text = """
        https://a.example/1.zip
          https://a.example/2.zip\u{20}
        not bir link
        magnet:?xt=urn:btih:1

        ftp://x/y
        """
        #expect(DownloadStore.parseLinks(text) == [
            "https://a.example/1.zip", "https://a.example/2.zip", "magnet:?xt=urn:btih:1", "ftp://x/y",
        ])
        #expect(DownloadStore.parseLinks("https://a\r\nhttps://b") == ["https://a", "https://b"])
    }
}

@Suite("Content-Disposition")
@MainActor
struct ContentDispositionTests {
    @Test("Standart biçimler", arguments: [
        ("attachment; filename=\"Rapor.pdf\"", "Rapor.pdf"),
        ("attachment; filename=Rapor.pdf", "Rapor.pdf"),
        ("inline; filename=\"a b.zip\"", "a b.zip"),
        ("attachment; filename*=UTF-8''Y%C4%B1ll%C4%B1k%20Rapor.pdf", "Yıllık Rapor.pdf"),
        // İkisi birden: filename* (UTF-8) öncelikli.
        ("attachment; filename=\"fallback.pdf\"; filename*=UTF-8''ger%C3%A7ek.pdf", "gerçek.pdf"),
        ("ATTACHMENT; FILENAME=\"BUYUK.TXT\"", "BUYUK.TXT"),
    ])
    func standard(header: String, name: String) {
        #expect(LinkProbe.fileName(fromDisposition: header) == name)
    }

    @Test("Broadcom: tür olmadan yalnızca filename= (aria2 bunu okumuyordu)")
    func broadcom() {
        #expect(LinkProbe.fileName(fromDisposition: "filename=VMware-Fusion-26H1u1-24921137_universal.dmg")
                == "VMware-Fusion-26H1u1-24921137_universal.dmg")
        #expect(LinkProbe.fileName(fromDisposition: "filename=\"VMware Fusion.dmg\"") == "VMware Fusion.dmg")
    }

    @Test("Ad yoksa nil")
    func missing() {
        #expect(LinkProbe.fileName(fromDisposition: "attachment") == nil)
        #expect(LinkProbe.fileName(fromDisposition: "inline") == nil)
        #expect(LinkProbe.fileName(fromDisposition: "") == nil)
    }
}

@Suite("Biçimler")
@MainActor
struct FormatTests {
    /// Ondalık ayracı bölgeye bağlı ("12,4" ya da "12.4").
    private func normalized(_ text: String) -> String { text.replacingOccurrences(of: ",", with: ".") }

    @Test("Boyut", arguments: [
        (Int64(0), "0 B"), (512, "512 B"), (1_024, "1.0 KB"), (1_536, "1.5 KB"), (10 * 1_024, "10 KB"),
        (1_048_576, "1.0 MB"), (13_002_342, "12 MB"), (1_073_741_824, "1.0 GB"),
        (5 * 1_099_511_627_776, "5.0 TB"), (-5, "0 B"),
    ] as [(Int64, String)])
    func size(bytes: Int64, text: String) {
        #expect(normalized(ByteFormat.size(bytes)) == text)
    }

    @Test("Hız")
    func speed() {
        #expect(normalized(ByteFormat.speed(1_572_864)) == "1.5 MB/sn")
    }

    @Test("Kalan süre", arguments: [
        (0.0, ""), (-3, ""), (Double.infinity, ""), (Double.nan, ""),
        (12.2, "~13 sn"), (59, "~59 sn"), (60, "~1 dk"), (61, "~2 dk"), (3_540, "~59 dk"), (3_599, "~1 sa"),
        (3_600, "~1 sa"), (7_500, "~2 sa 5 dk"),
    ] as [(Double, String)])
    func remaining(seconds: Double, text: String) {
        #expect(ByteFormat.remaining(seconds) == text)
    }
}

@Suite("Sürüm karşılaştırma")
@MainActor
struct VersionTests {
    @Test("Parça parça sayı olarak", arguments: [
        ("1.5.10", "1.5.9", true), ("1.10.0", "1.9.9", true), ("2.0", "1.99.99", true),
        ("1.9.5", "1.9.5", false), ("1.9.4", "1.9.5", false), ("1.9.5.1", "1.9.5", true),
        ("1.9.5", "1.9.5.0", false), ("2026.10.21.1", "2026.10.21", true), ("2026.9.30", "2026.10.1", false),
        ("1.0", "0", true),
    ] as [(String, String, Bool)])
    func compare(candidate: String, other: String, newer: Bool) {
        #expect(AppUpdater.isNewer(candidate, than: other) == newer)
        #expect(YtDlpUpdater.isNewer(candidate, than: other) == newer)
    }
}
