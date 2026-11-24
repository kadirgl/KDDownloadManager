using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace KDDownloadManager;

/// <summary>
/// The helper programs bundled next to the app by Windows/scripts/bundle-tools.ps1 (macOS: Executables):
///   tools\aria2c.exe, tools\yt-dlp\yt-dlp.exe (onedir), tools\ffmpeg\ffmpeg.exe (+ DLLs), tools\qjs.exe
/// A yt-dlp updated from inside the app (YtDlpUpdater) wins over the bundled one when newer.
/// Falls back to PATH so a developer build works with tools installed elsewhere.
/// </summary>
public static class Tools
{
    public static string BundledFolder => Path.Combine(AppFolders.AppDir, "tools");

    static readonly Dictionary<string, string> Bundled = new()
    {
        ["aria2c"] = "aria2c.exe",
        ["yt-dlp"] = Path.Combine("yt-dlp", "yt-dlp.exe"),
        ["ffmpeg"] = Path.Combine("ffmpeg", "ffmpeg.exe"),
        ["qjs"] = "qjs.exe",
    };

    public static string? Find(string name)
    {
        if (name == "yt-dlp" && YtDlpUpdater.PreferredBinary() is { } updated) return updated;
        if (Bundled.TryGetValue(name, out var relative))
        {
            var bundled = Path.Combine(BundledFolder, relative);
            if (File.Exists(bundled)) return bundled;
        }
        foreach (var dir in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(';', StringSplitOptions.RemoveEmptyEntries))
        {
            var candidate = Path.Combine(dir.Trim(), name + ".exe");
            if (File.Exists(candidate)) return candidate;
        }
        return null;
    }

    /// <summary>yt-dlp's JavaScript runtime for YouTube's challenges: deno if installed, else the bundled QuickJS.</summary>
    public static List<string> JavaScriptRuntimeArguments()
    {
        if (Find("deno") != null) return [];
        return Find("qjs") is { } qjs ? ["--no-js-runtimes", "--js-runtimes", "quickjs:" + qjs] : [];
    }

    /// <summary>Process start info: no console window, UTF-8 output, our tools first on PATH.</summary>
    public static ProcessStartInfo StartInfo(string file, IEnumerable<string> arguments, bool redirect = true)
    {
        var info = new ProcessStartInfo(file)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = redirect,
            RedirectStandardError = redirect,
            StandardOutputEncoding = redirect ? System.Text.Encoding.UTF8 : null,
            StandardErrorEncoding = redirect ? System.Text.Encoding.UTF8 : null,
        };
        foreach (var argument in arguments) info.ArgumentList.Add(argument);
        info.Environment["PYTHONUTF8"] = "1";
        info.Environment["PYTHONIOENCODING"] = "utf-8";
        info.Environment["PYTHONUNBUFFERED"] = "1";
        var path = string.Join(';', new[] { BundledFolder, Path.Combine(BundledFolder, "ffmpeg") }.Where(Directory.Exists));
        info.Environment["PATH"] = path + ";" + Environment.GetEnvironmentVariable("PATH");
        return info;
    }
}

/// <summary>
/// Windows job objects: every helper process (and its children, e.g. yt-dlp's ffmpeg and aria2c) is put
/// in the app-wide job, which kills them when the app exits, even when it crashes (macOS: --stop-with-process
/// and ProcessTree). Each yt-dlp run also gets its own job so pausing can stop the whole tree at once.
/// </summary>
public sealed class ProcessJob : IDisposable
{
    readonly IntPtr handle;

    public static readonly ProcessJob App = new(killOnClose: true);

    public ProcessJob(bool killOnClose = true)
    {
        handle = CreateJobObject(IntPtr.Zero, null);
        if (handle == IntPtr.Zero) throw new Win32Exception();
        if (killOnClose)
        {
            var info = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
            info.BasicLimitInformation.LimitFlags = 0x2000; // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
            var size = Marshal.SizeOf(info);
            var ptr = Marshal.AllocHGlobal(size);
            Marshal.StructureToPtr(info, ptr, false);
            SetInformationJobObject(handle, 9, ptr, (uint)size); // JobObjectExtendedLimitInformation
            Marshal.FreeHGlobal(ptr);
        }
    }

    public void Add(Process process)
    {
        try { AssignProcessToJobObject(handle, process.Handle); } catch { }
    }

    /// <summary>Stops every process in the job (the tree started from it).</summary>
    public void Terminate() => TerminateJobObject(handle, 1);

    public void Dispose() => CloseHandle(handle);

    /// <summary>Starts a helper inside the app-wide job (and optionally its own job too).</summary>
    public static Process Start(ProcessStartInfo info, ProcessJob? own = null)
    {
        var process = Process.Start(info) ?? throw new InvalidOperationException(info.FileName);
        App.Add(process);
        own?.Add(process);
        return process;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct JOBOBJECT_BASIC_LIMIT_INFORMATION
    {
        public long PerProcessUserTimeLimit, PerJobUserTimeLimit;
        public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize, MaximumWorkingSetSize;
        public uint ActiveProcessLimit;
        public UIntPtr Affinity;
        public uint PriorityClass, SchedulingClass;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct IO_COUNTERS { public ulong a, b, c, d, e, f; }

    [StructLayout(LayoutKind.Sequential)]
    struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION
    {
        public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
        public IO_COUNTERS IoInfo;
        public UIntPtr ProcessMemoryLimit, JobMemoryLimit, PeakProcessMemoryUsed, PeakJobMemoryUsed;
    }

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr CreateJobObject(IntPtr attributes, string? name);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool SetInformationJobObject(IntPtr job, int infoClass, IntPtr info, uint length);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool TerminateJobObject(IntPtr job, uint exitCode);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool CloseHandle(IntPtr handle);
}
