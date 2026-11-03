import Foundation

/// Link ekle'de indirmeden önce bağlantıyı denetler: dosya için sunucuya başlıkları isteyip adı, boyutu
/// ve parçalı indirmeyi destekleyip desteklemediğini; video için yt-dlp'den başlığı ve kaliteleri öğrenir.
enum LinkProbe {
    struct FileInfo: Sendable {
        var name: String?
        var size: Int64?
        /// Sunucu parça (Range) istemeyi destekliyor: parçalı iner, kaldığı yerden devam eder.
        var resumable: Bool
    }

    enum Outcome: Sendable {
        case file(FileInfo)
        case video(VideoFormats)
        /// Video bilgisi alınamadı; indirme sırasında yeniden denenir (örn. YouTube çerez bekliyor).
        case videoUnknown
        /// Link açılamadı; indirmek anlamsız.
        case invalid(String)
        /// Sunucu bir şey söyledi ama indirme yine de denenebilir (403, 5xx).
        case warning(String)
    }

    static let timeout: TimeInterval = 10

    static func check(_ link: String) async -> Outcome {
        switch DownloadSource.detect(link) {
        case .video:
            let cookies = await MainActor.run { CookieVault.shared.cookies(for: link) }
            guard let formats = try? await VideoFormats.fetch(link, cookies: cookies),
                  !formats.options.isEmpty else { return .videoUnknown }
            return .video(formats)
        case .direct:
            return await file(link)
        case .torrent:
            return .file(FileInfo(name: nil, size: nil, resumable: true))
        }
    }

    /// Sadece başlıklar okunur: ilk bayt istenir, gövde beklenmeden bağlantı kapatılır.
    private static func file(_ link: String) async -> Outcome {
        guard let url = URL(string: link), let scheme = url.scheme?.lowercased() else {
            return .invalid("Adres eksik ya da hatalı görünüyor.")
        }
        guard scheme == "http" || scheme == "https" else {
            // FTP vb. aria2 indirebiliyor ama burada denetlenemiyor.
            return .file(FileInfo(name: url.lastPathComponent, size: nil, resumable: false))
        }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        let response: HTTPURLResponse
        do {
            let (bytes, received) = try await URLSession.shared.bytes(for: request)
            bytes.task.cancel()
            guard let http = received as? HTTPURLResponse else { return .warning("Sunucu beklenmedik bir yanıt verdi.") }
            response = http
        } catch let error as URLError {
            switch error.code {
            case .timedOut: return .warning("Sunucu yanıt vermiyor.")
            case .cannotFindHost, .dnsLookupFailed: return .invalid("Sunucu bulunamadı. Adresi kontrol edip tekrar dene.")
            case .notConnectedToInternet: return .warning("İnternet bağlantısı yok.")
            case .unsupportedURL, .badURL: return .invalid("Adres eksik ya da hatalı görünüyor.")
            case .cannotConnectToHost: return .invalid("Sunucuya bağlanılamadı.")
            default: return .warning("Bağlantı denetlenemedi; indirme yine de denenebilir.")
            }
        } catch {
            return .warning("Bağlantı denetlenemedi; indirme yine de denenebilir.")
        }

        switch response.statusCode {
        case 200..<300:
            break
        case 404, 410:
            return .invalid("Sunucuda böyle bir dosya yok (\(response.statusCode)).")
        case 401, 403:
            return .warning("Sunucu erişime izin vermedi (\(response.statusCode)). Giriş gerekiyorsa Chrome'dan indirmeyi dene.")
        case 400..<500:
            return .invalid("Sunucu isteği kabul etmedi (\(response.statusCode)).")
        default:
            return .warning("Sunucu hata verdi (\(response.statusCode)); indirme yine de denenebilir.")
        }

        let headers = response.allHeaderFields
        func header(_ name: String) -> String? {
            headers.first { ($0.key as? String)?.caseInsensitiveCompare(name) == .orderedSame }?.value as? String
        }
        // Parça istendiğinde toplam boyut Content-Range'te: "bytes 0-0/12345678".
        let size = header("Content-Range").flatMap { Int64($0.split(separator: "/").last ?? "") }
            ?? (response.statusCode == 200 ? response.expectedContentLength : nil).flatMap { $0 > 0 ? $0 : nil }
        let resumable = response.statusCode == 206 || header("Accept-Ranges")?.lowercased() == "bytes"
        let name = header("Content-Disposition").flatMap(fileName(fromDisposition:))
            ?? response.url.map { $0.lastPathComponent.removingPercentEncoding ?? $0.lastPathComponent }
        return .file(FileInfo(name: name.flatMap { $0.isEmpty || $0 == "/" ? nil : $0 }, size: size, resumable: resumable))
    }

    /// Chrome'dan devralınacak bir indirme uygulamada da inebilir mi? İnebiliyorsa nil, inemiyorsa nedeni.
    /// Adres tarayıcının çerezi, referrer'ı ve kimliğiyle bir kez (ilk bayt) istenir. Chrome adresi zaten
    /// istediği için bu zararsız: yeniden istenemeyen bir bağlantıyı aria2 de indiremezdi.
    ///
    /// Eklenti bu sırada Chrome'un indirmesini duraklatıp en fazla 15 saniye cevap bekliyor. Yoklama ondan
    /// önce bitmeli: geç gelen bir "kabul" Chrome'unki sürerken uygulamada da indirme başlatırdı. Yavaş
    /// sunucular (uzun yönlendirme zincirleri) bu yüzden Chrome'a bırakılır.
    static func canTakeOver(_ request: DownloadRequest) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask { await probeTakeOver(request) }
            group.addTask {
                try? await Task.sleep(for: .seconds(takeOverDeadline))
                return "sunucu \(Int(takeOverDeadline)) saniyede yanıt vermedi"
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    static let takeOverDeadline: TimeInterval = 8

    private static func probeTakeOver(_ request: DownloadRequest) async -> String? {
        guard let url = URL(string: request.url), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        var probe = URLRequest(url: url, timeoutInterval: 6)
        probe.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        if let cookies = request.cookies { probe.setValue(cookies, forHTTPHeaderField: "Cookie") }
        if let referrer = request.referrer { probe.setValue(referrer, forHTTPHeaderField: "Referer") }
        if let agent = request.userAgent { probe.setValue(agent, forHTTPHeaderField: "User-Agent") }
        probe.httpShouldHandleCookies = false
        do {
            let (bytes, received) = try await URLSession.shared.bytes(for: probe)
            bytes.task.cancel()
            guard let http = received as? HTTPURLResponse else { return "beklenmedik yanıt" }
            guard (200..<300).contains(http.statusCode) else { return "sunucu \(http.statusCode) döndü" }
            // Service worker'ın sunduğu adresler sunucuda sayfanın HTML kabuğunu döndürüyor; Chrome ise
            // gerçek dosyayı (başka bir türde) indiriyordu.
            let type = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            let expected = (request.mime ?? "").lowercased()
            if type.hasPrefix("text/html"), !expected.isEmpty, !expected.hasPrefix("text/html") {
                return "dosya yerine sayfa döndü"
            }
            return nil
        } catch {
            return "adrese ulaşılamadı"
        }
    }

    /// `attachment; filename="Rapor.pdf"` ya da `filename*=UTF-8''Rapor%20Son.pdf`.
    static func fileName(fromDisposition value: String) -> String? {
        for part in value.split(separator: ";").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if part.lowercased().hasPrefix("filename*="), let encoded = part.split(separator: "'").last {
                return String(encoded).removingPercentEncoding
            }
        }
        for part in value.split(separator: ";").map({ $0.trimmingCharacters(in: .whitespaces) }) where part.lowercased().hasPrefix("filename=") {
            return String(part.dropFirst("filename=".count)).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return nil
    }
}
