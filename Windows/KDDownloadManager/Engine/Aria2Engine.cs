using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using KDDownloadManager.Models;

namespace KDDownloadManager.Engine;

/// <summary>
/// The real engine for HTTP/HTTPS/FTP (segmented), magnet and .torrent, through aria2c (macOS: Aria2Engine).
/// aria2c starts with the first download; status is polled every half second with system.multicall.
/// Runs on the UI thread: awaits resume there, like @MainActor on macOS.
/// </summary>
public sealed partial class Aria2Engine : IDownloadEngine
{
    readonly Aria2Daemon daemon = new();
    Aria2Client? client;
    Task<Aria2Client>? startup;
    bool polling;

    readonly Dictionary<Guid, DownloadItem> items = new();
    readonly Dictionary<Guid, string> gids = new();
    readonly Dictionary<Guid, List<string>> partialFiles = new();
    readonly HashSet<Guid> pausedByUser = new();
    readonly HashSet<Guid> singleConnection = new();
    readonly Dictionary<Guid, int> autoRetries = new();
    static readonly double[] RetryDelays = [0, 5, 15, 30, 60];
    static readonly HashSet<string> ConnectionErrorCodes = ["1", "2", "6", "22"];

    int maxConcurrent = Settings.DefaultMaxConcurrent;
    long? globalLimit;

    static readonly JsonArray StatusKeys = ["status", "totalLength", "completedLength", "downloadSpeed", "errorMessage", "errorCode", "followedBy"];
    static readonly JsonArray DetailedStatusKeys = ["status", "totalLength", "completedLength", "downloadSpeed", "errorMessage", "errorCode", "followedBy", "files", "bittorrent", "dir"];
    readonly HashSet<string> detailsKnown = new();
    readonly Dictionary<Guid, string> roots = new();

    public void Start(DownloadItem item)
    {
        items[item.Id] = item;
        Add(item);
    }

    public void Pause(DownloadItem item)
    {
        pausedByUser.Add(item.Id);
        item.SetStatus(DownloadStatus.Paused);
        if (gids.TryGetValue(item.Id, out var gid)) Send("aria2.forcePause", gid);
    }

    public void Resume(DownloadItem item)
    {
        items[item.Id] = item;
        pausedByUser.Remove(item.Id);
        autoRetries.Remove(item.Id);
        if (item.Status.Kind != StatusKind.Paused || !gids.TryGetValue(item.Id, out var gid))
        {
            // Failed or left from an earlier session: add again; --continue and the .aria2 file resume it.
            if (gids.Remove(item.Id, out var old)) Send("aria2.removeDownloadResult", old);
            Add(item);
            return;
        }
        item.SetStatus(DownloadStatus.Queued);
        Send("aria2.unpause", gid);
        StartPolling();
    }

    public void Cancel(DownloadItem item)
    {
        items.Remove(item.Id);
        roots.Remove(item.Id);
        singleConnection.Remove(item.Id);
        autoRetries.Remove(item.Id);
        pausedByUser.Remove(item.Id);
        partialFiles.Remove(item.Id, out var files);
        if (!gids.Remove(item.Id, out var gid))
        {
            if (!item.IsCompleted) Delete(LeftoverFiles(item));
            return;
        }
        if (item.IsCompleted)
        {
            Send("aria2.removeDownloadResult", gid);
            return;
        }
        _ = Task.Run(async () =>
        {
            if (client is not { } c) return;
            try { await c.Call("aria2.forceRemove", gid); } catch { }
            await Task.Delay(700);
            try { await c.Call("aria2.removeDownloadResult", gid); } catch { }
            Delete(files ?? []);
        });
    }

    public void SetSpeedLimit(long? limit, DownloadItem item)
    {
        item.SpeedLimit = limit;
        if (gids.TryGetValue(item.Id, out var gid))
            Send("aria2.changeOption", gid, new JsonObject { ["max-download-limit"] = (limit ?? 0).ToString() });
    }

    public void SetGlobalSpeedLimit(long? limit)
    {
        globalLimit = limit;
        if (client != null) Send("aria2.changeGlobalOption", new JsonObject { ["max-overall-download-limit"] = (limit ?? 0).ToString() });
    }

    public void SetMaxConcurrent(int count)
    {
        maxConcurrent = count;
        if (client != null) Send("aria2.changeGlobalOption", new JsonObject { ["max-concurrent-downloads"] = count.ToString() });
    }

    public void Shutdown() => daemon.Stop();

    // MARK: aria2 connection

    async Task<Aria2Client> Connected()
    {
        if (client != null) return client;
        startup ??= daemon.Start(maxConcurrent, globalLimit);
        try
        {
            var c = await startup;
            if (client == null)
            {
                client = c;
                try
                {
                    await c.Call("aria2.changeGlobalOption", new JsonObject
                    {
                        ["max-overall-download-limit"] = (globalLimit ?? 0).ToString(),
                        ["max-concurrent-downloads"] = maxConcurrent.ToString(),
                    });
                }
                catch { }
            }
            return c;
        }
        catch
        {
            startup = null;
            throw;
        }
    }

    async void Add(DownloadItem item)
    {
        item.SetStatus(DownloadStatus.Queued);
        var limitAtAdd = item.SpeedLimit;
        var connections = singleConnection.Contains(item.Id) ? 1 : Settings.ConnectionCount;
        var options = new JsonObject
        {
            ["dir"] = item.Folder,
            ["max-download-limit"] = (limitAtAdd ?? 0).ToString(),
            ["split"] = connections.ToString(),
            ["max-connection-per-server"] = connections.ToString(),
        };
        if (item.Referrer != null) options["referer"] = item.Referrer;
        if (item.UserAgent != null) options["user-agent"] = item.UserAgent;
        if (item.Cookies != null) options["header"] = new JsonArray("Cookie: " + item.Cookies);
        if (item.PreferredName != null) options["out"] = item.PreferredName;
        try
        {
            var c = await Connected();
            JsonNode? result;
            if (Uri.TryCreate(item.Url, UriKind.Absolute, out var uri) && uri.IsFile)
            {
                byte[] torrent;
                try { torrent = await File.ReadAllBytesAsync(uri.LocalPath); }
                catch { throw new Aria2Exception(L.T("Torrent dosyası okunamadı")); }
                if (!IsPrivate(torrent)) options["bt-tracker"] = string.Join(',', PublicTrackers);
                result = await c.Call("aria2.addTorrent", Convert.ToBase64String(torrent), new JsonArray(), options);
            }
            else
            {
                if (IsTrackerlessMagnet(item.Url)) options["bt-tracker"] = string.Join(',', PublicTrackers);
                result = await c.Call("aria2.addUri", new JsonArray(item.Url), options);
            }
            var gid = result?.GetValue<string>() ?? throw new Aria2Exception(L.T("aria2 indirme kimliği vermedi"));
            if (!items.ContainsKey(item.Id))
            {
                try { await c.Call("aria2.forceRemove", gid); } catch { }
                return;
            }
            gids[item.Id] = gid;
            if (item.SpeedLimit != limitAtAdd) SetSpeedLimit(item.SpeedLimit, item);
            if (pausedByUser.Contains(item.Id)) Send("aria2.forcePause", gid);
            StartPolling();
        }
        catch (Exception error)
        {
            item.SetStatus(DownloadStatus.Failed(error is Aria2Exception ? error.Message : L.T("İndirme motoru (aria2c) başlatılamadı")));
        }
    }

    /// <summary>Commands whose result is not awaited; errors show up in the next status poll.</summary>
    async void Send(string method, params JsonNode?[] parameters)
    {
        try
        {
            var c = await Connected();
            await c.Call(method, parameters);
        }
        catch { }
    }

    // MARK: Polling

    async void StartPolling()
    {
        if (polling) return;
        polling = true;
        try
        {
            while (await Poll()) await Task.Delay(500);
        }
        finally { polling = false; }
    }

    async Task<bool> Poll()
    {
        var tracked = gids.Where(pair => items.TryGetValue(pair.Key, out var item) && item.Status.Kind is StatusKind.Queued or StatusKind.Downloading)
            .ToDictionary(p => p.Key, p => p.Value);
        if (client == null || tracked.Count == 0) return false;
        var ids = tracked.Keys.ToList();
        var calls = ids.Select(id =>
        {
            var gid = tracked[id];
            return ("aria2.tellStatus", new JsonNode?[] { gid, (detailsKnown.Contains(gid) ? StatusKeys : DetailedStatusKeys).DeepClone() });
        });
        try
        {
            var results = await client.Multicall(calls);
            for (var i = 0; i < Math.Min(ids.Count, results.Count); i++)
            {
                var id = ids[i];
                if (!items.TryGetValue(id, out var item) || !gids.TryGetValue(id, out var gid) || gid != tracked[id]) continue;
                if (results[i].value is JsonObject status) Apply(status, item, gid);
            }
        }
        catch
        {
            if (!daemon.IsRunning)
            {
                DaemonStopped();
                return false;
            }
        }
        return true;
    }

    static string? Str(JsonNode? node) => node is JsonValue v && v.TryGetValue<string>(out var s) ? s : null;
    static long? Long(JsonNode? node) => long.TryParse(Str(node), out var n) ? n : null;

    void Apply(JsonObject status, DownloadItem item, string gid)
    {
        if (status["files"] is JsonArray files)
        {
            var paths = files.Select(f => Str(f?["path"])).Where(p => !string.IsNullOrEmpty(p) && !p!.StartsWith("[METADATA]"))
                .Select(p => p!.Replace('/', '\\')).ToList();
            var torrentName = Str(status["bittorrent"]?["info"]?["name"]);
            var dir = Str(status["dir"]);
            var root = torrentName != null && dir != null ? Path.Combine(dir.Replace('/', '\\'), torrentName) : paths.FirstOrDefault();
            var name = torrentName ?? (paths.Count > 0 ? Path.GetFileName(paths[0]) : null);
            if (name != null && item.FileName != name)
            {
                item.FileName = name;
                item.Category = DownloadCategories.ForFile(name);
            }
            if (root != null && paths.Count > 0)
            {
                partialFiles[item.Id] = [.. paths, root + ".aria2"];
                roots[item.Id] = root;
                detailsKnown.Add(gid);
            }
        }
        if (Long(status["totalLength"]) is { } total && total > 0) item.TotalBytes = total;
        if (Long(status["completedLength"]) is { } done) item.DownloadedBytes = done;

        var state = Str(status["status"]);
        if (pausedByUser.Contains(item.Id) && state is "active" or "waiting") return;

        switch (state)
        {
            case "active":
                item.SetStatus(DownloadStatus.Downloading, Long(status["downloadSpeed"]) ?? 0);
                break;
            case "waiting":
                item.SetStatus(DownloadStatus.Queued);
                break;
            case "paused":
                item.SetStatus(pausedByUser.Contains(item.Id) ? DownloadStatus.Paused : DownloadStatus.Queued);
                break;
            case "error":
                if (RetryWithSingleConnection(item, status)) return;
                item.SetStatus(DownloadStatus.Failed(ErrorText.Aria2(Str(status["errorCode"]), Str(status["errorMessage"]),
                    item.TotalBytes > 0 ? item.TotalBytes - item.DownloadedBytes : null)));
                break;
            case "complete":
                if (Str(status["followedBy"]?[0]) is { } next)
                {
                    // Magnet/.torrent: metadata done, the real download continues under a new gid.
                    gids[item.Id] = next;
                    return;
                }
                item.TotalBytes = Math.Max(item.TotalBytes, item.DownloadedBytes);
                item.DownloadedBytes = item.TotalBytes;
                item.Destination = roots.GetValueOrDefault(item.Id);
                detailsKnown.Remove(gid);
                item.SetStatus(DownloadStatus.Completed);
                break;
        }
    }

    void DaemonStopped()
    {
        client = null;
        startup = null;
        foreach (var id in gids.Keys)
            if (items.TryGetValue(id, out var item) && !item.IsCompleted)
                item.SetStatus(DownloadStatus.Failed(L.T("İndirme motoru (aria2c) durdu")));
        gids.Clear();
    }

    bool RetryWithSingleConnection(DownloadItem item, JsonObject status)
    {
        var message = Str(status["errorMessage"]) ?? "";
        var code = Str(status["errorCode"]) ?? "";
        var attempt = autoRetries.GetValueOrDefault(item.Id);
        if (item.Source != DownloadSource.Direct || attempt >= RetryDelays.Length
            || !(ConnectionErrorCodes.Contains(code) || message.Contains("No URI available"))
            || IsPermanentHttpError(message)) return false;
        autoRetries[item.Id] = attempt + 1;
        singleConnection.Add(item.Id);
        if (gids.Remove(item.Id, out var old)) Send("aria2.removeDownloadResult", old);
        item.SetStatus(DownloadStatus.Queued);
        _ = RetryLater(item, RetryDelays[attempt]);
        return true;
    }

    async Task RetryLater(DownloadItem item, double delay)
    {
        await Task.Delay(TimeSpan.FromSeconds(delay));
        if (items.ContainsKey(item.Id) && !gids.ContainsKey(item.Id) && !pausedByUser.Contains(item.Id) && item.Status.Kind == StatusKind.Queued)
            Add(item);
    }

    static bool IsPermanentHttpError(string message)
    {
        var match = StatusPattern().Match(message);
        if (!match.Success) return false;
        var status = int.Parse(match.Groups[1].Value);
        return status is >= 400 and < 500 && status != 408 && status != 429;
    }

    [GeneratedRegex(@"status=(\d{3})")]
    private static partial Regex StatusPattern();

    // MARK: Torrent

    static readonly string[] PublicTrackers =
    [
        "udp://tracker.opentrackr.org:1337/announce",
        "udp://open.stealth.si:80/announce",
        "udp://tracker.torrent.eu.org:451/announce",
        "udp://exodus.desync.com:6969/announce",
        "udp://open.demonii.com:1337/announce",
    ];

    static bool IsTrackerlessMagnet(string url) =>
        url.StartsWith("magnet:", StringComparison.OrdinalIgnoreCase) && !url.Contains("tr=");

    /// <summary>Private trackers' torrents ("7:privatei1e" in bencode) must not get foreign trackers.</summary>
    static bool IsPrivate(byte[] torrent) => torrent.AsSpan().IndexOf("7:privatei1e"u8) >= 0;

    static List<string> LeftoverFiles(DownloadItem item)
    {
        var path = Path.Combine(item.Folder, item.FileName);
        var control = path + ".aria2";
        return File.Exists(control) ? [path, control] : [];
    }

    static void Delete(IEnumerable<string> files)
    {
        foreach (var path in files)
        {
            try { if (File.Exists(path)) File.Delete(path); } catch { }
        }
    }
}
