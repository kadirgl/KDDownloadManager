using System.Text.Json.Nodes;
using KDDownloadManager.Models;

namespace KDDownloadManager.Engine;

/// <summary>Resolutions a video page offers and their estimated sizes, from yt-dlp (macOS: VideoFormats).</summary>
public sealed record VideoFormats(string Title, double? Duration, List<VideoFormats.Option> Options)
{
    public sealed record Option(VideoQuality Quality, long? Size);

    public sealed class FetchException(string message, bool timedOut = false) : Exception(message)
    {
        public bool TimedOut { get; } = timedOut;
    }

    public static readonly TimeSpan Deadline = TimeSpan.FromSeconds(20);

    /// <summary>The first run of a fresh yt-dlp is slow (Defender scans it); warm it up at launch.</summary>
    public static void WarmUp()
    {
        if (Tools.Find("yt-dlp") is not { } binary) return;
        _ = Task.Run(() =>
        {
            try
            {
                using var p = ProcessJob.Start(Tools.StartInfo(binary, ["--version"]));
                p.WaitForExit(30_000);
            }
            catch { }
        });
    }

    public static async Task<VideoFormats> Fetch(string url, List<BrowserCookie>? cookies = null)
    {
        var binary = Tools.Find("yt-dlp") ?? throw new FetchException(L.T("yt-dlp bulunamadı"));
        var work = Path.Combine(Path.GetTempPath(), "kd-formats-" + Guid.NewGuid().ToString("N"));
        try
        {
            var arguments = new List<string> { "-J", "--no-playlist", "--playlist-items", "1", "--no-warnings",
                "--socket-timeout", "10", "--extractor-retries", "1" };
            if (cookies is { Count: > 0 })
            {
                var file = Path.Combine(work, "cookies.txt");
                CookieVault.WriteNetscapeFile(cookies, file);
                arguments.AddRange(["--cookies", file]);
            }
            arguments.AddRange(Tools.JavaScriptRuntimeArguments());
            arguments.AddRange(["--", url]);

            var (data, exit, timedOut) = await Task.Run(async () =>
            {
                using var job = new ProcessJob();
                using var process = ProcessJob.Start(Tools.StartInfo(binary, arguments), job);
                var error = process.StandardError.ReadToEndAsync();
                var output = process.StandardOutput.ReadToEndAsync();
                using var cts = new CancellationTokenSource(Deadline);
                var killed = false;
                try { await process.WaitForExitAsync(cts.Token); }
                catch (OperationCanceledException)
                {
                    killed = true;
                    job.Terminate();
                    await process.WaitForExitAsync();
                }
                var text = await output;
                await error;
                return (text, process.ExitCode, killed);
            });
            if (timedOut) throw new FetchException(L.T("Video bilgisi zamanında alınamadı"), true);
            if (exit != 0) throw new FetchException(L.T("Video bilgisi alınamadı"));
            var info = JsonNode.Parse(data) ?? throw new FetchException(L.T("Video bilgisi alınamadı"));
            if (info["formats"] == null && info["url"] == null && info["entries"] is JsonArray { Count: > 0 } entries) info = entries[0]!;
            return Parse(info);
        }
        finally
        {
            try { Directory.Delete(work, true); } catch { }
        }
    }

    static string? Str(JsonNode? n) => n is JsonValue v && v.TryGetValue<string>(out var s) ? s : null;
    static double? Dbl(JsonNode? n) => n is JsonValue v && v.TryGetValue<double>(out var d) ? d : null;

    public static VideoFormats Parse(JsonNode info)
    {
        var formats = (info["formats"] as JsonArray ?? []).OfType<JsonObject>().ToList();
        var videos = formats.Where(f => (Str(f["vcodec"]) ?? "none") != "none" && Resolution(f) != null).ToList();
        var audios = formats.Where(f => Str(f["vcodec"]) == "none" && (Str(f["acodec"]) ?? "none") != "none").ToList();
        var audio = Best(audios.Where(f => Str(f["acodec"])?.StartsWith("mp4a") == true).ToList()) ?? Best(audios);
        var audioSize = audio != null ? Size(audio) : null;

        Option? OptionFor(VideoQuality quality, List<JsonObject> candidates)
        {
            if (candidates.Count == 0) return null;
            var h264 = candidates.Where(f => Str(f["vcodec"])?.StartsWith("avc1") == true).ToList();
            var pool = h264.Count == 0 ? candidates : h264;
            var videoOnly = pool.Where(f => (Str(f["acodec"]) ?? "none") == "none").ToList();
            if (Best(videoOnly.Count == 0 ? pool : videoOnly) is not { } video) return null;
            var hasAudio = (Str(video["acodec"]) ?? "none") != "none";
            var total = Size(video) is { } s ? s + (hasAudio ? 0 : audioSize ?? 0) : (long?)null;
            return new Option(quality, total);
        }

        var options = new List<Option>();
        var autoH264 = videos.Where(f => Str(f["vcodec"])?.StartsWith("avc1") == true).ToList();
        var autoPool = autoH264.Count == 0 ? videos : autoH264;
        var top = autoPool.Select(Resolution).Where(r => r != null).Max();
        if (top != null && OptionFor(VideoQuality.Auto, autoPool.Where(f => Resolution(f) == top).ToList()) is { } auto) options.Add(auto);
        foreach (var quality in VideoQualities.All)
        {
            if (quality.MaxHeight() is not { } height) continue;
            if (OptionFor(quality, videos.Where(f => Bucket(Resolution(f)) == height).ToList()) is { } found) options.Add(found);
        }
        if (options.Count == 0 && (formats.Count > 0 || info["url"] != null))
            options.Add(new Option(VideoQuality.Auto, Best(formats) is { } b ? Size(b) : null));
        if (audios.Count > 0 || videos.Count == 0) options.Add(new Option(VideoQuality.Audio, audioSize));
        return new VideoFormats(Str(info["title"]) ?? L.T("Video"), Dbl(info["duration"]), options);
    }

    static int? Resolution(JsonObject f)
    {
        var sides = new[] { Dbl(f["width"]), Dbl(f["height"]) }.Where(x => x != null).Select(x => (int)x!.Value).ToList();
        return sides.Count == 0 ? null : sides.Min();
    }

    static int? Bucket(int? resolution) =>
        resolution is not { } r ? null : new[] { 2160, 1440, 1080, 720, 480, 360 }.Cast<int?>().FirstOrDefault(b => r >= (int)(b!.Value * 0.9));

    static JsonObject? Best(List<JsonObject> formats)
    {
        var sized = formats.Where(f => Size(f) != null).ToList();
        return (sized.Count == 0 ? formats : sized).MaxBy(f => Dbl(f["tbr"]) ?? 0);
    }

    static long? Size(JsonObject f) => (long?)(Dbl(f["filesize"]) ?? Dbl(f["filesize_approx"]));
}
