// Testlerde WinUI'nin, Windows bildirimlerinin ve kabuğun yerine geçenler. Uygulama kodu bunları çağırdığında
// ne istendiği kaydedilir; testler bu kayıtlara bakar.
using System.Collections.Concurrent;
using System.Diagnostics;

namespace Windows.UI
{
    public struct Color
    {
        public byte A, R, G, B;
        public static Color FromArgb(byte a, byte r, byte g, byte b) => new() { A = a, R = r, G = g, B = b };
    }
}

namespace KDDownloadManager
{
    using KDDownloadManager.Models;

    /// <summary>App.xaml.cs'in testlerde kullanılan kısmı.</summary>
    public static class App
    {
        public static readonly ConcurrentQueue<string> Logs = new();
        public static int QuitRequests;
        public static void Log(string message) => Logs.Enqueue(message);
        public static void Add(Process process) { }
        public static void Quit() => Interlocked.Increment(ref QuitRequests);
        public static void Relaunch() { }
    }

    public static class Notifier
    {
        public static readonly ConcurrentQueue<string> Posted = new();
        public static void SetUp() { }
        public static void TearDown() { }
        public static void DownloadsAdded(List<string> names) => Posted.Enqueue("added:" + string.Join(",", names));
        public static void DownloadFinished(DownloadItem item) => Posted.Enqueue("finished:" + item.FileName);
        public static void DownloadFailed(DownloadItem item, string message) => Posted.Enqueue("failed:" + item.FileName + ":" + message);
        public static void UpdateAvailable(string version) => Posted.Enqueue("update:" + version);
    }

    public static class Shell
    {
        public static readonly ConcurrentQueue<string> Calls = new();
        public static void Reveal(string? file, string folder) => Calls.Enqueue("reveal:" + (file ?? folder));
        public static void OpenFolder(string folder) => Calls.Enqueue("open:" + folder);
        public static bool Open(string? file) { Calls.Enqueue("open:" + file); return file != null; }
        public static void Beep() { }
        public static void OpenUrl(string url) => Calls.Enqueue("url:" + url);
        public static string? ClipboardText() => null;
        public static Task<string?> ClipboardTextAsync() => Task.FromResult<string?>(null);
        public static void Copy(string text) => Calls.Enqueue("copy:" + text);
        public static long? FreeSpace(string folder) => null;
        public static string Abbreviated(string path) => path;
    }

    /// <summary>Çöp Kutusu yerine: dosyayı test klasöründeki "RecycleBin"e taşır.</summary>
    public static class RecycleBin
    {
        public static readonly ConcurrentQueue<string> Sent = new();
        public static bool Send(string path)
        {
            if (!File.Exists(path) && !Directory.Exists(path)) return false;
            Sent.Enqueue(path);
            var bin = Path.Combine(AppFolders.Support, "RecycleBin");
            Directory.CreateDirectory(bin);
            var target = Path.Combine(bin, Guid.NewGuid().ToString("N") + "-" + Path.GetFileName(path));
            if (File.Exists(path)) File.Move(path, target); else Directory.Move(path, target);
            return true;
        }
    }

    public static class Theme
    {
        public static string AccentHex { get; set; } = "#3B82F6";
    }
}
