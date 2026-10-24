import Foundation

/// Köprünün ihtiyacı kadar basit bir HTTP/1.1 istek ayrıştırıcısı.
struct HTTPRequest {
    let method: String
    let path: String
    /// Başlık adları küçük harfe çevrilmiş.
    let headers: [String: String]
    let body: Data

    enum ParseResult {
        case complete(HTTPRequest)
        case incomplete
        case invalid
    }

    static let maxHeaderSize = 16 * 1024
    static let maxBodySize = 1024 * 1024

    /// Şimdiye kadar gelen veriden bir istek çıkarmaya çalışır; gövde eksikse `.incomplete` döner.
    static func parse(_ data: Data) -> ParseResult {
        guard let headerEnd = data.firstRange(of: Data("\r\n\r\n".utf8)) else {
            return data.count > maxHeaderSize ? .invalid : .incomplete
        }
        guard let head = String(data: data[data.startIndex..<headerEnd.lowerBound], encoding: .utf8) else {
            return .invalid
        }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count == 3 else { return .invalid }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard let length = Int(headers["content-length"] ?? "0"), (0...maxBodySize).contains(length) else {
            return .invalid
        }
        let body = data[headerEnd.upperBound...]
        guard body.count >= length else { return .incomplete }

        return .complete(HTTPRequest(
            method: String(requestLine[0]),
            path: String(requestLine[1]),
            headers: headers,
            body: Data(body.prefix(length))
        ))
    }
}
