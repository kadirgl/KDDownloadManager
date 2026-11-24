using System.Text;
using KDDownloadManager.Models;

namespace KDDownloadManager;

/// <summary>
/// Cookies of video sites sent by the browser extension, for yt-dlp (YouTube's bot check). Kept in memory only;
/// yt-dlp gets a temporary file that only the current user can read and that is deleted when the run ends.
/// </summary>
public sealed class CookieVault
{
    public static readonly CookieVault Shared = new();

    readonly Dictionary<string, (DateTimeOffset date, List<BrowserCookie> cookies)> jars = new();
    readonly HashSet<string> wanted = new();
    readonly List<Action<string>> observers = new();
    static readonly TimeSpan Freshness = TimeSpan.FromMinutes(20);

    public void Store(List<BrowserCookie> cookies, string site)
    {
        if (cookies.Count == 0) return;
        var sorted = cookies.OrderBy(c => c.Domain).ThenBy(c => c.Path).ThenBy(c => c.Name, StringComparer.Ordinal).ToList();
        var changed = !jars.TryGetValue(site, out var old) || !old.cookies.SequenceEqual(sorted);
        jars[site] = (DateTimeOffset.Now, sorted);
        wanted.Remove(site);
        if (changed) foreach (var observer in observers) observer(site);
    }

    public List<BrowserCookie>? CookiesFor(string url) => Site(url) is { } site && jars.TryGetValue(site, out var jar) ? jar.cookies : null;

    public void RequestIfNeeded(string url)
    {
        if (!DownloadSources.IsKnownVideoSite(url) || Site(url) is not { } site) return;
        if (jars.TryGetValue(site, out var jar) && DateTimeOffset.Now - jar.date < Freshness) return;
        wanted.Add(site);
    }

    public void RequestFresh(string url)
    {
        if (DownloadSources.IsKnownVideoSite(url) && Site(url) is { } site) wanted.Add(site);
    }

    public IReadOnlyList<string> WantedSites => wanted.Order().ToList();

    public void Observe(Action<string> handler) => observers.Add(handler);

    public static string? Site(string url)
    {
        if (DownloadSources.Host(url) is not { } host) return null;
        var known = DownloadSources.VideoHosts.FirstOrDefault(h => host == h || host.EndsWith("." + h));
        if (known != null) return known == "youtu.be" ? "youtube.com" : known;
        return host.StartsWith("www.") ? host[4..] : host;
    }

    /// <summary>Netscape cookie file for yt-dlp; readable only by the current user (inherits the profile ACL).</summary>
    public static void WriteNetscapeFile(List<BrowserCookie> cookies, string path)
    {
        var lines = new StringBuilder("# Netscape HTTP Cookie File\n");
        foreach (var c in cookies)
        {
            var includeSubdomains = c.HostOnly == false || c.Domain.StartsWith('.');
            var domain = (c.HttpOnly == true ? "#HttpOnly_" : "") + c.Domain;
            var expiry = c.ExpirationDate is { } e ? ((long)e).ToString() : "0";
            string[] fields = [domain, includeSubdomains ? "TRUE" : "FALSE", c.Path, c.Secure ? "TRUE" : "FALSE", expiry, c.Name, c.Value];
            if (fields.Any(f => f.Contains('\t') || f.Contains('\n'))) continue;
            lines.Append(string.Join('\t', fields)).Append('\n');
        }
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, lines.ToString(), new UTF8Encoding(false));
    }
}
