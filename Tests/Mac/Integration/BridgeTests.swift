import Foundation
import Testing
@testable import KDDownloadManager

/// Eklentinin konuştuğu yerel kapı (127.0.0.1). Kurulu uygulamayla çakışmasın diye test portunda
/// (TestEnvironment.bridgePort) çalışır. Tek port olduğu için testler sırayla.
@Suite("Tarayıcı köprüsü", .serialized)
@MainActor
struct BridgeTests {
    /// Köprüye gelenler.
    @MainActor
    final class Recorder {
        var added: [[DownloadRequest]] = []
        var hellos: [String] = []
    }

    static let recorder = Recorder()
    static let bridge: ExtensionBridge = {
        TestEnvironment.prepare()
        let bridge = ExtensionBridge(onAdd: { recorder.added.append($0) }, onHello: { recorder.hellos.append($0) })
        bridge.start()
        return bridge
    }()

    static let storeOrigin = "chrome-extension://\(BrowserExtension.storeExtensionID)"

    init() async throws {
        TestEnvironment.prepare()
        #expect(ExtensionBridge.port == TestEnvironment.bridgePort)
        _ = Self.bridge
        Self.recorder.added.removeAll()
        Self.recorder.hellos.removeAll()
        // Dinlemeye başlaması için kısa bir an.
        try await Task.sleep(for: .milliseconds(50))
    }

    private func call(_ path: String, method: String = "POST", origin: String? = storeOrigin,
                      json: String? = nil) async throws -> (status: Int, body: JSONValue?, headers: [AnyHashable: Any]) {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(TestEnvironment.bridgePort)\(path)")!, timeoutInterval: 20)
        request.httpMethod = method
        if let origin { request.setValue(origin, forHTTPHeaderField: "Origin") }
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(json.utf8)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as! HTTPURLResponse
        return (http.statusCode, try? JSONDecoder().decode(JSONValue.self, from: data), http.allHeaderFields)
    }

    @Test("Bizim eklentimiz dışındaki kaynaklar reddedilir (web sayfaları indirme başlatamaz)")
    func rejectsForeignOrigins() async throws {
        for origin in [nil, "https://evil.example", "chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "null"] as [String?] {
            let reply = try await call("/add", origin: origin, json: #"{"links":[{"url":"https://a/b.zip"}]}"#)
            #expect(reply.status == 403, "\(origin ?? "Origin yok")")
        }
        #expect(Self.recorder.added.isEmpty)
    }

    @Test("Mağaza ve paketlenmemiş eklenti kimlikleri kabul edilir; CORS başlığı kaynağı yansıtır")
    func acceptsBothExtensionIDs() async throws {
        for id in [BrowserExtension.storeExtensionID, BrowserExtension.unpackedExtensionID] {
            let reply = try await call("/ping", origin: "chrome-extension://\(id)")
            #expect(reply.status == 200)
            #expect(reply.body?["app"]?.stringValue == "KD Download Manager")
            #expect(reply.headers["Access-Control-Allow-Origin"] as? String == "chrome-extension://\(id)")
        }
        #expect(try await call("/add", method: "OPTIONS").status == 204)
    }

    @Test("/add: linkler listeye iletilir")
    func add() async throws {
        let reply = try await call("/add", json: """
        {"links":[{"url":"https://a.example/1.zip","filename":"1.zip"},{"url":"https://www.youtube.com/watch?v=x","quality":"720"}]}
        """)
        #expect(reply.status == 200)
        #expect(reply.body?["added"]?.int64Value == 2)
        #expect(Self.recorder.added.first?.map(\.url) == ["https://a.example/1.zip", "https://www.youtube.com/watch?v=x"])
        #expect(Self.recorder.added.first?.last?.quality == .p720)
    }

    @Test("/add: boş, 100'den fazla, bozuk ya da link olmayan liste")
    func addRejects() async throws {
        #expect(try await call("/add", json: #"{"links":[]}"#).status == 400)
        let many = (0...100).map { #"{"url":"https://a/\#($0)"}"# }.joined(separator: ",")
        #expect(try await call("/add", json: #"{"links":[\#(many)]}"#).status == 400)
        #expect(try await call("/add", json: "bozuk").status == 400)
        #expect(try await call("/add", json: #"{"links":[{"url":"javascript:alert(1)"}]}"#).status == 422)
        #expect(Self.recorder.added.isEmpty)
    }

    @Test("Chrome indirmesi devralınırken sunucunun verdiği ad isteğe yazılır")
    func takeOverSetsName() async throws {
        let server = try await TestHTTPServer()
        server.route("/", .file(.pattern(size: 10), headers: ["Content-Disposition": "filename=Fusion.dmg"]))
        let reply = try await call("/add", json: """
        {"links":[{"url":"\(server.url("/?file=x"))","fromBrowserDownload":true,"mime":"application/octet-stream"}]}
        """)
        #expect(reply.status == 200)
        #expect(Self.recorder.added.first?.first?.filename == "Fusion.dmg")
    }

    @Test("Yeniden istenemeyen Chrome indirmesi tarayıcıda kalır (422)")
    func takeOverRefused() async throws {
        let server = try await TestHTTPServer()
        server.route("/tek", .status(403))
        let reply = try await call("/add", json: #"{"links":[{"url":"\#(server.url("/tek"))","fromBrowserDownload":true}]}"#)
        #expect(reply.status == 422)
        #expect(Self.recorder.added.isEmpty)
    }

    @Test("/hello tarayıcı adını bildirir; /cookies yalnızca video siteleri için")
    func helloAndCookies() async throws {
        let hello = try await call("/hello", json: #"{"browser":"Google Chrome","version":"1.9.5"}"#)
        #expect(hello.status == 200)
        #expect(hello.body?["wantsCookies"]?.arrayValue != nil)
        #expect(Self.recorder.hellos == ["Google Chrome"])

        let cookie = #"{"domain":".youtube.com","path":"/","name":"n","value":"v","secure":true}"#
        #expect(try await call("/cookies", json: #"{"site":"youtube.com","cookieJar":[\#(cookie)]}"#).status == 200)
        #expect(try await call("/cookies", json: #"{"site":"bank.example","cookieJar":[\#(cookie)]}"#).status == 400)
    }

    @Test("Bilinmeyen yol 404, /formats'ta http olmayan adres 422")
    func otherPaths() async throws {
        #expect(try await call("/yok").status == 404)
        #expect(try await call("/formats", json: #"{"url":"file:///etc/passwd"}"#).status == 422)
    }
}
