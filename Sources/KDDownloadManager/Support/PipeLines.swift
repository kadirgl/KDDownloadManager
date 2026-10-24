import Foundation

extension Pipe {
    /// Borudan gelen veriyi geldiği anda satırlara böler; süreç kapanınca biter.
    /// (`FileHandle.bytes.lines` borularda veriyi süreç kapanana kadar teslim etmiyor.)
    var lines: AsyncStream<String> {
        AsyncStream { continuation in
            let buffer = LineBuffer()
            fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    buffer.flush().forEach { continuation.yield($0) }
                    continuation.finish()
                } else {
                    buffer.append(data).forEach { continuation.yield($0) }
                }
            }
        }
    }
}

/// Yarım kalan satırı bir sonraki parçaya saklar. `readabilityHandler` sıralı çağrıldığı için
/// aynı anda tek bir iş parçacığından erişiliyor.
private final class LineBuffer: @unchecked Sendable {
    private var pending = Data()

    func append(_ data: Data) -> [String] {
        pending.append(data)
        var lines: [String] = []
        while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
            lines.append(String(decoding: pending[pending.startIndex..<newline], as: UTF8.self))
            pending.removeSubrange(pending.startIndex...newline)
        }
        return lines
    }

    func flush() -> [String] {
        defer { pending = Data() }
        return pending.isEmpty ? [] : [String(decoding: pending, as: UTF8.self)]
    }
}
