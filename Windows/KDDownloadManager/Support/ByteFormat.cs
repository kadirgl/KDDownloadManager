namespace KDDownloadManager;

/// <summary>"12,4 MB/sn", "12 GB" (English: "12.4 MB/s").</summary>
public static class ByteFormat
{
    static readonly string[] Units = ["B", "KB", "MB", "GB", "TB"];

    public static string Size(long bytes)
    {
        double value = Math.Max(bytes, 0);
        var unit = 0;
        while (value >= 1024 && unit < Units.Length - 1)
        {
            value /= 1024;
            unit++;
        }
        var digits = unit == 0 || value >= 10 ? 0 : 1;
        return value.ToString(digits == 0 ? "0" : "0.0", L.Culture) + " " + Units[unit];
    }

    public static string Speed(long bytesPerSecond) => L.F("%@/sn", Size(bytesPerSecond));

    /// <summary>"~13 sn", "~6 dk", "~2 sa 5 dk".</summary>
    public static string Remaining(double seconds)
    {
        if (!double.IsFinite(seconds) || seconds <= 0) return "";
        var total = (int)Math.Ceiling(seconds);
        if (total < 60) return L.F("~%lld sn", total);
        var minutes = (total + 59) / 60;
        if (minutes < 60) return L.F("~%lld dk", minutes);
        var hours = minutes / 60;
        var rest = minutes % 60;
        return rest == 0 ? L.F("~%lld sa", hours) : L.F("~%lld sa %lld dk", hours, rest);
    }

    /// <summary>"Bugün 14:32", "Dün 09:10", "28 Eki".</summary>
    public static string Finished(DateTimeOffset date)
    {
        var local = date.ToLocalTime();
        var time = local.ToString("t", L.Culture);
        if (local.Date == DateTime.Today) return L.F("Bugün %@", time);
        if (local.Date == DateTime.Today.AddDays(-1)) return L.F("Dün %@", time);
        return local.ToString("d MMM", L.Culture);
    }
}
