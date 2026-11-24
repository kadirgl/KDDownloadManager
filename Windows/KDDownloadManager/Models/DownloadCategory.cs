using Windows.UI;

namespace KDDownloadManager.Models;

public enum DownloadCategory { All, Video, Music, Image, App, Archive, Document, Other }

public enum CompletedSort { Newest, Name, Size }

public enum ListTab { Active, Completed }

public static class DownloadCategories
{
    public static readonly DownloadCategory[] All = Enum.GetValues<DownloadCategory>();

    public static string Title(this DownloadCategory c) => c switch
    {
        DownloadCategory.All => L.T("Tümü"),
        DownloadCategory.Video => L.T("Video"),
        DownloadCategory.Music => L.T("Müzik"),
        DownloadCategory.Image => L.T("Resim"),
        DownloadCategory.App => L.T("Uygulama"),
        DownloadCategory.Archive => L.T("Arşiv"),
        DownloadCategory.Document => L.T("Döküman"),
        _ => L.T("Diğer"),
    };

    /// <summary>Segoe Fluent Icons glyph for the category tile.</summary>
    public static string Glyph(this DownloadCategory c) => c switch
    {
        DownloadCategory.Video => "",
        DownloadCategory.Music => "",
        DownloadCategory.Image => "",
        DownloadCategory.App => "",
        DownloadCategory.Archive => "",
        DownloadCategory.Document => "",
        _ => "",
    };

    public static (Color top, Color bottom) Colors(this DownloadCategory c) => c switch
    {
        DownloadCategory.Video => (Hex(0xB48CF0), Hex(0x8150D6)),
        DownloadCategory.Music => (Hex(0xF57A9A), Hex(0xD4436A)),
        DownloadCategory.Image => (Hex(0x4FD1C5), Hex(0x1A9C93)),
        DownloadCategory.App => (Hex(0x5AA2F8), Hex(0x2C6FE0)),
        DownloadCategory.Archive => (Hex(0xD6AE74), Hex(0xA67840)),
        DownloadCategory.Document => (Hex(0x5FCB8A), Hex(0x2E9E5C)),
        _ => (Hex(0xA7AEBB), Hex(0x6B7280)),
    };

    public static Color Hex(uint rgb, byte alpha = 255) =>
        Color.FromArgb(alpha, (byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb);

    static readonly Dictionary<DownloadCategory, HashSet<string>> Extensions = new()
    {
        [DownloadCategory.Video] = ["mp4", "m4v", "mov", "mkv", "avi", "webm", "flv", "f4v", "wmv", "asf", "mpg", "mpeg", "mpe",
            "m2v", "m2ts", "mts", "ts", "3gp", "3g2", "ogv", "vob", "rm", "rmvb", "divx", "xvid", "hevc", "h264", "h265", "mxf", "dv"],
        [DownloadCategory.Music] = ["mp3", "m4a", "m4b", "m4p", "aac", "flac", "alac", "wav", "wave", "aif", "aiff", "aifc", "ogg",
            "oga", "opus", "wma", "mid", "midi", "amr", "ape", "wv", "caf", "dsf", "dff", "mka", "ac3", "dts"],
        [DownloadCategory.Image] = ["jpg", "jpeg", "jpe", "jfif", "pjpeg", "png", "apng", "gif", "webp", "avif", "heic", "heif",
            "jxl", "bmp", "dib", "tif", "tiff", "svg", "svgz", "ico", "icns", "psd", "ai", "eps", "raw", "dng", "cr2", "cr3", "nef",
            "nrw", "arw", "orf", "rw2", "raf", "srw", "pef", "xcf", "tga", "exr", "hdr"],
        [DownloadCategory.App] = ["dmg", "pkg", "mpkg", "app", "exe", "msi", "msix", "appx", "ipa", "apk", "aab", "xapk", "apkm",
            "deb", "rpm", "appimage", "snap", "flatpak", "jar", "iso", "img", "vhd", "vhdx", "vmdk", "ova", "msixbundle", "appxbundle"],
        [DownloadCategory.Archive] = ["zip", "zipx", "rar", "7z", "tar", "gz", "tgz", "bz2", "tbz", "tbz2", "xz", "txz", "zst",
            "tzst", "lz", "lzma", "lz4", "z", "cab", "arj", "lzh", "sit", "sitx", "cpio", "xar", "sea"],
        [DownloadCategory.Document] = ["pdf", "doc", "docx", "docm", "dot", "dotx", "xls", "xlsx", "xlsm", "xlsb", "ppt", "pptx",
            "pps", "ppsx", "odt", "ods", "odp", "odg", "rtf", "txt", "text", "md", "markdown", "csv", "tsv", "epub", "mobi", "azw",
            "azw3", "fb2", "djvu", "xps", "oxps", "pages", "numbers", "key", "tex", "log", "json", "xml", "yaml", "yml", "html",
            "htm", "srt", "vtt", "ass", "ssa", "sub"],
    };

    public static DownloadCategory ForFile(string name)
    {
        var ext = Path.GetExtension(name).TrimStart('.').ToLowerInvariant();
        if (ext.Length == 0) return DownloadCategory.Other;
        foreach (var (category, set) in Extensions)
            if (set.Contains(ext)) return category;
        return DownloadCategory.Other;
    }

    public static string Title(this CompletedSort s) => s switch
    {
        CompletedSort.Name => L.T("Ada göre"),
        CompletedSort.Size => L.T("Boyuta göre"),
        _ => L.T("En yeni"),
    };

    public static string Title(this ListTab t) => t == ListTab.Active ? L.T("Devam Eden") : L.T("Tamamlanan");

    public static bool Includes(this ListTab t, DownloadStatus status) =>
        t == ListTab.Active ? status.Kind != StatusKind.Completed : status.Kind == StatusKind.Completed;
}
