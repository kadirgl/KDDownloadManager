import Foundation

/// aria2c sürecini RPC modunda başlatır ve hazır olunca istemciyi verir.
@MainActor
final class Aria2Daemon {
    private var process: Process?

    var isRunning: Bool { process?.isRunning ?? false }

    func start(maxConcurrent: Int, globalLimit: Int64?) async throws -> Aria2Client {
        guard let binary = Executables.find("aria2c") else {
            throw Aria2Error(message: "aria2c bulunamadı (brew install aria2)")
        }
        let port = try Self.freePort()
        let secret = UUID().uuidString

        let process = Process()
        process.executableURL = binary
        process.arguments = [
            "--enable-rpc",
            "--rpc-listen-all=false",
            "--rpc-listen-port=\(port)",
            "--rpc-secret=\(secret)",
            // Uygulama kapanınca (çökse bile) aria2c de kapansın.
            "--stop-with-process=\(ProcessInfo.processInfo.processIdentifier)",
            "--continue=true",
            // 16 bağlantı bazı sunucularda IP'nin geçici olarak engellenmesine yol açıyor.
            "--max-connection-per-server=8",
            "--split=8",
            "--min-split-size=1M",
            "--file-allocation=none",
            "--max-concurrent-downloads=\(maxConcurrent)",
            "--max-overall-download-limit=\(globalLimit ?? 0)",
            // Torrent bitince paylaşmaya devam etmesin; aksi halde hiç "tamamlandı" olmaz.
            "--seed-time=0",
            "--console-log-level=warn"
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        self.process = process

        let client = Aria2Client(port: port, secret: secret)
        for _ in 0..<50 {
            if (try? await client.call("aria2.getVersion")) != nil {
                return client
            }
            guard process.isRunning else { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        stop()
        throw Aria2Error(message: "aria2c başlatılamadı")
    }

    func stop() {
        process?.terminate()
        process = nil
    }

    /// İşletim sisteminden boş bir yerel port ister.
    private static func freePort() throws -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Aria2Error(message: "Boş port bulunamadı") }
        defer { close(fd) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)

        let bound = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, length) == 0 && getsockname(fd, $0, &length) == 0
            }
        }
        guard bound else { throw Aria2Error(message: "Boş port bulunamadı") }
        return Int(UInt16(bigEndian: address.sin_port))
    }
}
