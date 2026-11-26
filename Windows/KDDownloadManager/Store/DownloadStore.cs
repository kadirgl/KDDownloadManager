using System.ComponentModel;
using System.Runtime.CompilerServices;
using KDDownloadManager.Engine;
using KDDownloadManager.Models;

namespace KDDownloadManager.Store;

public enum Route { List, AddLink, Settings, Onboarding }

/// <summary>
/// The app's single source of truth (macOS: DownloadStore): the list, filters and screen routing.
/// UI thread only. <see cref="PropertyChanged"/> fires for its own properties; <see cref="ItemsChanged"/> when
/// items are added/removed or one of them changes status.
/// </summary>
public sealed class DownloadStore : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    public event Action? ItemsChanged;

    public List<DownloadItem> Items { get; private set; } = [];

    DownloadCategory _category = DownloadCategory.All;
    public DownloadCategory Category { get => _category; set => Set(ref _category, value); }

    ListTab _tab = ListTab.Active;
    public ListTab Tab { get => _tab; set { if (Set(ref _tab, value) && value == ListTab.Active) SearchText = ""; } }

    Route _route = Route.List;
    public Route Route { get => _route; set => Set(ref _route, value); }

    public bool PanelVisible { get; set; }
    /// <summary>The browser whose "Kur" was pressed in Settings; the setup screen opens for it.</summary>
    public string? OnboardingBrowser { get; set; }
    Guid? _selection;
    public Guid? Selection { get => _selection; set => Set(ref _selection, value); }

    string _search = "";
    public string SearchText { get => _search; set => Set(ref _search, value); }

    public CompletedSort CompletedSort
    {
        get => Enum.TryParse<CompletedSort>(Settings.Get(Settings.CompletedSortKey, "Newest"), true, out var s) ? s : CompletedSort.Newest;
        set { Settings.Set(Settings.CompletedSortKey, value.ToString().ToLowerInvariant()); Raise(); }
    }

    public sealed record PendingDeletion(DownloadItem Item, int Index, bool WasRunning, bool TrashesFile, DateTimeOffset Deadline);

    PendingDeletion? _pending;
    public PendingDeletion? Pending { get => _pending; private set => Set(ref _pending, value); }
    public static readonly TimeSpan UndoWindow = TimeSpan.FromSeconds(5);
    CancellationTokenSource? deletionTimer;

    /// <summary>When the last running download finished (the tray icon's short check mark).</summary>
    public DateTimeOffset? FinishedAt { get; private set; }

    public Dictionary<string, DateTimeOffset> ExtensionSeen { get; private set; } =
        Settings.GetDates(Settings.ExtensionSeen).Where(p => DateTimeOffset.Now - p.Value < TimeSpan.FromDays(14)).ToDictionary();

    readonly IDownloadEngine engine;
    readonly DownloadArchive? archive;
    string? lastSaved;
    bool hadActive;
    bool statusChangedSinceSave;
    Dictionary<Guid, DownloadStatus> lastStatuses = new();

    long _displaySpeed;
    /// <summary>Smoothed total speed, updated once a second (raw values jump around).</summary>
    public long DisplaySpeed { get => _displaySpeed; private set => Set(ref _displaySpeed, value); }
    const double SpeedSmoothing = 0.35;

    public DownloadStore(IDownloadEngine engine, DownloadArchive? archive)
    {
        this.engine = engine;
        this.archive = archive;
        engine.SetGlobalSpeedLimit(Settings.GlobalLimit);
        engine.SetMaxConcurrent(Settings.MaxConcurrent);
        if (archive != null)
        {
            Items = archive.Load();
            foreach (var item in Items) Watch(item);
            CategorizeExtensionlessFiles();
            if (archive.Path == DownloadArchive.DefaultPath)
            {
                var ids = Items.Select(i => i.Id).ToHashSet();
                _ = Task.Run(() => YtDlpEngine.RemoveOrphanedTemporaryFolders(ids));
            }
            lastSaved = archive.Encode(Items);
            foreach (var item in Items.Where(i => i.Status.Kind == StatusKind.Queued)) engine.Start(item);
            ShowCompletedIfIdle();
        }
        hadActive = HasActive;
        lastStatuses = Items.ToDictionary(i => i.Id, i => i.Status);
        _ = Tick();
    }

    async Task Tick()
    {
        var seconds = 0;
        while (true)
        {
            await Task.Delay(1000);
            var raw = TotalSpeed;
            DisplaySpeed = raw == 0 ? 0 : (long)(DisplaySpeed * (1 - SpeedSmoothing) + raw * SpeedSmoothing);
            if (++seconds % 2 == 0 && (HasActive || statusChangedSinceSave))
            {
                statusChangedSinceSave = false;
                Save();
            }
        }
    }

    void Watch(DownloadItem item) => item.PropertyChanged += OnItemChanged;

    void OnItemChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName != nameof(DownloadItem.Status)) return;
        var active = HasActive;
        if (hadActive && !active) ShowCompletedIfIdle();
        hadActive = active;
        statusChangedSinceSave = true;
        NotifyStatusChanges();
        ItemsChanged?.Invoke();
    }

    public bool HasActive => Items.Any(i => ListTab.Active.Includes(i.Status));
    public bool HasFailures => Items.Any(i => i.IsFailed);
    public long TotalSpeed => Items.Sum(i => i.Speed);

    public bool ExtensionEverConnected => Settings.Get(Settings.ExtensionEverConnected, false) || ExtensionSeen.Count > 0;
    public bool NeedsOnboarding => !ExtensionEverConnected && !Settings.Get(Settings.OnboardingSkipped, false);

    public void PanelWillOpen()
    {
        if (Route == Route.List && NeedsOnboarding) Route = Route.Onboarding;
        if (Route == Route.List && HasFailures) Tab = ListTab.Active;
        ShowCompletedIfIdle();
    }

    public void SkipOnboarding()
    {
        Settings.Set(Settings.OnboardingSkipped, true);
        Route = Route.List;
    }

    public void ShowCompletedIfIdle()
    {
        if (Route != Route.List || HasActive || !Items.Any(i => i.IsCompleted)) return;
        Tab = ListTab.Completed;
    }

    void NotifyStatusChanges()
    {
        var current = new Dictionary<Guid, DownloadStatus>();
        var finished = false;
        foreach (var item in Items)
        {
            current[item.Id] = item.Status;
            if (!lastStatuses.TryGetValue(item.Id, out var previous) || previous == item.Status) continue;
            switch (item.Status.Kind)
            {
                case StatusKind.Completed:
                    if (WebPageInsteadOfFile(item) is { } page)
                    {
                        try { File.Delete(page); } catch { }
                        item.Destination = null;
                        item.Status = DownloadStatus.Failed(L.T("Dosya yerine bir web sayfası indi; site giriş istiyor olabilir. Tarayıcıdan indirmeyi deneyin."));
                        current[item.Id] = item.Status;
                        Notifier.DownloadFailed(item, L.T("Dosya yerine bir web sayfası indi"));
                        continue;
                    }
                    AddMissingExtension(item);
                    item.CompletedAt ??= DateTimeOffset.Now;
                    finished = true;
                    Notifier.DownloadFinished(item);
                    break;
                case StatusKind.Failed:
                    if (previous.Kind != StatusKind.Failed) Notifier.DownloadFailed(item, item.Status.Message ?? "");
                    break;
            }
        }
        lastStatuses = current;
        if (finished && !HasActive && !HasFailures) FinishedAt = DateTimeOffset.Now;
    }

    void AddMissingExtension(DownloadItem item)
    {
        if (item.Source != DownloadSource.Direct) return;
        var file = item.Destination ?? Path.Combine(item.Folder, item.FileName);
        if (Path.HasExtension(file) || !File.Exists(file) || FileType.SniffExtension(file) is not { } ext) return;
        var folder = Path.GetDirectoryName(file)!;
        var name = Path.GetFileName(file) + "." + ext;
        if (File.Exists(Path.Combine(folder, name))) name = FreshName(name, folder);
        var renamed = Path.Combine(folder, name);
        try { File.Move(file, renamed); } catch { return; }
        item.Destination = renamed;
        item.FileName = name;
    }

    void CategorizeExtensionlessFiles()
    {
        foreach (var item in Items.Where(i => i.IsCompleted && i.Source == DownloadSource.Direct && i.Category == DownloadCategory.Other))
        {
            var file = item.Destination ?? Path.Combine(item.Folder, item.FileName);
            if (!Path.HasExtension(file) && FileType.SniffExtension(file) is { } ext) item.Category = DownloadCategories.ForFile("x." + ext);
        }
    }

    /// <summary>A small file named like a zip/pdf/mp4 whose content is HTML: the server's login or error page.</summary>
    public static string? WebPageInsteadOfFile(DownloadItem item)
    {
        if (item.Source != DownloadSource.Direct) return null;
        var file = item.Destination ?? Path.Combine(item.Folder, item.FileName);
        var ext = Path.GetExtension(file).TrimStart('.').ToLowerInvariant();
        if (ext.Length == 0 || new[] { "html", "htm", "xhtml", "php", "asp", "aspx", "jsp", "txt", "xml", "svg" }.Contains(ext)) return null;
        try
        {
            var info = new System.IO.FileInfo(file);
            if (!info.Exists || info.Length == 0 || info.Length >= 2_000_000) return null;
            using var stream = info.OpenRead();
            var buffer = new byte[512];
            var read = stream.Read(buffer, 0, buffer.Length);
            var head = System.Text.Encoding.UTF8.GetString(buffer, 0, read).Trim().ToLowerInvariant();
            return head.StartsWith("<!doctype html") || head.StartsWith("<html") ? file : null;
        }
        catch { return null; }
    }

    public List<DownloadItem> VisibleItems
    {
        get
        {
            var filtered = Items.Where(i => Tab.Includes(i.Status) && (Category == DownloadCategory.All || i.Category == Category)).ToList();
            if (Tab != ListTab.Completed) return filtered;
            var query = SearchText.Trim();
            var found = query.Length == 0 ? filtered : filtered.Where(i =>
                i.FileName.Contains(query, StringComparison.CurrentCultureIgnoreCase)
                || (DownloadSources.Host(i.Url) ?? "").Contains(query, StringComparison.CurrentCultureIgnoreCase)).ToList();
            return CompletedSort switch
            {
                CompletedSort.Name => found.OrderBy(i => i.FileName, StringComparer.Create(L.Culture, true)).ToList(),
                CompletedSort.Size => found.OrderByDescending(i => i.TotalBytes).ToList(),
                _ => found.Select((item, index) => (item, index))
                    .OrderByDescending(p => p.item.CompletedAt ?? DateTimeOffset.MinValue).ThenBy(p => p.index)
                    .Select(p => p.item).ToList(),
            };
        }
    }

    // MARK: Actions

    public void AddLinks(string text, VideoQuality quality = VideoQuality.Auto, long? speedLimit = null, bool startPaused = false, string? saveAs = null)
    {
        var requests = ParseLinks(text).Select(url => new DownloadRequest(url, quality: quality)).ToList();
        if (requests.Count == 1 && !string.IsNullOrEmpty(saveAs)) requests[0].SaveAs = saveAs;
        Insert(requests.Where(r => DownloadSources.LooksLikeLink(r.Url)).ToList(), speedLimit, startPaused);
    }

    readonly Dictionary<string, DateTimeOffset> recentRequests = new();
    static readonly TimeSpan RepeatWindow = TimeSpan.FromSeconds(10);

    /// <summary>From the panel or the browser extension; the same request twice within a few seconds is ignored.</summary>
    public void Add(IEnumerable<DownloadRequest> requests)
    {
        var now = DateTimeOffset.Now;
        foreach (var old in recentRequests.Where(p => now - p.Value >= RepeatWindow).Select(p => p.Key).ToList()) recentRequests.Remove(old);
        Insert(requests.Where(request =>
        {
            if (!DownloadSources.LooksLikeLink(request.Url)) return false;
            var key = $"{request.Url}|{request.Quality?.Raw()}|{request.Video == true}|{request.SaveAs}";
            if (recentRequests.ContainsKey(key)) return false;
            recentRequests[key] = now;
            return true;
        }).ToList());
    }

    /// <summary>Command line / shell activation: magnet links, URLs and .torrent files.</summary>
    public void Open(IEnumerable<string> arguments)
    {
        var torrents = new List<string>();
        var links = new List<DownloadRequest>();
        foreach (var argument in arguments)
        {
            if (argument.EndsWith(".torrent", StringComparison.OrdinalIgnoreCase) && File.Exists(argument)) torrents.Add(argument);
            else if (DownloadSources.LooksLikeLink(argument)) links.Add(new DownloadRequest(argument));
        }
        AddTorrentFiles(torrents);
        Add(links);
    }

    /// <summary>.torrent files from disk are copied into the app's folder so the download survives the original being moved.</summary>
    public void AddTorrentFiles(IEnumerable<string> files)
    {
        var requests = new List<DownloadRequest>();
        foreach (var file in files)
        {
            var copy = Path.Combine(AppFolders.Torrents, Guid.NewGuid().ToString().ToUpperInvariant() + ".torrent");
            try { File.Copy(file, copy); } catch { continue; }
            requests.Add(new DownloadRequest(new Uri(copy).AbsoluteUri, Path.GetFileNameWithoutExtension(file)));
        }
        Insert(requests);
    }

    void Insert(List<DownloadRequest> requests, long? speedLimit = null, bool startPaused = false)
    {
        if (requests.Count == 0) return;
        var names = new List<string>();
        foreach (var request in requests)
        {
            var saveAs = request.SaveAs is { } s && SanitizedFileName(s) is { Length: > 0 } clean ? clean : null;
            var name = saveAs ?? (string.IsNullOrEmpty(request.Filename) ? null : request.Filename);
            var item = new DownloadItem(request.Url.Trim(), name, forceVideo: request.Video == true);
            item.PreferredName = saveAs ?? (item.Source == DownloadSource.Direct && name != null && SanitizedFileName(name) is { Length: > 0 } n ? n : null);
            if (item.PreferredName != null) item.FileName = item.PreferredName;
            item.Referrer = request.Referrer;
            item.UserAgent = request.UserAgent;
            item.Cookies = request.Cookies;
            item.Quality = request.Quality ?? VideoQuality.Auto;
            if (request.CookieJar is { } jar && CookieVault.Site(item.Url) is { } site) CookieVault.Shared.Store(jar, site);
            item.SpeedLimit = speedLimit;
            if (item.Source == DownloadSource.Direct && Items.Any(other => other.Source == DownloadSource.Direct
                && string.Equals(Path.GetFullPath(other.Folder), Path.GetFullPath(item.Folder), StringComparison.OrdinalIgnoreCase)
                && string.Equals(other.FileName, item.FileName, StringComparison.OrdinalIgnoreCase)))
            {
                var unique = FreshName(item.FileName, item.Folder);
                item.FileName = unique;
                item.PreferredName = unique;
            }
            Items.Insert(0, item);
            Watch(item);
            lastStatuses[item.Id] = item.Status;
            if (startPaused) item.Status = DownloadStatus.Paused;
            else engine.Start(item);
            names.Add(item.FileName);
        }
        Notifier.DownloadsAdded(names);
        Tab = ListTab.Active;
        Category = DownloadCategory.All;
        if (Route == Route.AddLink) Route = Route.List;
        hadActive = HasActive;
        ItemsChanged?.Invoke();
        Save();
    }

    public bool AllActivePaused
    {
        get
        {
            var active = Items.Where(i => ListTab.Active.Includes(i.Status) && !i.IsFailed).ToList();
            return active.Count > 0 && active.All(i => i.Status.Kind == StatusKind.Paused);
        }
    }

    public void PauseAll()
    {
        foreach (var item in Items.Where(i => i.Status.IsRunning).ToList()) engine.Pause(item);
    }

    public void ResumeAll()
    {
        foreach (var item in Items.Where(i => i.Status.Kind == StatusKind.Paused).ToList()) engine.Resume(item);
    }

    public void RetryFailed()
    {
        foreach (var item in Items.Where(i => i.IsFailed).ToList()) engine.Resume(item);
    }

    public void ClearCompleted()
    {
        foreach (var item in Items.Where(i => i.IsCompleted).ToList()) engine.Cancel(item);
        Items.RemoveAll(i => i.IsCompleted);
        Selection = null;
        ItemsChanged?.Invoke();
        Save();
    }

    public DownloadItem? ExistingItem(string url) => Items.FirstOrDefault(i => i.Url == url.Trim());

    /// <summary>A name free in the folder and the list: "Rapor.pdf" → "Rapor (1).pdf".</summary>
    public string FreshName(string name, string folder, bool keepExtension = true)
    {
        var ext = Path.GetExtension(name);
        var stem = ext.Length == 0 ? name : Path.GetFileNameWithoutExtension(name);
        var taken = Items.Select(i => i.FileName).ToHashSet(StringComparer.OrdinalIgnoreCase);
        for (var number = 1; number < 1000; number++)
        {
            var candidate = $"{stem} ({number}){ext}";
            if (!File.Exists(Path.Combine(folder, candidate)) && !taken.Contains(candidate))
                return keepExtension ? candidate : Path.GetFileNameWithoutExtension(candidate);
        }
        return name;
    }

    public void TogglePause(DownloadItem item)
    {
        switch (item.Status.Kind)
        {
            case StatusKind.Downloading or StatusKind.Queued or StatusKind.Processing: engine.Pause(item); break;
            case StatusKind.Paused or StatusKind.Failed: engine.Resume(item); break;
        }
    }

    // MARK: Delete and undo

    public void Delete(DownloadItem item)
    {
        CommitPendingDeletion();
        var index = Items.FindIndex(i => i.Id == item.Id);
        if (index < 0) return;
        var wasRunning = item.Status.IsRunning;
        if (wasRunning) engine.Pause(item);
        Items.RemoveAt(index);
        if (Selection == item.Id) Selection = null;
        Pending = new PendingDeletion(item, index, wasRunning, item.IsCompleted, DateTimeOffset.Now + UndoWindow);
        var cts = deletionTimer = new CancellationTokenSource();
        _ = Task.Delay(UndoWindow, cts.Token).ContinueWith(t =>
        {
            if (!t.IsCanceled) CommitPendingDeletion();
        }, TaskScheduler.FromCurrentSynchronizationContext());
        ItemsChanged?.Invoke();
        Save();
    }

    public void UndoDelete()
    {
        if (Pending is not { } pending) return;
        deletionTimer?.Cancel();
        Pending = null;
        Items.Insert(Math.Min(pending.Index, Items.Count), pending.Item);
        Tab = ListTab.Active.Includes(pending.Item.Status) ? ListTab.Active : ListTab.Completed;
        if (Category != DownloadCategory.All && Category != pending.Item.Category) Category = DownloadCategory.All;
        Selection = pending.Item.Id;
        if (pending.WasRunning) engine.Resume(pending.Item);
        ItemsChanged?.Invoke();
        Save();
    }

    public void CommitPendingDeletion(bool terminating = false)
    {
        if (Pending is not { } pending) return;
        deletionTimer?.Cancel();
        Pending = null;
        var item = pending.Item;
        if (pending.TrashesFile)
        {
            engine.Cancel(item);
            if (item.Destination is { } file) RecycleBin.Send(file);
            return;
        }
        Cancel(item);
        if (terminating && item.Source == DownloadSource.Direct)
        {
            var file = Path.Combine(item.Folder, item.FileName);
            var control = file + ".aria2";
            if (File.Exists(control))
            {
                try { File.Delete(file); File.Delete(control); } catch { }
            }
        }
    }

    public void RemoveFromList(DownloadItem item)
    {
        if (Selection == item.Id) Selection = null;
        Cancel(item);
    }

    public void Cancel(DownloadItem item)
    {
        engine.Cancel(item);
        Items.RemoveAll(i => i.Id == item.Id);
        item.PropertyChanged -= OnItemChanged;
        if (Uri.TryCreate(item.Url, UriKind.Absolute, out var uri) && uri.IsFile
            && string.Equals(Path.GetDirectoryName(uri.LocalPath), AppFolders.Torrents, StringComparison.OrdinalIgnoreCase))
        {
            try { File.Delete(uri.LocalPath); } catch { }
        }
        ItemsChanged?.Invoke();
        Save();
    }

    public void SetSpeedLimit(long? limit, DownloadItem item)
    {
        engine.SetSpeedLimit(limit, item);
        Save();
    }

    public void ApplyGlobalSpeedLimit() => engine.SetGlobalSpeedLimit(Settings.GlobalLimit);
    public void ApplyMaxConcurrent() => engine.SetMaxConcurrent(Settings.MaxConcurrent);

    public static void Reveal(DownloadItem item) => Shell.Reveal(item.Destination, item.Folder);

    public void ExtensionDidConnect(string browser)
    {
        if (Route == Route.Onboarding && !PanelVisible)
        {
            Route = Route.List;
            OnboardingBrowser = null;
        }
        ExtensionSeen[browser] = DateTimeOffset.Now;
        Settings.SetDates(Settings.ExtensionSeen, ExtensionSeen);
        Settings.Set(Settings.ExtensionEverConnected, true);
        Raise(nameof(ExtensionSeen));
    }

    /// <summary>App is exiting: commit a pending deletion, stop engines, save.</summary>
    public void Shutdown()
    {
        CommitPendingDeletion(terminating: true);
        Save();
        engine.Shutdown();
    }

    public void Save()
    {
        if (archive == null) return;
        var json = archive.Encode(Items);
        if (json == lastSaved) return;
        archive.Write(json);
        lastSaved = json;
    }

    // MARK: Helpers

    // Characters Windows refuses in file names (control characters are checked separately). A fixed list rather than
    // Path.GetInvalidFileNameChars(), so the rules are the same when the tests run on macOS.
    static readonly char[] Invalid = ['<', '>', ':', '"', '/', '\\', '|', '?', '*'];

    /// <summary>Characters that cannot be in a Windows file name become "-"; length is limited.</summary>
    public static string SanitizedFileName(string name)
    {
        var cleaned = new string(name.Select(c => Invalid.Contains(c) || char.IsControl(c) ? '-' : c).ToArray()).Trim().Trim('.').Trim();
        var reserved = new[] { "CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "LPT1", "LPT2", "LPT3" };
        if (reserved.Contains(Path.GetFileNameWithoutExtension(cleaned).ToUpperInvariant())) cleaned = "_" + cleaned;
        return LimitedFileName(cleaned);
    }

    /// <summary>Leaves room for ".aria2"/".part" and the folder path (MAX_PATH); keeps the extension.</summary>
    public static string LimitedFileName(string name, int maxChars = 150)
    {
        if (name.Length <= maxChars) return name;
        var ext = Path.GetExtension(name);
        if (ext.Length > 12) ext = "";
        var stem = name[..^ext.Length];
        return stem[..Math.Max(1, maxChars - ext.Length)].Trim() + ext;
    }

    public static List<string> ParseLinks(string text) =>
        text.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries).Select(l => l.Trim()).Where(DownloadSources.LooksLikeLink).ToList();

    bool Set<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return false;
        field = value;
        Raise(name);
        return true;
    }

    void Raise([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
