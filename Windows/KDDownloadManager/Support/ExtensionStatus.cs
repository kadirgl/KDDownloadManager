using KDDownloadManager.Store;

namespace KDDownloadManager;

/// <summary>Whether the extension is connected in each browser (macOS: DownloadStore.extensionStatus).</summary>
public static class ExtensionStatus
{
    public enum Kind { Connected, BrowserClosed, NotConnected, Disabled, NotInstalled }
    public enum ProblemKind { NotInstalled, NotConnected }

    /// <summary>The extension says hello once a minute; a little slack before it counts as gone.</summary>
    public static readonly TimeSpan ConnectedWindow = TimeSpan.FromSeconds(150);

    public static DateTimeOffset? LastSignal(DownloadStore store, BrowserExtension.Browser browser)
    {
        if (store.ExtensionSeen.TryGetValue(browser.Name, out var seen)) return seen;
        return BrowserExtension.UnnamedBrowsers.Contains(browser.Name) && store.ExtensionSeen.TryGetValue(BrowserExtension.UnnamedBrowser, out var any) ? any : null;
    }

    public static (Kind kind, DateTimeOffset? seen) Of(DownloadStore store, BrowserExtension.Browser browser)
    {
        var seen = LastSignal(store, browser);
        var recent = seen is { } s && DateTimeOffset.Now - s < ConnectedWindow;
        var (state, written) = BrowserExtension.InstallInfo(browser);
        switch (state)
        {
            case BrowserExtension.InstallState.NotInstalled or BrowserExtension.InstallState.Disabled:
                if (recent && written is { } w && seen > w) return (Kind.Connected, seen);
                return (state == BrowserExtension.InstallState.Disabled ? Kind.Disabled : Kind.NotInstalled, seen);
            case BrowserExtension.InstallState.Unknown when seen == null:
                return (Kind.NotInstalled, seen);
        }
        if (recent) return (Kind.Connected, seen);
        return (browser.IsRunning ? Kind.NotConnected : Kind.BrowserClosed, seen);
    }

    public static ProblemKind? Problem(DownloadStore store)
    {
        var statuses = BrowserExtension.InstalledBrowsers.Select(b => Of(store, b).kind).ToList();
        if (statuses.Count == 0 || statuses.Contains(Kind.Connected)) return null;
        if (statuses.All(k => k is Kind.NotInstalled or Kind.Disabled)) return ProblemKind.NotInstalled;
        if (statuses.Contains(Kind.NotConnected)) return ProblemKind.NotConnected;
        return null;
    }
}
