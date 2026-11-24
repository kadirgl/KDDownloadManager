using KDDownloadManager.Models;
using Microsoft.Windows.AppNotifications;
using Microsoft.Windows.AppNotifications.Builder;

namespace KDDownloadManager;

/// <summary>
/// "Download added / finished / failed" toasts through the Windows App SDK (macOS: Notifier). Clicking a finished
/// download's toast shows the file in File Explorer; the others open the panel.
/// </summary>
public static class Notifier
{
    public static bool IsAvailable { get; private set; }
    public static event Action? OpenPanelRequested;

    public static void SetUp()
    {
        try
        {
            AppNotificationManager.Default.NotificationInvoked += (_, args) => Handle(args.Arguments);
            AppNotificationManager.Default.Register();
            IsAvailable = true;
        }
        catch (Exception error)
        {
            System.Diagnostics.Debug.WriteLine("Notifications unavailable: " + error.Message);
        }
    }

    public static void TearDown()
    {
        if (!IsAvailable) return;
        try { AppNotificationManager.Default.Unregister(); } catch { }
    }

    /// <summary>Also used when the app was launched by clicking a toast.</summary>
    public static void Handle(IDictionary<string, string> arguments)
    {
        var file = arguments.TryGetValue("reveal", out var value) && value.Length > 0 ? value : null;
        App.Ui.TryEnqueue(() => Views.Ui.Guard(() =>
        {
            if (file != null && (File.Exists(file) || Directory.Exists(file))) Shell.Reveal(file, Path.GetDirectoryName(file)!);
            else OpenPanelRequested?.Invoke();
        }));
    }

    public static void DownloadsAdded(List<string> names)
    {
        if (!Settings.Enabled(Settings.NotifyOnAdd) || names.Count == 0) return;
        var title = names.Count == 1 ? L.T("İndirme eklendi") : L.F("%lld indirme eklendi", names.Count);
        Post(title, string.Join(", ", names.Take(3)) + (names.Count > 3 ? "…" : ""), null, silent: true);
    }

    public static void DownloadFinished(DownloadItem item)
    {
        if (!Settings.Enabled(Settings.NotifyOnFinish)) return;
        Post(L.T("İndirme tamamlandı"), item.FileName, item.Destination, silent: false);
    }

    public static void DownloadFailed(DownloadItem item, string message)
    {
        if (!Settings.Enabled(Settings.NotifyOnFail)) return;
        Post(L.T("İndirme başarısız"), $"{item.FileName}\n{message}", null, silent: false);
    }

    public static void UpdateAvailable(string version) =>
        Post(L.F("Yeni sürüm: %@", version), L.T("KD Download Manager'ı güncellemek için tıklayın."), null, silent: true);

    static void Post(string title, string body, string? file, bool silent)
    {
        System.Diagnostics.Debug.WriteLine($"[notification] {title}: {body}");
        if (!IsAvailable) return;
        try
        {
            var builder = new AppNotificationBuilder()
                .AddArgument("reveal", file ?? "")
                .AddText(title)
                .AddText(body);
            if (silent) builder.MuteAudio();
            AppNotificationManager.Default.Show(builder.BuildNotification());
        }
        catch { }
    }
}
