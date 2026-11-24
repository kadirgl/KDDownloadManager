using System.Diagnostics;
using System.Text.Json.Nodes;
using Microsoft.Win32;

namespace KDDownloadManager;

/// <summary>
/// Installing the browser extension (macOS: BrowserExtension). Chromium browsers (Chrome, Edge, Brave, Vivaldi,
/// Opera) all use the same extension, with the same ID thanks to the manifest's "key". The app copies the bundled
/// extension to %LOCALAPPDATA%\KDDownloadManager\BrowserExtension, which the user loads as an unpacked extension;
/// the copy is refreshed when the app updates and the extension reloads itself on a version change.
/// </summary>
public static class BrowserExtension
{
    public sealed record Browser(string Name, string Exe, string ProcessName, string ExtensionsPage, string DataFolder)
    {
        public bool IsRunning => Process.GetProcessesByName(ProcessName).Length > 0;
    }

    public const string ExtensionId = "necbfaijhfnnoikbppjdjcpfjekefdbk";

    static readonly string Local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
    static readonly string Roaming = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);

    static readonly (string name, string exe, string page, string data)[] Candidates =
    [
        ("Google Chrome", "chrome.exe", "chrome://extensions", Path.Combine(Local, @"Google\Chrome\User Data")),
        ("Microsoft Edge", "msedge.exe", "edge://extensions", Path.Combine(Local, @"Microsoft\Edge\User Data")),
        ("Brave", "brave.exe", "brave://extensions", Path.Combine(Local, @"BraveSoftware\Brave-Browser\User Data")),
        ("Vivaldi", "vivaldi.exe", "vivaldi://extensions", Path.Combine(Local, @"Vivaldi\User Data")),
        ("Opera", "opera.exe", "opera://extensions", Path.Combine(Roaming, @"Opera Software\Opera Stable")),
        ("Chromium", "chrome.exe", "chrome://extensions", Path.Combine(Local, @"Chromium\User Data")),
    ];

    /// <summary>Browsers that report themselves without a brand name.</summary>
    public const string UnnamedBrowser = "Chromium tabanlı tarayıcı";
    public static readonly HashSet<string> UnnamedBrowsers = ["Vivaldi", "Chromium"];

    static (DateTimeOffset date, List<Browser> browsers)? cache;

    public static List<Browser> InstalledBrowsers
    {
        get
        {
            if (cache is { } c && DateTimeOffset.Now - c.date < TimeSpan.FromSeconds(30)) return c.browsers;
            var browsers = new List<Browser>();
            foreach (var (name, exe, page, data) in Candidates)
            {
                var path = name == "Chromium" ? (Directory.Exists(data) ? FindExe(exe) : null) : FindExe(exe);
                if (name == "Google Chrome" && path != null && !Directory.Exists(Path.Combine(Local, @"Google\Chrome")) && path.Contains("Chromium")) path = null;
                if (path != null && !browsers.Any(b => b.Exe == path))
                    browsers.Add(new Browser(name, path, Path.GetFileNameWithoutExtension(exe), page, data));
            }
            cache = (DateTimeOffset.Now, browsers);
            return browsers;
        }
    }

    static string? FindExe(string exe)
    {
        foreach (var hive in new[] { Registry.CurrentUser, Registry.LocalMachine })
        {
            using var key = hive.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\App Paths\" + exe);
            if (key?.GetValue(null) is string path && File.Exists(path.Trim('"'))) return path.Trim('"');
        }
        return null;
    }

    public enum InstallState { Installed, Disabled, NotInstalled, Unknown }

    /// <summary>
    /// Whether the browser profile's (Secure) Preferences list the extension. These are settings files, not the
    /// cookie store; only the extension's own entry is looked at.
    /// </summary>
    public static (InstallState state, DateTimeOffset? written) InstallInfo(Browser browser)
    {
        if (!Directory.Exists(browser.DataFolder)) return (InstallState.Unknown, null);
        var profiles = new List<string> { browser.DataFolder };
        try
        {
            profiles.AddRange(Directory.GetDirectories(browser.DataFolder)
                .Where(d => Path.GetFileName(d) == "Default" || Path.GetFileName(d).StartsWith("Profile ")));
        }
        catch { }
        var readAny = false;
        var found = InstallState.NotInstalled;
        DateTimeOffset? written = null;
        foreach (var profile in profiles)
        {
            foreach (var file in new[] { "Secure Preferences", "Preferences" })
            {
                if (ExtensionSettings(Path.Combine(profile, file)) is not { } entry) continue;
                readAny = true;
                written = written is { } w && w > entry.modified ? w : entry.modified;
                if (entry.settings[ExtensionId] is not JsonObject ext || (ext["path"] == null && ext["location"] == null)) continue;
                if (IsDisabled(ext)) { if (found == InstallState.NotInstalled) found = InstallState.Disabled; }
                else return (InstallState.Installed, written);
            }
        }
        return (readAny ? found : InstallState.Unknown, written);
    }

    static bool IsDisabled(JsonObject entry)
    {
        if (entry["state"] is JsonValue s && s.TryGetValue<int>(out var state) && state == 0) return true;
        if (entry["disable_reasons"] is JsonValue r && r.TryGetValue<int>(out var reasons)) return reasons != 0;
        if (entry["disable_reasons"] is JsonArray list) return list.Count > 0;
        return false;
    }

    static readonly Dictionary<string, (DateTimeOffset modified, JsonObject settings)> parsed = new();

    static (JsonObject settings, DateTimeOffset modified)? ExtensionSettings(string file)
    {
        try
        {
            if (!File.Exists(file)) return null;
            DateTimeOffset modified = File.GetLastWriteTimeUtc(file);
            if (parsed.TryGetValue(file, out var cached) && cached.modified == modified) return (cached.settings, modified);
            using var stream = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            var settings = (JsonNode.Parse(stream)?["extensions"]?["settings"] as JsonObject) ?? new JsonObject();
            parsed[file] = (modified, settings);
            return (settings, modified);
        }
        catch { return null; }
    }

    /// <summary>The folder the browser loads (unpacked).</summary>
    public static string Folder => Path.Combine(AppFolders.Support, "BrowserExtension");

    /// <summary>The extension shipped with the app (next to the exe), or the repository's copy in a dev build.</summary>
    static string? Source
    {
        get
        {
            var bundled = Path.Combine(AppFolders.AppDir, "BrowserExtension");
            if (File.Exists(Path.Combine(bundled, "manifest.json"))) return bundled;
#if DEBUG
            for (var dir = new DirectoryInfo(AppFolders.AppDir); dir != null; dir = dir.Parent)
            {
                var repo = Path.Combine(dir.FullName, "ChromeExtension");
                if (File.Exists(Path.Combine(repo, "manifest.json"))) return repo;
            }
#endif
            return null;
        }
    }

    public static bool RefreshFolder()
    {
        if (Source is not { } source) return false;
        if (Version(Folder) is { } current && current == Version(source)) return true;
        try
        {
            var staging = Folder + ".new";
            if (Directory.Exists(staging)) Directory.Delete(staging, true);
            CopyDirectory(source, staging);
            if (Directory.Exists(Folder)) Directory.Delete(Folder, true);
            Directory.Move(staging, Folder);
            return true;
        }
        catch { return false; }
    }

    static void CopyDirectory(string from, string to)
    {
        Directory.CreateDirectory(to);
        foreach (var file in Directory.GetFiles(from)) File.Copy(file, Path.Combine(to, Path.GetFileName(file)), true);
        foreach (var dir in Directory.GetDirectories(from)) CopyDirectory(dir, Path.Combine(to, Path.GetFileName(dir)));
    }

    public static string? InstalledVersion => Version(Folder);

    static string? Version(string folder)
    {
        try { return JsonNode.Parse(File.ReadAllText(Path.Combine(folder, "manifest.json")))?["version"]?.GetValue<string>(); }
        catch { return null; }
    }

    /// <summary>Prepares the folder, copies its path, shows it in Explorer and opens the browser's extensions page.</summary>
    public static bool BeginInstall(Browser browser)
    {
        if (!RefreshFolder()) return false;
        Shell.Copy(Folder);
        Shell.Reveal(Folder, Folder);
        try { Process.Start(new ProcessStartInfo(browser.Exe) { ArgumentList = { browser.ExtensionsPage } }); } catch { }
        return true;
    }
}
