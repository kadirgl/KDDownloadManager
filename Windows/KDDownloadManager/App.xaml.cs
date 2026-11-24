using DispatcherQueueTimer = Microsoft.UI.Dispatching.DispatcherQueueTimer;
using System.Diagnostics;
using System.Runtime.InteropServices;
using KDDownloadManager.Bridge;
using KDDownloadManager.Engine;
using KDDownloadManager.Models;
using KDDownloadManager.Store;
using KDDownloadManager.Tray;
using KDDownloadManager.Views;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.Windows.AppLifecycle;
using Windows.Graphics;

namespace KDDownloadManager;

/// <summary>
/// The app lives in the notification area (macOS: AppDelegate + StatusItemController). The list, the engines and the
/// browser bridge run as soon as the app starts, whether or not the panel is ever opened.
/// </summary>
public partial class App : Application
{
    public static DispatcherQueue Ui { get; private set; } = null!;
    public static new App Current => (App)Application.Current;
    public static IntPtr PanelHandle => Current.panel?.Handle ?? IntPtr.Zero;

    DownloadStore store = null!;
    ExtensionBridge? bridge;
    TrayIcon tray = null!;
    PanelWindow? panel;
    DateTimeOffset? closedByDeactivationAt;
    int keepOpen;
    TrayIcon.IconState? iconState;
    DispatcherQueueTimer? doneTimer;
    readonly string[] arguments;
    bool quitting;

    public App(string[] arguments)
    {
        this.arguments = arguments;
        InitializeComponent();
        UnhandledException += (_, e) =>
        {
            Log("Unhandled: " + e.Exception + " | " + e.Message);
            e.Handled = true;
        };
        if (Environment.GetEnvironmentVariable("KD_TRACE") != null || File.Exists(Path.Combine(AppFolders.Support, "trace")))
            AppDomain.CurrentDomain.FirstChanceException += (_, e) => Log("First chance: " + e.Exception.GetType().Name + ": " + e.Exception.Message + "\n" + Environment.StackTrace);
        AppDomain.CurrentDomain.UnhandledException += (_, e) => Log("Domain: " + e.ExceptionObject);
        TaskScheduler.UnobservedTaskException += (_, e) => { Log("Task: " + e.Exception); e.SetObserved(); };
        DebugSettings.XamlResourceReferenceFailed += (_, e) => Log("Resource: " + e.Message);
        DebugSettings.BindingFailed += (_, e) => Log("Binding: " + e.Message);
    }

    /// <summary>
    /// Errors that would otherwise go unnoticed (%LOCALAPPDATA%\KDDownloadManager\app.log, kept under 1 MB).
    /// An empty file named "trace" next to it also logs every first-chance exception, for diagnosing crashes.
    /// </summary>
    public static void Log(string message)
    {
        try
        {
            var path = Path.Combine(AppFolders.Support, "app.log");
            if (File.Exists(path) && new FileInfo(path).Length > 1_000_000) File.Move(path, path + ".old", true);
            File.AppendAllText(path, $"{DateTimeOffset.Now:u} {message}\n");
        }
        catch { }
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        Ui = DispatcherQueue.GetForCurrentThread();
        Notifier.SetUp();
        Notifier.OpenPanelRequested += () => OpenPanel();

        var engine = new RoutingEngine(new Aria2Engine(), new YtDlpEngine());
        store = new DownloadStore(engine, DownloadArchive.Standard);

        tray = new TrayIcon();
        tray.Clicked += () => Views.Ui.Guard(TogglePanel);
        tray.ContextMenuRequested += (x, y) => Views.Ui.Guard(() => ShowTrayMenu(x, y));
        tray.NeedsRedraw += () => { iconState = null; Views.Ui.Guard(UpdateIcon); };
        string? balloonFile = null;
        Notifier.Fallback = (title, body, silent, file) =>
        {
            balloonFile = file;
            tray.ShowBalloon(title, body, silent);
        };
        tray.BalloonClicked += () => Views.Ui.Guard(() =>
        {
            if (balloonFile != null && File.Exists(balloonFile)) Shell.Reveal(balloonFile, Path.GetDirectoryName(balloonFile)!);
            else OpenPanel();
        });
        store.ItemsChanged += UpdateIcon;
        store.PropertyChanged += (_, e) => { if (e.PropertyName == nameof(DownloadStore.DisplaySpeed)) UpdateIcon(); };
        Settings.Changed += key => { if (key == Settings.ShowSpeedInTray) UpdateIcon(); };
        UpdateIcon();

        bridge = new ExtensionBridge(requests => store.Add(requests), browser => store.ExtensionDidConnect(browser));
        bridge.Start();

        YtDlpUpdater.RemoveOldVersions();
        VideoFormats.WarmUp();
        YtDlpUpdater.Shared.CheckAutomaticallyIfDue();
        AppUpdater.Shared.StartAutomaticChecks();
        if (Directory.Exists(BrowserExtension.Folder)) BrowserExtension.RefreshFolder();
        StartMenu.EnsureShortcut();
        LaunchAtLogin.Refresh();

        var activation = AppInstance.GetCurrent().GetActivatedEventArgs();
        if (activation.Kind == ExtendedActivationKind.AppNotification
            && activation.Data is Microsoft.Windows.AppNotifications.AppNotificationActivatedEventArgs toast)
        {
            Notifier.Handle(toast.Arguments);
        }
        else
        {
            var links = arguments.Where(IsOpenable).ToList();
            if (links.Count > 0) store.Open(links);
            // Started by hand (not at sign-in, not for a link): show the panel so the user sees the app is running.
            else if (!arguments.Contains("--background")) OpenPanel();
        }
    }

    /// <summary>A second launch (Start menu, a magnet link, a .torrent file, a toast) is redirected here.</summary>
    public void OnRedirected(AppActivationArguments activation)
    {
        Ui.TryEnqueue(() => Views.Ui.Guard(() =>
        {
            switch (activation.Kind)
            {
                case ExtendedActivationKind.AppNotification when activation.Data is Microsoft.Windows.AppNotifications.AppNotificationActivatedEventArgs toast:
                    Notifier.Handle(toast.Arguments);
                    break;
                case ExtendedActivationKind.Launch when activation.Data is Windows.ApplicationModel.Activation.ILaunchActivatedEventArgs launch:
                    // The command line of an unpackaged app starts with the exe's own path: keep only links and .torrent files.
                    var links = Program.SplitCommandLine(launch.Arguments).Where(IsOpenable).ToList();
                    if (links.Count > 0) store.Open(links);
                    else OpenPanel();
                    break;
                default:
                    OpenPanel();
                    break;
            }
        }));
    }

    static bool IsOpenable(string argument) =>
        DownloadSources.LooksLikeLink(argument) || argument.EndsWith(".torrent", StringComparison.OrdinalIgnoreCase);

    // MARK: Panel

    PanelWindow Panel()
    {
        if (panel != null) return panel;
        panel = new PanelWindow(store);
        panel.Deactivated += () =>
        {
            if (keepOpen > 0) return;
            panel.Hide();
            closedByDeactivationAt = DateTimeOffset.Now;
        };
        return panel;
    }

    /// <summary>
    /// Clicking the tray icon while the panel is open closes it. The click first activates the taskbar, which
    /// hides the panel (deactivation); the icon's click message comes right after and must not reopen it.
    /// </summary>
    void TogglePanel()
    {
        if (panel?.IsOpen == true) panel.Hide();
        else if (closedByDeactivationAt is { } closed && DateTimeOffset.Now - closed < TimeSpan.FromMilliseconds(500))
            closedByDeactivationAt = null;
        else OpenPanel();
    }

    public void OpenPanel()
    {
        var window = Panel();
        if (window.IsOpen)
        {
            TrayIcon.SetForegroundWindow(window.Handle);
            return;
        }
        GetCursorPos(out var cursor);
        window.Open(new TrayIconPlacement(tray.Bounds(), new PointInt32(cursor.X, cursor.Y)));
    }

    /// <summary>While a file/folder picker is open the panel must not hide when it loses focus.</summary>
    public static IDisposable KeepPanelOpen()
    {
        Current.keepOpen++;
        return new Releaser(() => Current.keepOpen--);
    }

    sealed class Releaser(Action release) : IDisposable
    {
        public void Dispose() => release();
    }

    void ShowTrayMenu(int x, int y)
    {
        var chosen = tray.ShowMenu(x, y,
        [
            (1, L.T("Paneli aç"), false),
            (2, L.T("Link ekle"), false),
            (3, L.T("Ayarlar"), false),
            (4, store.AllActivePaused ? L.T("Tümünü devam ettir") : L.T("Tümünü duraklat"), true),
            (5, L.T("İndirme klasörünü aç"), false),
            (6, L.T("Çıkış"), true),
        ]);
        switch (chosen)
        {
            case 1: store.Route = Route.List; OpenPanel(); break;
            case 2: store.Route = Route.AddLink; OpenPanel(); break;
            case 3: store.Route = Route.Settings; OpenPanel(); break;
            case 4: if (store.AllActivePaused) store.ResumeAll(); else store.PauseAll(); break;
            case 5: Shell.OpenFolder(Settings.DownloadFolder); break;
            case 6: Quit(); break;
        }
    }

    // MARK: Tray icon

    void UpdateIcon()
    {
        TrayIcon.IconState state;
        var step = 0;
        var running = store.Items.Where(i => i.Status.IsRunning).ToList();
        if (store.HasFailures) state = TrayIcon.IconState.Error;
        else if (running.Count > 0)
        {
            var sized = running.Where(i => i.TotalBytes > 0).ToList();
            var total = sized.Sum(i => i.TotalBytes);
            var done = sized.Sum(i => Math.Min(i.DownloadedBytes, i.TotalBytes));
            state = TrayIcon.IconState.Progress;
            step = total > 0 ? (int)Math.Floor((double)done / total * 36) : 0;
        }
        else if (store.FinishedAt is { } finished && DateTimeOffset.Now - finished < TimeSpan.FromSeconds(3))
        {
            state = TrayIcon.IconState.Done;
            doneTimer ??= Ui.CreateTimer();
            doneTimer.Interval = TimeSpan.FromSeconds(3.1) - (DateTimeOffset.Now - finished);
            doneTimer.IsRepeating = false;
            doneTimer.Tick -= DoneTick;
            doneTimer.Tick += DoneTick;
            doneTimer.Start();
        }
        else state = TrayIcon.IconState.Idle;

        var tip = state switch
        {
            TrayIcon.IconState.Error => L.T("KD Download Manager, indirme hatası var"),
            TrayIcon.IconState.Done => L.T("KD Download Manager, indirmeler tamamlandı"),
            TrayIcon.IconState.Progress => L.F("KD Download Manager, yüzde %lld indi", step * 100 / 36),
            _ => "KD Download Manager",
        };
        if (Settings.Get(Settings.ShowSpeedInTray, true) && store.DisplaySpeed > 0) tip += "\n↓ " + ByteFormat.Speed(store.DisplaySpeed);
        iconState = state;
        tray.Update(state, step, tip);
    }

    void DoneTick(DispatcherQueueTimer sender, object args) => Views.Ui.Guard(UpdateIcon);

    // MARK: Quit and relaunch

    public static void Quit()
    {
        var app = Current;
        if (app.quitting) return;
        app.quitting = true;
        app.panel?.Hide();
        app.bridge?.Stop();
        app.store.Shutdown();
        app.tray.Dispose();
        Notifier.TearDown();
        Program.ReleaseInstance();
        app.Exit();
        Environment.Exit(0);
    }

    /// <summary>Restarts the app (language change): a new copy starts once this one has exited.</summary>
    public static void Relaunch()
    {
        var exe = Environment.ProcessPath!;
        var script = $"$p = {Environment.ProcessId}; for ($i = 0; $i -lt 300 -and (Get-Process -Id $p -ErrorAction SilentlyContinue); $i++) {{ Start-Sleep -Milliseconds 200 }}; Start-Process -FilePath '{exe.Replace("'", "''")}'";
        Process.Start(new ProcessStartInfo("powershell.exe")
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            ArgumentList = { "-NoProfile", "-WindowStyle", "Hidden", "-Command", script },
        });
        Quit();
    }

    [StructLayout(LayoutKind.Sequential)] struct POINT { public int X, Y; }
    [DllImport("user32.dll")] static extern bool GetCursorPos(out POINT point);
}
