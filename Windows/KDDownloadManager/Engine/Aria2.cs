using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json.Nodes;
using KDDownloadManager.Models;

namespace KDDownloadManager.Engine;

/// <summary>What the UI expects from a download engine (macOS: DownloadEngine).</summary>
public interface IDownloadEngine
{
    void Start(DownloadItem item);
    void Pause(DownloadItem item);
    void Resume(DownloadItem item);
    void Cancel(DownloadItem item);
    void SetSpeedLimit(long? limit, DownloadItem item);
    void SetGlobalSpeedLimit(long? limit);
    void SetMaxConcurrent(int count);
    /// <summary>The app is exiting: stop helpers so partial files can be resumed next time.</summary>
    void Shutdown();
}

public sealed class Aria2Exception(string message) : Exception(message);

/// <summary>Thin client for aria2c's JSON-RPC interface.</summary>
public sealed class Aria2Client(int port, string secret)
{
    readonly Uri endpoint = new($"http://127.0.0.1:{port}/jsonrpc");
    readonly string token = "token:" + secret;
    static readonly HttpClient Http = new(new SocketsHttpHandler { UseProxy = false }) { Timeout = TimeSpan.FromSeconds(10) };

    public async Task<JsonNode?> Call(string method, params JsonNode?[] parameters)
    {
        var response = await Send(method, [JsonValue.Create(token), .. parameters]);
        if (response?["error"] is { } error) throw new Aria2Exception(error["message"]?.GetValue<string>() ?? L.T("aria2 hatası"));
        return response?["result"];
    }

    /// <summary>Several calls in one request; each result is the value or the call's error.</summary>
    public async Task<List<(JsonNode? value, string? error)>> Multicall(IEnumerable<(string method, JsonNode?[] parameters)> calls)
    {
        var payload = new JsonArray();
        foreach (var (method, parameters) in calls)
            payload.Add(new JsonObject { ["methodName"] = method, ["params"] = new JsonArray([JsonValue.Create(token), .. parameters]) });
        var response = await Send("system.multicall", [payload]);
        if (response?["error"] is { } error) throw new Aria2Exception(error["message"]?.GetValue<string>() ?? L.T("aria2 hatası"));
        var results = new List<(JsonNode?, string?)>();
        foreach (var entry in response?["result"]?.AsArray() ?? [])
            results.Add(entry is JsonArray { Count: > 0 } ok ? (ok[0], null) : (null, entry?["faultString"]?.GetValue<string>() ?? "aria2"));
        return results;
    }

    async Task<JsonNode?> Send(string method, JsonNode?[] parameters)
    {
        var body = new JsonObject
        {
            ["jsonrpc"] = "2.0",
            ["id"] = Guid.NewGuid().ToString(),
            ["method"] = method,
            ["params"] = new JsonArray(parameters.Select(p => p?.DeepClone()).ToArray()),
        };
        using var content = new StringContent(body.ToJsonString(), Encoding.UTF8, "application/json");
        using var response = await Http.PostAsync(endpoint, content);
        return JsonNode.Parse(await response.Content.ReadAsStringAsync());
    }
}

/// <summary>Starts aria2c in RPC mode and returns the client once it answers.</summary>
public sealed class Aria2Daemon
{
    Process? process;
    public Aria2Client? Client { get; private set; }

    public bool IsRunning => process is { HasExited: false };

    public async Task<Aria2Client> Start(int maxConcurrent, long? globalLimit)
    {
        var binary = Tools.Find("aria2c") ?? throw new Aria2Exception(L.T("aria2c bulunamadı"));
        var port = FreePort();
        var secret = Guid.NewGuid().ToString("N");
        string[] arguments =
        [
            "--enable-rpc", "--rpc-listen-all=false", $"--rpc-listen-port={port}", $"--rpc-secret={secret}",
            $"--stop-with-process={Environment.ProcessId}",
            "--continue=true",
            "--max-connection-per-server=8", "--split=8", "--min-split-size=1M",
            // Pre-allocating on NTFS is quick with falloc-less "prealloc"; none keeps it simple and sparse.
            "--file-allocation=none",
            "--retry-wait=3", "--max-tries=8",
            $"--max-concurrent-downloads={maxConcurrent}",
            $"--max-overall-download-limit={globalLimit ?? 0}",
            "--seed-time=0", "--follow-torrent=mem", "--rpc-save-upload-metadata=false",
            "--enable-dht=true", "--dht-entry-point=dht.transmissionbt.com:6881",
            $"--dht-file-path={Path.Combine(AppFolders.Support, "dht.dat")}",
            $"--dht-file-path6={Path.Combine(AppFolders.Support, "dht6.dat")}",
            "--auto-save-interval=10",
            "--console-log-level=warn",
        ];
        var info = Tools.StartInfo(binary, arguments, redirect: false);
        process = ProcessJob.Start(info);

        var client = new Aria2Client(port, secret);
        for (var i = 0; i < 80; i++)
        {
            try
            {
                await client.Call("aria2.getVersion");
                Client = client;
                return client;
            }
            catch { }
            if (process.HasExited) break;
            await Task.Delay(100);
        }
        Stop();
        throw new Aria2Exception(L.T("aria2c başlatılamadı"));
    }

    /// <summary>Asks aria2c to shut down (it writes the .aria2 control files), then makes sure it is gone.</summary>
    public void Stop()
    {
        var p = process;
        process = null;
        if (p == null) return;
        try
        {
            // On the thread pool: the UI thread is blocked here, so the call must not resume on it.
            if (Client is { } client && !p.HasExited) Task.Run(() => client.Call("aria2.forceShutdown")).Wait(1500);
            if (!p.WaitForExit(1500)) p.Kill();
        }
        catch { try { p.Kill(); } catch { } }
        Client = null;
    }

    static int FreePort()
    {
        var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        var port = ((IPEndPoint)listener.LocalEndpoint).Port;
        listener.Stop();
        return port;
    }
}
