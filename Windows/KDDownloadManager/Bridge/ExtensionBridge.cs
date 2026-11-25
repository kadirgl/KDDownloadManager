using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using KDDownloadManager.Engine;
using KDDownloadManager.Models;

namespace KDDownloadManager.Bridge;

/// <summary>
/// The local HTTP door the browser extension talks to (macOS: ExtensionBridge), with the same port,
/// endpoints and checks, so the same extension works with both apps:
/// - listens on 127.0.0.1 only;
/// - accepts requests only from our extension (<c>Origin: chrome-extension://&lt;id&gt;</c>); web pages cannot set Origin;
/// - POST /ping, /hello, /add, /formats, /cookies.
/// Connections are accepted on the thread pool; requests are handled on the UI thread (through <see cref="ui"/>).
/// </summary>
public sealed class ExtensionBridge
{
    public static int Port =>
#if DEBUG
        int.TryParse(Environment.GetEnvironmentVariable("KD_BRIDGE_PORT"), out var test) ? test :
#endif
        47615;

    /// <summary>The fixed ID that follows from the "key" in the extension's manifest.</summary>
    /// <summary>The Chrome Web Store copy's ID and the bundled unpacked copy's (manifest "key"); both in BrowserExtension.</summary>
    public static readonly HashSet<string> AllowedOrigins = BrowserExtension.ExtensionIds.Select(id => "chrome-extension://" + id).ToHashSet();

    const int MaxLinksPerRequest = 100;
    const int MaxHeaderSize = 16 * 1024;
    const int MaxBodySize = 1024 * 1024;

    readonly Action<List<DownloadRequest>> onAdd;
    readonly Action<string> onHello;
    readonly SynchronizationContext ui;
    TcpListener? listener;

    readonly Dictionary<string, (DateTimeOffset date, VideoFormats formats)> formatsCache = new();
    readonly Dictionary<string, (DateTimeOffset date, string message)> formatsFailures = new();
    readonly Dictionary<string, Task<(VideoFormats? formats, Exception? error)>> formatsLookups = new();
    static readonly TimeSpan FormatsCacheLifetime = TimeSpan.FromMinutes(10);
    static readonly TimeSpan FailureCacheLifetime = TimeSpan.FromMinutes(1);

    public bool IsListening { get; private set; }

    public ExtensionBridge(Action<List<DownloadRequest>> onAdd, Action<string> onHello)
    {
        this.onAdd = onAdd;
        this.onHello = onHello;
        ui = SynchronizationContext.Current ?? throw new InvalidOperationException("Start the bridge on the UI thread");
    }

    public void Start()
    {
        try
        {
            listener = new TcpListener(IPAddress.Loopback, Port);
            listener.Server.ExclusiveAddressUse = true;
            listener.Start();
            IsListening = true;
            _ = Task.Run(AcceptLoop);
        }
        catch (SocketException error)
        {
            // Most likely another copy of the app holds the port.
            System.Diagnostics.Debug.WriteLine($"Bridge could not start on {Port}: {error.Message}");
        }
    }

    public void Stop()
    {
        try { listener?.Stop(); } catch { }
        IsListening = false;
    }

    async Task AcceptLoop()
    {
        while (listener != null)
        {
            TcpClient client;
            try { client = await listener.AcceptTcpClientAsync(); }
            catch { return; }
            _ = Task.Run(() => Serve(client));
        }
    }

    sealed record Request(string Method, string Path, Dictionary<string, string> Headers, byte[] Body);

    async Task Serve(TcpClient client)
    {
        using (client)
        {
            var stream = client.GetStream();
            stream.ReadTimeout = 10_000;
            Request? request;
            try { request = await Read(stream); }
            catch { request = null; }
            (int status, JsonNode? body, string? origin) reply;
            if (request == null) reply = (400, Error(L.T("Geçersiz istek")), null);
            else
            {
                var done = new TaskCompletionSource<(int, JsonNode?, string?)>();
                ui.Post(async _ =>
                {
                    try { done.SetResult(await Respond(request)); }
                    catch (Exception e) { done.SetResult((500, Error(e.Message), request.Headers.GetValueOrDefault("origin"))); }
                }, null);
                reply = await done.Task;
            }
            try { await Write(stream, reply.status, reply.body, reply.origin); } catch { }
        }
    }

    static async Task<Request?> Read(NetworkStream stream)
    {
        var buffer = new List<byte>();
        var chunk = new byte[16 * 1024];
        var headerEnd = -1;
        while (headerEnd < 0)
        {
            var read = await stream.ReadAsync(chunk);
            if (read == 0) return null;
            buffer.AddRange(chunk.AsSpan(0, read));
            headerEnd = IndexOf(buffer, "\r\n\r\n"u8);
            if (headerEnd < 0 && buffer.Count > MaxHeaderSize) return null;
        }
        var head = Encoding.UTF8.GetString(buffer.GetRange(0, headerEnd).ToArray());
        var lines = head.Split("\r\n");
        var requestLine = lines[0].Split(' ');
        if (requestLine.Length != 3) return null;
        var headers = new Dictionary<string, string>();
        foreach (var line in lines.Skip(1))
        {
            var colon = line.IndexOf(':');
            if (colon > 0) headers[line[..colon].ToLowerInvariant()] = line[(colon + 1)..].Trim();
        }
        if (!int.TryParse(headers.GetValueOrDefault("content-length", "0"), out var length) || length < 0 || length > MaxBodySize) return null;
        var bodyStart = headerEnd + 4;
        while (buffer.Count - bodyStart < length)
        {
            var read = await stream.ReadAsync(chunk);
            if (read == 0) return null;
            buffer.AddRange(chunk.AsSpan(0, read));
        }
        return new Request(requestLine[0], requestLine[1], headers, buffer.GetRange(bodyStart, length).ToArray());
    }

    static int IndexOf(List<byte> data, ReadOnlySpan<byte> pattern)
    {
        for (var i = 0; i + pattern.Length <= data.Count; i++)
        {
            var match = true;
            for (var j = 0; j < pattern.Length && match; j++) match = data[i + j] == pattern[j];
            if (match) return i;
        }
        return -1;
    }

    static JsonObject Error(string message) => new() { ["error"] = message };

    static JsonNode? Parse(byte[] body)
    {
        try { return JsonNode.Parse(body); } catch { return null; }
    }

    async Task<(int, JsonNode?, string?)> Respond(Request request)
    {
        if (!request.Headers.TryGetValue("origin", out var origin) || !AllowedOrigins.Contains(origin))
            return (403, Error(L.T("Bu kaynaktan istek kabul edilmiyor")), null);

        switch (request.Method, request.Path)
        {
            case ("OPTIONS", _):
                return (204, null, origin);

            case ("GET" or "POST", "/ping"):
                return (200, new JsonObject { ["app"] = "KD Download Manager", ["accent"] = Theme.AccentHex }, origin);

            case ("POST", "/hello"):
            {
                var hello = Parse(request.Body);
                var browser = hello?["browser"] is JsonValue b && b.TryGetValue<string>(out var name) ? name[..Math.Min(60, name.Length)] : L.T("Tarayıcı");
                onHello(browser);
                var reply = new JsonObject
                {
                    ["app"] = "KD Download Manager",
                    ["wantsCookies"] = new JsonArray(CookieVault.Shared.WantedSites.Select(s => (JsonNode)s).ToArray()),
                };
                if (BrowserExtension.InstalledVersion is { } version) reply["extensionVersion"] = version;
                return (200, reply, origin);
            }

            case ("POST", "/cookies"):
            {
                var payload = Parse(request.Body);
                var site = payload?["site"] is JsonValue s && s.TryGetValue<string>(out var value) ? value : null;
                List<BrowserCookie>? jar = null;
                try { jar = payload?["cookieJar"]?.Deserialize<List<BrowserCookie>>(); } catch { }
                if (site == null || jar == null || !DownloadSources.VideoHosts.Contains(site))
                    return (400, Error(L.T("Geçersiz çerez listesi")), origin);
                CookieVault.Shared.Store(jar, site);
                return (200, new JsonObject { ["stored"] = jar.Count }, origin);
            }

            case ("POST", "/formats"):
            {
                var payload = Parse(request.Body);
                var url = payload?["url"] is JsonValue u && u.TryGetValue<string>(out var value) ? value : null;
                if (url == null || !url.StartsWith("http", StringComparison.OrdinalIgnoreCase))
                    return (422, Error(L.T("Geçersiz adres")), origin);
                List<BrowserCookie>? jar = null;
                try { jar = payload?["cookieJar"]?.Deserialize<List<BrowserCookie>>(); } catch { }
                if (jar != null && CookieVault.Site(url) is { } site) CookieVault.Shared.Store(jar, site);
                var (status, body) = await Formats(url);
                return (status, body, origin);
            }

            case ("POST", "/add"):
            {
                var payload = Parse(request.Body);
                if (payload?["links"] is not JsonArray array || array.Count is < 1 or > MaxLinksPerRequest)
                    return (400, Error(L.T("Geçersiz link listesi")), origin);
                var links = new List<DownloadRequest>();
                foreach (var entry in array)
                {
                    if (entry == null) continue;
                    using var document = JsonDocument.Parse(entry.ToJsonString());
                    if (DownloadRequest.FromJson(document.RootElement) is { } link) links.Add(link);
                }
                var valid = links.Where(l => DownloadSources.LooksLikeLink(l.Url)).ToList();
                if (valid.Count == 0) return (422, Error(L.T("Desteklenen bir link yok")), origin);
                if (!valid.Any(l => l.FromBrowserDownload == true))
                {
                    onAdd(valid);
                    return (200, new JsonObject { ["added"] = valid.Count }, origin);
                }
                // A download the browser started: can the server be asked again? If not (blob: files made by the
                // page, one-time links, form posts) refuse, and the extension lets the browser finish it.
                var accepted = new List<DownloadRequest>();
                foreach (var link in valid)
                {
                    if (link.FromBrowserDownload != true)
                    {
                        accepted.Add(link);
                        continue;
                    }
                    switch (await LinkProbe.CanTakeOver(link))
                    {
                        case LinkProbe.TakeOver.Refuse refuse:
                            System.Diagnostics.Debug.WriteLine($"Browser download not taken over ({refuse.Reason}): {link.Url}");
                            break;
                        case LinkProbe.TakeOver.Accept accept:
                            if (accept.Name != null) link.Filename = accept.Name;
                            accepted.Add(link);
                            break;
                    }
                }
                if (accepted.Count == 0) return (422, Error(L.T("Bu indirme tarayıcıda kalmalı")), origin);
                onAdd(accepted);
                return (200, new JsonObject { ["added"] = accepted.Count }, origin);
            }

            default:
                return (404, Error(L.T("Bulunamadı")), origin);
        }
    }

    async Task<(int, JsonNode)> Formats(string url)
    {
        var now = DateTimeOffset.Now;
        if (formatsCache.TryGetValue(url, out var cached) && now - cached.date < FormatsCacheLifetime) return (200, Json(cached.formats));
        if (formatsFailures.TryGetValue(url, out var failed) && now - failed.date < FailureCacheLifetime) return (502, Error(failed.message));
        if (!formatsLookups.TryGetValue(url, out var lookup))
        {
            lookup = Lookup(url);
            formatsLookups[url] = lookup;
        }
        var (formats, error) = await lookup;
        return formats != null ? (200, Json(formats)) : (502, Error(error?.Message ?? L.T("Video bilgisi alınamadı")));
    }

    async Task<(VideoFormats?, Exception?)> Lookup(string url)
    {
        try
        {
            var formats = await VideoFormats.Fetch(url, CookieVault.Shared.CookiesFor(url));
            foreach (var old in formatsCache.Where(p => DateTimeOffset.Now - p.Value.date >= FormatsCacheLifetime).Select(p => p.Key).ToList())
                formatsCache.Remove(old);
            formatsCache[url] = (DateTimeOffset.Now, formats);
            return (formats, null);
        }
        catch (Exception error)
        {
            if (error is not VideoFormats.FetchException { TimedOut: true }) formatsFailures[url] = (DateTimeOffset.Now, error.Message);
            return (null, error);
        }
        finally { formatsLookups.Remove(url); }
    }

    static JsonObject Json(VideoFormats formats) => new()
    {
        ["title"] = formats.Title,
        ["duration"] = formats.Duration,
        ["options"] = new JsonArray(formats.Options.Select(o => (JsonNode)new JsonObject
        {
            ["quality"] = o.Quality.Raw(),
            ["title"] = o.Quality.Title(),
            ["size"] = o.Size,
        }).ToArray()),
    };

    static async Task Write(NetworkStream stream, int status, JsonNode? json, string? origin)
    {
        var body = json == null ? [] : Encoding.UTF8.GetBytes(json.ToJsonString());
        var reason = status switch
        {
            200 => "OK", 204 => "No Content", 400 => "Bad Request", 403 => "Forbidden", 404 => "Not Found",
            422 => "Unprocessable Content", 502 => "Bad Gateway", _ => "OK",
        };
        var head = new StringBuilder($"HTTP/1.1 {status} {reason}\r\n")
            .Append("Content-Type: application/json; charset=utf-8\r\n")
            .Append($"Content-Length: {body.Length}\r\n")
            .Append("Connection: close\r\n");
        if (origin != null)
        {
            head.Append($"Access-Control-Allow-Origin: {origin}\r\n")
                .Append("Access-Control-Allow-Methods: GET, POST\r\n")
                .Append("Access-Control-Allow-Headers: Content-Type\r\n");
        }
        head.Append("\r\n");
        await stream.WriteAsync(Encoding.ASCII.GetBytes(head.ToString()));
        await stream.WriteAsync(body);
        await stream.FlushAsync();
    }
}
