using System.Net;
using System.Net.Http.Headers;
using System.Net.Sockets;
using KDDownloadManager.Engine;
using KDDownloadManager.Models;

namespace KDDownloadManager;

/// <summary>
/// Checks a link before downloading (macOS: LinkProbe): for files the server's headers (name, size, ranges),
/// for videos yt-dlp's title and qualities. Also decides whether a browser download can be taken over.
/// </summary>
public static class LinkProbe
{
    public sealed record FileInfo(string? Name, long? Size, bool Resumable);

    public abstract record Outcome
    {
        public sealed record File(FileInfo Info) : Outcome;
        public sealed record Video(VideoFormats Formats) : Outcome;
        public sealed record VideoUnknown : Outcome;
        public sealed record Invalid(string Reason) : Outcome;
        public sealed record Warning(string Message) : Outcome;
    }

    public static readonly TimeSpan Timeout = TimeSpan.FromSeconds(10);

    static HttpClient NewClient(TimeSpan timeout) =>
        new(new SocketsHttpHandler { UseCookies = false, AllowAutoRedirect = true, MaxAutomaticRedirections = 20, AutomaticDecompression = DecompressionMethods.None })
        { Timeout = timeout };

    static readonly HttpClient Client = NewClient(Timeout);
    static readonly HttpClient TakeOverClient = NewClient(TimeSpan.FromSeconds(6));

    public static async Task<Outcome> Check(string link, CancellationToken token = default)
    {
        switch (DownloadSources.Detect(link))
        {
            case DownloadSource.Video:
                try
                {
                    var formats = await VideoFormats.Fetch(link, CookieVault.Shared.CookiesFor(link));
                    return formats.Options.Count == 0 ? new Outcome.VideoUnknown() : new Outcome.Video(formats);
                }
                catch { return new Outcome.VideoUnknown(); }
            case DownloadSource.Torrent:
                return new Outcome.File(new FileInfo(null, null, true));
            default:
                return await ProbeFile(link, token);
        }
    }

    static async Task<Outcome> ProbeFile(string link, CancellationToken token)
    {
        if (!Uri.TryCreate(link.Trim(), UriKind.Absolute, out var uri)) return new Outcome.Invalid(L.T("Adres eksik ya da hatalı görünüyor."));
        if (uri.Scheme is not ("http" or "https"))
            return new Outcome.File(new FileInfo(Path.GetFileName(uri.AbsolutePath), null, false));
        var request = new HttpRequestMessage(HttpMethod.Get, uri);
        request.Headers.Range = new RangeHeaderValue(0, 0);
        HttpResponseMessage response;
        try
        {
            response = await Client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
        }
        catch (TaskCanceledException) when (!token.IsCancellationRequested) { return new Outcome.Warning(L.T("Sunucu yanıt vermiyor.")); }
        catch (HttpRequestException error) when (error.InnerException is SocketException socket)
        {
            return socket.SocketErrorCode switch
            {
                SocketError.HostNotFound or SocketError.NoData or SocketError.TryAgain => new Outcome.Invalid(L.T("Sunucu bulunamadı. Adresi kontrol edip tekrar dene.")),
                SocketError.NetworkUnreachable or SocketError.NetworkDown => new Outcome.Warning(L.T("İnternet bağlantısı yok.")),
                SocketError.ConnectionRefused => new Outcome.Invalid(L.T("Sunucuya bağlanılamadı.")),
                _ => new Outcome.Warning(L.T("Bağlantı denetlenemedi; indirme yine de denenebilir.")),
            };
        }
        catch (OperationCanceledException) { throw; }
        catch { return new Outcome.Warning(L.T("Bağlantı denetlenemedi; indirme yine de denenebilir.")); }

        using (response)
        {
            var code = (int)response.StatusCode;
            switch (code)
            {
                case >= 200 and < 300: break;
                case 404 or 410: return new Outcome.Invalid(L.F("Sunucuda böyle bir dosya yok (%lld).", code));
                case 401 or 403: return new Outcome.Warning(L.F("Sunucu erişime izin vermedi (%lld). Giriş gerekiyorsa Chrome'dan indirmeyi dene.", code));
                case >= 400 and < 500: return new Outcome.Invalid(L.F("Sunucu isteği kabul etmedi (%lld).", code));
                default: return new Outcome.Warning(L.F("Sunucu hata verdi (%lld); indirme yine de denenebilir.", code));
            }
            var size = response.Content.Headers.ContentRange?.Length
                ?? (code == 200 && response.Content.Headers.ContentLength is > 0 ? response.Content.Headers.ContentLength : null);
            var resumable = code == 206 || response.Headers.AcceptRanges.Contains("bytes");
            var name = DispositionName(response)
                ?? (response.RequestMessage?.RequestUri is { } final ? Uri.UnescapeDataString(Path.GetFileName(final.AbsolutePath)) : null);
            return new Outcome.File(new FileInfo(string.IsNullOrEmpty(name) ? null : name, size, resumable));
        }
    }

    public abstract record TakeOver
    {
        public sealed record Accept(string? Name) : TakeOver;
        public sealed record Refuse(string Reason) : TakeOver;
    }

    public static readonly TimeSpan TakeOverDeadline = TimeSpan.FromSeconds(8);

    /// <summary>
    /// Can the app download what the browser started? The address is requested once (first byte) with the
    /// browser's cookie, referrer and user agent. The extension waits at most 15 s, so slow servers stay in the browser.
    /// </summary>
    public static async Task<TakeOver> CanTakeOver(DownloadRequest request)
    {
        var probe = ProbeTakeOver(request);
        var winner = await Task.WhenAny(probe, Task.Delay(TakeOverDeadline));
        return winner == probe ? await probe : new TakeOver.Refuse($"sunucu {TakeOverDeadline.TotalSeconds} saniyede yanıt vermedi");
    }

    static async Task<TakeOver> ProbeTakeOver(DownloadRequest request)
    {
        if (!Uri.TryCreate(request.Url, UriKind.Absolute, out var uri) || uri.Scheme is not ("http" or "https"))
            return new TakeOver.Accept(null);
        var message = new HttpRequestMessage(HttpMethod.Get, uri);
        message.Headers.Range = new RangeHeaderValue(0, 0);
        if (request.Cookies != null) message.Headers.TryAddWithoutValidation("Cookie", request.Cookies);
        if (request.Referrer != null) message.Headers.TryAddWithoutValidation("Referer", request.Referrer);
        if (request.UserAgent != null) message.Headers.TryAddWithoutValidation("User-Agent", request.UserAgent);
        try
        {
            using var response = await TakeOverClient.SendAsync(message, HttpCompletionOption.ResponseHeadersRead);
            var code = (int)response.StatusCode;
            if (code is < 200 or >= 300) return new TakeOver.Refuse($"sunucu {code} döndü");
            var type = response.Content.Headers.ContentType?.MediaType?.ToLowerInvariant() ?? "";
            var expected = (request.Mime ?? "").ToLowerInvariant();
            if (type.StartsWith("text/html") && expected.Length > 0 && !expected.StartsWith("text/html"))
                return new TakeOver.Refuse("dosya yerine sayfa döndü");
            // The name comes from Content-Disposition, as in the browser; aria2 only reads that header when it is
            // fully standard (Broadcom sends "filename=x.dmg" without "attachment;", and the file became index.html).
            var name = DispositionName(response);
            return new TakeOver.Accept(string.IsNullOrEmpty(name) ? null : name);
        }
        catch { return new TakeOver.Refuse("adrese ulaşılamadı"); }
    }

    static string? DispositionName(HttpResponseMessage response) =>
        response.Content.Headers.TryGetValues("Content-Disposition", out var values) ? FileNameFromDisposition(string.Join(", ", values)) : null;

    /// <summary><c>attachment; filename="Rapor.pdf"</c> or <c>filename*=UTF-8''Rapor%20Son.pdf</c>.</summary>
    public static string? FileNameFromDisposition(string value)
    {
        var parts = value.Split(';').Select(p => p.Trim()).ToList();
        foreach (var part in parts)
        {
            if (part.StartsWith("filename*=", StringComparison.OrdinalIgnoreCase))
            {
                var encoded = part.Split('\'').Last();
                try { return Uri.UnescapeDataString(encoded); } catch { }
            }
        }
        foreach (var part in parts)
            if (part.StartsWith("filename=", StringComparison.OrdinalIgnoreCase))
                return part["filename=".Length..].Trim('"');
        return null;
    }
}
