using System.Text.RegularExpressions;

namespace KDDownloadManager;

/// <summary>Short, translated explanations for aria2 and yt-dlp errors (same rules as the macOS app).</summary>
public static partial class ErrorText
{
    public static string Aria2(string? code, string? message, long? remaining)
    {
        message ??= "";
        if (code == "9" || message.Contains("No space left", StringComparison.OrdinalIgnoreCase)
            || message.Contains("not enough disk space", StringComparison.OrdinalIgnoreCase))
            return DiskFull(remaining);
        if (HttpStatus(message) is { } status) return Http(status);
        return code switch
        {
            "2" => L.T("Bağlantı zaman aşımına uğradı"),
            "3" => L.T("Dosya sunucuda bulunamadı (404)"),
            "5" => L.T("Sunucu çok yavaş yanıt verdi"),
            "6" => L.T("Ağ bağlantısı koptu"),
            "8" => L.T("Sunucu kaldığı yerden devam etmeyi desteklemiyor"),
            "13" => L.T("Aynı adla bir dosya zaten var"),
            "15" or "16" or "17" or "18" => L.T("Dosya diske yazılamadı (klasör izni ya da disk sorunu)"),
            "19" => L.T("Sunucu bulunamadı; internet bağlantınızı kontrol edin"),
            "22" => L.T("Sunucu geçersiz bir yanıt verdi"),
            "23" => L.T("Çok fazla yönlendirme"),
            "24" => L.T("Giriş gerekiyor (yetkilendirme başarısız)"),
            "26" or "27" => L.T("Torrent dosyası ya da magnet linki bozuk"),
            "29" => L.T("Sunucu şu an çok yoğun; biraz sonra tekrar deneyin"),
            "32" => L.T("Dosya doğrulanamadı (sağlama toplamı tutmuyor)"),
            _ => message.Length == 0 ? L.T("İndirme başarısız") : message,
        };
    }

    public static string YtDlp(string? message, int exitCode)
    {
        if (string.IsNullOrEmpty(message)) return L.F("Video indirilemedi (kod %lld)", exitCode);
        (string[] needles, string text)[] rules =
        [
            (["No space left", "There is not enough space"], DiskFull(null)),
            (["Unsupported URL"], L.T("Bu sayfada indirilebilir video bulunamadı")),
            (["Private video"], L.T("Video gizli; yalnızca sahibi izleyebilir")),
            (["members-only", "Join this channel"], L.T("Video yalnızca kanal üyelerine açık")),
            (["Premieres in", "live event will begin", "This live event"], L.T("Canlı yayın ya da gösterim henüz başlamadı")),
            (["not available in your country", "geo restrict", "geo-restricted"], L.T("Video bu ülkede kullanılamıyor")),
            (["Video unavailable", "This video is unavailable", "has been removed", "no longer available"], L.T("Video kullanılamıyor ya da kaldırılmış")),
            (["Requested format is not available"], L.T("İstenen kalite bu videoda yok; Otomatik'i deneyin")),
            (["ffmpeg", "Postprocessing", "Conversion failed"], L.T("Video birleştirilemedi (ffmpeg)")),
            (["Unable to download webpage", "Failed to resolve", "getaddrinfo failed", "Name or service not known",
              "Connection refused", "Network is unreachable", "No connection could be made"], L.T("Siteye bağlanılamadı; internet bağlantınızı kontrol edin")),
            (["timed out"], L.T("Bağlantı zaman aşımına uğradı")),
        ];
        foreach (var (needles, text) in rules)
            if (needles.Any(n => message.Contains(n, StringComparison.OrdinalIgnoreCase))) return text;
        if (HttpStatus(message) is { } status) return Http(status);
        var prefix = SitePrefix().Match(message);
        return prefix.Success ? message[prefix.Length..] : message;
    }

    public static string DiskFull(long? remaining) =>
        remaining is > 0 ? L.F("Diskte yer kalmadı · %@ gerekli", ByteFormat.Size(remaining.Value)) : L.T("Diskte yer kalmadı");

    static string Http(int status) => status switch
    {
        401 => L.T("Giriş gerekiyor (401)"),
        403 => L.T("Sunucu erişime izin vermedi (403); bağlantının süresi dolmuş olabilir"),
        404 => L.T("Dosya sunucuda bulunamadı (404)"),
        410 => L.T("Dosya sunucudan kaldırılmış (410)"),
        416 => L.T("Sunucu kaldığı yerden devam etmeyi kabul etmedi (416)"),
        429 => L.T("Sunucu çok fazla istek dedi (429); biraz sonra tekrar deneyin"),
        >= 500 and < 600 => L.F("Sunucu hatası (%lld); biraz sonra tekrar deneyin", status),
        _ => L.F("Sunucu isteği reddetti (%lld)", status),
    };

    public static int? HttpStatus(string message)
    {
        var match = StatusPattern().Match(message);
        return match.Success ? int.Parse(match.Groups[1].Success ? match.Groups[1].Value : match.Groups[2].Value) : null;
    }

    [GeneratedRegex(@"status=(\d{3})|HTTP Error (\d{3})")]
    private static partial Regex StatusPattern();

    [GeneratedRegex(@"^\[[^\]]+\] [^:]+: ")]
    private static partial Regex SitePrefix();
}
