using System.Diagnostics;
using System.IO.Compression;
using System.Security.Cryptography;
using System.Text.Json.Nodes;

namespace KDDownloadManager;

/// <summary>
/// Keeps yt-dlp current (YouTube changes often) from yt-dlp's official GitHub releases (macOS: YtDlpUpdater).
/// The new version (onedir zip for this architecture) goes to %LOCALAPPDATA%\KDDownloadManager\yt-dlp\&lt;version&gt;,
/// is checked against the release's SHA2-256SUMS and must report the expected version before it is used.
/// </summary>
public sealed class YtDlpUpdater
{
    public abstract record UpdateState
    {
        public sealed record Idle : UpdateState;
        public sealed record Checking : UpdateState;
        public sealed record Downloading(string Version) : UpdateState;
        public sealed record UpToDate : UpdateState;
        public sealed record Updated(string Version) : UpdateState;
        public sealed record Failed(string Message) : UpdateState;
    }

    public static readonly YtDlpUpdater Shared = new();
    public event Action? Changed;

    UpdateState state = new UpdateState.Idle();
    public UpdateState State { get => state; private set { state = value; Changed?.Invoke(); } }
    public DateTimeOffset? LastCheck { get; private set; } = Settings.Get<DateTimeOffset?>(Settings.YtDlpLastCheck, null);

    static string Root => Path.Combine(AppFolders.Support, "yt-dlp");
    static string CurrentFile => Path.Combine(Root, "current.version");
    static string AssetName => AppUpdater.Architecture == "arm64" ? "yt-dlp_win_arm64.zip" : "yt-dlp_win.zip";

    static string? ReadVersion(string file)
    {
        try { return File.ReadAllText(file).Trim(); } catch { return null; }
    }

    public static string? BundledVersion => ReadVersion(Path.Combine(Tools.BundledFolder, "yt-dlp.version"));
    static string? DownloadedVersion => ReadVersion(CurrentFile);

    /// <summary>The downloaded yt-dlp if it is newer than the bundled one.</summary>
    public static string? PreferredBinary()
    {
        if (DownloadedVersion is not { } downloaded) return null;
        if (BundledVersion is { } bundled && !AppUpdater.IsNewer(downloaded, bundled)) return null;
        var exe = Path.Combine(Root, downloaded, "yt-dlp.exe");
        return File.Exists(exe) ? exe : null;
    }

    public string CurrentVersion => PreferredBinary() != null ? DownloadedVersion! : BundledVersion ?? "?";
    public bool IsUpdated => PreferredBinary() != null;

    public static void RemoveOldVersions()
    {
        if (!Directory.Exists(Root)) return;
        var keep = DownloadedVersion;
        foreach (var dir in Directory.GetDirectories(Root))
            if (Path.GetFileName(dir) != keep) try { Directory.Delete(dir, true); } catch { }
    }

    public async void CheckAutomaticallyIfDue()
    {
        if (!Settings.Get(Settings.YtDlpAutoUpdate, true)) return;
        if (LastCheck is { } last && DateTimeOffset.Now - last < TimeSpan.FromHours(24)) return;
        await Check();
    }

    static readonly HttpClient Http = CreateClient();

    static HttpClient CreateClient()
    {
        var client = new HttpClient { Timeout = TimeSpan.FromMinutes(5) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("KDDownloadManager-Windows");
        return client;
    }

    public async Task Check()
    {
        if (State is UpdateState.Checking or UpdateState.Downloading) return;
        State = new UpdateState.Checking();
        try
        {
            var request = new HttpRequestMessage(HttpMethod.Get, "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest");
            request.Headers.Accept.ParseAdd("application/vnd.github+json");
            using var response = await Http.SendAsync(request);
            response.EnsureSuccessStatusCode();
            var latest = JsonNode.Parse(await response.Content.ReadAsStringAsync())?["tag_name"]?.GetValue<string>()
                ?? throw new InvalidOperationException(L.T("Güncelleme bilgisi okunamadı"));
            LastCheck = DateTimeOffset.Now;
            Settings.Set(Settings.YtDlpLastCheck, LastCheck);
            if (!AppUpdater.IsNewer(latest, CurrentVersion))
            {
                State = new UpdateState.UpToDate();
                return;
            }
            State = new UpdateState.Downloading(latest);
            await Install(latest);
            State = new UpdateState.Updated(latest);
        }
        catch (Exception error)
        {
            State = new UpdateState.Failed(error.Message);
        }
    }

    static async Task Install(string version)
    {
        var release = $"https://github.com/yt-dlp/yt-dlp/releases/download/{version}/";
        var sums = await Http.GetStringAsync(release + "SHA2-256SUMS");
        var expected = sums.Split('\n').Select(l => l.Split(' ', StringSplitOptions.RemoveEmptyEntries))
            .FirstOrDefault(p => p.Length == 2 && p[1] == AssetName)?[0]
            ?? throw new InvalidOperationException(L.T("İndirilen yt-dlp doğrulanamadı"));
        var zip = await Http.GetByteArrayAsync(release + AssetName);
        if (!Convert.ToHexString(SHA256.HashData(zip)).Equals(expected, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException(L.T("İndirilen yt-dlp doğrulanamadı"));
        var target = Path.Combine(Root, version);
        var staging = target + ".new";
        await Task.Run(() =>
        {
            if (Directory.Exists(staging)) Directory.Delete(staging, true);
            new ZipArchive(new MemoryStream(zip)).ExtractToDirectory(staging);
        });
        // The zip holds yt-dlp.exe and _internal\ (possibly inside a folder).
        var exe = Directory.GetFiles(staging, "yt-dlp*.exe", SearchOption.AllDirectories).FirstOrDefault()
            ?? throw new InvalidOperationException(L.T("İndirilen yt-dlp açılamadı"));
        var home = Path.GetDirectoryName(exe)!;
        if (Path.GetFileName(exe) != "yt-dlp.exe") File.Move(exe, Path.Combine(home, "yt-dlp.exe"));
        if (await ReportedVersion(Path.Combine(home, "yt-dlp.exe")) != version)
            throw new InvalidOperationException(L.T("İndirilen yt-dlp açılamadı"));
        if (Directory.Exists(target)) Directory.Delete(target, true);
        Directory.Move(home, target);
        if (Directory.Exists(staging)) Directory.Delete(staging, true);
        await File.WriteAllTextAsync(CurrentFile, version);
    }

    static async Task<string?> ReportedVersion(string exe)
    {
        try
        {
            using var process = ProcessJob.Start(Tools.StartInfo(exe, ["--version"]));
            var output = await process.StandardOutput.ReadToEndAsync();
            await process.WaitForExitAsync();
            return output.Trim();
        }
        catch { return null; }
    }
}
