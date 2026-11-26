import Foundation
import Testing
@testable import KDDownloadManager

@Suite("Köprü: HTTP ayrıştırma")
@MainActor
struct HTTPRequestTests {
    private func parse(_ text: String) -> HTTPRequest.ParseResult { HTTPRequest.parse(Data(text.utf8)) }

    @Test("Tam istek: başlıklar küçük harfe çevrilir, gövde Content-Length kadar alınır")
    func complete() throws {
        let result = parse("POST /add HTTP/1.1\r\nOrigin: chrome-extension://x\r\nContent-Length: 5\r\n\r\nhelloEXTRA")
        guard case .complete(let request) = result else { Issue.record("tamamlanmadı: \(result)"); return }
        #expect(request.method == "POST")
        #expect(request.path == "/add")
        #expect(request.headers["origin"] == "chrome-extension://x")
        #expect(request.body == Data("hello".utf8))
    }

    @Test("Başlık ya da gövde eksikse bekler")
    func incomplete() {
        guard case .incomplete = parse("POST /add HTTP/1.1\r\nContent-Length: 5\r\n") else { Issue.record("başlık"); return }
        guard case .incomplete = parse("POST /add HTTP/1.1\r\nContent-Length: 5\r\n\r\nhel") else { Issue.record("gövde"); return }
    }

    @Test("Bozuk istekler reddedilir")
    func invalid() {
        guard case .invalid = parse("GARBAGE\r\n\r\n") else { Issue.record("istek satırı"); return }
        guard case .invalid = parse("POST /add HTTP/1.1\r\nContent-Length: -1\r\n\r\n") else { Issue.record("negatif"); return }
        guard case .invalid = parse("POST /add HTTP/1.1\r\nContent-Length: 99999999\r\n\r\n") else { Issue.record("büyük gövde"); return }
        guard case .invalid = HTTPRequest.parse(Data(repeating: 65, count: HTTPRequest.maxHeaderSize + 1)) else {
            Issue.record("bitmeyen başlık"); return
        }
    }

    @Test("Gövdesiz GET")
    func noBody() {
        guard case .complete(let request) = parse("GET /ping HTTP/1.1\r\nHost: x\r\n\r\n") else { Issue.record("GET"); return }
        #expect(request.body.isEmpty)
    }
}

@Suite("Eklentiden gelen istek")
@MainActor
struct DownloadRequestTests {
    private func decode(_ json: String) throws -> DownloadRequest {
        try JSONDecoder().decode(DownloadRequest.self, from: Data(json.utf8))
    }

    @Test("Tüm alanlar")
    func full() throws {
        let request = try decode("""
        {"url":"https://a/b.pdf","filename":"b.pdf","referrer":"https://a/","userAgent":"UA","cookies":"k=v",
         "quality":"720","video":true,"saveAs":"Başlık","fromBrowserDownload":true,"mime":"application/pdf",
         "cookieJar":[{"domain":".a","path":"/","name":"n","value":"v","secure":true}]}
        """)
        #expect(request.url == "https://a/b.pdf")
        #expect(request.filename == "b.pdf")
        #expect(request.quality == .p720)
        #expect(request.video == true)
        #expect(request.saveAs == "Başlık")
        #expect(request.fromBrowserDownload == true)
        #expect(request.mime == "application/pdf")
        #expect(request.cookieJar?.first?.name == "n")
    }

    @Test("Yalnızca adres")
    func minimal() throws {
        let request = try decode(#"{"url":"https://a/b"}"#)
        #expect(request.filename == nil && request.quality == nil && request.video == nil)
    }

    @Test("Eklentinin daha yeni sürümünden tanınmayan değerler isteği bozmaz")
    func tolerant() throws {
        let request = try decode(#"{"url":"https://a/b","quality":"8k","video":"evet","cookieJar":"bozuk","unknown":1}"#)
        #expect(request.quality == nil)
        #expect(request.video == nil)
        #expect(request.cookieJar == nil)
    }

    @Test("Adres yoksa reddedilir")
    func missingURL() {
        #expect(throws: (any Error).self) { try decode(#"{"filename":"a"}"#) }
    }
}

@Suite("JSON değeri")
@MainActor
struct JSONValueTests {
    @Test("Çözme, erişim ve geri yazma")
    func roundTrip() throws {
        let text = #"{"a":[1,"2",true,null],"b":{"c":"1048576"},"d":2.5}"#
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
        #expect(value["a"]?[0]?.int64Value == 1)
        #expect(value["a"]?[1]?.int64Value == 2)
        #expect(value["a"]?[2] == .bool(true))
        #expect(value["a"]?[3] == .null)
        #expect(value["a"]?[9] == nil)
        #expect(value["b"]?["c"]?.int64Value == 1_048_576)
        #expect(value["d"]?.doubleValue == 2.5)
        #expect(value["yok"] == nil)
        let again = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
        #expect(again == value)
    }

    @Test("Literal'lerden kurma")
    func literals() {
        let value: JSONValue = ["x": ["a", "b"]]
        #expect(value["x"]?.arrayValue?.count == 2)
        #expect(value["x"]?[1]?.stringValue == "b")
    }
}

@Suite("Hata metinleri")
@MainActor
struct ErrorTextTests {
    @Test("aria2 kodları", arguments: [
        ("3", "Dosya sunucuda bulunamadı (404)"), ("2", "Bağlantı zaman aşımına uğradı"),
        ("19", "Sunucu bulunamadı; internet bağlantınızı kontrol edin"), ("24", "Giriş gerekiyor (yetkilendirme başarısız)"),
        ("13", "Aynı adla bir dosya zaten var"), ("16", "Dosya diske yazılamadı (klasör izni ya da disk sorunu)"),
    ])
    func aria2Codes(code: String, text: String) {
        #expect(ErrorText.aria2(code: code, message: "x", remaining: nil) == text)
    }

    @Test("aria2: HTTP durumu metinden okunur, disk dolu önce gelir")
    func aria2Messages() {
        #expect(ErrorText.aria2(code: "22", message: "Response status is not successful. status=403", remaining: nil)
                .contains("403"))
        #expect(ErrorText.aria2(code: "22", message: "status=503", remaining: nil).hasPrefix("Sunucu hatası (503)"))
        #expect(ErrorText.aria2(code: "9", message: nil, remaining: nil) == "Diskte yer kalmadı")
        #expect(ErrorText.aria2(code: "1", message: "No space left on device", remaining: 2_048)
                .hasPrefix("Diskte yer kalmadı · "))
        #expect(ErrorText.aria2(code: "999", message: "bilinmeyen", remaining: nil) == "bilinmeyen")
        #expect(ErrorText.aria2(code: nil, message: nil, remaining: nil) == "İndirme başarısız")
    }

    @Test("yt-dlp hataları", arguments: [
        ("ERROR: [youtube] x: Private video. Sign in", "Video gizli; yalnızca sahibi izleyebilir"),
        ("ERROR: Unsupported URL: https://a", "Bu sayfada indirilebilir video bulunamadı"),
        ("ERROR: [youtube] x: Video unavailable", "Video kullanılamıyor ya da kaldırılmış"),
        ("ERROR: unable to download video data: HTTP Error 403: Forbidden",
         "Sunucu erişime izin vermedi (403); bağlantının süresi dolmuş olabilir"),
        ("ERROR: Postprocessing: Conversion failed!", "Video birleştirilemedi (ffmpeg)"),
        ("ERROR: Requested format is not available", "İstenen kalite bu videoda yok; Otomatik'i deneyin"),
    ])
    func ytDlp(message: String, text: String) {
        #expect(ErrorText.ytDlp(message, exitCode: 1) == text)
    }

    @Test("yt-dlp: tanınmayan hatada site öneki atılır")
    func ytDlpPrefix() {
        #expect(ErrorText.ytDlp("[generic] abc: garip bir sorun", exitCode: 1) == "garip bir sorun")
        #expect(ErrorText.ytDlp(nil, exitCode: 2) == "Video indirilemedi (kod 2)")
    }
}

@Suite("Hız sınırı paylaşımı")
@MainActor
struct RoutingShareTests {
    @Test("Eşit bölünür; kendi sınırı düşük olan sınırı kadar alır, artan diğerlerine kalır")
    func shares() {
        #expect(RoutingEngine.shares(of: 900, caps: [nil, nil, nil]) == [300, 300, 300])
        #expect(RoutingEngine.shares(of: 900, caps: [100, nil, nil]) == [100, 400, 400])
        #expect(RoutingEngine.shares(of: 900, caps: [100, 200, nil]) == [100, 200, 600])
        #expect(RoutingEngine.shares(of: 900, caps: [1_000, 1_000]) == [450, 450])
        #expect(RoutingEngine.shares(of: 900, caps: []) == [])
    }

    @Test("Toplam bütçe aşılmaz", arguments: [[nil, 50, 5_000, nil] as [Int64?], [1, 1, 1], [nil]])
    func neverExceeds(caps: [Int64?]) {
        let result = RoutingEngine.shares(of: 10_000, caps: caps)
        #expect(result.reduce(0, +) <= 10_000)
        for (share, cap) in zip(result, caps) { if let cap { #expect(share <= cap) } }
    }
}

@Suite("yt-dlp biçim seçimi")
@MainActor
struct YtDlpArgumentTests {
    let ffmpeg = URL(fileURLWithPath: "/opt/ffmpeg")

    @Test("ffmpeg varken: H.264/AAC tercih edilir ve MP4'te birleşir")
    func withFFmpeg() {
        let auto = YtDlpEngine.formatArguments(for: .auto, ffmpeg: ffmpeg)
        #expect(auto.starts(with: ["--ffmpeg-location", "/opt/ffmpeg"]))
        #expect(auto.contains("bv*+ba/b"))
        #expect(auto.contains("mp4"))
        let p720 = YtDlpEngine.formatArguments(for: .p720, ffmpeg: ffmpeg)
        #expect(p720.contains { $0.hasPrefix("res:720") })
        let audio = YtDlpEngine.formatArguments(for: .audio, ffmpeg: ffmpeg)
        #expect(audio.contains("-x") && audio.contains("mp3"))
    }

    @Test("ffmpeg yokken: birleştirme gerektirmeyen tek dosya")
    func withoutFFmpeg() {
        #expect(YtDlpEngine.formatArguments(for: .auto, ffmpeg: nil) == ["-f", "b"])
        #expect(YtDlpEngine.formatArguments(for: .audio, ffmpeg: nil) == ["-f", "ba[ext=m4a]/ba/b"])
        #expect(YtDlpEngine.formatArguments(for: .p1080, ffmpeg: nil) == ["-f", "b", "-S", "res:1080"])
        for quality in VideoQuality.allCases {
            #expect(!YtDlpEngine.formatArguments(for: quality, ffmpeg: nil).contains("-x"))
        }
    }
}

@Suite("Video kaliteleri")
@MainActor
struct VideoFormatsTests {
    private func format(_ id: String, vcodec: String, acodec: String = "none", width: Int? = nil, height: Int? = nil,
                        size: Int64? = nil, tbr: Int = 0) -> JSONValue {
        var object: [String: JSONValue] = ["format_id": .string(id), "vcodec": .string(vcodec), "acodec": .string(acodec),
                                           "tbr": .number(Double(tbr))]
        if let width { object["width"] = .number(Double(width)) }
        if let height { object["height"] = .number(Double(height)) }
        if let size { object["filesize"] = .number(Double(size)) }
        return .object(object)
    }

    @Test("YouTube benzeri liste: çözünürlükler, ses eklenmiş boyutlar, otomatik = en iyi H.264")
    func youtubeLike() {
        let info: JSONValue = .object([
            "title": "Deneme", "duration": .number(212),
            "formats": .array([
                format("140", vcodec: "none", acodec: "mp4a.40.2", size: 3_000_000, tbr: 128),
                format("251", vcodec: "none", acodec: "opus", size: 3_500_000, tbr: 160),
                format("18", vcodec: "avc1.42001E", acodec: "mp4a.40.2", width: 640, height: 360, size: 9_000_000, tbr: 500),
                format("134", vcodec: "avc1.4d401e", width: 640, height: 360, size: 5_000_000, tbr: 300),
                format("136", vcodec: "avc1.4d401f", width: 1280, height: 720, size: 20_000_000, tbr: 1_200),
                format("137", vcodec: "avc1.640028", width: 1920, height: 1080, size: 40_000_000, tbr: 2_500),
                format("248", vcodec: "vp9", width: 1920, height: 1080, size: 30_000_000, tbr: 2_000),
                format("313", vcodec: "vp9", width: 3840, height: 2160, size: 200_000_000, tbr: 15_000),
            ]),
        ])
        let formats = VideoFormats.parse(info)
        #expect(formats.title == "Deneme")
        #expect(formats.duration == 212)
        let qualities = formats.options.map(\.quality)
        #expect(qualities == [.auto, .p2160, .p1080, .p720, .p360, .audio])

        let size = Dictionary(formats.options.map { ($0.quality, $0.size) }, uniquingKeysWith: { a, _ in a })
        // Otomatik: H.264'ün en iyisi (1080p) + AAC sesi.
        #expect(size[.auto] == 43_000_000)
        #expect(size[.p1080] == 43_000_000)
        #expect(size[.p720] == 23_000_000)
        // 360p'de sesli tek dosya (18) değil, sadece görüntü (134) + ses: boyutlar yukarıdan aşağı azalır.
        #expect(size[.p360] == 8_000_000)
        #expect(size[.audio] == 3_000_000)
    }

    @Test("Dikey video (Shorts): kısa kenar çözünürlük sayılır; ayrı ses yoksa 'sadece ses' sunulmaz")
    func vertical() {
        let info: JSONValue = .object(["title": "Dikey", "formats": .array([
            format("a", vcodec: "avc1", width: 1080, height: 1920, size: 10, tbr: 1),
        ])])
        #expect(VideoFormats.parse(info).options.map(\.quality) == [.auto, .p1080])
    }

    @Test("Çözünürlük bilgisi olmayan akış yine de indirilebilir")
    func unknownResolution() {
        let info: JSONValue = .object(["title": "Akış", "url": "https://x/a.m3u8", "formats": .array([
            format("hls", vcodec: "avc1", acodec: "mp4a"),
        ])])
        let options = VideoFormats.parse(info).options
        #expect(options.first?.quality == .auto)
    }

    @Test("Başlıksız bilgi")
    func untitled() {
        #expect(VideoFormats.parse(.object([:])).title == "Video")
    }
}
