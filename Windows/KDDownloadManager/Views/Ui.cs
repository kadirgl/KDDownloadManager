using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media;
using Windows.UI;
using Windows.UI.Text;

namespace KDDownloadManager.Views;

/// <summary>Small helpers to build the panel's controls in code.</summary>
/// <summary>
/// Thin progress bar: a track and a filled part (macOS: ProgressBar in Components). WinUI's ProgressBar is not
/// used, its composition animations failed natively in the test VM like ProgressRing's.
/// </summary>
public sealed class Bar : Grid
{
    readonly ColumnDefinition done = new() { Width = new GridLength(0, GridUnitType.Star) };
    readonly ColumnDefinition rest = new() { Width = new GridLength(1, GridUnitType.Star) };
    readonly Border fill = new() { CornerRadius = new CornerRadius(2) };

    public Bar(double height = 4)
    {
        Height = height;
        CornerRadius = new CornerRadius(height / 2);
        Background = Theme.SubtleFill;
        ColumnDefinitions.Add(done);
        ColumnDefinitions.Add(rest);
        Children.Add(fill);
    }

    public double Value
    {
        set
        {
            var v = Math.Clamp(double.IsFinite(value) ? value : 0, 0, 1);
            done.Width = new GridLength(v, GridUnitType.Star);
            rest.Width = new GridLength(1 - v, GridUnitType.Star);
        }
    }

    public Brush Fill { set => fill.Background = value; }
}

public static class Ui
{
    /// <summary>
    /// Runs a timer or framework callback; an exception there would otherwise end the app (fail-fast in the
    /// dispatcher), so it is logged instead.
    /// </summary>
    public static void Guard(Action action)
    {
        try { action(); }
        catch (Exception error) { App.Log("Guard: " + error); }
    }

    /// <summary>
    /// A small spinning ring. WinUI's ProgressRing failed natively when added to the panel (self-contained 1.8),
    /// so this is a glyph rotated by a plain Storyboard.
    /// </summary>
    public static FrameworkElement Spinner(double size = 18, Brush? brush = null)
    {
        var icon = Icon("\uE895", size, brush ?? Theme.AccentBrush());
        var rotate = new RotateTransform();
        icon.RenderTransform = rotate;
        icon.RenderTransformOrigin = new Windows.Foundation.Point(0.5, 0.5);
        var animation = new Microsoft.UI.Xaml.Media.Animation.DoubleAnimation
        {
            From = 0,
            To = 360,
            Duration = new Duration(TimeSpan.FromSeconds(1)),
            RepeatBehavior = Microsoft.UI.Xaml.Media.Animation.RepeatBehavior.Forever,
        };
        Microsoft.UI.Xaml.Media.Animation.Storyboard.SetTarget(animation, rotate);
        Microsoft.UI.Xaml.Media.Animation.Storyboard.SetTargetProperty(animation, "Angle");
        var storyboard = new Microsoft.UI.Xaml.Media.Animation.Storyboard();
        storyboard.Children.Add(animation);
        icon.Loaded += (_, _) => storyboard.Begin();
        icon.Unloaded += (_, _) => storyboard.Stop();
        return icon;
    }

    /// <summary>Gives keyboard focus to the list page that contains <paramref name="element"/>.</summary>
    public static void FocusList(DependencyObject element)
    {
        for (var node = element; node != null; node = VisualTreeHelper.GetParent(node))
            if (node is ListPage page) { page.Focus(FocusState.Programmatic); return; }
    }

    public static readonly FontFamily Icons = new("Segoe Fluent Icons, Segoe MDL2 Assets");

    public static TextBlock Text(string text, double size = 13, FontWeight? weight = null, Brush? brush = null, bool wrap = false, bool trim = true)
    {
        var block = new TextBlock
        {
            Text = text,
            FontSize = size,
            FontWeight = weight ?? FontWeights.Normal,
            TextWrapping = wrap ? TextWrapping.WrapWholeWords : TextWrapping.NoWrap,
            TextTrimming = trim && !wrap ? TextTrimming.CharacterEllipsis : TextTrimming.None,
            VerticalAlignment = VerticalAlignment.Center,
        };
        if (brush != null) block.Foreground = brush;
        return block;
    }

    public static TextBlock Secondary(string text, double size = 12, bool wrap = false) => Text(text, size, brush: Theme.SecondaryText, wrap: wrap);

    public static FontIcon Icon(string glyph, double size = 14, Brush? brush = null)
    {
        var icon = new FontIcon { Glyph = glyph, FontFamily = Icons, FontSize = size, VerticalAlignment = VerticalAlignment.Center };
        if (brush != null) icon.Foreground = brush;
        return icon;
    }

    public static StackPanel Row(double spacing = 8, params UIElement[] children)
    {
        var panel = new StackPanel { Orientation = Orientation.Horizontal, Spacing = spacing, VerticalAlignment = VerticalAlignment.Center };
        foreach (var child in children) panel.Children.Add(child);
        return panel;
    }

    public static StackPanel Column(double spacing = 8, params UIElement[] children)
    {
        var panel = new StackPanel { Orientation = Orientation.Vertical, Spacing = spacing };
        foreach (var child in children) panel.Children.Add(child);
        return panel;
    }

    /// <summary>Round icon button with a tooltip (glass button on macOS).</summary>
    public static Button IconButton(string glyph, string tip, Action action, double size = 34, Brush? tint = null)
    {
        var button = new Button
        {
            Content = Icon(glyph, 14, tint),
            Width = size,
            Height = size,
            Padding = new Thickness(0),
            CornerRadius = new CornerRadius(size / 2),
        };
        ToolTipService.SetToolTip(button, tip);
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(button, tip);
        button.Click += (_, _) => action();
        return button;
    }

    /// <summary>
    /// A button showing its value and a chevron that opens a menu (set <c>Flyout</c>). DropDownButton is not used:
    /// its animated chevron (AnimatedIcon) failed natively in the test VM, like ProgressRing.
    /// </summary>
    public static Button MenuButton(string text) => new()
    {
        Content = Row(6, Text(text, 13, FontWeights.SemiBold), Icon("\uE70D", 10)),
        CornerRadius = new CornerRadius(8),
        Padding = new Thickness(10, 4, 8, 4),
    };

    public static Button Pill(string text, Action action, string? glyph = null, double height = 30, double fontSize = 12.5)
    {
        object content = glyph == null ? Text(text, fontSize, FontWeights.SemiBold) : Row(6, Icon(glyph, 12), Text(text, fontSize, FontWeights.SemiBold));
        var button = new Button
        {
            Content = content,
            Height = height,
            Padding = new Thickness(12, 0, 12, 0),
            CornerRadius = new CornerRadius(height / 2),
            VerticalAlignment = VerticalAlignment.Center,
        };
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(button, text);
        button.Click += (_, _) => action();
        return button;
    }

    /// <summary>Accent-colored main button (Download, Add link).</summary>
    public static Button AccentButton(string text, string? glyph, Action action, double height = 40)
    {
        var foreground = Theme.Brush(Theme.OnAccent);
        var label = Text(text, 14, FontWeights.SemiBold, foreground);
        object content = glyph == null ? label : Row(8, Icon(glyph, 14, foreground), label);
        var button = new Button
        {
            Content = content,
            Height = height,
            Padding = new Thickness(18, 0, 18, 0),
            CornerRadius = new CornerRadius(height / 2),
            Background = Theme.AccentBrush(),
            BorderThickness = new Thickness(0),
            HorizontalAlignment = HorizontalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Center,
        };
        // Keep the accent on hover/press too (the default style switches to grey).
        foreach (var key in new[] { "ButtonBackgroundPointerOver", "ButtonBackgroundPressed" })
            button.Resources[key] = Theme.AccentBrush(key.EndsWith("Pressed") ? 0.8 : 0.9);
        foreach (var key in new[] { "ButtonForegroundPointerOver", "ButtonForegroundPressed" })
            button.Resources[key] = foreground;
        button.Resources["ButtonBackgroundDisabled"] = Theme.AccentBrush(0.4);
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(button, text);
        button.Click += (_, _) => action();
        return button;
    }

    public static Border Card(UIElement child, Thickness? padding = null, Color? tint = null)
    {
        return new Border
        {
            Child = child,
            Padding = padding ?? new Thickness(14, 12, 14, 12),
            CornerRadius = new CornerRadius(Theme.CardRadius),
            Background = tint is { } t ? Theme.Brush(t, 0.12) : Theme.CardBackground,
            BorderBrush = tint is { } s ? Theme.Brush(s, 0.4) : Theme.CardStroke,
            BorderThickness = new Thickness(1),
        };
    }

    public static TextBlock SectionLabel(string title) =>
        new() { Text = title.ToUpper(L.Culture), FontSize = 11, FontWeight = FontWeights.SemiBold, Foreground = Theme.SecondaryText, CharacterSpacing = 40, Margin = new Thickness(4, 0, 0, 0) };

    public static Border Divider() => new() { Height = 1, Background = Theme.Divider, Margin = new Thickness(0, 2, 0, 2) };

    /// <summary>Label on the left, control on the right, optional note below.</summary>
    public static UIElement SettingRow(string title, UIElement control, string? note = null)
    {
        var grid = new Grid { ColumnSpacing = 10 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var label = Text(title, 13.5, wrap: true);
        grid.Children.Add(label);
        if (control is FrameworkElement element)
        {
            element.VerticalAlignment = VerticalAlignment.Center;
            // Screen readers (and UI tests) know the switch or field by its row's title.
            if (Microsoft.UI.Xaml.Automation.AutomationProperties.GetName(element) is null or "")
                Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(element, title);
        }
        Grid.SetColumn((FrameworkElement)control, 1);
        grid.Children.Add(control);
        if (note == null) return grid;
        return Column(4, grid, Secondary(note, 11.5, wrap: true));
    }

    public static ToggleSwitch Toggle(bool isOn, Action<bool> changed)
    {
        // Only the track (40 px plus its border): the template keeps room for On/Off text on the right even when it is empty, which
        // pushed the switch to the middle of the card.
        var toggle = new ToggleSwitch
        {
            IsOn = isOn,
            OnContent = null,
            OffContent = null,
            MinWidth = 0,
            Width = 44,
            HorizontalAlignment = HorizontalAlignment.Right,
            Margin = new Thickness(0, -4, 0, -4),
        };
        toggle.Resources["ToggleSwitchPreContentMargin"] = 0.0;
        toggle.Resources["ToggleSwitchPostContentMargin"] = 0.0;
        Accentize(toggle);
        toggle.Toggled += (_, _) => changed(toggle.IsOn);
        return toggle;
    }

    /// <summary>Toggle switch in the app's accent color instead of Windows' accent.</summary>
    public static void Accentize(ToggleSwitch toggle)
    {
        toggle.Resources["ToggleSwitchFillOn"] = Theme.AccentBrush();
        toggle.Resources["ToggleSwitchFillOnPointerOver"] = Theme.AccentBrush(0.9);
        toggle.Resources["ToggleSwitchFillOnPressed"] = Theme.AccentBrush(0.8);
        toggle.Resources["ToggleSwitchStrokeOn"] = Theme.AccentBrush();
        toggle.Resources["ToggleSwitchKnobFillOn"] = Theme.Brush(Theme.OnAccent);
        toggle.Resources["ToggleSwitchKnobFillOnPointerOver"] = Theme.Brush(Theme.OnAccent);
        toggle.Resources["ToggleSwitchKnobFillOnPressed"] = Theme.Brush(Theme.OnAccent);
    }

    /// <summary>Segmented choice (theme, language) as a row of toggle pills.</summary>
    public static StackPanel Segmented<T>(IEnumerable<(T value, string title)> options, T selected, Action<T> changed)
    {
        var panel = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 2, Padding = new Thickness(2) };
        var border = new List<ToggleButton>();
        foreach (var (value, title) in options)
        {
            var button = new ToggleButton
            {
                Content = Text(title, 12, FontWeights.SemiBold),
                IsChecked = EqualityComparer<T>.Default.Equals(value, selected),
                Height = 28,
                Padding = new Thickness(10, 0, 10, 0),
                CornerRadius = new CornerRadius(14),
            };
            button.Resources["ToggleButtonBackgroundChecked"] = Theme.AccentBrush();
            button.Resources["ToggleButtonBackgroundCheckedPointerOver"] = Theme.AccentBrush(0.9);
            button.Resources["ToggleButtonBackgroundCheckedPressed"] = Theme.AccentBrush(0.8);
            button.Resources["ToggleButtonForegroundChecked"] = Theme.Brush(Theme.OnAccent);
            button.Resources["ToggleButtonForegroundCheckedPointerOver"] = Theme.Brush(Theme.OnAccent);
            button.Resources["ToggleButtonForegroundCheckedPressed"] = Theme.Brush(Theme.OnAccent);
            var captured = value;
            button.Click += (_, _) =>
            {
                foreach (var other in border) other.IsChecked = other == button;
                changed(captured);
            };
            border.Add(button);
            panel.Children.Add(button);
        }
        return panel;
    }

    /// <summary>"−  3 indirme  +" stepper.</summary>
    public static StackPanel Stepper(int value, int min, int max, Func<int, string> format, Action<int> changed)
    {
        var label = Text(format(value), 13, FontWeights.SemiBold);
        label.MinWidth = 70;
        label.TextAlignment = TextAlignment.Center;
        var current = value;
        Button Step(string glyph, int delta, string tip) => IconButton(glyph, tip, () =>
        {
            var next = Math.Clamp(current + delta, min, max);
            if (next == current) return;
            current = next;
            label.Text = format(current);
            changed(current);
        }, 28);
        return Row(4, Step("", -1, L.T("Azalt")), label, Step("", 1, L.T("Artır")));
    }

    /// <summary>Rounded tile with the category's gradient and glyph.</summary>
    public static Border CategoryIcon(Models.DownloadCategory category, double size = 40)
    {
        var (top, bottom) = Models.DownloadCategories.Colors(category);
        return new Border
        {
            Width = size,
            Height = size,
            CornerRadius = new CornerRadius(size * 0.28),
            Background = new LinearGradientBrush
            {
                StartPoint = new Windows.Foundation.Point(0, 0),
                EndPoint = new Windows.Foundation.Point(0, 1),
                GradientStops = { new GradientStop { Color = top, Offset = 0 }, new GradientStop { Color = bottom, Offset = 1 } },
            },
            Child = Icon(Models.DownloadCategories.Glyph(category), size * 0.42, Theme.Brush(Microsoft.UI.Colors.White)),
            VerticalAlignment = VerticalAlignment.Center,
        };
    }

    public static readonly (string title, long? limit)[] SpeedOptions =
        [(L.T("Sınırsız"), null), .. new long[] { 1, 2, 5, 10, 25, 50 }.Select(mb => (L.F("%lld MB/sn", mb), (long?)(mb * 1_048_576)))];

    /// <summary>Speed limit menu (per download or global).</summary>
    public static MenuFlyout SpeedLimitMenu(string title, long? current, Action<long?> selected, bool showsGlobalNote = true)
    {
        var menu = new MenuFlyout();
        menu.Items.Add(new MenuFlyoutItem { Text = title, IsEnabled = false });
        menu.Items.Add(new MenuFlyoutSeparator());
        var options = SpeedOptions.ToList();
        if (current is { } c && !options.Any(o => o.limit == c)) options.Add((L.F("%lld MB/sn", c / 1_048_576), c));
        foreach (var (text, limit) in options.OrderBy(o => o.limit ?? 0))
        {
            var item = new ToggleMenuFlyoutItem { Text = text, IsChecked = current == limit };
            var captured = limit;
            item.Click += (_, _) => selected(captured);
            menu.Items.Add(item);
        }
        if (showsGlobalNote && Settings.GlobalLimitEnabled)
        {
            menu.Items.Add(new MenuFlyoutSeparator());
            menu.Items.Add(new MenuFlyoutItem { Text = L.F("Genel sınır %lld MB/sn; daha yüksek değerler bununla kısıtlanır.", (long)Settings.GlobalLimitMB), IsEnabled = false });
        }
        return menu;
    }
}
