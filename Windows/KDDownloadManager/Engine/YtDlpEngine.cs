using System.Diagnostics;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using KDDownloadManager.Models;

namespace KDDownloadManager.Engine;

/// <summary>
/// yt-dlp engine for YouTube and other video sites (macOS: YtDlpEngine). One yt-dlp process per download;
/// progress comes as machine-readable "KDPROG {json}" lines. Pausing stops the process tree (its job object),
/// resuming starts it again and yt-dlp continues from its .part files. Partial files live in a per-download
/// temporary folder, so only finished files appear in the download folder.
/// </summary>
public sealed partial class YtDlpEngine : IDownloadEngine
{
    enum StopReason { Pause, Cancel, Restart }

    sealed class Job(Process process, ProcessJob tree)
    {
        public Process Process { get; } = process;
        public ProcessJob Tree { get; } = tree;
        public StopReason? StopReason;
        public bool UsedCookies;
        public bool UsedSegmented;
    }

    readonly HashSet<Guid> awaitingCookies = new();
    readonly Dictionary<Guid, DownloadItem> items = new();
    readonly List<Guid> queue = new();
    readonly Dictionary<Guid, Job> jobs = new();
    readonly Dictionary<Guid, Dictionary<string, long>> parts = new();
    readonly Dictionary<Guid, long> expectedTotal = new();
    readonly Dictionary<Guid, long> segmentedBytes = new();
    readonly Dictionary<Guid, int> expectedParts = new();
    readonly Dictionary<Guid, HashSet<string>> finishedParts = new();
    readonly HashSet<Guid> singleConnection = new();

    int maxConcurrent = Settings.DefaultMaxConcurrent;
    long? globalLimit;

    public YtDlpEngine()
    {
        CookieVault.Shared.Observe(CookiesArrived);
    }

    public void Start(DownloadItem item)
    {
        items[item.Id] = item;
        Enqueue(item);
    }

    public void Pause(DownloadItem item)
    {
        queue.Remove(item.Id);
        item.SetStatus(DownloadStatus.Paused);
        Stop(item.Id, StopReason.Pause);
    }

    public void Resume(DownloadItem item)
    {
        items[item.Id] = item;
        awaitingCookies.Remove(item.Id);
        Enqueue(item);
    }

    void CookiesArrived(string site)
    {
        foreach (var id in awaitingCookies.ToList())
            if (items.TryGetValue(id, out var item) && CookieVault.Site(item.Url) == site && item.IsFailed)
                Resume(item);
    }

    public void Cancel(DownloadItem item)
    {
        items.Remove(item.Id);
        awaitingCookies.Remove(item.Id);
        singleConnection.Remove(item.Id);
        segmentedBytes.Remove(item.Id);
        expectedParts.Remove(item.Id);
        finishedParts.Remove(item.Id);
        queue.Remove(item.Id);
        expectedTotal.Remove(item.Id);
        parts.Remove(item.Id);
        if (jobs.ContainsKey(item.Id)) Stop(item.Id, StopReason.Cancel);
        else RemoveTemporaryFolder(item.Id);
    }

    public void SetSpeedLimit(long? limit, DownloadItem item)
    {
        item.SpeedLimit = limit;
        // While ffmpeg merges nothing downloads; interrupting would break the merge.
        if (item.Status.Kind == StatusKind.Downloading) Stop(item.Id, StopReason.Restart);
    }

    public void SetGlobalSpeedLimit(long? limit)
    {
        if (globalLimit == limit) return;
        globalLimit = limit;
        foreach (var id in jobs.Keys.Where(id => items.GetValueOrDefault(id)?.Status.Kind == StatusKind.Downloading).ToList())
            Stop(id, StopReason.Restart);
    }

    public void SetMaxConcurrent(int count)
    {
        maxConcurrent = count;
        LaunchNext();
    }

    public void Shutdown()
    {
        foreach (var job in jobs.Values)
        {
            job.StopReason = StopReason.Pause;
            job.Tree.Terminate();
        }
    }

    // MARK: Processes

    void Enqueue(DownloadItem item)
    {
        item.SetStatus(DownloadStatus.Queued);
        if (!queue.Contains(item.Id)) queue.Add(item.Id);
        LaunchNext();
    }

    void LaunchNext()
    {
        while (jobs.Count < maxConcurrent)
        {
            var index = queue.FindIndex(id => !jobs.ContainsKey(id));
            if (index < 0) break;
            var id = queue[index];
            queue.RemoveAt(index);
            if (items.TryGetValue(id, out var item)) Launch(item);
        }
    }

    void Stop(Guid id, StopReason reason)
    {
        if (!jobs.TryGetValue(id, out var job)) return;
        job.StopReason = reason;
        job.Tree.Terminate();
    }

    async void Launch(DownloadItem item)
    {
        if (Tools.Find("yt-dlp") is not { } binary)
        {
            item.SetStatus(DownloadStatus.Failed(L.T("yt-dlp bulunamadı")));
            return;
        }
        var cookies = CookieVault.Shared.CookiesFor(item.Url);
        var arguments = Arguments(item, cookies);
        CookieVault.Shared.RequestIfNeeded(item.Url);
        var tree = new ProcessJob();
        Process process;
        try { process = ProcessJob.Start(Tools.StartInfo(binary, arguments), tree); }
        catch (Exception error)
        {
            tree.Dispose();
            item.SetStatus(DownloadStatus.Failed(error.Message));
            return;
        }
        var job = new Job(process, tree) { UsedCookies = cookies != null, UsedSegmented = arguments.Contains("--downloader") };
        segmentedBytes[item.Id] = 0;
        finishedParts[item.Id] = new();
        jobs[item.Id] = job;
        item.SetStatus(DownloadStatus.Downloading);

        // The error is on stderr as "ERROR: ..."; keep the last one.
        var lastError = Task.Run(async () =>
        {
            string? last = null;
            while (await process.StandardError.ReadLineAsync() is { } line)
                if (line.StartsWith("ERROR:")) last = line["ERROR:".Length..].Trim();
            return last;
        });
        while (await process.StandardOutput.ReadLineAsync() is { } line)
        {
            if (items.ContainsKey(item.Id) && job.StopReason == null)
                foreach (var part in OutputLines(line)) Handle(part, item);
        }
        await process.WaitForExitAsync();
        Finish(item, job, process.ExitCode, await lastError);
    }

    void Finish(DownloadItem item, Job job, int status, string? error)
    {
        jobs.Remove(item.Id);
        job.Tree.Dispose();
        try { File.Delete(CookieFile(item.Id)); } catch { }
        try
        {
            switch (job.StopReason)
            {
                case StopReason.Cancel:
                    RemoveTemporaryFolder(item.Id);
                    break;
                case StopReason.Pause:
                    break;
                case StopReason.Restart:
                    if (items.ContainsKey(item.Id) && item.Status.Kind is StatusKind.Downloading or StatusKind.Processing) Launch(item);
                    break;
                default:
                    if (!items.ContainsKey(item.Id)) return;
                    if (status != 0)
                    {
                        if (error != null && IsBotCheck(error))
                        {
                            awaitingCookies.Add(item.Id);
                            CookieVault.Shared.RequestFresh(item.Url);
                            item.SetStatus(DownloadStatus.Failed(job.UsedCookies
                                ? L.T("Site oturum doğrulaması istedi (robot ya da yaş kontrolü). Tarayıcıda siteye giriş yapın; indirme kendiliğinden yeniden denenecek.")
                                : L.T("Site oturum doğrulaması istedi; tarayıcı çerezleri bekleniyor. Eklenti bağlıysa bir dakika içinde yeniden denenecek.")));
                            return;
                        }
                        if (job.UsedSegmented && singleConnection.Add(item.Id))
                        {
                            // Some sites refuse parallel connections (403/429); continue with one.
                            Launch(item);
                            return;
                        }
                        item.SetStatus(DownloadStatus.Failed(ErrorText.YtDlp(error, status)));
                        return;
                    }
                    if (item.Destination is { } path && File.Exists(path)) item.TotalBytes = new FileInfo(path).Length;
                    item.TotalBytes = Math.Max(item.TotalBytes, item.DownloadedBytes);
                    item.DownloadedBytes = item.TotalBytes;
                    parts.Remove(item.Id);
                    expectedTotal.Remove(item.Id);
                    segmentedBytes.Remove(item.Id);
                    expectedParts.Remove(item.Id);
                    finishedParts.Remove(item.Id);
                    RemoveTemporaryFolder(item.Id);
                    item.SetStatus(DownloadStatus.Completed);
                    break;
            }
        }
        finally { LaunchNext(); }
    }

    static bool IsBotCheck(string message)
    {
        var lower = message.ToLowerInvariant();
        return lower.Contains("not a bot") || lower.Contains("confirm you");
    }

    static string CookieFile(Guid id) => Path.Combine(TemporaryFolder(id), "cookies.txt");

    List<string> Arguments(DownloadItem item, List<BrowserCookie>? cookies)
    {
        var output = (item.PreferredName?.Replace("%", "%%") ?? "%(title).150B") + ".%(ext)s";
        var arguments = new List<string>
        {
            "--no-playlist", "--newline", "--progress", "--progress-delta", "0.5", "--no-simulate",
            // Without it yt-dlp writes to the pipe in the ANSI code page: Turkish letters in titles and paths came
            // back as "?" and the finished file could not be found ("Maç Özeti" → "Ma? ?zeti").
            "--encoding", "utf-8",
            // Windows: no characters that are invalid in file names, and no over-long paths.
            "--windows-filenames",
            "-P", item.Folder,
            "-P", "temp:" + TemporaryFolder(item.Id),
            "-o", output,
            "--print", "before_dl:KDINFO %(.{title,filesize,filesize_approx,requested_formats.:.filesize,requested_formats.:.filesize_approx})j",
            "--print", "after_move:KDFILE %(filepath)s",
            "--progress-template", "download:KDPROG %(progress.{status,downloaded_bytes,total_bytes,total_bytes_estimate,speed,filename})j",
        };
        arguments.AddRange(FormatArguments(item.Quality, Tools.Find("ffmpeg")));
        arguments.AddRange(Tools.JavaScriptRuntimeArguments());
        if (cookies != null)
        {
            try
            {
                CookieVault.WriteNetscapeFile(cookies, CookieFile(item.Id));
                arguments.AddRange(["--cookies", CookieFile(item.Id)]);
            }
            catch { }
        }
        arguments.AddRange(SegmentedArguments(item));
        if (!DownloadSources.IsKnownVideoSite(item.Url))
        {
            if (item.Referrer != null) arguments.AddRange(["--referer", item.Referrer]);
            if (item.UserAgent != null) arguments.AddRange(["--user-agent", item.UserAgent]);
        }
        var limits = new[] { item.SpeedLimit, globalLimit }.Where(l => l != null).Select(l => l!.Value).ToList();
        if (limits.Count > 0) arguments.AddRange(["--limit-rate", limits.Min().ToString()]);
        arguments.AddRange(["--", item.Url]);
        return arguments;
    }

    List<string> SegmentedArguments(DownloadItem item)
    {
        var connections = Settings.ConnectionCount;
        var arguments = new List<string> { "--concurrent-fragments", connections.ToString() };
        if (connections <= 1 || singleConnection.Contains(item.Id) || Tools.Find("aria2c") is not { } aria2) return arguments;
        arguments.AddRange([
            "--downloader", aria2,
            "--downloader-args",
            $"aria2c:-x{connections} -s{connections} -j{connections} -k1M --stop-with-process={Environment.ProcessId} --summary-interval=1",
        ]);
        return arguments;
    }

    /// <summary>Format choice by quality; video and audio are merged into MP4 by ffmpeg.</summary>
    public static List<string> FormatArguments(VideoQuality quality, string? ffmpeg)
    {
        if (ffmpeg == null)
        {
            return quality switch
            {
                VideoQuality.Audio => ["-f", "ba[ext=m4a]/ba/b"],
                VideoQuality.Auto => ["-f", "b"],
                _ => ["-f", "b", "-S", "res:" + quality.Raw()],
            };
        }
        List<string> tools = ["--ffmpeg-location", Path.GetDirectoryName(ffmpeg)!];
        return quality switch
        {
            VideoQuality.Audio => [.. tools, "-f", "ba/b", "-x", "--audio-format", "mp3", "--audio-quality", "0"],
            // H.264/AAC plays everywhere on Windows (Movies & TV, Media Player).
            VideoQuality.Auto => [.. tools, "-f", "bv*+ba/b", "-S", "vcodec:h264,res,acodec:aac", "--merge-output-format", "mp4"],
            _ => [.. tools, "-f", "bv*+ba/b", "-S", $"res:{quality.Raw()},vcodec:h264,acodec:aac", "--merge-output-format", "mp4"],
        };
    }

    static string? Str(JsonNode? n) => n is JsonValue v && v.TryGetValue<string>(out var s) ? s : null;
    static long? Num(JsonNode? n) => n is JsonValue v ? (v.TryGetValue<long>(out var l) ? l : v.TryGetValue<double>(out var d) ? (long)d : null) : null;

    static readonly string[] Markers = ["KDINFO ", "KDPROG ", "KDFILE "];

    /// <summary>
    /// Splits an output line into separate messages. aria2c leaves its last progress line without a line break at the end
    /// of every part, so yt-dlp's "part finished" message was glued to it: <c>[#caef46 70MiB/77MiB(91%) …]KDPROG {"status":
    /// "finished", …}</c>. Taken for an aria2 readout, the message was lost: the downloaded amount fell back to the second
    /// part's few MB (the download seemed to start over) and then jumped to complete.
    /// </summary>
    /// <remarks>Only tool output lines ("[#…]", "[download]") are split, and only once: our own messages (a video title)
    /// stay as they are.</remarks>
    public static List<string> OutputLines(string line)
    {
        if (!line.StartsWith('[')) return [line];
        var at = Markers.Select(m => line.IndexOf(m, StringComparison.Ordinal)).Where(i => i >= 0).DefaultIfEmpty(-1).Min();
        if (at < 0) return [line];
        var head = line[..at];
        return head.Trim().Length == 0 ? [line[at..]] : [head, line[at..]];
    }

    void Handle(string line, DownloadItem item)
    {
        if (line.StartsWith("[#"))
        {
            HandleSegmentedProgress(line, item);
            return;
        }
        var space = line.IndexOf(' ');
        if (space < 0) return;
        var tag = line[..space];
        var payload = line[(space + 1)..];
        switch (tag)
        {
            case "KDINFO":
            {
                if (Decode(payload) is not JsonObject info) return;
                if (Str(info["title"]) is { } title) item.FileName = title;
                var exact = info["requested_formats.:.filesize"] as JsonArray ?? [];
                var approx = info["requested_formats.:.filesize_approx"] as JsonArray ?? [];
                var count = Math.Max(exact.Count, approx.Count);
                long requested = 0;
                for (var i = 0; i < count; i++)
                    requested += (i < exact.Count ? Num(exact[i]) : null) ?? (i < approx.Count ? Num(approx[i]) : null) ?? 0;
                expectedParts[item.Id] = Math.Max(1, count);
                var total = requested > 0 ? requested : Num(info["filesize"]) ?? Num(info["filesize_approx"]) ?? 0;
                if (total > 0)
                {
                    expectedTotal[item.Id] = total;
                    item.TotalBytes = total;
                }
                break;
            }
            case "KDPROG":
            {
                if (Decode(payload) is not JsonObject progress || Str(progress["filename"]) is not { } file) return;
                var state = Str(progress["status"]);
                var itemParts = parts.TryGetValue(item.Id, out var p) ? p : parts[item.Id] = new();
                itemParts[file] = Num(progress["downloaded_bytes"]) ?? itemParts.GetValueOrDefault(file);
                if (state == "finished")
                {
                    finishedParts.TryAdd(item.Id, new());
                    finishedParts[item.Id].Add(file);
                    segmentedBytes[item.Id] = 0;
                }
                item.DownloadedBytes = itemParts.Values.Sum() + segmentedBytes.GetValueOrDefault(item.Id);
                if (!expectedTotal.ContainsKey(item.Id) && (Num(progress["total_bytes"]) ?? Num(progress["total_bytes_estimate"])) is { } partTotal)
                    item.TotalBytes = item.DownloadedBytes - itemParts.GetValueOrDefault(file) + partTotal;
                if ((finishedParts.GetValueOrDefault(item.Id)?.Count ?? 0) >= expectedParts.GetValueOrDefault(item.Id, 1))
                    item.SetStatus(DownloadStatus.Processing);
                else
                    item.SetStatus(DownloadStatus.Downloading, Num(progress["speed"]) ?? item.Speed);
                break;
            }
            case "KDFILE":
                item.Destination = payload.Trim();
                item.FileName = Path.GetFileName(payload.Trim());
                break;
        }
    }

    /// <summary>aria2c's line every second: "[#24f96e 2.0MiB/29MiB(7%) CN:8 DL:1.0MiB ETA:26s]".</summary>
    void HandleSegmentedProgress(string line, DownloadItem item)
    {
        var match = Readout().Match(line);
        if (!match.Success || Bytes(match.Groups[1].Value, match.Groups[2].Value) is not { } done) return;
        segmentedBytes[item.Id] = done;
        var finished = parts.GetValueOrDefault(item.Id)?.Values.Sum() ?? 0;
        item.DownloadedBytes = finished + done;
        if (!expectedTotal.ContainsKey(item.Id) && Bytes(match.Groups[3].Value, match.Groups[4].Value) is { } partTotal)
            item.TotalBytes = finished + partTotal;
        var speed = SpeedPattern().Match(line);
        item.SetStatus(DownloadStatus.Downloading, speed.Success ? Bytes(speed.Groups[1].Value, speed.Groups[2].Value) ?? item.Speed : item.Speed);
    }

    [GeneratedRegex(@"\[#\w+ ([\d.]+)([KMGT]?i?B)/([\d.]+)([KMGT]?i?B)")]
    private static partial Regex Readout();

    [GeneratedRegex(@"DL:([\d.]+)([KMGT]?i?B)")]
    private static partial Regex SpeedPattern();

    static long? Bytes(string value, string unit)
    {
        if (!double.TryParse(value, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var number)) return null;
        var multiplier = unit switch { "KiB" => 1024d, "MiB" => 1_048_576d, "GiB" => 1_073_741_824d, "TiB" => 1_099_511_627_776d, _ => 1d };
        return (long)(number * multiplier);
    }

    static JsonNode? Decode(string json)
    {
        try { return JsonNode.Parse(json); } catch { return null; }
    }

    static string TemporaryFolder(Guid id) => Path.Combine(AppFolders.Caches, "yt-dlp", id.ToString().ToUpperInvariant());

    /// <summary>Temporary folders of downloads that are no longer in the list (left after a crash).</summary>
    public static void RemoveOrphanedTemporaryFolders(HashSet<Guid> keep)
    {
        var root = Path.Combine(AppFolders.Caches, "yt-dlp");
        if (!Directory.Exists(root)) return;
        foreach (var folder in Directory.GetDirectories(root))
        {
            if (Guid.TryParse(Path.GetFileName(folder), out var id) && !keep.Contains(id))
                try { Directory.Delete(folder, true); } catch { }
        }
    }

    static void RemoveTemporaryFolder(Guid id)
    {
        try { Directory.Delete(TemporaryFolder(id), true); } catch { }
    }
}
