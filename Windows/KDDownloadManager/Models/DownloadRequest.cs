using System.Text.Json;
using System.Text.Json.Serialization;

namespace KDDownloadManager.Models;

/// <summary>A cookie as the browser extension sends it (chrome.cookies fields).</summary>
public sealed record BrowserCookie
{
    [JsonPropertyName("domain")] public string Domain { get; init; } = "";
    [JsonPropertyName("path")] public string Path { get; init; } = "/";
    [JsonPropertyName("name")] public string Name { get; init; } = "";
    [JsonPropertyName("value")] public string Value { get; init; } = "";
    [JsonPropertyName("secure")] public bool Secure { get; init; }
    [JsonPropertyName("httpOnly")] public bool? HttpOnly { get; init; }
    [JsonPropertyName("hostOnly")] public bool? HostOnly { get; init; }
    [JsonPropertyName("expirationDate")] public double? ExpirationDate { get; init; }
}

/// <summary>
/// A download request from the panel or the browser extension (same JSON as the macOS app's DownloadRequest).
/// Fields the extension may add later are ignored; an unknown quality counts as automatic.
/// </summary>
public sealed class DownloadRequest
{
    public string Url { get; set; } = "";
    public string? Filename { get; set; }
    public string? Referrer { get; set; }
    public string? UserAgent { get; set; }
    public string? Cookies { get; set; }
    public VideoQuality? Quality { get; set; }
    public List<BrowserCookie>? CookieJar { get; set; }
    public bool? Video { get; set; }
    public string? SaveAs { get; set; }
    public bool? FromBrowserDownload { get; set; }
    public string? Mime { get; set; }

    public DownloadRequest() { }
    public DownloadRequest(string url, string? filename = null, VideoQuality? quality = null)
    {
        Url = url;
        Filename = filename;
        Quality = quality;
    }

    /// <summary>Lenient parse of one entry of /add's "links" array; null if there is no url.</summary>
    public static DownloadRequest? FromJson(JsonElement e)
    {
        if (e.ValueKind != JsonValueKind.Object || !e.TryGetProperty("url", out var url) || url.ValueKind != JsonValueKind.String)
            return null;
        string? Str(string key) => e.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;
        bool? Bool(string key) => e.TryGetProperty(key, out var v) && v.ValueKind is JsonValueKind.True or JsonValueKind.False ? v.GetBoolean() : null;
        var request = new DownloadRequest
        {
            Url = url.GetString()!,
            Filename = Str("filename"),
            Referrer = Str("referrer"),
            UserAgent = Str("userAgent"),
            Cookies = Str("cookies"),
            Quality = VideoQualities.Parse(Str("quality")),
            Video = Bool("video"),
            SaveAs = Str("saveAs"),
            FromBrowserDownload = Bool("fromBrowserDownload"),
            Mime = Str("mime"),
        };
        if (e.TryGetProperty("cookieJar", out var jar) && jar.ValueKind == JsonValueKind.Array)
        {
            try { request.CookieJar = jar.Deserialize<List<BrowserCookie>>(); } catch (JsonException) { }
        }
        return request;
    }
}
