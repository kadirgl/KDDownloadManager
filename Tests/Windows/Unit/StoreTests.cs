using KDDownloadManager.Models;
using KDDownloadManager.Store;
using Xunit;

namespace KDDownloadManager.Tests;

/// <summary>Listenin davranışı, sahte motorla (Mac: StoreTests.swift).</summary>
public class StoreTests
{
    readonly RecordingEngine engine = new();
    readonly DownloadStore store;

    public StoreTests() => store = new DownloadStore(engine, null);

    [Fact]
    public void AddLinks()
    {
        store.AddLinks("https://a.example/1.zip\nmerhaba\nhttps://a.example/2.pdf");
        Assert.Equal(["2.pdf", "1.zip"], store.Items.Select(i => i.FileName));
        Assert.Equal(2, engine.Calls.Count(c => c.StartsWith("start:")));
        Assert.Equal(ListTab.Active, store.Tab);
    }

    [Fact]
    public void SaveAsIsSanitized()
    {
        store.AddLinks("https://a.example/x", saveAs: "Yeni/Ad.pdf");
        Assert.Equal("Yeni-Ad.pdf", store.Items[0].FileName);
        Assert.Equal("Yeni-Ad.pdf", store.Items[0].PreferredName);
    }

    [Fact]
    public void BrowserNameGoesToAria2()
    {
        store.Add([new DownloadRequest("https://download.example.com/?file=abc123", "VMware-Fusion.dmg") { FromBrowserDownload = true }]);
        Assert.Equal("VMware-Fusion.dmg", store.Items[0].FileName);
        Assert.Equal("VMware-Fusion.dmg", store.Items[0].PreferredName);
        Assert.Equal(DownloadCategory.App, store.Items[0].Category);

        store.Add([new DownloadRequest("https://www.youtube.com/watch?v=1", "watch")]);
        Assert.Null(store.Items[0].PreferredName);
    }

    [Fact]
    public void DuplicateRequestIgnored()
    {
        var request = new DownloadRequest("https://a.example/tekrar.zip");
        store.Add([request]);
        store.Add([request]);
        Assert.Single(store.Items);
        store.Add([new DownloadRequest("https://www.youtube.com/watch?v=1", quality: VideoQuality.P720),
                   new DownloadRequest("https://www.youtube.com/watch?v=1", quality: VideoQuality.Audio)]);
        Assert.Equal(3, store.Items.Count);
    }

    [Fact]
    public void UniqueNamesIgnoreCase()
    {
        store.AddLinks("https://a.example/rapor.pdf");
        store.AddLinks("https://b.example/rapor.pdf");
        store.AddLinks("https://c.example/RAPOR.pdf");
        Assert.Equal(["RAPOR (2).pdf", "rapor (1).pdf", "rapor.pdf"], store.Items.Select(i => i.FileName));
    }

    [Fact]
    public void FreshNameChecksDisk()
    {
        var folder = TestEnvironment.Scratch();
        File.WriteAllBytes(Path.Combine(folder, "a (1).zip"), []);
        Assert.Equal("a (2).zip", store.FreshName("a.zip", folder));
        Assert.Equal("video (1)", store.FreshName("video", folder, keepExtension: false));
    }

    [Fact]
    public void StartPausedAndLimits()
    {
        store.AddLinks("https://a.example/bekle.zip", startPaused: true);
        Assert.Equal(StatusKind.Paused, store.Items[0].Status.Kind);
        Assert.DoesNotContain(engine.Calls, c => c.StartsWith("start:"));

        store.AddLinks("https://a.example/s.zip", speedLimit: 512_000);
        Assert.Equal(512_000, store.Items[0].SpeedLimit);
        store.SetSpeedLimit(null, store.Items[0]);
        Assert.Equal($"limit:{store.Items[0].Id}:", engine.Calls[^1]);
    }

    [Fact]
    public void PauseResumeRetry()
    {
        store.AddLinks("https://a.example/1.zip\nhttps://a.example/2.zip");
        var first = store.Items[0];
        store.TogglePause(first);
        Assert.Equal(StatusKind.Paused, first.Status.Kind);
        store.TogglePause(first);
        Assert.Equal(StatusKind.Downloading, first.Status.Kind);
        store.PauseAll();
        Assert.True(store.AllActivePaused);
        store.ResumeAll();
        Assert.All(store.Items, i => Assert.Equal(StatusKind.Downloading, i.Status.Kind));
        store.Items[1].SetStatus(DownloadStatus.Failed("x"));
        Assert.True(store.HasFailures);
        store.RetryFailed();
        Assert.False(store.HasFailures);
    }

    [Fact]
    public void DeleteAndUndo()
    {
        store.AddLinks("https://a.example/1.zip\nhttps://a.example/2.zip\nhttps://a.example/3.zip");
        var middle = store.Items[1];
        store.Delete(middle);
        Assert.DoesNotContain(middle, store.Items);
        Assert.Equal(middle, store.Pending?.Item);
        Assert.Contains("pause:" + middle.Id, engine.Calls);
        store.UndoDelete();
        Assert.Equal(middle, store.Items[1]);
        Assert.Null(store.Pending);
        Assert.Equal("resume:" + middle.Id, engine.Calls[^1]);
    }

    [Fact]
    public void DeletingCompletedSendsFileToRecycleBin()
    {
        var file = Path.Combine(TestEnvironment.Scratch(), "bitti.txt");
        File.WriteAllText(file, "x");
        store.AddLinks("https://a.example/bitti.txt");
        var item = store.Items[0];
        item.SetStatus(DownloadStatus.Completed);
        item.Destination = file;
        store.Delete(item);
        Assert.True(File.Exists(file));
        store.CommitPendingDeletion();
        Assert.False(File.Exists(file));
        Assert.Contains(file, RecycleBin.Sent);
    }

    [Fact]
    public void VisibleItemsFilterSortSearch()
    {
        store.AddLinks("https://a.example/b-film.mp4\nhttps://cdn.site.example/a-rapor.pdf\nhttps://a.example/c-sarki.mp3\nhttps://a.example/inen.zip");
        var byName = store.Items.ToDictionary(i => i.FileName);
        foreach (var (name, size, day) in new[] { ("b-film.mp4", 300, 1), ("a-rapor.pdf", 100, 3), ("c-sarki.mp3", 200, 2) })
        {
            var item = byName[name];
            item.SetStatus(DownloadStatus.Completed);
            item.TotalBytes = size;
            item.CompletedAt = DateTimeOffset.FromUnixTimeSeconds(day * 86_400);
        }
        store.Tab = ListTab.Active;
        Assert.Equal(["inen.zip"], store.VisibleItems.Select(i => i.FileName));
        store.Tab = ListTab.Completed;
        store.CompletedSort = CompletedSort.Newest;
        Assert.Equal(["a-rapor.pdf", "c-sarki.mp3", "b-film.mp4"], store.VisibleItems.Select(i => i.FileName));
        store.CompletedSort = CompletedSort.Name;
        Assert.Equal(["a-rapor.pdf", "b-film.mp4", "c-sarki.mp3"], store.VisibleItems.Select(i => i.FileName));
        store.CompletedSort = CompletedSort.Size;
        Assert.Equal(["b-film.mp4", "c-sarki.mp3", "a-rapor.pdf"], store.VisibleItems.Select(i => i.FileName));
        store.Category = DownloadCategory.Music;
        Assert.Equal(["c-sarki.mp3"], store.VisibleItems.Select(i => i.FileName));
        store.Category = DownloadCategory.All;
        store.SearchText = "site.example";
        Assert.Equal(["a-rapor.pdf"], store.VisibleItems.Select(i => i.FileName));
    }

    [Fact]
    public void WebPageInsteadOfFile()
    {
        var folder = TestEnvironment.Scratch();
        DownloadItem Item(string name, string content)
        {
            var file = Path.Combine(folder, name);
            File.WriteAllText(file, content);
            return new DownloadItem("https://a.example/" + name, folder: folder) { Status = DownloadStatus.Completed, Destination = file };
        }
        Assert.NotNull(DownloadStore.WebPageInsteadOfFile(Item("setup.zip", "  <!DOCTYPE html><html>Giriş yapın")));
        Assert.Null(DownloadStore.WebPageInsteadOfFile(Item("gercek.zip", "PK\u0003\u0004...")));
        Assert.Null(DownloadStore.WebPageInsteadOfFile(Item("sayfa.html", "<html>")));
        Assert.Null(DownloadStore.WebPageInsteadOfFile(Item("adsız", "<html>")));
    }

    [Fact]
    public void LoadsArchiveAndResumesQueued()
    {
        var archive = new DownloadArchive(Path.Combine(TestEnvironment.Scratch(), "downloads.json"));
        var queued = new DownloadItem("https://a.example/devam.zip") { Status = DownloadStatus.Downloading };
        var paused = new DownloadItem("https://a.example/bekle.zip") { Status = DownloadStatus.Paused };
        archive.Write(archive.Encode([queued, paused]));
        var engine = new RecordingEngine();
        var store = new DownloadStore(engine, archive);
        Assert.Equal(2, store.Items.Count);
        Assert.Contains("start:" + queued.Id, engine.Calls);
        Assert.DoesNotContain("start:" + paused.Id, engine.Calls);
        store.Cancel(store.Items[0]);
        Assert.Single(archive.Load());
    }
}
