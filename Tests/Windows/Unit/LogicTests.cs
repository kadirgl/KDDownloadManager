using System.Text.Json;
using System.Text.Json.Nodes;
using KDDownloadManager.Engine;
using KDDownloadManager.Models;
using KDDownloadManager.Store;
using Xunit;

namespace KDDownloadManager.Tests;

/// <summary>Linkin hangi motora gideceği ve indirme satırının ilk adı (Mac: LinkTests.swift).</summary>
public class LinkTests
{
    [Theory]
    [InlineData("https://www.youtube.com/watch?v=abc")]
    [InlineData("https://youtu.be/abc")]
    [InlineData("https://m.youtube.com/watch?v=1")]
    [InlineData("https://vimeo.com/1234")]
    [InlineData("https://x.com/user/status/1")]
    [InlineData("HTTPS://WWW.YOUTUBE.COM/watch?v=CAPS")]
    public void VideoSites(string link)
    {
        Assert.Equal(DownloadSource.Video, DownloadSources.Detect(link));
        Assert.True(DownloadSources.IsKnownVideoSite(link));
    }

    [Fact]
    public void StreamsTorrentsAndFiles()
    {
        Assert.Equal(DownloadSource.Video, DownloadSources.Detect("https://cdn.example.com/live/master.m3u8?token=1"));
        Assert.Equal(DownloadSource.Video, DownloadSources.Detect("https://cdn.example.com/a/manifest.mpd"));
        Assert.False(DownloadSources.IsKnownVideoSite("https://cdn.example.com/live/master.m3u8"));
        Assert.Equal(DownloadSource.Torrent, DownloadSources.Detect("magnet:?xt=urn:btih:abc&dn=ubuntu.iso"));
        Assert.Equal(DownloadSource.Torrent, DownloadSources.Detect("https://releases.ubuntu.com/a.iso.torrent"));
        Assert.Equal(DownloadSource.Direct, DownloadSources.Detect("https://example.com/file.zip"));
        Assert.Equal(DownloadSource.Direct, DownloadSources.Detect("https://notyoutube.com/a.mp4"));
        Assert.Equal(DownloadSource.Direct, DownloadSources.Detect("https://youtube.com.evil.example/a"));
    }

    [Fact]
    public void LooksLikeLink()
    {
        foreach (var link in new[] { "http://a.b", "https://a.b/c", "  https://a.b  ", "FTP://x/y", "magnet:?xt=1" })
            Assert.True(DownloadSources.LooksLikeLink(link), link);
        foreach (var text in new[] { "", "www.example.com", "javascript:alert(1)", "file:///etc/passwd", "merhaba" })
            Assert.False(DownloadSources.LooksLikeLink(text), text);
    }

    [Fact]
    public void SuggestedNames()
    {
        Assert.Equal("Yillik Rapor.pdf", new DownloadItem("https://example.com/files/Yillik%20Rapor.pdf").FileName);
        Assert.Equal("a.zip", new DownloadItem("https://example.com/files/a.zip?x=1").FileName);
        // Broadcom'un "/?file=…" adresleri: adreste ad yok.
        Assert.Equal("İndirme", new DownloadItem("https://example.com/?file=VMware-Fusion.dmg").FileName);
        Assert.Equal("ubuntu-24.04.iso", new DownloadItem("magnet:?xt=urn:btih:0000&dn=ubuntu-24.04.iso").FileName);
        Assert.Equal("YouTube videosu", new DownloadItem("https://www.youtube.com/watch?v=x").FileName);
    }

    [Fact]
    public void CategoryFollowsNameAndQuality()
    {
        var file = new DownloadItem("https://example.com/download");
        Assert.Equal(DownloadCategory.Other, file.Category);
        file.FileName = "kurulum.exe";
        Assert.Equal(DownloadCategory.App, file.Category);

        var video = new DownloadItem("https://www.youtube.com/watch?v=x");
        video.Quality = VideoQuality.Audio;
        Assert.Equal(DownloadCategory.Music, video.Category);
        video.Quality = VideoQuality.P720;
        Assert.Equal(DownloadCategory.Video, video.Category);
    }

    [Fact]
    public void ProgressAndRemaining()
    {
        var item = new DownloadItem("https://example.com/a.bin") { TotalBytes = 1_000, DownloadedBytes = 250 };
        Assert.Equal(0.25, item.Progress);
        Assert.Null(item.RemainingSeconds);
        item.Speed = 75;
        Assert.Equal(10, item.RemainingSeconds);
        item.DownloadedBytes = 5_000;
        Assert.Equal(1, item.Progress);
    }

    [Theory]
    [InlineData("film.MKV", DownloadCategory.Video)]
    [InlineData("şarkı.mp3", DownloadCategory.Music)]
    [InlineData("foto.HEIC", DownloadCategory.Image)]
    [InlineData("Kurulum.dmg", DownloadCategory.App)]
    [InlineData("setup.msi", DownloadCategory.App)]
    [InlineData("a.7z", DownloadCategory.Archive)]
    [InlineData("yedek.tar.gz", DownloadCategory.Archive)]
    [InlineData("rapor.pdf", DownloadCategory.Document)]
    [InlineData("adsız", DownloadCategory.Other)]
    [InlineData("video.mp4.part", DownloadCategory.Other)]
    public void Categories(string name, DownloadCategory category) => Assert.Equal(category, DownloadCategories.ForFile(name));

    [Fact]
    public void Tabs()
    {
        Assert.True(ListTab.Completed.Includes(DownloadStatus.Completed));
        foreach (var status in new[] { DownloadStatus.Queued, DownloadStatus.Downloading, DownloadStatus.Paused, DownloadStatus.Failed("x") })
        {
            Assert.True(ListTab.Active.Includes(status));
            Assert.False(ListTab.Completed.Includes(status));
        }
    }
}

public class FileNameTests
{
    [Fact]
    public void Sanitize()
    {
        Assert.Equal("a-b-c-d-e-f-g-h-i.pdf", DownloadStore.SanitizedFileName("a<b>c:d\"e/f\\g|h?i.pdf"));
        Assert.Equal("a-b-c.pdf", DownloadStore.SanitizedFileName("a/b:c.pdf"));
        Assert.Equal("a-b-c-d.txt", DownloadStore.SanitizedFileName("a<b>c|d.txt"));
        Assert.Equal("Rapor.pdf", DownloadStore.SanitizedFileName("  Rapor.pdf  "));
        Assert.Equal("satır-sonu.txt", DownloadStore.SanitizedFileName("satır\nsonu.txt"));
        Assert.Equal("gizli.txt", DownloadStore.SanitizedFileName("...gizli.txt"));
        // Windows'ta ayrılmış adlar dosya olarak açılamaz.
        Assert.Equal("_CON.txt", DownloadStore.SanitizedFileName("CON.txt"));
        Assert.Equal("_nul", DownloadStore.SanitizedFileName("nul"));
    }

    [Fact]
    public void Limit()
    {
        var limited = DownloadStore.LimitedFileName(new string('ğ', 300) + ".mp4");
        Assert.True(limited.Length <= 150);
        Assert.EndsWith(".mp4", limited);
        Assert.Equal("kısa.pdf", DownloadStore.LimitedFileName("kısa.pdf"));
    }

    [Fact]
    public void ParseLinks()
    {
        var text = "https://a.example/1.zip\r\n  https://a.example/2.zip \nnot bir link\nmagnet:?xt=urn:btih:1\n\nftp://x/y";
        Assert.Equal(["https://a.example/1.zip", "https://a.example/2.zip", "magnet:?xt=urn:btih:1", "ftp://x/y"], DownloadStore.ParseLinks(text));
    }

    [Theory]
    [InlineData("attachment; filename=\"Rapor.pdf\"", "Rapor.pdf")]
    [InlineData("attachment; filename=Rapor.pdf", "Rapor.pdf")]
    [InlineData("attachment; filename*=UTF-8''Y%C4%B1ll%C4%B1k%20Rapor.pdf", "Yıllık Rapor.pdf")]
    [InlineData("attachment; filename=\"fallback.pdf\"; filename*=UTF-8''ger%C3%A7ek.pdf", "gerçek.pdf")]
    // Broadcom: tür olmadan yalnızca filename= (aria2 bunu okumuyordu).
    [InlineData("filename=VMware-Fusion-26H1u1_universal.dmg", "VMware-Fusion-26H1u1_universal.dmg")]
    public void ContentDisposition(string header, string name) => Assert.Equal(name, LinkProbe.FileNameFromDisposition(header));

    [Fact]
    public void ContentDispositionWithoutName()
    {
        Assert.Null(LinkProbe.FileNameFromDisposition("attachment"));
        Assert.Null(LinkProbe.FileNameFromDisposition(""));
    }
}

public class FormatTests
{
    static string Normalized(string text) => text.Replace(',', '.');

    [Theory]
    [InlineData(0, "0 B")]
    [InlineData(512, "512 B")]
    [InlineData(1_536, "1.5 KB")]
    [InlineData(10 * 1_024, "10 KB")]
    [InlineData(1_048_576, "1.0 MB")]
    [InlineData(1_073_741_824, "1.0 GB")]
    public void Size(long bytes, string text) => Assert.Equal(text, Normalized(ByteFormat.Size(bytes)));

    [Theory]
    [InlineData(0, "")]
    [InlineData(12.2, "~13 sn")]
    [InlineData(61, "~2 dk")]
    [InlineData(3_600, "~1 sa")]
    [InlineData(7_500, "~2 sa 5 dk")]
    public void Remaining(double seconds, string text) => Assert.Equal(text, ByteFormat.Remaining(seconds));

    [Theory]
    [InlineData("1.5.10", "1.5.9", true)]
    [InlineData("1.10.0", "1.9.9", true)]
    [InlineData("1.9.5", "1.9.5", false)]
    [InlineData("1.9.4", "1.9.5", false)]
    [InlineData("1.9.5", "1.9.5.0", false)]
    [InlineData("2026.10.21.1", "2026.10.21", true)]
    public void Versions(string candidate, string other, bool newer)
    {
        Assert.Equal(newer, AppUpdater.IsNewer(candidate, other));
    }

    [Fact]
    public void ErrorTexts()
    {
        Assert.Equal("Dosya sunucuda bulunamadı (404)", ErrorText.Aria2("3", "x", null));
        Assert.Contains("403", ErrorText.Aria2("22", "Response status is not successful. status=403", null));
        Assert.Equal("Diskte yer kalmadı", ErrorText.Aria2("9", null, null));
        Assert.StartsWith("Diskte yer kalmadı · ", ErrorText.Aria2("1", "not enough disk space", 2_048));
        Assert.Equal("bilinmeyen", ErrorText.Aria2("999", "bilinmeyen", null));
        Assert.Equal("Video gizli; yalnızca sahibi izleyebilir", ErrorText.YtDlp("ERROR: [youtube] x: Private video. Sign in", 1));
        Assert.Equal("Bu sayfada indirilebilir video bulunamadı", ErrorText.YtDlp("ERROR: Unsupported URL: https://a", 1));
        Assert.Equal("garip bir sorun", ErrorText.YtDlp("[generic] abc: garip bir sorun", 1));
    }

    [Fact]
    public void Shares()
    {
        Assert.Equal([300, 300, 300], RoutingEngine.Shares(900, [null, null, null]));
        Assert.Equal([100, 400, 400], RoutingEngine.Shares(900, [100, null, null]));
        Assert.Equal([100, 200, 600], RoutingEngine.Shares(900, [100, 200, null]));
        Assert.Empty(RoutingEngine.Shares(900, []));
    }

    [Fact]
    public void YtDlpFormatArguments()
    {
        Assert.Equal(["-f", "b"], YtDlpEngine.FormatArguments(VideoQuality.Auto, null));
        Assert.Equal(["-f", "ba[ext=m4a]/ba/b"], YtDlpEngine.FormatArguments(VideoQuality.Audio, null));
        var auto = YtDlpEngine.FormatArguments(VideoQuality.Auto, @"C:\tools\ffmpeg.exe");
        Assert.Contains("bv*+ba/b", auto);
        Assert.Contains(YtDlpEngine.FormatArguments(VideoQuality.Audio, @"C:\ffmpeg.exe"), a => a == "mp3");
    }
}

public class ParsingTests
{
    static JsonNode Format(string id, string vcodec, string acodec = "none", int? width = null, int? height = null, long? size = null, int tbr = 0)
    {
        var node = new JsonObject { ["format_id"] = id, ["vcodec"] = vcodec, ["acodec"] = acodec, ["tbr"] = tbr };
        if (width is { } w) node["width"] = w;
        if (height is { } h) node["height"] = h;
        if (size is { } s) node["filesize"] = s;
        return node;
    }

    [Fact]
    public void VideoFormatsLikeYouTube()
    {
        var info = new JsonObject
        {
            ["title"] = "Deneme",
            ["duration"] = 212,
            ["formats"] = new JsonArray(
                Format("140", "none", "mp4a.40.2", size: 3_000_000, tbr: 128),
                Format("18", "avc1.42001E", "mp4a.40.2", 640, 360, 9_000_000, 500),
                Format("134", "avc1.4d401e", width: 640, height: 360, size: 5_000_000, tbr: 300),
                Format("136", "avc1.4d401f", width: 1280, height: 720, size: 20_000_000, tbr: 1_200),
                Format("137", "avc1.640028", width: 1920, height: 1080, size: 40_000_000, tbr: 2_500),
                Format("313", "vp9", width: 3840, height: 2160, size: 200_000_000, tbr: 15_000)),
        };
        // yt-dlp çıktısı gibi metinden çözülmüş olsun (sayılar JsonElement).
        var formats = VideoFormats.Parse(JsonNode.Parse(info.ToJsonString())!);
        Assert.Equal("Deneme", formats.Title);
        Assert.Equal(212, formats.Duration);
        Assert.Equal([VideoQuality.Auto, VideoQuality.P2160, VideoQuality.P1080, VideoQuality.P720, VideoQuality.P360, VideoQuality.Audio],
            formats.Options.Select(o => o.Quality));
        var size = formats.Options.GroupBy(o => o.Quality).ToDictionary(g => g.Key, g => g.First().Size);
        Assert.Equal(43_000_000, size[VideoQuality.Auto]);
        Assert.Equal(23_000_000, size[VideoQuality.P720]);
        Assert.Equal(8_000_000, size[VideoQuality.P360]);
        Assert.Equal(3_000_000, size[VideoQuality.Audio]);
    }

    [Fact]
    public void RequestFromJson()
    {
        using var doc = JsonDocument.Parse("""
            {"url":"https://a/b.pdf","filename":"b.pdf","quality":"720","video":true,"saveAs":"Başlık",
             "fromBrowserDownload":true,"mime":"application/pdf",
             "cookieJar":[{"domain":".a","path":"/","name":"n","value":"v","secure":true}]}
            """);
        var request = DownloadRequest.FromJson(doc.RootElement)!;
        Assert.Equal("b.pdf", request.Filename);
        Assert.Equal(VideoQuality.P720, request.Quality);
        Assert.True(request.Video);
        Assert.True(request.FromBrowserDownload);
        Assert.Equal("n", request.CookieJar![0].Name);

        // Eklentinin daha yeni sürümünden tanınmayan değerler isteği bozmaz; adres yoksa reddedilir.
        using var odd = JsonDocument.Parse("""{"url":"https://a/b","quality":"8k","video":"evet","cookieJar":"bozuk"}""");
        var tolerant = DownloadRequest.FromJson(odd.RootElement)!;
        Assert.Null(tolerant.Quality);
        Assert.Null(tolerant.Video);
        Assert.Null(tolerant.CookieJar);
        using var missing = JsonDocument.Parse("""{"filename":"a"}""");
        Assert.Null(DownloadRequest.FromJson(missing.RootElement));
    }

    [Fact]
    public void CookieSitesAndNetscapeFile()
    {
        Assert.Equal("youtube.com", CookieVault.Site("https://www.youtube.com/watch?v=1"));
        Assert.Equal("youtube.com", CookieVault.Site("https://youtu.be/x"));
        Assert.Equal("example.com", CookieVault.Site("https://WWW.Example.com/a"));
        Assert.Null(CookieVault.Site("bozuk"));

        var file = Path.Combine(TestEnvironment.Scratch(), "a", "cookies.txt");
        CookieVault.WriteNetscapeFile([
            new BrowserCookie { Domain = ".youtube.com", Path = "/", Name = "SID", Value = "abc", Secure = true, HttpOnly = true, HostOnly = false, ExpirationDate = 1_900_000_000.7 },
            new BrowserCookie { Domain = "www.youtube.com", Path = "/", Name = "PREF", Value = "x", HostOnly = true },
            new BrowserCookie { Domain = ".youtube.com", Path = "/", Name = "BAD", Value = "a\tb" },
        ], file);
        Assert.Equal([
            "# Netscape HTTP Cookie File",
            "#HttpOnly_.youtube.com\tTRUE\t/\tTRUE\t1900000000\tSID\tabc",
            "www.youtube.com\tFALSE\t/\tFALSE\t0\tPREF\tx",
        ], File.ReadAllLines(file));
    }

    [Fact]
    public void FileSignatures()
    {
        string? Sniff(params byte[] bytes)
        {
            var file = Path.Combine(TestEnvironment.Scratch(), "adsız");
            File.WriteAllBytes(file, [.. bytes, .. new byte[32]]);
            return FileType.SniffExtension(file);
        }
        byte[] Ascii(string text) => System.Text.Encoding.ASCII.GetBytes(text);
        Assert.Equal("jpg", Sniff(0xFF, 0xD8, 0xFF, 0xE0));
        Assert.Equal("png", Sniff(0x89, 0x50, 0x4E, 0x47));
        Assert.Equal("pdf", Sniff(Ascii("%PDF-1.7")));
        Assert.Equal("zip", Sniff(0x50, 0x4B, 0x03, 0x04));
        Assert.Equal("webp", Sniff([.. Ascii("RIFF"), 0, 0, 0, 0, .. Ascii("WEBP")]));
        Assert.Equal("mp4", Sniff([0, 0, 0, 0x18, .. Ascii("ftypisom")]));
        Assert.Null(Sniff(Ascii("merhaba dünya")));
        Assert.Null(FileType.SniffExtension(Path.Combine(TestEnvironment.Root, "yok", "böyle")));
    }

    [Fact]
    public void ArchiveRoundTrip()
    {
        var archive = new DownloadArchive(Path.Combine(TestEnvironment.Scratch(), "downloads.json"));
        var folder = TestEnvironment.Scratch();
        var active = new DownloadItem("https://a.example/big.iso", folder: folder) { TotalBytes = 100, DownloadedBytes = 40, SpeedLimit = 1_048_576 };
        active.Status = DownloadStatus.Downloading;
        active.Referrer = "https://a.example/";
        active.Cookies = "session=GİZLİ";
        active.PreferredName = "big.iso";
        var failed = new DownloadItem("https://a.example/f.zip", folder: folder) { Status = DownloadStatus.Failed("Sunucu hatası (503)") };
        var done = new DownloadItem("https://a.example/d.pdf", folder: folder) { Status = DownloadStatus.Completed, CompletedAt = DateTimeOffset.FromUnixTimeSeconds(1_800_000_000) };
        var video = new DownloadItem("https://www.youtube.com/watch?v=1") { Quality = VideoQuality.Audio };
        var pageVideo = new DownloadItem("https://news.example/sayfa", forceVideo: true);

        var json = archive.Encode([active, failed, done, video, pageVideo]);
        Assert.DoesNotContain("GİZLİ", json);
        archive.Write(json);
        var loaded = archive.Load();
        Assert.Equal(new[] { active, failed, done, video, pageVideo }.Select(i => i.Id), loaded.Select(i => i.Id));
        Assert.Equal(StatusKind.Queued, loaded[0].Status.Kind);
        Assert.Equal(DownloadStatus.Failed("Sunucu hatası (503)"), loaded[1].Status);
        Assert.Equal(StatusKind.Completed, loaded[2].Status.Kind);
        Assert.Equal(done.CompletedAt, loaded[2].CompletedAt);
        Assert.Equal(1_048_576, loaded[0].SpeedLimit);
        Assert.Null(loaded[0].Cookies);
        Assert.Equal("big.iso", loaded[0].PreferredName);
        Assert.Equal(DownloadCategory.Music, loaded[3].Category);
        Assert.Equal(DownloadSource.Video, loaded[4].Source);
        Assert.Equal(archive.Encode(loaded), archive.Encode(loaded));
    }

    [Fact]
    public void ArchiveSkipsBrokenRecords()
    {
        var archive = new DownloadArchive(Path.Combine(TestEnvironment.Scratch(), "downloads.json"));
        Assert.Empty(archive.Load());
        var good = archive.Encode([new DownloadItem("https://a.example/ok.zip") { Status = DownloadStatus.Completed }]);
        var records = JsonNode.Parse(good)!.AsArray();
        records.Add(new JsonObject { ["id"] = "bozuk", ["state"] = "uçuyor" });
        archive.Write(records.ToJsonString());
        Assert.Equal(["https://a.example/ok.zip"], archive.Load().Select(i => i.Url));
        archive.Write("{bu json değil");
        Assert.Empty(archive.Load());
    }
}
