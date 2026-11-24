using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace KDDownloadManager;

public enum AppLanguage { System, Turkish, English }

/// <summary>
/// UI language. Texts are written in Turkish in the code (as in the macOS app); English comes from
/// Strings\en.json, generated from the macOS Localizable.xcstrings plus Windows-only texts
/// (Windows/scripts/strings.py). Placeholders use the xcstrings format: %@, %lld, %1$@ …
/// The language changes when the app is restarted.
/// </summary>
public static partial class L
{
    public static AppLanguage Stored => Settings.Get<string?>(Settings.Language, null) switch
    {
        "tr" => AppLanguage.Turkish,
        "en" => AppLanguage.English,
        _ => AppLanguage.System,
    };

    public static readonly AppLanguage LaunchChoice = Stored;

    public static void Store(AppLanguage language) => Settings.Set(Settings.Language, language switch
    {
        AppLanguage.Turkish => "tr",
        AppLanguage.English => "en",
        _ => null,
    });

    public static string Title(this AppLanguage language) => language switch
    {
        AppLanguage.Turkish => "Türkçe",
        AppLanguage.English => "English",
        _ => L.T("Sistem"),
    };

    /// <summary>"tr" or "en": the language shown now.</summary>
    public static readonly string Current = LaunchChoice switch
    {
        AppLanguage.Turkish => "tr",
        AppLanguage.English => "en",
        _ => CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "tr" ? "tr" : "en",
    };

    /// <summary>Number formats follow the UI language (decimal comma in Turkish).</summary>
    public static readonly CultureInfo Culture = Current == "tr" ? new CultureInfo("tr-TR") : new CultureInfo("en-US");

    /// <summary>
    /// Key → a string, plural forms {"one", "other"}, or {"value", "substitutions"} where %1$#@name@ in the value
    /// is replaced by the plural form of argument "arg" (the xcstrings format, see Windows/scripts/strings.py).
    /// </summary>
    static readonly Dictionary<string, JsonElement> English = LoadEnglish();

    static Dictionary<string, JsonElement> LoadEnglish()
    {
        if (Current != "en") return new();
        try
        {
            var path = Path.Combine(AppContext.BaseDirectory, "Strings", "en.json");
            return JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(File.ReadAllText(path)) ?? new();
        }
        catch { return new(); }
    }

    static string? Form(JsonElement forms, object? count)
    {
        var one = count is IConvertible c && Convert.ToDouble(c, CultureInfo.InvariantCulture) == 1;
        if (one && forms.TryGetProperty("one", out var single)) return single.GetString();
        return forms.TryGetProperty("other", out var other) ? other.GetString() : null;
    }

    /// <summary>Translated text for a Turkish key.</summary>
    public static string T(string key)
    {
        if (!English.TryGetValue(key, out var value)) return key;
        return value.ValueKind switch
        {
            JsonValueKind.String => value.GetString() is { Length: > 0 } text ? text : key,
            JsonValueKind.Object when value.TryGetProperty("value", out _) => F(key),
            JsonValueKind.Object => Form(value, 2) ?? key,
            _ => key,
        };
    }

    static string Template(string key, object?[] args)
    {
        if (!English.TryGetValue(key, out var value)) return key;
        switch (value.ValueKind)
        {
            case JsonValueKind.String:
                return value.GetString() is { Length: > 0 } text ? text : key;
            case JsonValueKind.Object when value.TryGetProperty("value", out var template):
                var result = template.GetString() ?? key;
                foreach (var substitution in value.GetProperty("substitutions").EnumerateObject())
                {
                    var arg = substitution.Value.GetProperty("arg").GetInt32() - 1;
                    var count = arg >= 0 && arg < args.Length ? args[arg] : null;
                    var form = (Form(substitution.Value, count) ?? "%arg").Replace("%arg", Convert.ToString(count, Culture));
                    result = Regex.Replace(result, @"%(\d+\$)?#@" + Regex.Escape(substitution.Name) + "@", form.Replace("$", "$$"));
                }
                return result;
            case JsonValueKind.Object:
                return Form(value, args.FirstOrDefault(a => a is int or long or double)) ?? key;
            default:
                return key;
        }
    }

    /// <summary>Translated text with %@ / %lld / %1$@ placeholders filled in order (or by position).</summary>
    public static string F(string key, params object?[] args)
    {
        var template = Template(key, args);
        var next = 0;
        return Placeholder().Replace(template, match =>
        {
            if (match.Value == "%%") return "%";
            var index = match.Groups[1].Success ? int.Parse(match.Groups[1].Value) - 1 : next++;
            return index >= 0 && index < args.Length ? Convert.ToString(args[index], Culture) ?? "" : "";
        });
    }

    [GeneratedRegex(@"%%|%(?:(\d+)\$)?(?:@|lld|ld|d|lf|f|s)")]
    private static partial Regex Placeholder();

    /// <summary>Percent: "%45" in Turkish, "45%" in English.</summary>
    public static string Percent(double fraction)
    {
        var value = (int)Math.Floor(fraction * 100);
        return Current == "tr" ? $"%{value}" : $"{value}%";
    }

    /// <summary>"2 saat önce" / "2 hours ago".</summary>
    public static string Relative(DateTimeOffset date)
    {
        var span = DateTimeOffset.Now - date;
        if (span.TotalSeconds < 60) return L.T("az önce");
        if (span.TotalMinutes < 60) return L.F("%lld dakika önce", (int)span.TotalMinutes);
        if (span.TotalHours < 24) return L.F("%lld saat önce", (int)span.TotalHours);
        return L.F("%lld gün önce", (int)span.TotalDays);
    }
}
