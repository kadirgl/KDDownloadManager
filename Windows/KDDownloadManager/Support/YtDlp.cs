namespace KDDownloadManager;

/// <summary>
/// The bundled yt-dlp (macOS: YtDlp). It is only updated together with the app (a signed release); the app no longer
/// downloads yt-dlp by itself. 1.9.5 and older could, into %LOCALAPPDATA%\KDDownloadManager\yt-dlp; that copy is
/// deleted at launch.
/// </summary>
public static class YtDlp
{
    public static void RemoveDownloadedCopies()
    {
        try
        {
            var root = Path.Combine(AppFolders.Support, "yt-dlp");
            if (Directory.Exists(root)) Directory.Delete(root, recursive: true);
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }
}
