using KDDownloadManager.Models;

namespace KDDownloadManager.Engine;

/// <summary>
/// Sends video sites to yt-dlp and everything else to aria2, and shares the global speed limit between them
/// (macOS: RoutingEngine): every downloading item gets an equal share; items whose own limit is lower give
/// the rest to the others.
/// </summary>
public sealed class RoutingEngine(IDownloadEngine files, IDownloadEngine videos) : IDownloadEngine
{
    readonly Dictionary<Guid, DownloadItem> items = new();
    long? globalLimit;
    (long? files, long? videos)? applied;
    CancellationTokenSource? monitor;
    const double VideoRestartThreshold = 0.15;

    IDownloadEngine EngineFor(DownloadItem item) => item.Source == DownloadSource.Video ? videos : files;

    public void Start(DownloadItem item)
    {
        items[item.Id] = item;
        EngineFor(item).Start(item);
    }

    public void Pause(DownloadItem item) => EngineFor(item).Pause(item);

    public void Resume(DownloadItem item)
    {
        items[item.Id] = item;
        EngineFor(item).Resume(item);
    }

    public void Cancel(DownloadItem item)
    {
        items.Remove(item.Id);
        EngineFor(item).Cancel(item);
    }

    public void SetSpeedLimit(long? limit, DownloadItem item)
    {
        EngineFor(item).SetSpeedLimit(limit, item);
        Rebalance();
    }

    public async void SetGlobalSpeedLimit(long? limit)
    {
        globalLimit = limit;
        monitor?.Cancel();
        monitor = null;
        if (limit == null)
        {
            Apply((null, null));
            return;
        }
        Rebalance();
        var cts = monitor = new CancellationTokenSource();
        try
        {
            while (!cts.IsCancellationRequested)
            {
                await Task.Delay(1000, cts.Token);
                Rebalance();
            }
        }
        catch (TaskCanceledException) { }
    }

    public void SetMaxConcurrent(int count)
    {
        files.SetMaxConcurrent(count);
        videos.SetMaxConcurrent(count);
    }

    public void Shutdown()
    {
        files.Shutdown();
        videos.Shutdown();
    }

    void Rebalance()
    {
        if (globalLimit is not { } total) return;
        var active = items.Values.Where(i => i.Status.Kind == StatusKind.Downloading).ToList();
        var shares = Shares(total, active.Select(i => i.SpeedLimit).ToList());
        var fileShares = active.Zip(shares).Where(p => p.First.Source != DownloadSource.Video).Select(p => p.Second).ToList();
        var videoShares = active.Zip(shares).Where(p => p.First.Source == DownloadSource.Video).Select(p => p.Second).ToList();
        long? filesPlan = fileShares.Count == 0 ? total : fileShares.Sum();
        long? videosPlan = videoShares.Count == 0 ? total : videoShares.Max();
        if (applied?.videos is { } old && videosPlan is { } next && old > 0 && Math.Abs((double)(next - old)) / old < VideoRestartThreshold)
            videosPlan = old;
        Apply((filesPlan, videosPlan));
    }

    void Apply((long? files, long? videos) plan)
    {
        if (applied == plan) return;
        if (plan.files != applied?.files) files.SetGlobalSpeedLimit(plan.files);
        if (plan.videos != applied?.videos) videos.SetGlobalSpeedLimit(plan.videos);
        applied = plan;
    }

    public static List<long> Shares(long total, List<long?> caps)
    {
        var result = new long[caps.Count];
        var open = new HashSet<int>(Enumerable.Range(0, caps.Count));
        var remaining = total;
        while (open.Count > 0)
        {
            var equal = remaining / open.Count;
            var capped = open.Where(i => caps[i] is { } cap && cap <= equal).ToList();
            if (capped.Count == 0)
            {
                foreach (var i in open) result[i] = equal;
                break;
            }
            foreach (var i in capped)
            {
                result[i] = caps[i]!.Value;
                remaining -= caps[i]!.Value;
                open.Remove(i);
            }
        }
        return result.ToList();
    }
}
