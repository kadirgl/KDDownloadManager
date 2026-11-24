using System.Text;

namespace KDDownloadManager;

/// <summary>The real type of a file saved without extension, from its first bytes (macOS: FileType).</summary>
public static class FileType
{
    public static string? SniffExtension(string path)
    {
        byte[] bytes;
        try
        {
            using var stream = File.OpenRead(path);
            var buffer = new byte[64];
            var read = stream.Read(buffer, 0, buffer.Length);
            if (read < 4) return null;
            bytes = buffer[..read];
        }
        catch { return null; }

        bool Starts(byte[] prefix, int offset = 0) => bytes.Length >= offset + prefix.Length && bytes.AsSpan(offset, prefix.Length).SequenceEqual(prefix);
        bool Ascii(string text, int offset = 0) => Starts(Encoding.ASCII.GetBytes(text), offset);

        if (Starts([0xFF, 0xD8, 0xFF])) return "jpg";
        if (Starts([0x89, 0x50, 0x4E, 0x47])) return "png";
        if (Ascii("GIF8")) return "gif";
        if (Ascii("RIFF") && Ascii("WEBP", 8)) return "webp";
        if (Ascii("RIFF") && Ascii("WAVE", 8)) return "wav";
        if (Ascii("RIFF") && Ascii("AVI ", 8)) return "avi";
        if (Ascii("ftyp", 4) && bytes.Length >= 12)
        {
            return Encoding.ASCII.GetString(bytes, 8, 4) switch
            {
                "avif" or "avis" => "avif",
                "heic" or "heix" or "mif1" or "msf1" => "heic",
                "qt  " => "mov",
                "M4A " or "M4B " => "m4a",
                _ => "mp4",
            };
        }
        if (Ascii("%PDF")) return "pdf";
        if (Starts([0x50, 0x4B, 0x03, 0x04])) return "zip";
        if (Ascii("Rar!")) return "rar";
        if (Starts([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C])) return "7z";
        if (Starts([0x1F, 0x8B])) return "gz";
        if (Starts([0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00])) return "xz";
        if (Ascii("BZh")) return "bz2";
        if (Ascii("ID3") || Starts([0xFF, 0xFB]) || Starts([0xFF, 0xF3]) || Starts([0xFF, 0xF2])) return "mp3";
        if (Ascii("fLaC")) return "flac";
        if (Ascii("OggS")) return "ogg";
        if (Starts([0x1A, 0x45, 0xDF, 0xA3])) return Encoding.ASCII.GetString(bytes).Contains("webm") ? "webm" : "mkv";
        if (Ascii("MZ")) return "exe";
        if (Ascii("BM")) return "bmp";
        if (Starts([0x49, 0x49, 0x2A, 0x00]) || Starts([0x4D, 0x4D, 0x00, 0x2A])) return "tiff";
        var text = Encoding.UTF8.GetString(bytes).ToLowerInvariant();
        if (text.StartsWith("<svg") || (text.StartsWith("<?xml") && text.Contains("<svg"))) return "svg";
        return null;
    }
}
