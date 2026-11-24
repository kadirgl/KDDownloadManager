using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Text.Json.Serialization;

namespace KDDownloadManager.Models;

/// <summary>Which engine handles a download (macOS: DownloadSource).</summary>
public enum DownloadSource { Direct, Video, Torrent }

public static class DownloadSources
{
    public static readonly string[] VideoHosts = BuildVideoHosts();

    static string[] BuildVideoHosts()
    {
        var hosts = new List<string> { "youtube.com", "youtu.be", "vimeo.com", "dailymotion.com", "twitch.tv",
            "twitter.com", "x.com", "instagram.com", "tiktok.com", "facebook.com" };
#if DEBUG
        // Lets tests run the yt-dlp path without YouTube.
        if (Environment.GetEnvironmentVariable("KD_VIDEO_HOSTS") is { } extra)
            hosts.AddRange(extra.Split(',', StringSplitOptions.RemoveEmptyEntries));
#endif
        return hosts.ToArray();
    }

    public static string? Host(string link) =>
        Uri.TryCreate(link.Trim(), UriKind.Absolute, out var uri) && !string.IsNullOrEmpty(uri.Host) ? uri.Host.ToLowerInvariant() : null;

    static bool MatchesVideoHost(string? host) =>
        host != null && VideoHosts.Any(h => host == h || host.EndsWith("." + h));

    public static DownloadSource Detect(string link)
    {
        var lower = link.Trim().ToLowerInvariant();
        if (lower.StartsWith("magnet:") || lower.EndsWith(".torrent")) return DownloadSource.Torrent;
        if (MatchesVideoHost(Host(lower))) return DownloadSource.Video;
        // HLS/DASH streams caught by the extension are downloaded and joined by yt-dlp.
        if (Uri.TryCreate(lower, UriKind.Absolute, out var uri))
        {
            var path = uri.AbsolutePath;
            if (path.EndsWith(".m3u8") || path.EndsWith(".mpd")) return DownloadSource.Video;
        }
        return DownloadSource.Direct;
    }

    public static bool IsKnownVideoSite(string link) => MatchesVideoHost(Host(link));

    public static bool LooksLikeLink(string text)
    {
        var lower = text.Trim().ToLowerInvariant();
        return lower.StartsWith("http://") || lower.StartsWith("https://") || lower.StartsWith("ftp://") || lower.StartsWith("magnet:");
    }
}

public enum StatusKind { Queued, Downloading, Processing, Paused, Completed, Failed }

/// <summary>Status plus the error message for failures (macOS: DownloadStatus).</summary>
public readonly record struct DownloadStatus(StatusKind Kind, string? Message = null)
{
    public static readonly DownloadStatus Queued = new(StatusKind.Queued);
    public static readonly DownloadStatus Downloading = new(StatusKind.Downloading);
    public static readonly DownloadStatus Processing = new(StatusKind.Processing);
    public static readonly DownloadStatus Paused = new(StatusKind.Paused);
    public static readonly DownloadStatus Completed = new(StatusKind.Completed);
    public static DownloadStatus Failed(string message) => new(StatusKind.Failed, message);
    public bool IsRunning => Kind is StatusKind.Downloading or StatusKind.Queued or StatusKind.Processing;
}

[JsonConverter(typeof(JsonStringEnumConverter<VideoQuality>))]
public enum VideoQuality
{
    [JsonStringEnumMemberName("auto")] Auto,
    [JsonStringEnumMemberName("2160")] P2160,
    [JsonStringEnumMemberName("1440")] P1440,
    [JsonStringEnumMemberName("1080")] P1080,
    [JsonStringEnumMemberName("720")] P720,
    [JsonStringEnumMemberName("480")] P480,
    [JsonStringEnumMemberName("360")] P360,
    [JsonStringEnumMemberName("audio")] Audio,
}

public static class VideoQualities
{
    public static readonly VideoQuality[] All = Enum.GetValues<VideoQuality>();

    public static string Raw(this VideoQuality q) => q switch
    {
        VideoQuality.Auto => "auto", VideoQuality.Audio => "audio",
        _ => q.ToString()[1..],
    };

    public static VideoQuality? Parse(string? raw) => All.Cast<VideoQuality?>().FirstOrDefault(q => q!.Value.Raw() == raw);

    public static string Title(this VideoQuality q) => q switch
    {
        VideoQuality.Auto => L.T("Otomatik"),
        VideoQuality.P2160 => "2160p (4K)",
        VideoQuality.Audio => L.T("Sadece ses (MP3)"),
        _ => q.Raw() + "p",
    };

    public static int? MaxHeight(this VideoQuality q) => q is VideoQuality.Auto or VideoQuality.Audio ? null : int.Parse(q.Raw());
}

/// <summary>One download in the list. Changed on the UI thread only; raises PropertyChanged for the views.</summary>
public sealed class DownloadItem : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;

    public Guid Id { get; }
    public string Url { get; }
    public DownloadSource Source { get; }
    public string Folder { get; set; }

    string _fileName;
    /// <summary>May change while downloading (the server's real name); the category follows it.</summary>
    public string FileName
    {
        get => _fileName;
        set
        {
            if (_fileName == value) return;
            _fileName = value;
            if (Source != DownloadSource.Video) Category = DownloadCategories.ForFile(value);
            Raise();
        }
    }

    DownloadCategory _category;
    public DownloadCategory Category { get => _category; set => Set(ref _category, value); }

    long _total;
    public long TotalBytes { get => _total; set { if (Set(ref _total, value)) Raise(nameof(Progress)); } }

    long _done;
    public long DownloadedBytes { get => _done; set { if (Set(ref _done, value)) Raise(nameof(Progress)); } }

    long _speed;
    public long Speed { get => _speed; set => Set(ref _speed, value); }

    long? _limit;
    public long? SpeedLimit { get => _limit; set => Set(ref _limit, value); }

    DownloadStatus _status;
    public DownloadStatus Status { get => _status; set { if (Set(ref _status, value)) Raise(nameof(Progress)); } }

    string? _destination;
    public string? Destination { get => _destination; set => Set(ref _destination, value); }

    public string? Referrer { get; set; }
    public string? UserAgent { get; set; }
    /// <summary>Never written to disk.</summary>
    public string? Cookies { get; set; }
    public string? PreferredName { get; set; }
    public DateTimeOffset? CompletedAt { get; set; }

    VideoQuality _quality = VideoQuality.Auto;
    public VideoQuality Quality
    {
        get => _quality;
        set
        {
            if (!Set(ref _quality, value)) return;
            if (Source == DownloadSource.Video) Category = value == VideoQuality.Audio ? DownloadCategory.Music : DownloadCategory.Video;
        }
    }

    public double Progress => Status.Kind == StatusKind.Completed ? 1 : TotalBytes <= 0 ? 0 : Math.Min((double)DownloadedBytes / TotalBytes, 1);
    public bool IsFailed => Status.Kind == StatusKind.Failed;
    public bool IsCompleted => Status.Kind == StatusKind.Completed;

    public double? RemainingSeconds => Speed > 0 && TotalBytes > DownloadedBytes ? (double)(TotalBytes - DownloadedBytes) / Speed : null;

    public DownloadItem(string url, string? fileName = null, string? folder = null, Guid? id = null,
        long totalBytes = 0, long downloadedBytes = 0, DownloadStatus? status = null, bool forceVideo = false)
    {
        Id = id ?? Guid.NewGuid();
        Url = url;
        Source = forceVideo ? DownloadSource.Video : DownloadSources.Detect(url);
        Folder = folder ?? Settings.DownloadFolder;
        _fileName = fileName ?? SuggestedName(url, Source);
        _category = Source == DownloadSource.Video ? DownloadCategory.Video : DownloadCategories.ForFile(_fileName);
        _total = totalBytes;
        _done = downloadedBytes;
        _status = status ?? DownloadStatus.Queued;
    }

    /// <summary>Engines' status update; unchanged values do not notify.</summary>
    public void SetStatus(DownloadStatus status, long speed = 0)
    {
        Status = status;
        Speed = speed;
    }

    public static string SuggestedName(string url, DownloadSource source)
    {
        switch (source)
        {
            case DownloadSource.Torrent:
                var dn = QueryValue(url, "dn");
                if (!string.IsNullOrEmpty(dn)) return dn;
                return Uri.TryCreate(url, UriKind.Absolute, out var t) ? Path.GetFileName(Uri.UnescapeDataString(t.AbsolutePath)) is { Length: > 0 } n ? n : "Torrent" : "Torrent";
            case DownloadSource.Video:
                return L.F("%@ videosu", SiteName(url));
            default:
                if (!Uri.TryCreate(url, UriKind.Absolute, out var u)) return L.T("İndirme");
                var name = Path.GetFileName(u.AbsolutePath.TrimEnd('/'));
                if (string.IsNullOrEmpty(name) || u.AbsolutePath == "/") return L.T("İndirme");
                return Uri.UnescapeDataString(name);
        }
    }

    public static string? QueryValue(string url, string key)
    {
        var q = url.IndexOf('?');
        if (q < 0) return null;
        foreach (var part in url[(q + 1)..].Split('&'))
        {
            var eq = part.IndexOf('=');
            var k = eq < 0 ? part : part[..eq];
            if (k == key) return Uri.UnescapeDataString((eq < 0 ? "" : part[(eq + 1)..]).Replace('+', ' '));
        }
        return null;
    }

    static string SiteName(string url)
    {
        var host = (DownloadSources.Host(url) ?? "").Replace("www.", "");
        var names = new Dictionary<string, string>
        {
            ["youtube.com"] = "YouTube", ["youtu.be"] = "YouTube", ["m.youtube.com"] = "YouTube",
            ["vimeo.com"] = "Vimeo", ["dailymotion.com"] = "Dailymotion", ["twitch.tv"] = "Twitch",
            ["twitter.com"] = "X", ["x.com"] = "X", ["instagram.com"] = "Instagram",
            ["tiktok.com"] = "TikTok", ["facebook.com"] = "Facebook",
        };
        return names.TryGetValue(host, out var n) ? n : host.Length == 0 ? "Video" : host;
    }

    bool Set<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return false;
        field = value;
        Raise(name);
        return true;
    }

    void Raise([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
