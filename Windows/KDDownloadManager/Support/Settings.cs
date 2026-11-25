using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace KDDownloadManager;

/// <summary>
/// User settings (macOS: UserDefaults / SettingsKey), stored as JSON in %LOCALAPPDATA%\KDDownloadManager\settings.json.
/// Read and written on the UI thread; <see cref="Changed"/> fires after every change.
/// </summary>
public static class Settings
{
    public static event Action<string>? Changed;

    static readonly string FilePath = Path.Combine(AppFolders.Support, "settings.json");
    static readonly JsonObject Values = Load();

    static JsonObject Load()
    {
        try { return JsonNode.Parse(File.ReadAllText(FilePath)) as JsonObject ?? new JsonObject(); }
        catch { return new JsonObject(); }
    }

    static void Save()
    {
        try
        {
            var temp = FilePath + ".tmp";
            File.WriteAllText(temp, Values.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
            File.Move(temp, FilePath, true);
        }
        catch (IOException) { }
    }

    public static T Get<T>(string key, T fallback)
    {
        try { return Values[key] is { } node ? node.GetValue<T>() : fallback; }
        catch { return fallback; }
    }

    public static void Set<T>(string key, T? value)
    {
        if (value is null) Values.Remove(key); else Values[key] = JsonValue.Create(value);
        Save();
        Changed?.Invoke(key);
    }

    public static Dictionary<string, DateTimeOffset> GetDates(string key)
    {
        var result = new Dictionary<string, DateTimeOffset>();
        if (Values[key] is JsonObject obj)
            foreach (var (name, value) in obj)
                if (value is JsonValue v && v.TryGetValue<DateTimeOffset>(out var date)) result[name] = date;
        return result;
    }

    public static void SetDates(string key, Dictionary<string, DateTimeOffset> dates)
    {
        var obj = new JsonObject();
        foreach (var (name, date) in dates) obj[name] = date;
        Values[key] = obj;
        Save();
        Changed?.Invoke(key);
    }

    // Keys (same names as the macOS app).
    public const string ShowSpeedInTray = "showSpeedInMenuBar";
    public const string GlobalLimitEnabledKey = "globalLimitEnabled";
    public const string GlobalLimitMBKey = "globalLimitMB";
    public const double DefaultGlobalLimitMB = 10;
    public const string MaxConcurrentKey = "maxConcurrent";
    public const int DefaultMaxConcurrent = 3;
    public const string DownloadFolderKey = "downloadFolder";
    public const string ExtensionSeen = "extensionSeen";
    public const string NotifyOnAdd = "notifyOnAdd";
    public const string NotifyOnFinish = "notifyOnFinish";
    public const string NotifyOnFail = "notifyOnFail";
    public const string AppTheme = "appTheme";
    public const string AccentColor = "accentColor";
    public const string AccentCustomColor = "accentCustomColor";
    public const string YtDlpAutoUpdate = "ytDlpAutoUpdate";
    public const string YtDlpLastCheck = "ytDlpLastCheck";
    public const string AppAutoUpdateCheck = "appAutoUpdateCheck";
    public const string AppUpdateLastCheck = "appUpdateLastCheck";
    public const string AppUpdateAnnounced = "appUpdateAnnounced";
    public const string AppUpdateBannerDismissed = "appUpdateBannerDismissed";
    public const string OnboardingSkipped = "onboardingSkipped";
    public const string ExtensionEverConnected = "extensionEverConnected";
    public const string ExtensionBannerDismissed = "extensionBannerDismissed";
    public const string CompletedSortKey = "completedSort";
    public const string ConnectionsKey = "connections";
    public const int DefaultConnections = 8;
    public const string Language = "language";
    public const string ShortcutCreated = "startMenuShortcutCreated";

    public static string DefaultDownloadFolder
    {
        get
        {
#if DEBUG
            if (Environment.GetEnvironmentVariable("KD_DOWNLOAD_FOLDER") is { Length: > 0 } test) return test;
#endif
            try
            {
                var downloads = new Guid("374DE290-123F-4565-9164-39C4925E467B");
                if (SHGetKnownFolderPath(downloads, 0, IntPtr.Zero, out var path) == 0)
                {
                    var result = Marshal.PtrToStringUni(path)!;
                    Marshal.FreeCoTaskMem(path);
                    return result;
                }
            }
            catch { }
            return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
        }
    }

    public static string DownloadFolder
    {
        get
        {
#if DEBUG
            // Tests must not touch the real download folder.
            if (Environment.GetEnvironmentVariable("KD_DOWNLOAD_FOLDER") is { Length: > 0 } test) return test;
#endif
            return Get<string?>(DownloadFolderKey, null) ?? DefaultDownloadFolder;
        }
        set => Set(DownloadFolderKey, value);
    }

    public static int ConnectionCount => Math.Clamp(Get(ConnectionsKey, DefaultConnections), 1, 16);
    public static int MaxConcurrent => Math.Clamp(Get(MaxConcurrentKey, DefaultMaxConcurrent), 1, 10);
    public static bool GlobalLimitEnabled => Get(GlobalLimitEnabledKey, false);
    public static double GlobalLimitMB => Get(GlobalLimitMBKey, DefaultGlobalLimitMB);
    public static long? GlobalLimit => GlobalLimitEnabled ? (long)(GlobalLimitMB * 1_048_576) : null;
    public static bool Enabled(string key) => Get(key, true);

    [DllImport("shell32.dll")]
    static extern int SHGetKnownFolderPath([MarshalAs(UnmanagedType.LPStruct)] Guid id, uint flags, IntPtr token, out IntPtr path);
}

/// <summary>The app's own folders (macOS: ~/Library/Application Support/KDDownloadManager).</summary>
public static class AppFolders
{
    public static string Support { get; } = Created(
#if DEBUG
        Environment.GetEnvironmentVariable("KD_SUPPORT_DIR") is { Length: > 0 } test ? test :
#endif
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "KDDownloadManager"));

    public static string Torrents => Created(Path.Combine(Support, "Torrents"));
    public static string Caches => Created(Path.Combine(Support, "Cache"));

    /// <summary>Folder of the running app (KDDownloadManager.exe).</summary>
    public static string AppDir => AppContext.BaseDirectory;

    /// <summary>Installed by the setup (Windows/installer), not unpacked from a zip: its uninstaller sits next to the exe.</summary>
    public static bool IsInstalled => File.Exists(Path.Combine(AppDir, "unins000.exe"));

    static string Created(string path)
    {
        Directory.CreateDirectory(path);
        return path;
    }
}
