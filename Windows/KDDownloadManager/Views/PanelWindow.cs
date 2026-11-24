using System.Runtime.InteropServices;
using KDDownloadManager.Store;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Windows.Graphics;
using Windows.System;
using WinRT.Interop;

namespace KDDownloadManager.Views;

/// <summary>
/// The compact panel that opens from the tray icon (macOS: the glass NSPanel in StatusItemController):
/// borderless, acrylic, always on top, not in the taskbar or Alt+Tab, next to the tray icon. It hides when
/// another window is activated. Shows one screen at a time depending on <see cref="DownloadStore.Route"/>.
/// </summary>
public sealed class PanelWindow : Window
{
    readonly DownloadStore store;
    readonly Grid root = new();
    readonly Border host = new();
    public IntPtr Handle { get; }
    public event Action? Deactivated;
    public bool IsOpen { get; private set; }

    public PanelWindow(DownloadStore store)
    {
        this.store = store;
        Title = "KD Download Manager";
        Handle = WindowNative.GetWindowHandle(this);
        ExtendsContentIntoTitleBar = true;
        SystemBackdrop = new DesktopAcrylicBackdrop();

        var presenter = OverlappedPresenter.Create();
        presenter.IsResizable = false;
        presenter.IsMaximizable = false;
        presenter.IsMinimizable = false;
        presenter.IsAlwaysOnTop = true;
        presenter.SetBorderAndTitleBar(true, false);
        AppWindow.SetPresenter(presenter);
        AppWindow.IsShownInSwitchers = false;
        AppWindow.SetIcon(Path.Combine(AppFolders.AppDir, "Assets", "app.ico"));
        var corner = 2; // DWMWCP_ROUND
        DwmSetWindowAttribute(Handle, 33, ref corner, sizeof(int));

        root.RequestedTheme = Theme.ElementTheme;
        root.Children.Add(host);
        root.AllowDrop = true;
        root.DragOver += (_, e) => e.AcceptedOperation = Windows.ApplicationModel.DataTransfer.DataPackageOperation.Copy;
        root.Drop += OnDrop;
        root.KeyDown += OnKeyDown;
        Content = root;

        Activated += (_, e) =>
        {
            if (e.WindowActivationState == WindowActivationState.Deactivated && IsOpen) Deactivated?.Invoke();
        };
        AppWindow.Closing += (_, e) =>
        {
            // Alt+F4 hides the panel; the app keeps running in the tray.
            e.Cancel = true;
            Hide();
        };
        store.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(DownloadStore.Route)) ShowRoute();
        };
        Settings.Changed += key =>
        {
            if (key is Settings.AppTheme) root.RequestedTheme = Theme.ElementTheme;
            if (key is Settings.AccentColor or Settings.AccentCustomColor or Settings.AppTheme) Rebuild();
        };
    }

    /// <summary>Rebuilds the current screen (theme or accent changed).</summary>
    public void Rebuild()
    {
        if (IsOpen) ShowRoute();
    }

    void ShowRoute()
    {
        if (!IsOpen) return;
        try
        {
            host.Child = store.Route switch
            {
                Route.AddLink => new AddLinkPage(store),
                Route.Settings => new SettingsPage(store),
                Route.Onboarding => new OnboardingPage(store),
                _ => new ListPage(store),
            };
        }
        catch (Exception e) { App.Log("Screen failed: " + e); }
    }

    public void Open(TrayIconPlacement placement)
    {
        store.PanelWillOpen();
        store.PanelVisible = true;
        IsOpen = true;
        ShowRoute();
        Place(placement);
        AppWindow.Show(true);
        Activate();
        Tray.TrayIcon.SetForegroundWindow(Handle);
        // Focus the content so the keyboard shortcuts work right away.
        if (host.Child is Control control) control.Focus(FocusState.Programmatic);
        else root.Focus(FocusState.Programmatic);
    }

    public void Hide()
    {
        if (!IsOpen) return;
        IsOpen = false;
        store.PanelVisible = false;
        AppWindow.Hide();
        // Do not keep the screens (and their timers) alive while hidden.
        host.Child = null;
    }

    void Place(TrayIconPlacement placement)
    {
        var anchor = placement.IconRect;
        var point = anchor is { } r ? new PointInt32((r.Left + r.Right) / 2, (r.Top + r.Bottom) / 2) : placement.Cursor;
        var area = DisplayArea.GetFromPoint(point, DisplayAreaFallback.Primary);
        var work = area.WorkArea;
        var outer = area.OuterBounds;
        var scale = DpiAt(point) / 96.0;
        var gap = (int)(12 * scale);
        var width = (int)(Theme.PanelWidth * scale);
        var height = Math.Min((int)(Theme.PanelHeight * scale), work.Height - 2 * gap);

        // Which edge the taskbar is on: where the work area is smaller than the screen.
        int x, y;
        if (work.Y > outer.Y) { x = point.X - width / 2; y = work.Y + gap; }                       // top
        else if (work.X > outer.X) { x = work.X + gap; y = point.Y - height / 2; }                  // left
        else if (work.X + work.Width < outer.X + outer.Width) { x = work.X + work.Width - width - gap; y = point.Y - height / 2; } // right
        else { x = point.X - width / 2; y = work.Y + work.Height - height - gap; }                  // bottom
        x = Math.Clamp(x, work.X + gap, work.X + work.Width - width - gap);
        y = Math.Clamp(y, work.Y + gap, work.Y + work.Height - height - gap);
        AppWindow.MoveAndResize(new RectInt32(x, y, width, height));
    }

    static uint DpiAt(PointInt32 point)
    {
        try
        {
            var monitor = MonitorFromPoint(new POINT { X = point.X, Y = point.Y }, 2);
            return GetDpiForMonitor(monitor, 0, out var dpi, out _) == 0 ? dpi : 96;
        }
        catch { return 96; }
    }

    void OnKeyDown(object sender, KeyRoutedEventArgs e)
    {
        var ctrl = Microsoft.UI.Input.InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.Control).HasFlag(Windows.UI.Core.CoreVirtualKeyStates.Down);
        if (e.Key == VirtualKey.Escape)
        {
            if (store.Route == Route.List) Hide();
            else store.Route = Route.List;
            e.Handled = true;
            return;
        }
        if (ctrl && e.Key == VirtualKey.W)
        {
            Hide();
            e.Handled = true;
            return;
        }
        if (host.Child is ListPage list) e.Handled = list.HandleKey(e.Key, ctrl);
    }

    async void OnDrop(object sender, DragEventArgs e)
    {
        var data = e.DataView;
        if (data.Contains(Windows.ApplicationModel.DataTransfer.StandardDataFormats.StorageItems))
        {
            var files = (await data.GetStorageItemsAsync()).Select(i => i.Path).Where(p => p.EndsWith(".torrent", StringComparison.OrdinalIgnoreCase)).ToList();
            store.AddTorrentFiles(files);
        }
        else if (data.Contains(Windows.ApplicationModel.DataTransfer.StandardDataFormats.WebLink))
        {
            store.Add([new Models.DownloadRequest((await data.GetWebLinkAsync()).AbsoluteUri)]);
        }
        else if (data.Contains(Windows.ApplicationModel.DataTransfer.StandardDataFormats.Text))
        {
            var text = await data.GetTextAsync();
            store.Add(DownloadStore.ParseLinks(text).Select(l => new Models.DownloadRequest(l)));
        }
    }

    [StructLayout(LayoutKind.Sequential)] struct POINT { public int X, Y; }
    [DllImport("user32.dll")] static extern IntPtr MonitorFromPoint(POINT point, uint flags);
    [DllImport("shcore.dll")] static extern int GetDpiForMonitor(IntPtr monitor, int type, out uint dpiX, out uint dpiY);
    [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
}

/// <summary>Where the tray icon is (physical pixels), or the cursor if Windows does not tell.</summary>
public readonly record struct TrayIconPlacement(Tray.TrayIcon.RECT? IconRect, PointInt32 Cursor);
