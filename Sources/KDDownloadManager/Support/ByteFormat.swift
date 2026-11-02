import Foundation

/// Tasarımdaki "12,4 MB/sn", "12 GB" biçimi.
enum ByteFormat {
    private static let units = ["B", "KB", "MB", "GB", "TB"]
    private static let locale = Locale(identifier: "tr_TR")

    static func size(_ bytes: Int64) -> String {
        var value = Double(max(bytes, 0))
        var unit = 0
        while value >= 1024, unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        let digits = (unit == 0 || value >= 10) ? 0 : 1
        let number = value.formatted(
            .number.precision(.fractionLength(digits)).grouping(.never).locale(locale)
        )
        return "\(number) \(units[unit])"
    }

    static func speed(_ bytesPerSecond: Int64) -> String {
        size(bytesPerSecond) + "/sn"
    }

    /// Kalan süre: "~13 sn", "~6 dk", "~2 sa 5 dk".
    static func remaining(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "" }
        let total = Int(seconds.rounded(.up))
        if total < 60 { return "~\(total) sn" }
        let minutes = (total + 59) / 60
        if minutes < 60 { return "~\(minutes) dk" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "~\(hours) sa" : "~\(hours) sa \(rest) dk"
    }
}
