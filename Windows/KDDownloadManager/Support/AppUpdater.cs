using System.Diagnostics;
using System.IO.Compression;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Org.BouncyCastle.Crypto.Parameters;
using Org.BouncyCastle.Crypto.Signers;

namespace KDDownloadManager;

/// <summary>
/// Updates the app from GitHub Releases with the same signature scheme as the macOS app (macOS: AppUpdater).
///
/// Each release (tag v1.9.3) may carry, next to the macOS zip, one Windows zip per architecture
/// (<c>KDDownloadManager-Windows-arm64-1.9.3.zip</c>, <c>…-x64-…</c>) and its Ed25519 signature (<c>….zip.sig</c>,
/// base64). Only the developer's private key (macOS Keychain, scripts/release-windows.sh) can sign; the public key
/// is scripts/update-public-key.txt, embedded at build time. A fake release cannot be installed even if the GitHub
/// account or the download path is compromised. The unpacked app's version is checked too.
///
/// Install: a hidden PowerShell script waits for the app to exit, swaps the app folder (rolling back on failure)
/// and starts the new version. Running downloads were saved and resume on launch.
/// </summary>
public sealed partial class AppUpdater
{
    public abstract record UpdateState
    {
        public sealed record Idle : UpdateState;
        public sealed record Checking : UpdateState;
        public sealed record UpToDate : UpdateState;
        public sealed record Available(Release Release) : UpdateState;
        public sealed record Downloading(Release Release, double Progress) : UpdateState;
        public sealed record Installing(Release Release) : UpdateState;
        public sealed record Failed(string Message) : UpdateState;
    }

    public sealed record Release(string Version, string Notes, Uri Archive, Uri Signature, long Size, Uri? Page);

    public static readonly AppUpdater Shared = new();
    public event Action? Changed;

    UpdateState state = new UpdateState.Idle();
    public UpdateState State { get => state; private set { state = value; Changed?.Invoke(); } }

    public DateTimeOffset? LastCheck { get; private set; } = Settings.Get<DateTimeOffset?>(Settings.AppUpdateLastCheck, null);

    static readonly TimeSpan AutomaticInterval = TimeSpan.FromHours(24);
    const long MaximumSize = 600L * 1024 * 1024;
    CancellationTokenSource? download;

    static readonly HttpClient Http = CreateClient();

    static HttpClient CreateClient()
    {
        var client = new HttpClient { Timeout = TimeSpan.FromSeconds(60) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("KDDownloadManager-Windows/" + CurrentVersion);
        return client;
    }

    public static string CurrentVersion
    {
        get
        {
            var version = Assembly.GetExecutingAssembly().GetName().Version;
            return version == null ? "0" : $"{version.Major}.{version.Minor}.{version.Build}";
        }
    }

    public static string Architecture => RuntimeInformation.ProcessArchitecture == System.Runtime.InteropServices.Architecture.Arm64 ? "arm64" : "x64";

    static string? Repository =>
#if DEBUG
        Environment.GetEnvironmentVariable("KD_UPDATE_REPO") ??
#endif
        Assembly.GetExecutingAssembly().GetCustomAttributes<AssemblyMetadataAttribute>().FirstOrDefault(a => a.Key == "UpdateRepository")?.Value;

    static byte[]? PublicKey
    {
        get
        {
            string? encoded =
#if DEBUG
                Environment.GetEnvironmentVariable("KD_UPDATE_KEY") ??
#endif
                null;
            if (encoded == null)
            {
                using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("update-public-key.txt");
                if (stream == null) return null;
                encoded = new StreamReader(stream).ReadToEnd();
            }
            try
            {
                var key = Convert.FromBase64String(encoded.Trim());
                return key.Length == 32 ? key : null;
            }
            catch { return null; }
        }
    }

    static Uri? LatestApi =>
#if DEBUG
        Environment.GetEnvironmentVariable("KD_UPDATE_API") is { } test ? new Uri(test) :
#endif
        string.IsNullOrEmpty(Repository) ? null : new Uri($"https://api.github.com/repos/{Repository}/releases/latest");

    /// <summary>The folder being replaced: the running app's.</summary>
    static string InstalledFolder => Path.TrimEndingDirectorySeparator(AppFolders.AppDir);

    public static bool IsAvailable => LatestApi != null && PublicKey != null && File.Exists(Path.Combine(InstalledFolder, "KDDownloadManager.exe"));

    public static string? InstallProblem
    {
        get
        {
            var parent = Path.GetDirectoryName(InstalledFolder)!;
            try
            {
                var probe = Path.Combine(parent, ".kd-write-test-" + Guid.NewGuid().ToString("N"));
                File.WriteAllText(probe, "");
                File.Delete(probe);
                return null;
            }
            catch
            {
                return L.F("%@ klasörüne yazma izni yok; yeni sürümü GitHub'dan indirin.", parent);
            }
        }
    }

    public bool IsBusy => State is UpdateState.Checking or UpdateState.Downloading or UpdateState.Installing;
    public Release? AvailableRelease => State is UpdateState.Available a ? a.Release : null;

    public async void StartAutomaticChecks()
    {
        if (!IsAvailable) return;
        while (true)
        {
            var due = LastCheck is not { } last || DateTimeOffset.Now - last >= AutomaticInterval;
            if (Settings.Get(Settings.AppAutoUpdateCheck, true) && due && !IsBusy && AvailableRelease == null)
                await Check(quietly: true);
            await Task.Delay(TimeSpan.FromHours(1));
        }
    }

    public async Task Check(bool quietly = false)
    {
        if (IsBusy || LatestApi is not { } api) return;
        State = new UpdateState.Checking();
        try
        {
            var release = await LatestRelease(api);
            LastCheck = DateTimeOffset.Now;
            Settings.Set(Settings.AppUpdateLastCheck, LastCheck);
            if (release == null || !IsNewer(release.Version, CurrentVersion))
            {
                State = new UpdateState.UpToDate();
                return;
            }
            State = new UpdateState.Available(release);
            if (Settings.Get<string?>(Settings.AppUpdateAnnounced, null) != release.Version)
            {
                Settings.Set(Settings.AppUpdateAnnounced, release.Version);
                Notifier.UpdateAvailable(release.Version);
            }
        }
        catch (Exception error)
        {
            State = quietly ? new UpdateState.Idle() : new UpdateState.Failed(error.Message);
        }
    }

    public static bool IsNewer(string candidate, string other)
    {
        int[] Parts(string v) => v.Split('.').Select(p => int.TryParse(p, out var n) ? n : 0).ToArray();
        var a = Parts(candidate);
        var b = Parts(other);
        for (var i = 0; i < Math.Max(a.Length, b.Length); i++)
        {
            var x = i < a.Length ? a[i] : 0;
            var y = i < b.Length ? b[i] : 0;
            if (x != y) return x > y;
        }
        return false;
    }

    sealed class UpdateException(string message) : Exception(message);

    public static string AssetName(string version) => $"KDDownloadManager-Windows-{Architecture}-{version}.zip";

    static async Task<Release?> LatestRelease(Uri api)
    {
        var request = new HttpRequestMessage(HttpMethod.Get, api);
        request.Headers.Accept.ParseAdd("application/vnd.github+json");
        using var response = await Http.SendAsync(request);
        var status = (int)response.StatusCode;
        if (status == 404) return null;
        if (status != 200) throw new UpdateException(L.F("Güncelleme bilgisi alınamadı (HTTP %lld)", status));
        var info = JsonNode.Parse(await response.Content.ReadAsStringAsync());
        var tag = info?["tag_name"]?.GetValue<string>() ?? throw new UpdateException(L.T("Güncelleme bilgisi okunamadı"));
        var version = tag.StartsWith('v') ? tag[1..] : tag;
        if (!VersionPattern().IsMatch(version)) throw new UpdateException(L.F("Sürüm numarası anlaşılamadı: %@", tag));
        var assets = info?["assets"] as JsonArray ?? [];
        (Uri url, long size)? Asset(string name)
        {
            var found = assets.FirstOrDefault(a => a?["name"]?.GetValue<string>() == name);
            if (found?["browser_download_url"]?.GetValue<string>() is not { } link || !Uri.TryCreate(link, UriKind.Absolute, out var url)) return null;
            if (url.Scheme != "https" && !IsTesting) return null;
            return (url, found["size"]?.GetValue<long>() ?? 0);
        }
        var asset = AssetName(version);
        // A release without a signed Windows zip (e.g. macOS-only) is not an update for this app.
        if (Asset(asset) is not { } archive || Asset(asset + ".sig") is not { } signature) return null;
        return new Release(version, info?["body"]?.GetValue<string>()?.Trim() ?? "", archive.url, signature.url, archive.size,
            info?["html_url"]?.GetValue<string>() is { } page ? new Uri(page) : null);
    }

    [GeneratedRegex(@"^\d+(\.\d+){0,3}$")]
    private static partial Regex VersionPattern();

    static bool IsTesting =>
#if DEBUG
        Environment.GetEnvironmentVariable("KD_UPDATE_API") != null;
#else
        false;
#endif

    public async void Install()
    {
        if (AvailableRelease is not { } release) return;
        if (InstallProblem is { } problem)
        {
            State = new UpdateState.Failed(problem);
            return;
        }
        var cts = download = new CancellationTokenSource();
        State = new UpdateState.Downloading(release, 0);
        try
        {
            var staged = await Download(release, cts.Token);
            State = new UpdateState.Installing(release);
            ReplaceAndRelaunch(staged);
        }
        catch (OperationCanceledException) { State = new UpdateState.Available(release); }
        catch (Exception error) { State = new UpdateState.Failed(error.Message); }
    }

    public void Cancel() => download?.Cancel();

    static string WorkFolder => Path.Combine(AppFolders.Caches, "Update");

    async Task<string> Download(Release release, CancellationToken token)
    {
        if (PublicKey is not { } key) throw new UpdateException(L.T("Güncelleme anahtarı yok"));
        if (release.Size > MaximumSize) throw new UpdateException(L.T("Güncelleme dosyası beklenenden büyük"));

        var signatureText = await Http.GetStringAsync(release.Signature, token);
        byte[] signature;
        try { signature = Convert.FromBase64String(signatureText.Trim()); }
        catch { throw new UpdateException(L.T("Güncellemenin imzası okunamadı")); }

        using var response = await Http.GetAsync(release.Archive, HttpCompletionOption.ResponseHeadersRead, token);
        if (!response.IsSuccessStatusCode) throw new UpdateException(L.T("Güncelleme indirilemedi"));
        var expected = response.Content.Headers.ContentLength ?? release.Size;
        if (expected > MaximumSize) throw new UpdateException(L.T("Güncelleme dosyası beklenenden büyük"));
        await using var source = await response.Content.ReadAsStreamAsync(token);
        using var memory = new MemoryStream();
        var buffer = new byte[256 * 1024];
        int read;
        while ((read = await source.ReadAsync(buffer, token)) > 0)
        {
            memory.Write(buffer, 0, read);
            if (memory.Length > MaximumSize) throw new UpdateException(L.T("Güncelleme dosyası beklenenden büyük"));
            if (expected > 0) State = new UpdateState.Downloading(release, Math.Min(1, (double)memory.Length / expected));
        }
        var archive = CorruptedForTesting(memory.ToArray());
        token.ThrowIfCancellationRequested();

        if (!Verify(archive, signature, key)) throw new UpdateException(L.T("Güncellemenin imzası doğrulanamadı; kurulmadı"));
        State = new UpdateState.Downloading(release, 1);
        return await Task.Run(() => Unpack(archive, release.Version), token);
    }

    /// <summary>Ed25519 (RFC 8032), as CryptoKit's Curve25519.Signing on macOS.</summary>
    public static bool Verify(byte[] data, byte[] signature, byte[] publicKey)
    {
        try
        {
            var verifier = new Ed25519Signer();
            verifier.Init(false, new Ed25519PublicKeyParameters(publicKey, 0));
            verifier.BlockUpdate(data, 0, data.Length);
            return verifier.VerifySignature(signature);
        }
        catch { return false; }
    }

    public static bool VerifyFiles(string file, string signatureFile)
    {
        try
        {
            return PublicKey is { } key && Verify(File.ReadAllBytes(file), Convert.FromBase64String(File.ReadAllText(signatureFile).Trim()), key);
        }
        catch { return false; }
    }

    static string Unpack(byte[] archive, string version)
    {
        if (Directory.Exists(WorkFolder)) Directory.Delete(WorkFolder, true);
        var folder = Path.Combine(WorkFolder, version);
        Directory.CreateDirectory(folder);
        try
        {
            using var zip = new ZipArchive(new MemoryStream(archive));
            zip.ExtractToDirectory(folder);
        }
        catch { throw new UpdateException(L.T("Güncelleme açılamadı")); }
        var app = Path.Combine(folder, "KDDownloadManager");
        var exe = Path.Combine(app, "KDDownloadManager.exe");
        var info = File.Exists(exe) ? FileVersionInfo.GetVersionInfo(exe) : null;
        var found = info == null ? null : $"{info.FileMajorPart}.{info.FileMinorPart}.{info.FileBuildPart}";
        if (found != version) throw new UpdateException(L.T("İndirilen paket beklenen sürüm değil; kurulmadı"));
        return app;
    }

    static void ReplaceAndRelaunch(string staged)
    {
        var target = InstalledFolder;
        var script = Path.Combine(WorkFolder, "install.ps1");
        File.WriteAllText(script, """
            param($ProcessId, $Target, $Staged, $Relaunch)
            $ErrorActionPreference = 'SilentlyContinue'
            for ($i = 0; $i -lt 300 -and (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Milliseconds 200 }
            Start-Sleep -Milliseconds 500
            $backup = "$Target.eski"
            Remove-Item -Recurse -Force $backup
            $moved = $false
            for ($i = 0; $i -lt 20 -and -not $moved; $i++) {
              try { Move-Item -LiteralPath $Target -Destination $backup -ErrorAction Stop; $moved = $true } catch { Start-Sleep -Milliseconds 500 }
            }
            if ($moved) {
              try { Move-Item -LiteralPath $Staged -Destination $Target -ErrorAction Stop; Remove-Item -Recurse -Force $backup }
              catch { Move-Item -LiteralPath $backup -Destination $Target }
            }
            Remove-Item -Recurse -Force (Split-Path $Staged)
            if ($Relaunch -eq 'relaunch') { Start-Process -FilePath (Join-Path $Target 'KDDownloadManager.exe') }
            """);
        var info = new ProcessStartInfo("powershell.exe")
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            ArgumentList = { "-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", script,
                Environment.ProcessId.ToString(), target, staged, RelaunchAfterInstall ? "relaunch" : "stay" },
        };
        Process.Start(info);
        App.Quit();
    }

    static bool RelaunchAfterInstall =>
#if DEBUG
        Environment.GetEnvironmentVariable("KD_APP_UPDATE_TEST") == null;
#else
        true;
#endif

    static byte[] CorruptedForTesting(byte[] data)
    {
#if DEBUG
        if (Environment.GetEnvironmentVariable("KD_UPDATE_CORRUPT") != null && data.Length > 0) data[data.Length / 2] ^= 0xFF;
#endif
        return data;
    }
}
