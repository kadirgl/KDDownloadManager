using KDDownloadManager.Models;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using Windows.UI;
using Windows.UI.ViewManagement;

namespace KDDownloadManager;

public enum AppThemeChoice { System, Light, Dark }

public enum AccentChoice { Orange, System, Blue, Purple, Pink, Red, Green, Teal, Custom }

/// <summary>Colors and sizes of the panel (macOS: Theme / AppTheme / AccentChoice).</summary>
public static class Theme
{
    public const double PanelWidth = 460;
    public const double PanelHeight = 680;
    public const double Margin = 16;
    public const double CardRadius = 14;

    public static AppThemeChoice ThemeChoice
    {
        get => Enum.TryParse<AppThemeChoice>(Settings.Get(Settings.AppTheme, "system"), true, out var t) ? t : AppThemeChoice.System;
        set => Settings.Set(Settings.AppTheme, value.ToString().ToLowerInvariant());
    }

    public static ElementTheme ElementTheme => ThemeChoice switch
    {
        AppThemeChoice.Light => ElementTheme.Light,
        AppThemeChoice.Dark => ElementTheme.Dark,
        _ => ElementTheme.Default,
    };

    public static string Title(this AppThemeChoice t) => t switch
    {
        AppThemeChoice.Light => L.T("Açık"),
        AppThemeChoice.Dark => L.T("Koyu"),
        _ => L.T("Sistem"),
    };

    public static AccentChoice Accent
    {
        get => Enum.TryParse<AccentChoice>(Settings.Get(Settings.AccentColor, "orange"), true, out var a) ? a : AccentChoice.Orange;
        set => Settings.Set(Settings.AccentColor, value.ToString().ToLowerInvariant());
    }

    public static string Title(this AccentChoice a) => a switch
    {
        AccentChoice.Orange => L.T("Turuncu"),
        AccentChoice.System => L.T("Sistem vurgu rengi"),
        AccentChoice.Blue => L.T("Mavi"),
        AccentChoice.Purple => L.T("Mor"),
        AccentChoice.Pink => L.T("Pembe"),
        AccentChoice.Red => L.T("Kırmızı"),
        AccentChoice.Green => L.T("Yeşil"),
        AccentChoice.Teal => L.T("Turkuaz"),
        _ => L.T("Özel renk"),
    };

    public static Color ColorOf(AccentChoice a) => a switch
    {
        AccentChoice.Orange => DownloadCategories.Hex(0xF08A2E),
        AccentChoice.System => new UISettings().GetColorValue(UIColorType.Accent),
        AccentChoice.Blue => DownloadCategories.Hex(0x0A84FF),
        AccentChoice.Purple => DownloadCategories.Hex(0x8E5CF7),
        AccentChoice.Pink => DownloadCategories.Hex(0xFF2D78),
        AccentChoice.Red => DownloadCategories.Hex(0xFF3B30),
        AccentChoice.Green => DownloadCategories.Hex(0x30B350),
        AccentChoice.Teal => DownloadCategories.Hex(0x14B8C4),
        _ => ParseHex(Settings.Get(Settings.AccentCustomColor, "")) ?? DownloadCategories.Hex(0xF08A2E),
    };

    public static Color AccentColor => ColorOf(Accent);

    /// <summary>"#RRGGBB"; the extension uses the app's accent too (/ping).</summary>
    public static string AccentHex => Hex(AccentColor);

    public static string Hex(Color c) => $"#{c.R:X2}{c.G:X2}{c.B:X2}";

    public static Color? ParseHex(string text)
    {
        text = text.Trim().TrimStart('#');
        return text.Length == 6 && uint.TryParse(text, System.Globalization.NumberStyles.HexNumber, null, out var value)
            ? DownloadCategories.Hex(value) : null;
    }

    /// <summary>Dark text on light accents (yellow, teal), white otherwise.</summary>
    public static Color OnAccent
    {
        get
        {
            var c = AccentColor;
            double Channel(byte v) { var s = v / 255.0; return s <= 0.03928 ? s / 12.92 : Math.Pow((s + 0.055) / 1.055, 2.4); }
            var luminance = 0.2126 * Channel(c.R) + 0.7152 * Channel(c.G) + 0.0722 * Channel(c.B);
            return (luminance + 0.05) / 0.05 > 1.05 / (luminance + 0.05) && luminance > 0.45 ? DownloadCategories.Hex(0x1D1D1F) : Colors.White;
        }
    }

    public static SolidColorBrush Brush(Color c, double opacity = 1) => new(Color.FromArgb((byte)(c.A * opacity), c.R, c.G, c.B));
    public static SolidColorBrush AccentBrush(double opacity = 1) => Brush(AccentColor, opacity);

    public static readonly Color Error = DownloadCategories.Hex(0xE5484D);
    public static readonly Color Warning = DownloadCategories.Hex(0xD99A1E);
    public static readonly Color Success = DownloadCategories.Hex(0x22A559);

    /// <summary>Whether the panel is drawn dark (setting, or Windows' app mode when "Sistem").</summary>
    public static bool IsDark => ThemeChoice switch
    {
        AppThemeChoice.Dark => true,
        AppThemeChoice.Light => false,
        _ => new UISettings().GetColorValue(UIColorType.Background).R < 128,
    };

    /// <summary>
    /// Theme-aware brushes from the Fluent resources. They live in the theme dictionaries of XamlControlsResources,
    /// which the code-side indexer does not search, so the dictionary of the current theme is read directly.
    /// </summary>
    public static Brush Resource(string key)
    {
        var theme = IsDark ? "Dark" : "Light";
        foreach (var dictionary in Application.Current.Resources.MergedDictionaries.Prepend(Application.Current.Resources))
        {
            foreach (var name in new[] { theme, "Default" })
            {
                if (dictionary.ThemeDictionaries.TryGetValue(name, out var themed) && themed is ResourceDictionary d
                    && d.TryGetValue(key, out var value) && value is Brush brush) return brush;
            }
            if (dictionary.TryGetValue(key, out var plain) && plain is Brush b) return b;
        }
        return new SolidColorBrush(IsDark ? Colors.White : Colors.Black);
    }
    // The panel's own palette (macOS Theme): Fluent's theme brushes resolve their colors only inside the XAML
    // tree, so brushes made in code would come out black.
    static Brush Pick(uint light, double lightAlpha, uint dark, double darkAlpha) =>
        IsDark ? Brush(DownloadCategories.Hex(dark), darkAlpha) : Brush(DownloadCategories.Hex(light), lightAlpha);
    public static Brush PrimaryText => Pick(0x1D1D1F, 1, 0xFFFFFF, 1);
    public static Brush SecondaryText => Pick(0x000000, 0.62, 0xFFFFFF, 0.70);
    public static Brush TertiaryText => Pick(0x000000, 0.45, 0xFFFFFF, 0.50);
    public static Brush CardBackground => Pick(0xFFFFFF, 0.62, 0xFFFFFF, 0.07);
    public static Brush CardStroke => Pick(0x000000, 0.07, 0xFFFFFF, 0.09);
    public static Brush SubtleFill => Pick(0x000000, 0.07, 0xFFFFFF, 0.18);
    public static Brush ControlFill => Pick(0xFFFFFF, 0.75, 0xFFFFFF, 0.12);
    public static Brush Divider => Pick(0x000000, 0.08, 0xFFFFFF, 0.08);
    public static Brush ToastBackground => Pick(0xF6F6F8, 0.96, 0x2C2A33, 0.96);
}
