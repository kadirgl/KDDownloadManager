using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace KDDownloadManager;

/// <summary>Explorer, default apps and the clipboard (macOS: NSWorkspace / NSPasteboard).</summary>
public static class Shell
{
    /// <summary>Shows the file selected in File Explorer, or opens the folder.</summary>
    public static void Reveal(string? file, string folder)
    {
        try
        {
            if (file != null && (File.Exists(file) || Directory.Exists(file)))
                Process.Start(new ProcessStartInfo("explorer.exe") { ArgumentList = { "/select,", file } });
            else
                OpenFolder(folder);
        }
        catch { }
    }

    public static void OpenFolder(string folder)
    {
        try
        {
            Directory.CreateDirectory(folder);
            Process.Start(new ProcessStartInfo(folder) { UseShellExecute = true });
        }
        catch { }
    }

    /// <summary>Opens a file with its default app; false if it no longer exists.</summary>
    public static bool Open(string? file)
    {
        if (file == null || !(File.Exists(file) || Directory.Exists(file))) return false;
        try
        {
            Process.Start(new ProcessStartInfo(file) { UseShellExecute = true });
            return true;
        }
        catch { return false; }
    }

    public static void Beep() => MessageBeep(0);

    [DllImport("user32.dll")] static extern bool MessageBeep(uint type);

    public static void OpenUrl(string url)
    {
        try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); } catch { }
    }

    public static string? ClipboardText()
    {
        try
        {
            var content = Windows.ApplicationModel.DataTransfer.Clipboard.GetContent();
            if (!content.Contains(Windows.ApplicationModel.DataTransfer.StandardDataFormats.Text)) return null;
            return content.GetTextAsync().AsTask().GetAwaiter().GetResult();
        }
        catch { return null; }
    }

    public static async Task<string?> ClipboardTextAsync()
    {
        try
        {
            var content = Windows.ApplicationModel.DataTransfer.Clipboard.GetContent();
            if (!content.Contains(Windows.ApplicationModel.DataTransfer.StandardDataFormats.Text)) return null;
            return await content.GetTextAsync();
        }
        catch { return null; }
    }

    public static void Copy(string text)
    {
        try
        {
            var package = new Windows.ApplicationModel.DataTransfer.DataPackage();
            package.SetText(text);
            Windows.ApplicationModel.DataTransfer.Clipboard.SetContent(package);
            Windows.ApplicationModel.DataTransfer.Clipboard.Flush();
        }
        catch { }
    }

    /// <summary>Free space on the drive of a folder.</summary>
    public static long? FreeSpace(string folder)
    {
        try { return new DriveInfo(Path.GetPathRoot(Path.GetFullPath(folder))!).AvailableFreeSpace; }
        catch { return null; }
    }

    /// <summary>"C:\Users\kadir\Downloads" → "~\Downloads" like macOS' abbreviatingWithTildeInPath.</summary>
    public static string Abbreviated(string path)
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        return path.StartsWith(home, StringComparison.OrdinalIgnoreCase) ? "~" + path[home.Length..] : path;
    }
}

/// <summary>Moves completed files to the Recycle Bin (macOS: trashItem).</summary>
public static class RecycleBin
{
    public static void Send(string path)
    {
        try
        {
            if (File.Exists(path))
                Microsoft.VisualBasic.FileIO.FileSystem.DeleteFile(path, Microsoft.VisualBasic.FileIO.UIOption.OnlyErrorDialogs,
                    Microsoft.VisualBasic.FileIO.RecycleOption.SendToRecycleBin);
            else if (Directory.Exists(path))
                Microsoft.VisualBasic.FileIO.FileSystem.DeleteDirectory(path, Microsoft.VisualBasic.FileIO.UIOption.OnlyErrorDialogs,
                    Microsoft.VisualBasic.FileIO.RecycleOption.SendToRecycleBin);
        }
        catch { }
    }
}

/// <summary>"Start when I sign in": HKCU\...\Run (macOS: SMAppService).</summary>
public static class LaunchAtLogin
{
    const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    const string Name = "KD Download Manager";

    static string Command => $"\"{Environment.ProcessPath}\" --background";

    public static bool IsEnabled
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey);
            return key?.GetValue(Name) is string value && value.Contains(Path.GetFileName(Environment.ProcessPath!), StringComparison.OrdinalIgnoreCase);
        }
    }

    public static void Set(bool enabled)
    {
        using var key = Registry.CurrentUser.CreateSubKey(RunKey);
        if (enabled) key.SetValue(Name, Command);
        else key.DeleteValue(Name, false);
    }

    /// <summary>After an update moved the app, keep the entry pointing at the current exe.</summary>
    public static void Refresh()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKey, true);
        if (key?.GetValue(Name) is string value && value != Command) key.SetValue(Name, Command);
    }
}

/// <summary>
/// magnet: links and .torrent files open with the app (per user, HKCU\Software\Classes; macOS: TorrentHandler).
/// Windows then lets the user confirm the default in Settings › Apps › Default apps.
/// </summary>
public static class TorrentHandler
{
    const string ProgId = "KDDownloadManager.Torrent";

    static string Command => $"\"{Environment.ProcessPath}\" \"%1\"";

    public static bool IsRegistered
    {
        get
        {
            using var magnet = Registry.CurrentUser.OpenSubKey(@"Software\Classes\magnet\shell\open\command");
            return magnet?.GetValue(null) is string value && value == Command;
        }
    }

    /// <summary>The app that opens magnet links now (from the user's choice), for display.</summary>
    public static string? CurrentHandler()
    {
        using var choice = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\Shell\Associations\UrlAssociations\magnet\UserChoice");
        if (choice?.GetValue("ProgId") is string progId) return progId == ProgId ? "KD Download Manager" : progId;
        using var magnet = Registry.ClassesRoot.OpenSubKey(@"magnet\shell\open\command");
        return magnet?.GetValue(null) is string command ? Path.GetFileNameWithoutExtension(command.Trim('"').Split('"')[0]) : null;
    }

    public static void Register()
    {
        var exe = Environment.ProcessPath!;
        using (var magnet = Registry.CurrentUser.CreateSubKey(@"Software\Classes\magnet"))
        {
            magnet.SetValue(null, "URL:magnet");
            magnet.SetValue("URL Protocol", "");
            using var icon = magnet.CreateSubKey("DefaultIcon");
            icon.SetValue(null, $"\"{exe}\",0");
            using var command = magnet.CreateSubKey(@"shell\open\command");
            command.SetValue(null, Command);
        }
        using (var prog = Registry.CurrentUser.CreateSubKey(@"Software\Classes\" + ProgId))
        {
            prog.SetValue(null, "Torrent");
            using var icon = prog.CreateSubKey("DefaultIcon");
            icon.SetValue(null, $"\"{exe}\",0");
            using var command = prog.CreateSubKey(@"shell\open\command");
            command.SetValue(null, Command);
        }
        using (var ext = Registry.CurrentUser.CreateSubKey(@"Software\Classes\.torrent"))
        {
            ext.SetValue(null, ProgId);
            using var open = ext.CreateSubKey("OpenWithProgids");
            open.SetValue(ProgId, Array.Empty<byte>(), RegistryValueKind.None);
        }
        SHChangeNotify(0x08000000, 0, IntPtr.Zero, IntPtr.Zero); // SHCNE_ASSOCCHANGED
    }

    [DllImport("shell32.dll")]
    static extern void SHChangeNotify(int eventId, uint flags, IntPtr item1, IntPtr item2);
}

/// <summary>A Start menu shortcut, created on first launch so the app can be found and pinned.</summary>
public static class StartMenu
{
    public static string ShortcutPath => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), "KD Download Manager.lnk");

    public static void EnsureShortcut()
    {
        try
        {
            var target = Environment.ProcessPath!;
            if (File.Exists(ShortcutPath) && Settings.Get<string?>(Settings.ShortcutCreated, null) == target) return;
            var link = (IShellLinkW)new ShellLink();
            link.SetPath(target);
            link.SetWorkingDirectory(Path.GetDirectoryName(target)!);
            link.SetDescription("KD Download Manager");
            link.SetIconLocation(target, 0);
            ((IPersistFile)link).Save(ShortcutPath, true);
            Settings.Set(Settings.ShortcutCreated, target);
        }
        catch { }
    }

    [ComImport, Guid("00021401-0000-0000-C000-000000000046")]
    class ShellLink;

    [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("000214F9-0000-0000-C000-000000000046")]
    interface IShellLinkW
    {
        void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder file, int max, IntPtr data, uint flags);
        void GetIDList(out IntPtr list);
        void SetIDList(IntPtr list);
        void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder name, int max);
        void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string name);
        void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder dir, int max);
        void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string dir);
        void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder args, int max);
        void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string args);
        void GetHotkey(out short hotkey);
        void SetHotkey(short hotkey);
        void GetShowCmd(out int show);
        void SetShowCmd(int show);
        void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder path, int max, out int index);
        void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string path, int index);
        void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string path, uint reserved);
        void Resolve(IntPtr hwnd, uint flags);
        void SetPath([MarshalAs(UnmanagedType.LPWStr)] string file);
    }

    [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("0000010b-0000-0000-C000-000000000046")]
    interface IPersistFile
    {
        void GetClassID(out Guid id);
        [PreserveSig] int IsDirty();
        void Load([MarshalAs(UnmanagedType.LPWStr)] string file, uint mode);
        void Save([MarshalAs(UnmanagedType.LPWStr)] string file, [MarshalAs(UnmanagedType.Bool)] bool remember);
        void SaveCompleted([MarshalAs(UnmanagedType.LPWStr)] string file);
        void GetCurFile([MarshalAs(UnmanagedType.LPWStr)] out string file);
    }
}
