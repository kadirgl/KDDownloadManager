import Foundation
import Network

/// Testler için 127.0.0.1'de çalışan küçük HTTP sunucusu. Gerçek sitelerin davranışı (Broadcom'un
/// türsüz Content-Disposition'ı, parçalı indirme, 404, HTML hata sayfası…) internete çıkmadan taklit edilir.
/// `Range` istekleri 206 ile yanıtlanır; aria2 dosyayı birkaç bağlantıyla parça parça indirebilir.
final class TestHTTPServer: @unchecked Sendable {
    struct Request: Sendable {
        let method: String
        let path: String
        /// Adlar küçük harf.
        let headers: [String: String]
        let body: Data
    }

    struct Response: Sendable {
        var status: Int = 200
        var headers: [String: String] = [:]
        var body: Data = Data()
        /// Gövdeyi parça parça ve bu kadar bekleyerek gönder (yavaş sunucu; duraklatma testleri için).
        var chunkDelay: Double = 0
        /// false: Range isteklerine de tüm dosyayla 200 dön.
        var acceptsRanges = true

        static func file(_ data: Data, headers: [String: String] = [:], chunkDelay: Double = 0) -> Response {
            Response(status: 200, headers: headers, body: data, chunkDelay: chunkDelay)
        }

        static func status(_ code: Int, _ text: String = "") -> Response {
            Response(status: code, headers: ["Content-Type": "text/plain"], body: Data(text.utf8), acceptsRanges: false)
        }
    }

    typealias Handler = @Sendable (Request) -> Response

    private let listener: NWListener
    private let queue = DispatchQueue(label: "TestHTTPServer")
    private let lock = NSLock()
    private var routes: [String: Handler] = [:]
    private var log: [Request] = []
    let port: UInt16

    init() async throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        let ready = AsyncStream<UInt16?>.makeStream()
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: ready.continuation.yield(listener.port?.rawValue)
            case .failed, .cancelled: ready.continuation.yield(nil)
            default: break
            }
        }
        var port: UInt16?
        listener.newConnectionHandler = { _ in }
        listener.start(queue: queue)
        for await value in ready.stream { port = value; break }
        guard let port else { throw URLError(.cannotConnectToHost) }
        self.port = port
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
    }

    deinit { listener.cancel() }

    func stop() { listener.cancel() }

    func url(_ path: String) -> String { "http://127.0.0.1:\(port)\(path)" }

    /// `path` sorgu dizesiyle birlikte eşleşir; bulunamazsa sorgusuz hali denenir.
    func route(_ path: String, _ handler: @escaping Handler) {
        lock.withLock { routes[path] = handler }
    }

    func route(_ path: String, _ response: Response) {
        route(path) { _ in response }
    }

    /// Gelen istekler (sırayla).
    var requests: [Request] { lock.withLock { log } }

    func requests(to path: String) -> [Request] {
        requests.filter { $0.path == path || $0.path.hasPrefix(path + "?") }
    }

    // MARK: - Bağlantılar

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = Self.parse(buffer) {
                self.respond(to: request, on: connection)
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                self.receive(connection, buffer: buffer)
            }
        }
    }

    private static func parse(_ data: Data) -> Request? {
        guard let end = data.firstRange(of: Data("\r\n\r\n".utf8)),
              let head = String(data: data[data.startIndex..<end.lowerBound], encoding: .utf8) else { return nil }
        var lines = head.components(separatedBy: "\r\n")
        let first = lines.removeFirst().split(separator: " ")
        guard first.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let body = data[end.upperBound...]
        guard body.count >= length else { return nil }
        return Request(method: String(first[0]), path: String(first[1]), headers: headers, body: Data(body.prefix(length)))
    }

    private func respond(to request: Request, on connection: NWConnection) {
        let handler: Handler? = lock.withLock {
            log.append(request)
            let bare = String(request.path.split(separator: "?", maxSplits: 1).first ?? "")
            return routes[request.path] ?? routes[bare]
        }
        var response = handler?(request) ?? .status(404, "yok")
        var status = response.status
        var body = response.body

        // Range: bytes=a-b | bytes=a-
        if response.acceptsRanges, status == 200 {
            response.headers["Accept-Ranges"] = "bytes"
            if let range = request.headers["range"], let parsed = Self.byteRange(range, size: body.count) {
                status = 206
                response.headers["Content-Range"] = "bytes \(parsed.lowerBound)-\(parsed.upperBound)/\(body.count)"
                body = body.subdata(in: parsed.lowerBound..<(parsed.upperBound + 1))
            }
        }
        response.headers["Content-Length"] = String(body.count)
        response.headers["Connection"] = "close"
        var head = "HTTP/1.1 \(status) \(Self.reason(status))\r\n"
        for (name, value) in response.headers { head += "\(name): \(value)\r\n" }
        head += "\r\n"

        let isHead = request.method == "HEAD"
        if response.chunkDelay > 0, !isHead {
            connection.send(content: Data(head.utf8), completion: .contentProcessed { _ in })
            sendSlowly(body, chunk: 16 * 1024, delay: response.chunkDelay, on: connection)
        } else {
            connection.send(content: Data(head.utf8) + (isHead ? Data() : body), completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func sendSlowly(_ body: Data, chunk: Int, delay: Double, on connection: NWConnection) {
        guard !body.isEmpty, connection.state == .ready else { connection.cancel(); return }
        let part = body.prefix(chunk)
        connection.send(content: part, completion: .contentProcessed { [weak self] error in
            guard error == nil else { connection.cancel(); return }
            self?.queue.asyncAfter(deadline: .now() + delay) {
                self?.sendSlowly(body.dropFirst(part.count), chunk: chunk, delay: delay, on: connection)
            }
        })
    }

    private static func byteRange(_ header: String, size: Int) -> ClosedRange<Int>? {
        guard size > 0, header.hasPrefix("bytes=") else { return nil }
        let spec = header.dropFirst("bytes=".count).split(separator: ",").first ?? ""
        let parts = spec.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        if parts[0].isEmpty, let suffix = Int(parts[1]) { return max(size - suffix, 0)...(size - 1) }
        guard let start = Int(parts[0]), start < size else { return nil }
        let end = Int(parts[1]).map { min($0, size - 1) } ?? (size - 1)
        return start <= end ? start...end : nil
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: "OK"
        case 206: "Partial Content"
        case 302: "Found"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 500: "Internal Server Error"
        default: "Status"
        }
    }
}

extension Data {
    /// Tekrarlanmayan, kolay doğrulanan deneme içeriği.
    static func pattern(size: Int, seed: UInt8 = 7) -> Data {
        var data = Data(count: size)
        data.withUnsafeMutableBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            var value = UInt32(seed)
            for index in 0..<size {
                value = value &* 1_103_515_245 &+ 12_345
                bytes[index] = UInt8(truncatingIfNeeded: value >> 16)
            }
        }
        return data
    }
}
