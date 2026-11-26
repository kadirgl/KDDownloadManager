using System.Net.Http.Headers;
using System.Text;
using System.Text.Json.Nodes;
using KDDownloadManager.Bridge;
using KDDownloadManager.Engine;
using KDDownloadManager.Models;
using KDDownloadManager.Store;
using Org.BouncyCastle.Crypto.Generators;
using Org.BouncyCastle.Crypto.Parameters;
using Org.BouncyCastle.Crypto.Signers;
using Org.BouncyCastle.Security;
using Xunit;

namespace KDDownloadManager.Tests;

/// <summary>Link denetimi ve Chrome indirmesini devralma, yerel sunucuya karşı (Mac: LinkProbeTests.swift).</summary>
public class LinkProbeTests : IDisposable
{
    readonly TestServer server = new();
    public void Dispose() => server.Dispose();

    [Fact]
    public async Task ResumableServer()
    {
        server.Route("/indir", TestServer.Response.File(TestServer.Pattern(123_456), new() { ["Content-Disposition"] = "attachment; filename=\"Kurulum.exe\"" }));
        var outcome = Assert.IsType<LinkProbe.Outcome.File>(await LinkProbe.Check(server.Url("/indir?token=1")));
        Assert.Equal(123_456, outcome.Info.Size);
        Assert.True(outcome.Info.Resumable);
        Assert.Equal("Kurulum.exe", outcome.Info.Name);
    }

    [Fact]
    public async Task NotResumableNameFromPath()
    {
        server.Route("/dosyalar/Rapor%202026.pdf", TestServer.Response.File(TestServer.Pattern(5_000)) with { AcceptsRanges = false });
        var outcome = Assert.IsType<LinkProbe.Outcome.File>(await LinkProbe.Check(server.Url("/dosyalar/Rapor%202026.pdf")));
        Assert.Equal(5_000, outcome.Info.Size);
        Assert.False(outcome.Info.Resumable);
        Assert.Equal("Rapor 2026.pdf", outcome.Info.Name);
    }

    [Fact]
    public async Task Statuses()
    {
        foreach (var (path, code) in new[] { ("/yok", 404), ("/gitti", 410), ("/kotu", 400) })
        {
            server.Route(path, TestServer.Response.Code(code));
            Assert.IsType<LinkProbe.Outcome.Invalid>(await LinkProbe.Check(server.Url(path)));
        }
        foreach (var (path, code) in new[] { ("/yasak", 403), ("/hata", 500) })
        {
            server.Route(path, TestServer.Response.Code(code));
            Assert.IsType<LinkProbe.Outcome.Warning>(await LinkProbe.Check(server.Url(path)));
        }
        Assert.IsType<LinkProbe.Outcome.Invalid>(await LinkProbe.Check("bu bir adres değil"));
    }

    [Fact]
    public async Task TakeOverBroadcom()
    {
        server.Route("/", TestServer.Response.File(TestServer.Pattern(64), new() { ["Content-Disposition"] = "filename=VMware-Fusion.dmg" }));
        var request = new DownloadRequest(server.Url("/?file=abc&token=xyz"))
        {
            FromBrowserDownload = true, Mime = "application/octet-stream",
            Cookies = "session=1", Referrer = "https://support.broadcom.com/", UserAgent = "TestBrowser/1.0",
        };
        var accept = Assert.IsType<LinkProbe.TakeOver.Accept>(await LinkProbe.CanTakeOver(request));
        Assert.Equal("VMware-Fusion.dmg", accept.Name);
        var sent = server.RequestsTo("/").Last().Headers;
        Assert.Equal("session=1", sent["cookie"]);
        Assert.Equal("https://support.broadcom.com/", sent["referer"]);
        Assert.Equal("TestBrowser/1.0", sent["user-agent"]);
    }

    [Fact]
    public async Task TakeOverRefusals()
    {
        server.Route("/sw.pdf", TestServer.Response.Text("<html>", new() { ["Content-Type"] = "text/html; charset=utf-8" }));
        Assert.IsType<LinkProbe.TakeOver.Refuse>(await LinkProbe.CanTakeOver(new DownloadRequest(server.Url("/sw.pdf")) { Mime = "application/pdf" }));
        Assert.IsType<LinkProbe.TakeOver.Accept>(await LinkProbe.CanTakeOver(new DownloadRequest(server.Url("/sw.pdf")) { Mime = "text/html" }));
        server.Route("/tek", TestServer.Response.Code(403));
        Assert.IsType<LinkProbe.TakeOver.Refuse>(await LinkProbe.CanTakeOver(new DownloadRequest(server.Url("/tek"))));
    }
}

/// <summary>Eklentinin konuştuğu yerel kapı, test portunda (Mac: BridgeTests.swift).</summary>
[Collection("bridge")]
public class BridgeTests : IDisposable
{
    readonly List<List<DownloadRequest>> added = [];
    readonly List<string> hellos = [];
    readonly ExtensionBridge bridge;
    static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(20) };
    static readonly string StoreOrigin = "chrome-extension://" + BrowserExtension.StoreExtensionId;

    public BridgeTests()
    {
        Assert.Equal(TestEnvironment.BridgePort, ExtensionBridge.Port);
        SynchronizationContext.SetSynchronizationContext(new SynchronizationContext());
        bridge = new ExtensionBridge(list => { lock (added) added.Add(list); }, name => { lock (hellos) hellos.Add(name); });
        bridge.Start();
        Assert.True(bridge.IsListening);
    }

    public void Dispose() => bridge.Stop();

    async Task<(int status, JsonNode? body, HttpResponseMessage response)> Call(string path, string? json = null, string? origin = null,
        HttpMethod? method = null, bool sendOrigin = true)
    {
        var request = new HttpRequestMessage(method ?? HttpMethod.Post, $"http://127.0.0.1:{TestEnvironment.BridgePort}{path}");
        if (sendOrigin) request.Headers.TryAddWithoutValidation("Origin", origin ?? StoreOrigin);
        if (json != null) request.Content = new StringContent(json, Encoding.UTF8, new MediaTypeHeaderValue("application/json"));
        var response = await Http.SendAsync(request);
        var text = await response.Content.ReadAsStringAsync();
        JsonNode? body = null;
        try { body = text.Length > 0 ? JsonNode.Parse(text) : null; } catch { }
        return ((int)response.StatusCode, body, response);
    }

    [Fact]
    public async Task RejectsForeignOrigins()
    {
        const string links = """{"links":[{"url":"https://a/b.zip"}]}""";
        Assert.Equal(403, (await Call("/add", links, sendOrigin: false)).status);
        foreach (var origin in new[] { "https://evil.example", "chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "null" })
            Assert.Equal(403, (await Call("/add", links, origin)).status);
        Assert.Empty(added);
    }

    [Fact]
    public async Task AcceptsBothExtensionIds()
    {
        foreach (var id in new[] { BrowserExtension.StoreExtensionId, BrowserExtension.UnpackedExtensionId })
        {
            var reply = await Call("/ping", origin: "chrome-extension://" + id);
            Assert.Equal(200, reply.status);
            Assert.Equal("KD Download Manager", reply.body?["app"]?.GetValue<string>());
            Assert.Equal("chrome-extension://" + id, reply.response.Headers.GetValues("Access-Control-Allow-Origin").Single());
        }
        Assert.Equal(204, (await Call("/add", method: HttpMethod.Options)).status);
    }

    [Fact]
    public async Task AddAndRejections()
    {
        var reply = await Call("/add", """{"links":[{"url":"https://a.example/1.zip"},{"url":"https://www.youtube.com/watch?v=x","quality":"720"}]}""");
        Assert.Equal(200, reply.status);
        Assert.Equal(2, reply.body?["added"]?.GetValue<int>());
        Assert.Equal(VideoQuality.P720, added.Single()[1].Quality);

        Assert.Equal(400, (await Call("/add", """{"links":[]}""")).status);
        var many = string.Join(",", Enumerable.Range(0, 101).Select(i => $$"""{"url":"https://a/{{i}}"}"""));
        Assert.Equal(400, (await Call("/add", $$"""{"links":[{{many}}]}""")).status);
        Assert.Equal(400, (await Call("/add", "bozuk")).status);
        Assert.Equal(422, (await Call("/add", """{"links":[{"url":"javascript:alert(1)"}]}""")).status);
        Assert.Single(added);
    }

    [Fact]
    public async Task TakeOverSetsNameOrStaysInBrowser()
    {
        using var server = new TestServer();
        server.Route("/", TestServer.Response.File(TestServer.Pattern(10), new() { ["Content-Disposition"] = "filename=Fusion.dmg" }));
        server.Route("/tek", TestServer.Response.Code(403));
        var ok = await Call("/add", $$"""{"links":[{"url":"{{server.Url("/?file=x")}}","fromBrowserDownload":true}]}""");
        Assert.Equal(200, ok.status);
        Assert.Equal("Fusion.dmg", added.Single().Single().Filename);
        Assert.Equal(422, (await Call("/add", $$"""{"links":[{"url":"{{server.Url("/tek")}}","fromBrowserDownload":true}]}""")).status);
    }

    [Fact]
    public async Task HelloCookiesAndUnknownPaths()
    {
        Assert.Equal(200, (await Call("/hello", """{"browser":"Microsoft Edge","version":"1.9.5"}""")).status);
        Assert.Equal(["Microsoft Edge"], hellos);
        const string cookie = """{"domain":".youtube.com","path":"/","name":"n","value":"v","secure":true}""";
        Assert.Equal(200, (await Call("/cookies", $$"""{"site":"youtube.com","cookieJar":[{{cookie}}]}""")).status);
        Assert.Equal(400, (await Call("/cookies", $$"""{"site":"bank.example","cookieJar":[{{cookie}}]}""")).status);
        Assert.Equal(404, (await Call("/yok")).status);
        Assert.Equal(422, (await Call("/formats", """{"url":"file:///C:/Windows/win.ini"}""")).status);
    }
}

[CollectionDefinition("bridge", DisableParallelization = true)]
public class BridgeCollection;

/// <summary>Güncelleme: sürüm bilgisi ve Ed25519 imzası. Gerçek imza anahtarına dokunulmaz; testte anahtar üretilir.</summary>
[Collection("updater")]
public class UpdaterTests : IDisposable
{
    readonly TestServer server = new();
    readonly Ed25519PrivateKeyParameters key;

    public UpdaterTests()
    {
        var generator = new Ed25519KeyPairGenerator();
        generator.Init(new Ed25519KeyGenerationParameters(new SecureRandom()));
        key = (Ed25519PrivateKeyParameters)generator.GenerateKeyPair().Private;
        Environment.SetEnvironmentVariable("KD_UPDATE_API", server.Url("/releases/latest"));
        Environment.SetEnvironmentVariable("KD_UPDATE_KEY", Convert.ToBase64String(key.GeneratePublicKey().GetEncoded()));
    }

    public void Dispose()
    {
        Environment.SetEnvironmentVariable("KD_UPDATE_API", null);
        Environment.SetEnvironmentVariable("KD_UPDATE_KEY", null);
        server.Dispose();
    }

    byte[] Sign(byte[] data)
    {
        var signer = new Ed25519Signer();
        signer.Init(true, key);
        signer.BlockUpdate(data, 0, data.Length);
        return signer.GenerateSignature();
    }

    void Release(string tag, params string[] assets)
    {
        var list = string.Join(",", assets.Select(a => $$"""{"name":"{{a}}","browser_download_url":"{{server.Url("/dl/" + a)}}","size":1000}"""));
        server.Route("/releases/latest", TestServer.Response.Text($$"""{"tag_name":"{{tag}}","body":" Notlar ","assets":[{{list}}]}"""));
    }

    [Fact]
    public void SignatureVerification()
    {
        var data = TestServer.Pattern(50_000);
        var publicKey = key.GeneratePublicKey().GetEncoded();
        Assert.True(AppUpdater.Verify(data, Sign(data), publicKey));
        Assert.False(AppUpdater.Verify([.. data, 0], Sign(data), publicKey));
        var other = new Ed25519PrivateKeyParameters(new SecureRandom());
        Assert.False(AppUpdater.Verify(data, Sign(data), other.GeneratePublicKey().GetEncoded()));
        Assert.False(AppUpdater.Verify(data, [1, 2, 3], publicKey));

        // Dosyadan: imza base64 metin.
        var folder = TestEnvironment.Scratch();
        File.WriteAllBytes(Path.Combine(folder, "a.exe"), data);
        File.WriteAllText(Path.Combine(folder, "a.exe.sig"), Convert.ToBase64String(Sign(data)) + "\n");
        Assert.True(AppUpdater.VerifyFiles(Path.Combine(folder, "a.exe"), Path.Combine(folder, "a.exe.sig")));
    }

    [Fact]
    public async Task PrefersSetupThenZipAndIgnoresMacOnly()
    {
        var arch = AppUpdater.Architecture;
        Release("v99.1.0", $"KDDownloadManager-Windows-{arch}-99.1.0-Setup.exe", $"KDDownloadManager-Windows-{arch}-99.1.0-Setup.exe.sig",
            $"KDDownloadManager-Windows-{arch}-99.1.0.zip", $"KDDownloadManager-Windows-{arch}-99.1.0.zip.sig");
        await AppUpdater.Shared.Check();
        var available = Assert.IsType<AppUpdater.UpdateState.Available>(AppUpdater.Shared.State);
        Assert.True(available.Release.IsSetup);
        Assert.Equal("99.1.0", available.Release.Version);
        Assert.Equal("Notlar", available.Release.Notes);

        Release("v99.2.0", $"KDDownloadManager-Windows-{arch}-99.2.0.zip", $"KDDownloadManager-Windows-{arch}-99.2.0.zip.sig");
        await AppUpdater.Shared.Check();
        Assert.False(Assert.IsType<AppUpdater.UpdateState.Available>(AppUpdater.Shared.State).Release.IsSetup);

        // Yalnızca Mac'e çıkan sürüm (1.9.5 gibi) Windows için güncelleme değil.
        Release("v99.3.0", "KDDownloadManager-99.3.0.zip", "KDDownloadManager-99.3.0.zip.sig");
        await AppUpdater.Shared.Check();
        Assert.IsType<AppUpdater.UpdateState.UpToDate>(AppUpdater.Shared.State);

        // İmzasız Setup sayılmaz.
        Release("v99.4.0", $"KDDownloadManager-Windows-{arch}-99.4.0-Setup.exe");
        await AppUpdater.Shared.Check();
        Assert.IsType<AppUpdater.UpdateState.UpToDate>(AppUpdater.Shared.State);

        // Başka mimarinin paketi de sayılmaz.
        var otherArch = arch == "arm64" ? "x64" : "arm64";
        Release("v99.5.0", $"KDDownloadManager-Windows-{otherArch}-99.5.0-Setup.exe", $"KDDownloadManager-Windows-{otherArch}-99.5.0-Setup.exe.sig");
        await AppUpdater.Shared.Check();
        Assert.IsType<AppUpdater.UpdateState.UpToDate>(AppUpdater.Shared.State);
    }

    [Fact]
    public async Task OddResponses()
    {
        server.Route("/releases/latest", TestServer.Response.Code(404));
        await AppUpdater.Shared.Check();
        Assert.IsType<AppUpdater.UpdateState.UpToDate>(AppUpdater.Shared.State);

        Release("nightly");
        await AppUpdater.Shared.Check();
        Assert.Equal("Sürüm numarası anlaşılamadı: nightly", Assert.IsType<AppUpdater.UpdateState.Failed>(AppUpdater.Shared.State).Message);

        server.Route("/releases/latest", TestServer.Response.Code(500));
        await AppUpdater.Shared.Check(quietly: true);
        Assert.IsType<AppUpdater.UpdateState.Idle>(AppUpdater.Shared.State);
    }
}

[CollectionDefinition("updater", DisableParallelization = true)]
public class UpdaterCollection;

/// <summary>Gerçek aria2c.exe ile uçtan uca indirme; yalnızca Windows'ta (sanal makinede) çalışır.</summary>
public class Aria2DownloadTests : IDisposable
{
    readonly TestServer server = new();
    public void Dispose() => server.Dispose();

    [WindowsFact]
    public async Task BroadcomNameAndContent()
    {
        if (Tools.Find("aria2c") == null) return;
        var name = $"VMware-Fusion-{Guid.NewGuid().ToString("N")[..6]}.dmg";
        var content = TestServer.Pattern(2_500_000);
        server.Route("/", TestServer.Response.File(content, new() { ["Content-Disposition"] = "filename=" + name }));
        var store = new DownloadStore(new Aria2Engine(), null);
        store.Add([new DownloadRequest(server.Url("/?file=" + Guid.NewGuid()), name)]);
        var item = store.Items[0];
        Assert.True(await TestEnvironment.WaitUntil(() => item.IsCompleted || item.IsFailed, 30));
        Assert.True(item.IsCompleted, item.Status.Message);
        Assert.Equal(content, File.ReadAllBytes(Path.Combine(TestEnvironment.Downloads, name)));
    }
}
