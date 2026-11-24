using System.Text.Json;
using System.Text.Json.Serialization;
using KDDownloadManager.Models;

namespace KDDownloadManager.Store;

/// <summary>
/// Keeps the download list as JSON (macOS: DownloadArchive) in %LOCALAPPDATA%\KDDownloadManager\downloads.json.
/// Cookies are never written. Unreadable records are skipped one by one and the file is backed up first.
/// </summary>
public sealed class DownloadArchive(string path)
{
    public string Path { get; } = path;

    public static string DefaultPath => System.IO.Path.Combine(AppFolders.Support, "downloads.json");

    public static DownloadArchive Standard =>
#if DEBUG
        // Tests must not touch the real list.
        Environment.GetEnvironmentVariable("KD_ARCHIVE") is { Length: > 0 } test ? new(test) :
#endif
        new(DefaultPath);

    enum State { Active, Paused, Completed, Failed }

    sealed class Record
    {
        public Guid Id { get; set; }
        public string Url { get; set; } = "";
        public string FileName { get; set; } = "";
        public string Folder { get; set; } = "";
        public long TotalBytes { get; set; }
        public long DownloadedBytes { get; set; }
        public long? SpeedLimit { get; set; }
        public State State { get; set; }
        public string? Error { get; set; }
        public string? Destination { get; set; }
        public string? Referrer { get; set; }
        public string? UserAgent { get; set; }
        public VideoQuality? Quality { get; set; }
        public bool? Video { get; set; }
        public string? PreferredName { get; set; }
        public DateTimeOffset? CompletedAt { get; set; }
    }

    static readonly JsonSerializerOptions Options = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };

    public List<DownloadItem> Load()
    {
        string text;
        try { text = File.ReadAllText(Path); } catch { return []; }
        var items = new List<DownloadItem>();
        var damaged = false;
        try
        {
            using var document = JsonDocument.Parse(text);
            foreach (var element in document.RootElement.EnumerateArray())
            {
                try
                {
                    var record = element.Deserialize<Record>(Options);
                    if (record == null || record.Url.Length == 0) { damaged = true; continue; }
                    items.Add(ToItem(record));
                }
                catch (JsonException) { damaged = true; }
            }
        }
        catch (Exception) { damaged = true; }
        if (damaged)
        {
            try { File.Copy(Path, System.IO.Path.ChangeExtension(Path, $"bozuk-{DateTimeOffset.Now.ToUnixTimeSeconds()}.json")); } catch { }
        }
        return items;
    }

    static DownloadItem ToItem(Record r)
    {
        var status = r.State switch
        {
            State.Active => DownloadStatus.Queued,
            State.Paused => DownloadStatus.Paused,
            State.Completed => DownloadStatus.Completed,
            _ => DownloadStatus.Failed(r.Error ?? L.T("İndirme başarısız")),
        };
        return new DownloadItem(r.Url, r.FileName, r.Folder, r.Id, r.TotalBytes, r.DownloadedBytes, status, r.Video == true)
        {
            PreferredName = r.PreferredName,
            CompletedAt = r.CompletedAt,
            SpeedLimit = r.SpeedLimit,
            Destination = r.Destination,
            Referrer = r.Referrer,
            UserAgent = r.UserAgent,
            Quality = r.Quality ?? VideoQuality.Auto,
        };
    }

    public string Encode(IEnumerable<DownloadItem> items) => JsonSerializer.Serialize(items.Select(item => new Record
    {
        Id = item.Id,
        Url = item.Url,
        FileName = item.FileName,
        Folder = item.Folder,
        TotalBytes = item.TotalBytes,
        DownloadedBytes = item.DownloadedBytes,
        SpeedLimit = item.SpeedLimit,
        State = item.Status.Kind switch
        {
            StatusKind.Paused => State.Paused,
            StatusKind.Completed => State.Completed,
            StatusKind.Failed => State.Failed,
            _ => State.Active,
        },
        Error = item.Status.Kind == StatusKind.Failed ? item.Status.Message : null,
        Destination = item.Destination,
        Referrer = item.Referrer,
        UserAgent = item.UserAgent,
        Quality = item.Quality == VideoQuality.Auto ? null : item.Quality,
        Video = item.Source == DownloadSource.Video && DownloadSources.Detect(item.Url) != DownloadSource.Video ? true : null,
        PreferredName = item.PreferredName,
        CompletedAt = item.CompletedAt,
    }).ToList(), Options);

    public void Write(string json)
    {
        try
        {
            Directory.CreateDirectory(System.IO.Path.GetDirectoryName(Path)!);
            var temp = Path + ".tmp";
            File.WriteAllText(temp, json);
            File.Move(temp, Path, true);
        }
        catch (IOException) { }
    }
}
