using Microsoft.UI;
using Microsoft.UI.Input;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Windows.UI;

namespace KDDownloadManager.Views;

/// <summary>
/// Custom accent color: a saturation/brightness square, a hue strip and a hex field. WinUI's ColorPicker is not used:
/// opening it crashed the app natively (stowed exception in Microsoft.UI.Xaml.dll, self-contained 1.8), like
/// ProgressRing did. Everything here is plain borders and gradients.
/// </summary>
public sealed class ColorChooser : StackPanel
{
    const double AreaWidth = 232;
    const double AreaHeight = 140;
    const double HueHeight = 14;

    double hue, saturation, value;
    readonly Border area = new() { Width = AreaWidth, Height = AreaHeight, CornerRadius = new CornerRadius(8) };
    readonly Ellipse areaMarker = MakeMarker();
    readonly Ellipse hueMarker = MakeMarker();
    readonly Canvas areaCanvas = new() { Width = AreaWidth, Height = AreaHeight };
    readonly Canvas hueCanvas = new() { Width = AreaWidth, Height = HueHeight };
    readonly Border preview = new() { Width = 26, Height = 26, CornerRadius = new CornerRadius(13), BorderThickness = new Thickness(1) };
    readonly TextBox hex = new() { Width = 110, MaxLength = 7, FontSize = 13 };
    bool updatingHex;

    public Color Color => FromHsv(hue, saturation, value);

    public ColorChooser(Color initial)
    {
        Spacing = 10;
        (hue, saturation, value) = ToHsv(initial);

        var whiteOverlay = new Border
        {
            CornerRadius = new CornerRadius(8),
            Background = Gradient(new Windows.Foundation.Point(0, 0), new Windows.Foundation.Point(1, 0),
                Color.FromArgb(255, 255, 255, 255), Color.FromArgb(0, 255, 255, 255)),
        };
        var blackOverlay = new Border
        {
            CornerRadius = new CornerRadius(8),
            Background = Gradient(new Windows.Foundation.Point(0, 0), new Windows.Foundation.Point(0, 1),
                Color.FromArgb(0, 0, 0, 0), Color.FromArgb(255, 0, 0, 0)),
        };
        areaCanvas.Children.Add(areaMarker);
        var areaGrid = new Grid { Width = AreaWidth, Height = AreaHeight, Background = new SolidColorBrush(Colors.Transparent) };
        areaGrid.Children.Add(area);
        areaGrid.Children.Add(whiteOverlay);
        areaGrid.Children.Add(blackOverlay);
        areaGrid.Children.Add(areaCanvas);
        Track(areaGrid, p =>
        {
            saturation = Math.Clamp(p.X / AreaWidth, 0, 1);
            value = 1 - Math.Clamp(p.Y / AreaHeight, 0, 1);
            Update();
        });

        var hueStops = new GradientStopCollection();
        for (var i = 0; i <= 6; i++) hueStops.Add(new GradientStop { Color = FromHsv(i * 60 % 360, 1, 1), Offset = i / 6.0 });
        var hueStrip = new Border
        {
            Width = AreaWidth,
            Height = HueHeight,
            CornerRadius = new CornerRadius(HueHeight / 2),
            Background = new LinearGradientBrush(hueStops, 0),
        };
        hueCanvas.Children.Add(hueMarker);
        var hueGrid = new Grid { Width = AreaWidth, Height = HueHeight, Background = new SolidColorBrush(Colors.Transparent) };
        hueGrid.Children.Add(hueStrip);
        hueGrid.Children.Add(hueCanvas);
        Track(hueGrid, p =>
        {
            hue = Math.Clamp(p.X / AreaWidth, 0, 1) * 359.9;
            Update();
        });

        preview.BorderBrush = Theme.CardStroke;
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(hex, L.T("Özel renk"));
        hex.TextChanged += (_, _) =>
        {
            if (updatingHex) return;
            if (Theme.ParseHex(hex.Text) is { } c)
            {
                (hue, saturation, value) = ToHsv(c);
                Update(fromHex: true);
            }
        };

        Children.Add(areaGrid);
        Children.Add(hueGrid);
        Children.Add(Ui.Row(10, preview, hex));
        Update();
    }

    void Update(bool fromHex = false)
    {
        var color = Color;
        area.Background = new SolidColorBrush(FromHsv(hue, 1, 1));
        Place(areaMarker, saturation * AreaWidth, (1 - value) * AreaHeight);
        Place(hueMarker, hue / 360 * AreaWidth, HueHeight / 2);
        preview.Background = new SolidColorBrush(color);
        if (fromHex) return;
        updatingHex = true;
        hex.Text = Theme.Hex(color);
        updatingHex = false;
    }

    static void Place(Ellipse marker, double x, double y)
    {
        Canvas.SetLeft(marker, x - marker.Width / 2);
        Canvas.SetTop(marker, y - marker.Height / 2);
    }

    static Ellipse MakeMarker() => new()
    {
        Width = 14,
        Height = 14,
        Stroke = new SolidColorBrush(Colors.White),
        StrokeThickness = 2.5,
        Fill = new SolidColorBrush(Colors.Transparent),
        IsHitTestVisible = false,
    };

    static LinearGradientBrush Gradient(Windows.Foundation.Point start, Windows.Foundation.Point end, Color from, Color to) => new()
    {
        StartPoint = start,
        EndPoint = end,
        GradientStops = { new GradientStop { Color = from, Offset = 0 }, new GradientStop { Color = to, Offset = 1 } },
    };

    /// <summary>Calls <paramref name="moved"/> with the pointer position while the button is held (captured).</summary>
    static void Track(UIElement element, Action<Windows.Foundation.Point> moved)
    {
        var dragging = false;
        element.PointerPressed += (_, e) =>
        {
            dragging = element.CapturePointer(e.Pointer);
            moved(e.GetCurrentPoint(element).Position);
            e.Handled = true;
        };
        element.PointerMoved += (_, e) =>
        {
            if (dragging) moved(e.GetCurrentPoint(element).Position);
        };
        void Release(object _, PointerRoutedEventArgs e)
        {
            dragging = false;
            element.ReleasePointerCapture(e.Pointer);
        }
        element.PointerReleased += Release;
        element.PointerCaptureLost += (_, _) => dragging = false;
    }

    public static Color FromHsv(double h, double s, double v)
    {
        var c = v * s;
        var x = c * (1 - Math.Abs(h / 60 % 2 - 1));
        var m = v - c;
        var (r, g, b) = (h % 360) switch
        {
            < 60 => (c, x, 0.0),
            < 120 => (x, c, 0.0),
            < 180 => (0.0, c, x),
            < 240 => (0.0, x, c),
            < 300 => (x, 0.0, c),
            _ => (c, 0.0, x),
        };
        byte B(double t) => (byte)Math.Round(Math.Clamp(t + m, 0, 1) * 255);
        return Color.FromArgb(255, B(r), B(g), B(b));
    }

    public static (double h, double s, double v) ToHsv(Color color)
    {
        double r = color.R / 255.0, g = color.G / 255.0, b = color.B / 255.0;
        var max = Math.Max(r, Math.Max(g, b));
        var min = Math.Min(r, Math.Min(g, b));
        var d = max - min;
        double h = 0;
        if (d > 0)
        {
            if (max == r) h = 60 * ((g - b) / d % 6);
            else if (max == g) h = 60 * ((b - r) / d + 2);
            else h = 60 * ((r - g) / d + 4);
        }
        if (h < 0) h += 360;
        return (h, max == 0 ? 0 : d / max, max);
    }
}
