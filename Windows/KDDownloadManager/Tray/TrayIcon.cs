using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace KDDownloadManager.Tray;

/// <summary>
/// The notification-area (tray) icon, straight on Win32 Shell_NotifyIcon (macOS: the NSStatusItem in
/// StatusItemController). A hidden window receives the icon's mouse messages; the icon image is drawn at runtime
/// (idle, progress ring, red error dot, check mark) at the system's small-icon size, in the taskbar's text color.
/// </summary>
public sealed class TrayIcon : IDisposable
{
    public enum IconState { Idle, Progress, Error, Done }

    public event Action? Clicked;
    public event Action<int, int>? ContextMenuRequested;
    /// <summary>Taskbar theme or DPI changed: the owner should redraw the current state.</summary>
    public event Action? NeedsRedraw;
    /// <summary>The user clicked a balloon shown with <see cref="ShowBalloon"/>.</summary>
    public event Action? BalloonClicked;

    readonly WndProc proc;
    readonly IntPtr hwnd;
    readonly uint taskbarCreated;
    IntPtr icon;
    (IconState state, int step, bool light)? drawn;
    string tip = "KD Download Manager";
    bool added;
    const uint CallbackMessage = 0x8000 + 1; // WM_APP + 1
    const uint IconId = 1;

    public IntPtr WindowHandle => hwnd;

    public TrayIcon()
    {
        proc = WindowProc;
        var hInstance = GetModuleHandle(null);
        var wc = new WNDCLASSEX
        {
            cbSize = (uint)Marshal.SizeOf<WNDCLASSEX>(),
            lpfnWndProc = Marshal.GetFunctionPointerForDelegate(proc),
            hInstance = hInstance,
            lpszClassName = "KDDownloadManagerTray",
        };
        RegisterClassEx(ref wc);
        hwnd = CreateWindowEx(0, wc.lpszClassName, "KD Download Manager", 0x80000000 /* WS_POPUP */, 0, 0, 0, 0, IntPtr.Zero, IntPtr.Zero, hInstance, IntPtr.Zero);
        taskbarCreated = RegisterWindowMessage("TaskbarCreated");
        Update(IconState.Idle, 0, tip);
    }

    /// <summary>Redraws only when the look changes (progress in 36 steps, like macOS).</summary>
    public void Update(IconState state, int step, string tooltip)
    {
        var light = TaskbarIsLight();
        var look = (state, state == IconState.Progress ? step : 0, light);
        var tipChanged = tooltip != tip;
        tip = tooltip;
        if (drawn == look && !tipChanged && added) return;
        if (drawn != look || icon == IntPtr.Zero)
        {
            var old = icon;
            icon = IconPainter.Create(state, step / 36.0, light, (int)(GetSystemMetrics(49 /* SM_CXSMICON */) * Dpi() / 96));
            drawn = look;
            Apply();
            if (old != IntPtr.Zero) DestroyIcon(old);
        }
        else Apply();
    }

    void Apply()
    {
        var data = Data();
        data.uFlags = 0x1 | 0x2 | 0x4 | 0x80; // NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP
        data.uCallbackMessage = CallbackMessage;
        data.hIcon = icon;
        data.szTip = tip.Length > 127 ? tip[..127] : tip;
        if (!added || !Shell_NotifyIcon(1 /* NIM_MODIFY */, ref data))
        {
            added = Shell_NotifyIcon(0 /* NIM_ADD */, ref data);
            data.uVersion = 4;
            Shell_NotifyIcon(4 /* NIM_SETVERSION */, ref data);
        }
    }

    NOTIFYICONDATA Data() => new()
    {
        cbSize = (uint)Marshal.SizeOf<NOTIFYICONDATA>(),
        hWnd = hwnd,
        uID = IconId,
        szTip = "",
        szInfo = "",
        szInfoTitle = "",
    };

    /// <summary>The icon's rectangle on screen (physical pixels), to place the panel next to it.</summary>
    public RECT? Bounds()
    {
        var id = new NOTIFYICONIDENTIFIER { cbSize = (uint)Marshal.SizeOf<NOTIFYICONIDENTIFIER>(), hWnd = hwnd, uID = IconId, guidItem = Guid.Empty };
        return Shell_NotifyIconGetRect(ref id, out var rect) == 0 ? rect : null;
    }

    uint Dpi()
    {
        try { return GetDpiForWindow(hwnd) is var d && d > 0 ? d : 96; } catch { return 96; }
    }

    static bool TaskbarIsLight()
    {
        using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
        return key?.GetValue("SystemUsesLightTheme") is int value && value == 1;
    }

    IntPtr WindowProc(IntPtr h, uint message, IntPtr w, IntPtr l)
    {
        if (message == CallbackMessage)
        {
            var e = (uint)(l.ToInt64() & 0xFFFF);
            switch (e)
            {
                case 0x0202: // WM_LBUTTONUP
                    Clicked?.Invoke();
                    break;
                case 0x007B: // WM_CONTEXTMENU (version 4: right click / Shift+F10)
                    var x = (short)(w.ToInt64() & 0xFFFF);
                    var y = (short)((w.ToInt64() >> 16) & 0xFFFF);
                    ContextMenuRequested?.Invoke(x, y);
                    break;
                case 0x0405: // NIN_BALLOONUSERCLICK
                    BalloonClicked?.Invoke();
                    break;
                case 0x0400: // NIN_SELECT via keyboard (Enter / Space)
                case 0x0401: // NIN_KEYSELECT
                    break;
            }
            return IntPtr.Zero;
        }
        if (message == taskbarCreated)
        {
            // Explorer restarted: the icon must be added again.
            added = false;
            Apply();
        }
        if (message == 0x001A /* WM_SETTINGCHANGE */ || message == 0x02E0 /* WM_DPICHANGED */)
        {
            drawn = null;
            NeedsRedraw?.Invoke();
        }
        return DefWindowProc(h, message, w, l);
    }

    /// <summary>A Win32 popup menu at the cursor; returns the chosen command (0 if none).</summary>
    /// <summary>A notification from the tray icon (Windows shows it like a toast).</summary>
    public void ShowBalloon(string title, string text, bool silent)
    {
        var data = Data();
        data.uFlags = 0x10; // NIF_INFO
        data.szInfoTitle = title.Length > 63 ? title[..63] : title;
        data.szInfo = text.Length > 255 ? text[..255] : text;
        data.dwInfoFlags = 0x1 | (silent ? 0x10u : 0); // NIIF_INFO | NIIF_NOSOUND (as WinForms' NotifyIcon)
        data.uVersion = 10_000; // uTimeout: the same union field
        if (!Shell_NotifyIcon(1 /* NIM_MODIFY */, ref data)) App.Log($"Balloon failed: {Marshal.GetLastWin32Error()} added={added}");
    }

    public int ShowMenu(int x, int y, IEnumerable<(int id, string title, bool separatorBefore)> items)
    {
        var menu = CreatePopupMenu();
        foreach (var (id, title, separator) in items)
        {
            if (separator) AppendMenu(menu, 0x800 /* MF_SEPARATOR */, 0, null);
            AppendMenu(menu, 0, (uint)id, title);
        }
        SetForegroundWindow(hwnd);
        var chosen = TrackPopupMenu(menu, 0x0100 /* TPM_RETURNCMD */ | 0x0020 /* TPM_BOTTOMALIGN */ | 0x0008 /* TPM_RIGHTALIGN */, x, y, 0, hwnd, IntPtr.Zero);
        PostMessage(hwnd, 0, IntPtr.Zero, IntPtr.Zero);
        DestroyMenu(menu);
        return chosen;
    }

    public void Dispose()
    {
        var data = Data();
        Shell_NotifyIcon(2 /* NIM_DELETE */, ref data);
        data.uFlags = 0;
        if (icon != IntPtr.Zero) DestroyIcon(icon);
        DestroyWindow(hwnd);
    }

    // MARK: Win32

    delegate IntPtr WndProc(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct WNDCLASSEX
    {
        public uint cbSize, style;
        public IntPtr lpfnWndProc;
        public int cbClsExtra, cbWndExtra;
        public IntPtr hInstance, hIcon, hCursor, hbrBackground;
        public string? lpszMenuName;
        public string lpszClassName;
        public IntPtr hIconSm;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct NOTIFYICONDATA
    {
        public uint cbSize;
        public IntPtr hWnd;
        public uint uID, uFlags, uCallbackMessage;
        public IntPtr hIcon;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string szTip;
        public uint dwState, dwStateMask;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string szInfo;
        public uint uVersion;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string szInfoTitle;
        public uint dwInfoFlags;
        public Guid guidItem;
        public IntPtr hBalloonIcon;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct NOTIFYICONIDENTIFIER
    {
        public uint cbSize;
        public IntPtr hWnd;
        public uint uID;
        public Guid guidItem;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern ushort RegisterClassEx(ref WNDCLASSEX wc);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr CreateWindowEx(uint exStyle, string className, string title, uint style, int x, int y, int w, int h, IntPtr parent, IntPtr menu, IntPtr instance, IntPtr param);
    [DllImport("user32.dll")] static extern IntPtr DefWindowProc(IntPtr hwnd, uint message, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] static extern bool DestroyWindow(IntPtr hwnd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern uint RegisterWindowMessage(string name);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr GetModuleHandle(string? name);
    [DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern bool Shell_NotifyIcon(uint message, ref NOTIFYICONDATA data);
    [DllImport("shell32.dll")] static extern int Shell_NotifyIconGetRect(ref NOTIFYICONIDENTIFIER id, out RECT rect);
    [DllImport("user32.dll")] static extern int GetSystemMetrics(int index);
    [DllImport("user32.dll")] static extern uint GetDpiForWindow(IntPtr hwnd);
    [DllImport("user32.dll")] static extern bool DestroyIcon(IntPtr icon);
    [DllImport("user32.dll")] static extern IntPtr CreatePopupMenu();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool AppendMenu(IntPtr menu, uint flags, uint id, string? text);
    [DllImport("user32.dll")] static extern int TrackPopupMenu(IntPtr menu, uint flags, int x, int y, int reserved, IntPtr hwnd, IntPtr rect);
    [DllImport("user32.dll")] static extern bool DestroyMenu(IntPtr menu);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")] static extern bool PostMessage(IntPtr hwnd, uint message, IntPtr w, IntPtr l);
}

/// <summary>Draws the tray icon into a 32-bit ARGB bitmap with 4×4 supersampling (no System.Drawing).</summary>
static class IconPainter
{
    public static IntPtr Create(TrayIcon.IconState state, double fraction, bool lightTaskbar, int size)
    {
        size = Math.Clamp(size, 16, 64);
        var pixels = new uint[size * size];
        var ink = lightTaskbar ? (r: 0x1Fu, g: 0x1Fu, b: 0x1Fu) : (r: 0xFFu, g: 0xFFu, b: 0xFFu);
        var s = size / 16.0; // design grid: 16×16
        const int samples = 4;
        for (var py = 0; py < size; py++)
        for (var px = 0; px < size; px++)
        {
            double inkCover = 0, trackCover = 0, redCover = 0;
            for (var sy = 0; sy < samples; sy++)
            for (var sx = 0; sx < samples; sx++)
            {
                var x = (px + (sx + 0.5) / samples) / s;
                var y = (py + (sy + 0.5) / samples) / s;
                var (i, t, r) = Shade(state, fraction, x, y);
                inkCover += i ? 1 : 0;
                trackCover += t ? 1 : 0;
                redCover += r ? 1 : 0;
            }
            var n = samples * samples;
            double ai = inkCover / n, at = trackCover / n * 0.35, ar = redCover / n;
            // Composite: track under ink, red dot on top.
            var a = ai + at * (1 - ai);
            var cr = ink.r * a; var cg = ink.g * a; var cb = ink.b * a;
            var alpha = a * (1 - ar) + ar;
            cr = cr * (1 - ar) + 0xE5 * ar; cg = cg * (1 - ar) + 0x48 * ar; cb = cb * (1 - ar) + 0x4D * ar;
            var A = (uint)Math.Round(alpha * 255);
            pixels[py * size + px] = (A << 24) | ((uint)Math.Round(cr) << 16) | ((uint)Math.Round(cg) << 8) | (uint)Math.Round(cb);
        }
        return ToIcon(pixels, size);
    }

    /// <summary>Which layers cover the point (x, y) on the 16×16 grid.</summary>
    static (bool ink, bool track, bool red) Shade(TrayIcon.IconState state, double fraction, double x, double y)
    {
        const double cx = 8, cy = 8, radius = 6.6;
        var dist = Math.Sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy));
        bool Ring(double width) => Math.Abs(dist - radius) <= width / 2;
        bool Segment(double ax, double ay, double bx, double by, double width)
        {
            double vx = bx - ax, vy = by - ay, wx = x - ax, wy = y - ay;
            var t = Math.Clamp((wx * vx + wy * vy) / (vx * vx + vy * vy), 0, 1);
            double dx = wx - t * vx, dy = wy - t * vy;
            return dx * dx + dy * dy <= width * width / 4;
        }
        bool Arrow(double scale) =>
            Segment(8, 8 - 3.4 * scale, 8, 8 + 3.2 * scale, 1.7) || Segment(8 - 3 * scale, 8 + 0.4 * scale, 8, 8 + 3.3 * scale, 1.7) || Segment(8 + 3 * scale, 8 + 0.4 * scale, 8, 8 + 3.3 * scale, 1.7);
        bool Check() => Segment(4.9, 8.2, 7.1, 10.4, 1.7) || Segment(7.1, 10.4, 11.2, 5.9, 1.7);

        switch (state)
        {
            case TrayIcon.IconState.Progress:
            {
                var onRing = Ring(1.9);
                var angle = (Math.Atan2(x - cx, -(y - cy)) + 2 * Math.PI) % (2 * Math.PI); // clockwise from 12 o'clock
                var inArc = onRing && angle <= fraction * 2 * Math.PI;
                return (inArc || Arrow(0.8), onRing && !inArc, false);
            }
            case TrayIcon.IconState.Done:
                return (Ring(1.5) || Check(), false, false);
            case TrayIcon.IconState.Error:
            {
                var dot = Math.Sqrt((x - 12.8) * (x - 12.8) + (y - 3.2) * (y - 3.2)) <= 3.0;
                var gap = Math.Sqrt((x - 12.8) * (x - 12.8) + (y - 3.2) * (y - 3.2)) <= 4.0;
                return (!gap && (Ring(1.5) || Arrow(0.85)), false, dot);
            }
            default:
                return (Ring(1.5) || Arrow(0.85), false, false);
        }
    }

    static IntPtr ToIcon(uint[] pixels, int size)
    {
        var header = new BITMAPV5HEADER
        {
            bV5Size = (uint)Marshal.SizeOf<BITMAPV5HEADER>(),
            bV5Width = size,
            bV5Height = -size, // top-down
            bV5Planes = 1,
            bV5BitCount = 32,
            bV5Compression = 3, // BI_BITFIELDS
            bV5RedMask = 0x00FF0000,
            bV5GreenMask = 0x0000FF00,
            bV5BlueMask = 0x000000FF,
            bV5AlphaMask = 0xFF000000,
        };
        var dc = GetDC(IntPtr.Zero);
        var color = CreateDIBSection(dc, ref header, 0, out var bits, IntPtr.Zero, 0);
        ReleaseDC(IntPtr.Zero, dc);
        // Premultiplied alpha is not required for icons; straight ARGB.
        Marshal.Copy(pixels.Select(p => unchecked((int)p)).ToArray(), 0, bits, pixels.Length);
        var mask = CreateBitmap(size, size, 1, 1, IntPtr.Zero);
        var info = new ICONINFO { fIcon = true, hbmColor = color, hbmMask = mask };
        var icon = CreateIconIndirect(ref info);
        DeleteObject(color);
        DeleteObject(mask);
        return icon;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct BITMAPV5HEADER
    {
        public uint bV5Size;
        public int bV5Width, bV5Height;
        public ushort bV5Planes, bV5BitCount;
        public uint bV5Compression, bV5SizeImage;
        public int bV5XPelsPerMeter, bV5YPelsPerMeter;
        public uint bV5ClrUsed, bV5ClrImportant, bV5RedMask, bV5GreenMask, bV5BlueMask, bV5AlphaMask, bV5CSType;
        public int e1, e2, e3, e4, e5, e6, e7, e8, e9;
        public uint bV5GammaRed, bV5GammaGreen, bV5GammaBlue, bV5Intent, bV5ProfileData, bV5ProfileSize, bV5Reserved;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct ICONINFO
    {
        [MarshalAs(UnmanagedType.Bool)] public bool fIcon;
        public int xHotspot, yHotspot;
        public IntPtr hbmMask, hbmColor;
    }

    [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr hwnd);
    [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr hwnd, IntPtr dc);
    [DllImport("gdi32.dll")] static extern IntPtr CreateDIBSection(IntPtr dc, ref BITMAPV5HEADER header, uint usage, out IntPtr bits, IntPtr section, uint offset);
    [DllImport("gdi32.dll")] static extern IntPtr CreateBitmap(int w, int h, uint planes, uint bits, IntPtr data);
    [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr obj);
    [DllImport("user32.dll")] static extern IntPtr CreateIconIndirect(ref ICONINFO info);
}
