using System.Runtime.InteropServices;
using Microsoft.UI.Dispatching;
using Microsoft.Windows.AppLifecycle;

namespace KDDownloadManager;

/// <summary>
/// Entry point: one copy of the app per user. A second launch (Start menu, magnet link, .torrent, toast click)
/// hands its activation to the running copy and exits.
/// </summary>
public static class Program
{
    static AppInstance? instance;

    [STAThread]
    static int Main(string[] args)
    {
        // Release check: "KDDownloadManager.exe --verify-update <zip> <zip.sig>" exits 0 only if the signature is
        // valid for the embedded public key (the same check the in-app updater makes).
        if (args.Length == 3 && args[0] == "--verify-update")
            return AppUpdater.VerifyFiles(args[1], args[2]) ? 0 : 1;
        WinRT.ComWrappersSupport.InitializeComWrappers();
        instance = AppInstance.FindOrRegisterForKey("KDDownloadManager-" + Environment.UserName);
        if (!instance.IsCurrent)
        {
            var activation = AppInstance.GetCurrent().GetActivatedEventArgs();
            // This launch came from the user (Start menu, a link), so it may bring a window to the front; hand that
            // right to the running copy, otherwise its panel cannot take the focus and closes again at once.
            AllowSetForegroundWindow((int)instance.ProcessId);
            // Redirecting must not block this STA thread.
            Task.Run(() => instance.RedirectActivationToAsync(activation).AsTask().Wait()).Wait(TimeSpan.FromSeconds(5));
            return 0;
        }
        instance.Activated += (_, activation) => App.Current?.OnRedirected(activation);

        Microsoft.UI.Xaml.Application.Start(parameters =>
        {
            SynchronizationContext.SetSynchronizationContext(new SafeContext(DispatcherQueue.GetForCurrentThread()));
            new App(args);
        });
        return 0;
    }

    public static void ReleaseInstance()
    {
        try { instance?.UnregisterKey(); } catch { }
    }

    /// <summary>Splits a command line like Windows does (quotes, backslashes).</summary>
    public static string[] SplitCommandLine(string commandLine)
    {
        if (string.IsNullOrWhiteSpace(commandLine)) return [];
        var argv = CommandLineToArgvW(commandLine, out var count);
        if (argv == IntPtr.Zero) return [];
        try
        {
            var result = new string[count];
            for (var i = 0; i < count; i++) result[i] = Marshal.PtrToStringUni(Marshal.ReadIntPtr(argv, i * IntPtr.Size))!;
            return result;
        }
        finally { LocalFree(argv); }
    }

    [DllImport("user32.dll")] static extern bool AllowSetForegroundWindow(int processId);
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)] static extern IntPtr CommandLineToArgvW(string commandLine, out int count);
    [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr memory);

    /// <summary>
    /// UI-thread context for awaits. An exception escaping an async void handler (a button, a timer, an engine
    /// callback) is logged instead of ending the process with a fail-fast in the dispatcher.
    /// </summary>
    sealed class SafeContext(DispatcherQueue queue) : SynchronizationContext
    {
        public override void Post(SendOrPostCallback callback, object? state) =>
            queue.TryEnqueue(() =>
            {
                try { callback(state); }
                catch (Exception error) { App.Log("Async: " + error); }
            });

        public override void Send(SendOrPostCallback callback, object? state)
        {
            if (queue.HasThreadAccess) { callback(state); return; }
            using var done = new ManualResetEventSlim();
            Exception? failure = null;
            queue.TryEnqueue(() =>
            {
                try { callback(state); } catch (Exception error) { failure = error; } finally { done.Set(); }
            });
            done.Wait();
            if (failure != null) throw failure;
        }

        public override SynchronizationContext CreateCopy() => this;
    }
}
