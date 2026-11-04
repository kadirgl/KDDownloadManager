import Foundation

/// Bir video sayfasının sunduğu çözünürlükleri ve tahmini boyutlarını yt-dlp'den öğrenir
/// (Chrome eklentisindeki kalite listesi için).
struct VideoFormats: Sendable {
    struct Option: Sendable {
        let quality: VideoQuality
        /// Görüntü + ses tahmini boyutu; bilinmiyorsa nil.
        let size: Int64?
    }

    let title: String
    /// Süre (sn); bilinmiyorsa nil.
    var duration: Double?
    let options: [Option]

    struct FetchError: LocalizedError {
        let message: String
        var timedOut = false
        var errorDescription: String? { message }
    }

    /// Kalite listesi en fazla bu kadar beklenir; sonra yt-dlp durdurulur (eklenti 30 sn bekliyor).
    static let deadline: TimeInterval = 20

    /// yt-dlp'nin yeni kopyası (uygulama kurulunca ya da güncellenince) ilk çalıştırmada macOS yüzlerce
    /// kitaplığını denetlediği için ~5 sn geç açılıyor. Bu gecikme kullanıcının ilk kalite listesine
    /// yansımasın diye açılışta bir kez boşta çalıştırılır.
    static func warmUp() {
        guard let binary = Executables.find("yt-dlp") else { return }
        Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = binary
            process.arguments = ["--version"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }
    }

    /// `cookies` verilirse yt-dlp'ye geçici bir çerez dosyasıyla verilir (YouTube robot doğrulaması için).
    static func fetch(_ url: String, cookies: [BrowserCookie]? = nil) async throws -> VideoFormats {
        guard let binary = Executables.find("yt-dlp") else {
            throw FetchError(message: "yt-dlp bulunamadı (brew install yt-dlp)")
        }
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("kd-formats-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: work) }
        var cookieArguments: [String] = []
        if let cookies, !cookies.isEmpty {
            let file = work.appendingPathComponent("cookies.txt")
            try CookieVault.writeNetscapeFile(cookies, to: file)
            cookieArguments = ["--cookies", file.path]
        }
        let data = try await Task.detached { () throws -> Data in
            let process = Process()
            process.executableURL = binary
            // Birden çok video gömülü sayfalarda (haber siteleri) yalnızca ilki çözülür; hepsi tek tek
            // açılınca liste çok uzun sürebiliyordu.
            process.arguments = ["-J", "--no-playlist", "--playlist-items", "1", "--no-warnings",
                                 "--socket-timeout", "10", "--extractor-retries", "1"]
                + cookieArguments + Executables.javaScriptRuntimeArguments + ["--", url]
            process.environment = Executables.environment
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            try process.run()
            let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + deadline, execute: timer)
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            timer.cancel()
            guard process.terminationStatus == 0 else {
                if process.terminationReason == .uncaughtSignal {
                    throw FetchError(message: "Video bilgisi zamanında alınamadı", timedOut: true)
                }
                throw FetchError(message: "Video bilgisi alınamadı")
            }
            return data
        }.value
        var info = try JSONDecoder().decode(JSONValue.self, from: data)
        // Sayfada birden çok video: ilkinin biçimleri.
        if info["formats"] == nil, info["url"] == nil, let first = info["entries"]?.arrayValue?.first {
            info = first
        }
        return parse(info)
    }

    /// yt-dlp'nin biçim listesini standart çözünürlüklere ayırır. yt-dlp gibi "çözünürlük" olarak
    /// kısa kenarı alır; dikey videolarda (Shorts) da doğru sınıf çıksın diye.
    static func parse(_ info: JSONValue) -> VideoFormats {
        let formats = info["formats"]?.arrayValue ?? []
        let videos = formats.filter { ($0["vcodec"]?.stringValue ?? "none") != "none" && resolution(of: $0) != nil }
        let audios = formats.filter {
            ($0["vcodec"]?.stringValue ?? "") == "none" && ($0["acodec"]?.stringValue ?? "none") != "none"
        }
        // Birleştirmede kullanılacak ses: mümkünse AAC (mp4a), içinden en yüksek bitrate.
        let audio = best(audios.filter { $0["acodec"]?.stringValue?.hasPrefix("mp4a") == true }) ?? best(audios)
        let audioSize = audio.flatMap(size)

        // Her çözünürlükte aynı tür biçim seçilsin ki boyutlar yukarıdan aşağı azalsın: önce H.264, onun içinde
        // sadece görüntü olanlar. YouTube'un 360p'deki sesli tek dosyası (18) ayrıca ses eklenince 480p'yi
        // geçiyordu.
        func option(_ quality: VideoQuality, from candidates: [JSONValue]) -> Option? {
            guard !candidates.isEmpty else { return nil }
            let h264 = candidates.filter { $0["vcodec"]?.stringValue?.hasPrefix("avc1") == true }
            let pool = h264.isEmpty ? candidates : h264
            let videoOnly = pool.filter { ($0["acodec"]?.stringValue ?? "none") == "none" }
            guard let video = best(videoOnly.isEmpty ? pool : videoOnly) else { return nil }
            let hasAudio = (video["acodec"]?.stringValue ?? "none") != "none"
            let total = size(of: video).map { $0 + (hasAudio ? 0 : audioSize ?? 0) }
            return Option(quality: quality, size: total)
        }

        var options: [Option] = []
        // Otomatik: H.264'ün en iyisi; yoksa en iyi görüntü.
        let h264 = videos.filter { $0["vcodec"]?.stringValue?.hasPrefix("avc1") == true }
        let autoPool = h264.isEmpty ? videos : h264
        let topResolution = autoPool.compactMap(resolution).max()
        if let top = topResolution, let auto = option(.auto, from: autoPool.filter { resolution(of: $0) == top }) {
            options.append(auto)
        }
        for quality in VideoQuality.allCases {
            guard let height = quality.maxHeight else { continue }
            if let found = option(quality, from: videos.filter { bucket(resolution(of: $0)) == height }) {
                options.append(found)
            }
        }
        // Bazı sitelerde (doğrudan dosya, bilgisi eksik akış) biçimlerde çözünürlük yok; yine de indirilebilir.
        if options.isEmpty, !formats.isEmpty || info["url"] != nil {
            options.append(Option(quality: .auto, size: best(formats).flatMap(size)))
        }
        if !audios.isEmpty || videos.isEmpty {
            options.append(Option(quality: .audio, size: audioSize))
        }
        return VideoFormats(
            title: info["title"]?.stringValue ?? "Video",
            duration: info["duration"]?.doubleValue,
            options: options
        )
    }

    private static func resolution(of format: JSONValue) -> Int? {
        let sides = [format["width"]?.int64Value, format["height"]?.int64Value].compactMap { $0 }
        return sides.min().map(Int.init)
    }

    /// 1920×1080 → 1080, 3840×2160 → 2160 gibi; 360'tan küçükler listelenmez.
    private static func bucket(_ resolution: Int?) -> Int? {
        guard let resolution else { return nil }
        return [2160, 1440, 1080, 720, 480, 360].first { resolution >= Int(Double($0) * 0.9) }
    }

    /// En yüksek bitrate'li biçim. Boyutu bilinmeyenler (HLS/m3u8 akışları) yt-dlp'nin de tercih
    /// etmediği biçimler olduğundan, boyutu bilinen varsa onlar arasından seçilir.
    private static func best(_ formats: [JSONValue]) -> JSONValue? {
        let sized = formats.filter { size(of: $0) != nil }
        return (sized.isEmpty ? formats : sized).max { ($0["tbr"]?.int64Value ?? 0) < ($1["tbr"]?.int64Value ?? 0) }
    }

    private static func size(of format: JSONValue) -> Int64? {
        format["filesize"]?.int64Value ?? format["filesize_approx"]?.int64Value
    }
}
