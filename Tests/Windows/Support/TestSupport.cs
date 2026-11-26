using System.Collections.Concurrent;
using System.Net;
using System.Net.Sockets;
using System.Runtime.CompilerServices;
using KDDownloadManager.Engine;
using KDDownloadManager.Models;
using Xunit;

namespace KDDownloadManager.Tests;

/// <summary>
/// Testler gerçek listeye, ayarlara ve indirme klasörüne dokunmasın: uygulama kodu ilk okumadan önce her şey
/// geçici bir klasöre yönlendirilir (modül yüklenirken).
/// </summary>
public static class TestEnvironment
{
    public static readonly string Root = Environment.GetEnvironmentVariable("KD_TEST_ROOT") is { Length: > 0 } root
        ? Path.Combine(root, "windows")
        : Path.Combine(Path.GetTempPath(), "KDDownloadManagerTests-win-" + Environment.ProcessId);

    public const int BridgePort = 47_691;

    public static string Downloads => Path.Combine(Root, "Downloads");

    [ModuleInitializer]
    internal static void Prepare()
    {
        Directory.CreateDirectory(Downloads);
        Environment.SetEnvironmentVariable("KD_SUPPORT_DIR", Path.Combine(Root, "Support"));
        Environment.SetEnvironmentVariable("KD_DOWNLOAD_FOLDER", Downloads);
        Environment.SetEnvironmentVariable("KD_BRIDGE_PORT", BridgePort.ToString());
        // Metinler Türkçe kalsın (beklenen değerler Türkçe).
        Settings.Set(Settings.Language, "tr");
        foreach (var key in new[] { Settings.NotifyOnAdd, Settings.NotifyOnFinish, Settings.NotifyOnFail }) Settings.Set(key, false);
    }

    public static string Scratch([CallerMemberName] string name = "")
    {
        var folder = Path.Combine(Root, "scratch", name + "-" + Guid.NewGuid().ToString("N")[..8]);
        Directory.CreateDirectory(folder);
        return folder;
    }

    /// <summary>Depo kökü (Package.swift'in klasörü).</summary>
    public static string Repository
    {
        get
        {
            var dir = AppContext.BaseDirectory;
            while (dir != null && !File.Exists(Path.Combine(dir, "Package.swift"))) dir = Path.GetDirectoryName(dir);
            return dir ?? throw new InvalidOperationException("Package.swift bulunamadı");
        }
    }

    public static async Task<bool> WaitUntil(Func<bool> condition, double seconds)
    {
        var deadline = DateTime.UtcNow.AddSeconds(seconds);
        while (DateTime.UtcNow < deadline)
        {
            if (condition()) return true;
            await Task.Delay(50);
        }
        return condition();
    }
}

/// <summary>Yalnızca Windows'ta çalışan testler (gerçek aria2c.exe, iş nesneleri, Kayıt Defteri).</summary>
public sealed class WindowsFactAttribute : FactAttribute
{
    public WindowsFactAttribute()
    {
        if (!OperatingSystem.IsWindows()) Skip = "Yalnızca Windows'ta (sanal makinede) çalışır";
    }
}

/// <summary>Listenin motora ne söylediğini kaydeden sahte motor.</summary>
public sealed class RecordingEngine : IDownloadEngine
{
    public readonly List<string> Calls = [];

    public void Start(DownloadItem item) { Calls.Add("start:" + item.Id); item.SetStatus(DownloadStatus.Downloading); }
    public void Pause(DownloadItem item) { Calls.Add("pause:" + item.Id); item.SetStatus(DownloadStatus.Paused); }
    public void Resume(DownloadItem item) { Calls.Add("resume:" + item.Id); item.SetStatus(DownloadStatus.Downloading); }
    public void Cancel(DownloadItem item) => Calls.Add("cancel:" + item.Id);
    public void SetSpeedLimit(long? limit, DownloadItem item) { Calls.Add($"limit:{item.Id}:{limit}"); item.SpeedLimit = limit; }
    public void SetGlobalSpeedLimit(long? limit) => Calls.Add($"global:{limit}");
    public void SetMaxConcurrent(int count) => Calls.Add($"concurrent:{count}");
    public void Shutdown() => Calls.Add("shutdown");
}

/// <summary>
/// 127.0.0.1'de küçük HTTP sunucusu: gerçek sitelerin davranışını (Broadcom'un türsüz Content-Disposition'ı, parçalı
/// indirme, 404, HTML hata sayfası…) internete çıkmadan taklit eder. Range istekleri 206 ile yanıtlanır.
/// </summary>
public sealed class TestServer : IDisposable
{
    public sealed record Request(string Method, string Path, Dictionary<string, string> Headers);

    public sealed record Response(int Status, Dictionary<string, string> Headers, byte[] Body, bool AcceptsRanges = true)
    {
        public static Response File(byte[] body, Dictionary<string, string>? headers = null) => new(200, headers ?? [], body);
        public static Response Text(string text, Dictionary<string, string>? headers = null) =>
            new(200, headers ?? new() { ["Content-Type"] = "text/plain" }, System.Text.Encoding.UTF8.GetBytes(text));
        public static Response Code(int code) => new(code, new() { ["Content-Type"] = "text/plain" }, [], false);
    }

    readonly TcpListener listener = new(IPAddress.Loopback, 0);
    readonly ConcurrentDictionary<string, Func<Request, Response>> routes = new();
    public readonly ConcurrentQueue<Request> Requests = new();
    public int Port { get; }

    public TestServer()
    {
        listener.Start();
        Port = ((IPEndPoint)listener.LocalEndpoint).Port;
        _ = Task.Run(AcceptLoop);
    }

    public string Url(string path) => $"http://127.0.0.1:{Port}{path}";

    public void Route(string path, Response response) => routes[path] = _ => response;

    public IEnumerable<Request> RequestsTo(string path) => Requests.Where(r => r.Path == path || r.Path.StartsWith(path + "?"));

    async Task AcceptLoop()
    {
        while (true)
        {
            TcpClient client;
            try { client = await listener.AcceptTcpClientAsync(); }
            catch { return; }
            _ = Task.Run(() => Serve(client));
        }
    }

    async Task Serve(TcpClient client)
    {
        using (client)
        {
            try
            {
                var stream = client.GetStream();
                var reader = new StreamReader(stream, System.Text.Encoding.ASCII, false, 1024, leaveOpen: true);
                var first = await reader.ReadLineAsync();
                if (string.IsNullOrEmpty(first)) return;
                var parts = first.Split(' ');
                var headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                string? line;
                while (!string.IsNullOrEmpty(line = await reader.ReadLineAsync()))
                {
                    var colon = line.IndexOf(':');
                    if (colon > 0) headers[line[..colon].Trim().ToLowerInvariant()] = line[(colon + 1)..].Trim();
                }
                var request = new Request(parts[0], parts[1], headers);
                Requests.Enqueue(request);
                var bare = request.Path.Split('?')[0];
                var response = (routes.TryGetValue(request.Path, out var exact) ? exact : routes.TryGetValue(bare, out var plain) ? plain : null)
                    ?.Invoke(request) ?? Response.Code(404);

                var status = response.Status;
                var body = response.Body;
                var outHeaders = new Dictionary<string, string>(response.Headers);
                if (response.AcceptsRanges && status == 200)
                {
                    outHeaders["Accept-Ranges"] = "bytes";
                    if (headers.TryGetValue("range", out var range) && ByteRange(range, body.Length) is var (start, end))
                    {
                        status = 206;
                        outHeaders["Content-Range"] = $"bytes {start}-{end}/{body.Length}";
                        body = body[start..(end + 1)];
                    }
                }
                outHeaders["Content-Length"] = body.Length.ToString();
                outHeaders["Connection"] = "close";
                var head = $"HTTP/1.1 {status} X\r\n" + string.Concat(outHeaders.Select(h => $"{h.Key}: {h.Value}\r\n")) + "\r\n";
                await stream.WriteAsync(System.Text.Encoding.UTF8.GetBytes(head));
                if (request.Method != "HEAD") await stream.WriteAsync(body);
            }
            catch (IOException) { }
            catch (SocketException) { }
        }
    }

    static (int start, int end)? ByteRange(string header, int size)
    {
        if (size == 0 || !header.StartsWith("bytes=")) return null;
        var spec = header[6..].Split(',')[0].Split('-');
        if (spec.Length != 2 || !int.TryParse(spec[0], out var start) || start >= size) return null;
        var end = int.TryParse(spec[1], out var e) ? Math.Min(e, size - 1) : size - 1;
        return start <= end ? (start, end) : null;
    }

    public void Dispose() => listener.Stop();

    public static byte[] Pattern(int size, int seed = 7)
    {
        var data = new byte[size];
        uint value = (uint)seed;
        for (var i = 0; i < size; i++)
        {
            value = value * 1_103_515_245 + 12_345;
            data[i] = (byte)(value >> 16);
        }
        return data;
    }
}
