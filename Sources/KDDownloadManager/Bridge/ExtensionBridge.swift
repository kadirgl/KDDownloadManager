import Foundation
import Network

/// Chrome eklentisinin linkleri gönderdiği yerel HTTP kapısı.
///
/// - Sadece 127.0.0.1'i dinler; ağdaki başka bilgisayarlar erişemez.
/// - Sadece bizim eklentimizden gelen istekleri kabul eder (`Origin: chrome-extension://<kimlik>`).
///   Web sayfaları Origin başlığını değiştiremediği için bir site uygulamaya indirme başlatamaz.
///
/// Uç noktalar:
/// - `POST /ping` → uygulama çalışıyor mu (eklentinin durum göstergesi için). Chrome, izinli
///   adreslere giden GET isteklerinde Origin göndermediği için durum sorgusu da POST ile yapılır.
/// - `POST /hello` → `{"browser": "Google Chrome", "version": "1.1.0"}`; eklenti bunu dakikada bir
///   gönderir, Ayarlar'daki "bağlı" göstergesi buradan beslenir
/// - `POST /add` → `{"links": [DownloadRequest, ...]}`
/// - `POST /formats` → `{"url": "...", "cookieJar": [...]}`; videonun sunduğu kaliteler ve tahmini boyutları
/// - `POST /cookies` → `{"site": "youtube.com", "cookieJar": [...]}`; `/hello` cevabındaki
///   `wantsCookies` listesine karşılık eklentinin gönderdiği çerezler
@MainActor
final class ExtensionBridge {
    nonisolated static let port: UInt16 = {
        #if DEBUG
        // Denemelerde kurulu uygulamanın portuyla çakışmamak için.
        if let value = ProcessInfo.processInfo.environment["KD_BRIDGE_PORT"].flatMap(UInt16.init) {
            return value
        }
        #endif
        return 47615
    }()

    /// Eklentinin manifest'indeki "key" alanından türeyen sabit kimlik.
    /// Eklenti Chrome Web Mağazası'na konursa mağazanın verdiği kimlik de buraya eklenmeli.
    static let allowedOrigins: Set<String> = ["chrome-extension://necbfaijhfnnoikbppjdjcpfjekefdbk"]

    private static let maxLinksPerRequest = 100

    private let onAdd: ([DownloadRequest]) -> Void
    private let onHello: (String) -> Void
    private var listener: NWListener?

    /// yt-dlp'nin kalite listesi birkaç saniye sürüyor; açılır pencere tekrar açıldığında beklemesin.
    private var formatsCache: [String: (date: Date, formats: VideoFormats)] = [:]
    private static let formatsCacheLifetime: TimeInterval = 600

    init(onAdd: @escaping ([DownloadRequest]) -> Void, onHello: @escaping (String) -> Void) {
        self.onAdd = onAdd
        self.onHello = onHello
    }

    func start() {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: Self.port)!)
        parameters.allowLocalEndpointReuse = true
        do {
            let listener = try NWListener(using: parameters)
            listener.stateUpdateHandler = { state in
                if case .failed(let error) = state {
                    // Büyük ihtimalle uygulamanın başka bir kopyası portu kullanıyor.
                    print("Chrome köprüsü başlatılamadı (port \(Self.port)): \(error)")
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated {
                    self?.accept(connection)
                }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            print("Chrome köprüsü başlatılamadı: \(error)")
        }
    }

    // MARK: - Bağlantılar

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self else {
                    connection.cancel()
                    return
                }
                var buffer = buffer
                if let data { buffer.append(data) }

                switch HTTPRequest.parse(buffer) {
                case .complete(let request):
                    self.respond(to: request, on: connection)
                case .incomplete where !isComplete && error == nil:
                    self.receive(on: connection, buffer: buffer)
                case .incomplete, .invalid:
                    Self.send(status: 400, ["error": "Geçersiz istek"], origin: nil, on: connection)
                }
            }
        }
    }

    private func respond(to request: HTTPRequest, on connection: NWConnection) {
        guard let origin = request.headers["origin"], Self.allowedOrigins.contains(origin) else {
            Self.send(status: 403, ["error": "Bu kaynaktan istek kabul edilmiyor"], origin: nil, on: connection)
            return
        }

        switch (request.method, request.path) {
        case ("OPTIONS", _):
            Self.send(status: 204, nil, origin: origin, on: connection)

        case ("GET", "/ping"), ("POST", "/ping"):
            // Eklenti, uygulamada seçilen vurgu rengini kullanıyor.
            Self.send(status: 200, ["app": "KD Download Manager", "accent": .string(AccentChoice.current.hex)],
                      origin: origin, on: connection)

        case ("POST", "/hello"):
            let hello = try? JSONDecoder().decode(JSONValue.self, from: request.body)
            let browser = hello?["browser"]?.stringValue.map { String($0.prefix(60)) } ?? "Tarayıcı"
            onHello(browser)
            // Çerezi gereken video siteleri; eklenti hemen /cookies ile gönderir.
            let wanted = JSONValue.array(CookieVault.shared.wantedSites.map { .string($0) })
            Self.send(status: 200, ["app": "KD Download Manager", "wantsCookies": wanted], origin: origin, on: connection)

        case ("POST", "/cookies"):
            struct Payload: Decodable {
                var site: String
                var cookieJar: [BrowserCookie]
            }
            guard let payload = try? JSONDecoder().decode(Payload.self, from: request.body),
                  DownloadSource.videoHostList.contains(payload.site) else {
                Self.send(status: 400, ["error": "Geçersiz çerez listesi"], origin: origin, on: connection)
                return
            }
            CookieVault.shared.store(payload.cookieJar, for: payload.site)
            Self.send(status: 200, ["stored": .number(Double(payload.cookieJar.count))], origin: origin, on: connection)

        case ("POST", "/formats"):
            struct Payload: Decodable {
                var url: String
                var cookieJar: [BrowserCookie]?
            }
            // Herhangi bir sayfa: yt-dlp video bulamazsa 502 döner, eklenti "video bulunamadı" der.
            guard let payload = try? JSONDecoder().decode(Payload.self, from: request.body),
                  payload.url.lowercased().hasPrefix("http") else {
                Self.send(status: 422, ["error": "Geçersiz adres"], origin: origin, on: connection)
                return
            }
            if let jar = payload.cookieJar, let site = CookieVault.site(of: payload.url) {
                CookieVault.shared.store(jar, for: site)
            }
            sendFormats(for: payload.url, origin: origin, on: connection)

        case ("POST", "/add"):
            struct Payload: Decodable {
                var links: [DownloadRequest]
            }
            guard let payload = try? JSONDecoder().decode(Payload.self, from: request.body),
                  (1...Self.maxLinksPerRequest).contains(payload.links.count) else {
                Self.send(status: 400, ["error": "Geçersiz link listesi"], origin: origin, on: connection)
                return
            }
            let valid = payload.links.filter { DownloadSource.looksLikeLink($0.url) }
            guard !valid.isEmpty else {
                Self.send(status: 422, ["error": "Desteklenen bir link yok"], origin: origin, on: connection)
                return
            }
            onAdd(valid)
            Self.send(status: 200, ["added": .number(Double(valid.count))], origin: origin, on: connection)

        default:
            Self.send(status: 404, ["error": "Bulunamadı"], origin: origin, on: connection)
        }
    }

    private func sendFormats(for url: String, origin: String, on connection: NWConnection) {
        if let cached = formatsCache[url], Date().timeIntervalSince(cached.date) < Self.formatsCacheLifetime {
            Self.send(status: 200, Self.json(cached.formats), origin: origin, on: connection)
            return
        }
        Task {
            do {
                let formats = try await VideoFormats.fetch(url, cookies: CookieVault.shared.cookies(for: url))
                // Süresi geçenleri at; önbellek sınırsız büyümesin.
                formatsCache = formatsCache.filter { Date().timeIntervalSince($0.value.date) < Self.formatsCacheLifetime }
                formatsCache[url] = (Date(), formats)
                Self.send(status: 200, Self.json(formats), origin: origin, on: connection)
            } catch {
                Self.send(status: 502, ["error": .string(error.localizedDescription)], origin: origin, on: connection)
            }
        }
    }

    private static func json(_ formats: VideoFormats) -> JSONValue {
        [
            "title": .string(formats.title),
            "duration": formats.duration.map { .number($0) } ?? .null,
            "options": .array(formats.options.map { option in
                [
                    "quality": .string(option.quality.rawValue),
                    "title": .string(option.quality.title),
                    "size": option.size.map { .number(Double($0)) } ?? .null
                ]
            })
        ]
    }

    private static func send(status: Int, _ json: JSONValue?, origin: String?, on connection: NWConnection) {
        let body = json.flatMap { try? JSONEncoder().encode($0) } ?? Data()
        let reason = [200: "OK", 204: "No Content", 400: "Bad Request", 403: "Forbidden",
                      404: "Not Found", 422: "Unprocessable Content", 502: "Bad Gateway"][status] ?? "OK"
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
            + "Content-Type: application/json; charset=utf-8\r\n"
            + "Content-Length: \(body.count)\r\n"
            + "Connection: close\r\n"
        if let origin {
            head += "Access-Control-Allow-Origin: \(origin)\r\n"
                + "Access-Control-Allow-Methods: GET, POST\r\n"
                + "Access-Control-Allow-Headers: Content-Type\r\n"
        }
        head += "\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
