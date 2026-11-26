using KDDownloadManager.Engine;
using Xunit;

namespace KDDownloadManager.Tests;

/// <summary>yt-dlp is only updated with the app (Mac: YtDlpTests.swift).</summary>
public class YtDlpTests
{
    [Fact]
    public void RemovesDownloadedCopies()
    {
        var root = Path.Combine(AppFolders.Support, "yt-dlp");
        Directory.CreateDirectory(Path.Combine(root, "2026.11.23"));
        File.WriteAllText(Path.Combine(root, "2026.11.23", "yt-dlp.exe"), "x");
        File.WriteAllText(Path.Combine(root, "current.version"), "2026.11.23");
        var settings = Path.Combine(AppFolders.Support, "settings.json");
        YtDlp.RemoveDownloadedCopies();
        Assert.False(Directory.Exists(root));
        Assert.True(File.Exists(settings));
        YtDlp.RemoveDownloadedCopies();
    }

    [Fact]
    public void ListingSkipsJavaScript() =>
        Assert.Equal(["--no-js-runtimes", "--extractor-args", "youtube:player_skip=js"], VideoFormats.ListingArguments);
}
