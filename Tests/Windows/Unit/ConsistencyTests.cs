using System.Text.Json;
using System.Text.RegularExpressions;
using Xunit;

namespace KDDownloadManager.Tests;

/// <summary>Windows uygulamasının çevirileri ve Mac ile paylaşılan değerler.</summary>
public partial class ConsistencyTests
{
    static string Repo => TestEnvironment.Repository;

    [GeneratedRegex("""\bL\.[TF]\(\s*"((?:[^"\\]|\\.)*)"\s*[,)]""")]
    private static partial Regex LocalizedLiteral();

    [Fact]
    public void EveryTextHasAnEnglishTranslation()
    {
        var english = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(
            File.ReadAllText(Path.Combine(Repo, "Windows", "KDDownloadManager", "Strings", "en.json")))!;
        var missing = new SortedSet<string>();
        foreach (var file in Directory.EnumerateFiles(Path.Combine(Repo, "Windows", "KDDownloadManager"), "*.cs", SearchOption.AllDirectories))
        {
            if (file.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}") || file.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}")) continue;
            foreach (Match match in LocalizedLiteral().Matches(File.ReadAllText(file)))
            {
                var key = Regex.Unescape(match.Groups[1].Value);
                if (!english.ContainsKey(key)) missing.Add($"{Path.GetFileName(file)}: {key}");
            }
        }
        Assert.True(missing.Count == 0, "en.json'da çevirisi olmayan metinler (Windows/scripts/strings.py):\n" + string.Join("\n", missing));
    }

    [Fact]
    public void ExtensionIdsMatchMac()
    {
        var mac = File.ReadAllText(Path.Combine(Repo, "Sources", "KDDownloadManager", "Support", "BrowserExtension.swift"));
        Assert.Contains($"storeExtensionID = \"{BrowserExtension.StoreExtensionId}\"", mac);
        Assert.Contains($"unpackedExtensionID = \"{BrowserExtension.UnpackedExtensionId}\"", mac);
        Assert.Contains($"storeListingLive = {(BrowserExtension.StoreListingLive ? "true" : "false")}", mac);
        Assert.Equal(!BrowserExtension.StoreListingLive, BrowserExtension.StoreUrl == null);
    }

    [Fact]
    public void VideoHostsMatchMac()
    {
        var mac = File.ReadAllText(Path.Combine(Repo, "Sources", "KDDownloadManager", "Models", "DownloadItem.swift"));
        foreach (var host in Models.DownloadSources.VideoHosts) Assert.Contains($"\"{host}\"", mac);
    }
}
