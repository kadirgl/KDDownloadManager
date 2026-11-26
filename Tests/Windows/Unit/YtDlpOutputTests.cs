using KDDownloadManager.Engine;
using Xunit;

namespace KDDownloadManager.Tests;

/// <summary>
/// yt-dlp output on Windows: aria2c leaves its last readout without a line break, so the "part finished" message is glued
/// to it (recorded from a real download; Mac: YtDlpProgressTests.swift).
/// </summary>
public class YtDlpOutputTests
{
    [Fact]
    public void SplitsGluedFinishedMessage()
    {
        const string glued = """[#caef46 70MiB/77MiB(91%) CN:8 DL:74MiB]KDPROG {"status": "finished", "downloaded_bytes": 80911999}""";
        Assert.Equal(["[#caef46 70MiB/77MiB(91%) CN:8 DL:74MiB]", """KDPROG {"status": "finished", "downloaded_bytes": 80911999}"""],
            YtDlpEngine.OutputLines(glued));
    }

    [Theory]
    [InlineData("[#acafac 1.0MiB/3.2MiB(30%) CN:1 DL:2.3MiB]")]
    [InlineData("KDFILE C:\\Users\\x\\Downloads\\a.mp4")]
    // Our own message is never split, even if the title contains a marker.
    [InlineData("""KDINFO {"title": "KDPROG nedir? KDFILE açıklaması"}""")]
    [InlineData("")]
    public void LeavesOtherLinesAlone(string line) => Assert.Equal([line], YtDlpEngine.OutputLines(line));
}
