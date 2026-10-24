import Foundation

struct Aria2Error: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// aria2c'nin JSON-RPC arayüzüyle (HTTP) konuşan ince istemci.
/// https://aria2.github.io/manual/en/html/aria2c.html#rpc-interface
final class Aria2Client: Sendable {
    private let endpoint: URL
    private let token: JSONValue
    private let session: URLSession

    init(port: Int, secret: String) {
        endpoint = URL(string: "http://127.0.0.1:\(port)/jsonrpc")!
        token = .string("token:" + secret)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        session = URLSession(configuration: config)
    }

    /// Tek bir RPC çağrısı; gizli anahtar parametrelerin başına otomatik eklenir.
    @discardableResult
    func call(_ method: String, _ params: [JSONValue] = []) async throws -> JSONValue {
        let response = try await send(method, [token] + params)
        if let error = response["error"] {
            throw Aria2Error(message: error["message"]?.stringValue ?? "aria2 hatası")
        }
        return response["result"] ?? .null
    }

    /// Birden çok çağrıyı tek istekte yapar (`system.multicall`).
    /// Dönen dizi çağrılarla aynı sırada; her eleman sonuç ya da o çağrının hatası.
    func multicall(_ calls: [(method: String, params: [JSONValue])]) async throws -> [Result<JSONValue, Aria2Error>] {
        let payload = JSONValue.array(calls.map { call in
            ["methodName": .string(call.method), "params": .array([token] + call.params)]
        })
        let response = try await send("system.multicall", [payload])
        if let error = response["error"] {
            throw Aria2Error(message: error["message"]?.stringValue ?? "aria2 hatası")
        }
        return (response["result"]?.arrayValue ?? []).map { entry in
            // Başarılı çağrı tek elemanlı dizi, başarısız çağrı {faultCode, faultString} döner.
            if let value = entry[0] {
                .success(value)
            } else {
                .failure(Aria2Error(message: entry["faultString"]?.stringValue ?? "aria2 hatası"))
            }
        }
    }

    private func send(_ method: String, _ params: [JSONValue]) async throws -> JSONValue {
        let body: JSONValue = [
            "jsonrpc": "2.0",
            "id": .string(UUID().uuidString),
            "method": .string(method),
            "params": .array(params)
        ]
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        // aria2 hatalarda da gövdede JSON döndürüyor; HTTP durum koduna bakmıyoruz.
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }
}
