import Foundation

/// Tasarımdaki "24 MB/S", "12 GB" biçimi.
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
        size(bytesPerSecond) + "/S"
    }
}
