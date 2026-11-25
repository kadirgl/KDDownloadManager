using DispatcherQueueTimer = Microsoft.UI.Dispatching.DispatcherQueueTimer;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;

namespace KDDownloadManager.Views;

/// <summary>
/// A row that scrolls sideways (the category rail). Not a ScrollViewer: that one keeps the mouse wheel to itself and,
/// with vertical scrolling off, did nothing with it, so a mouse could not reach the categories past the edge.
/// <list type="bullet">
/// <item>A mouse wheel notch or an arrow button glides to the next item (an animation, not a jump), and every stop
/// starts at an item's left edge, so no sliver of a cut-off item is left at the edge.</item>
/// <item>Touchpad and touch scrolling follow the fingers, then settle on the nearest item.</item>
/// <item>While the row overflows, both arrows keep their place (the one that cannot go further is dimmed), so the
/// row never shifts sideways because an arrow came or went.</item>
/// <item>An item that gets keyboard focus is scrolled into view.</item>
/// </list>
/// </summary>
public sealed class SideScroller : Grid
{
    const double ArrowSize = 26;
    const int Notch = 120; // one mouse wheel step (WHEEL_DELTA)

    readonly Grid viewport = new();
    readonly Canvas host = new(); // measures the row at its full width
    readonly TranslateTransform shift = new();
    readonly Panel items;
    readonly Button left, right;
    readonly DispatcherQueueTimer settle;
    Storyboard? running;
    double offset; // where the row is going (the animation may still be on its way)

    public SideScroller(Panel items)
    {
        this.items = items;
        items.RenderTransform = shift;
        host.Children.Add(items);
        viewport.Children.Add(host);
        viewport.Background = Theme.Clear; // hit-testable everywhere, for the wheel
        viewport.ManipulationMode = ManipulationModes.TranslateX | ManipulationModes.TranslateInertia;
        viewport.ManipulationDelta += (_, e) => Follow(offset - e.Delta.Translation.X);
        viewport.ManipulationCompleted += (_, _) => Glide(NearestStop(offset));
        viewport.PointerWheelChanged += OnWheel;
        SizeChanged += (_, _) => Update();
        viewport.SizeChanged += (_, _) => Update();
        items.SizeChanged += (_, _) =>
        {
            host.Height = items.ActualHeight;
            Update();
        };
        items.GettingFocus += (_, e) =>
        {
            if (e.NewFocusedElement is FrameworkElement element) DispatcherQueue.TryEnqueue(() => Reveal(element));
        };

        // A touchpad sends many small wheel steps; once they stop, settle on an item.
        settle = DispatcherQueue.CreateTimer();
        settle.Interval = TimeSpan.FromMilliseconds(160);
        settle.IsRepeating = false;
        settle.Tick += (_, _) => Ui.Guard(() => Glide(NearestStop(offset)));

        ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        SetColumn(viewport, 1);
        Children.Add(viewport);
        left = Arrow("", L.T("Sola kaydır"), -1);
        right = Arrow("", L.T("Sağa kaydır"), 1);
        left.Margin = new Thickness(0, 0, 2, 0);
        right.Margin = new Thickness(2, 0, 0, 0);
        SetColumn(right, 2);
        Children.Add(left);
        Children.Add(right);
    }

    bool Overflows => items.ActualWidth > ActualWidth + 0.5;

    /// <summary>The farthest the row scrolls: the last item's start that shows everything to its right.</summary>
    double End
    {
        get
        {
            var max = Math.Max(0, items.ActualWidth - viewport.ActualWidth);
            // Prefer stopping on an item's edge just past the plain maximum (a little empty space at the right end)
            // over leaving part of an item at the left edge.
            foreach (var start in Starts()) if (start >= max - 0.5) return start;
            return max;
        }
    }

    IEnumerable<double> Starts()
    {
        foreach (var child in items.Children)
            if (child is FrameworkElement element && element.Visibility == Visibility.Visible)
                yield return element.TransformToVisual(items).TransformPoint(default).X;
    }

    /// <summary>Item edges the row can rest on, from 0 to <see cref="End"/>.</summary>
    List<double> Stops()
    {
        var end = End;
        var stops = Starts().Where(s => s > 0.5 && s < end - 0.5).Prepend(0).Append(end).Distinct().ToList();
        stops.Sort();
        return stops;
    }

    double NearestStop(double at) => Stops().OrderBy(s => Math.Abs(s - at)).First();

    /// <summary>The next stop past where the row is going, in <paramref name="direction"/> (+1 toward the end).</summary>
    double NextStop(int direction)
    {
        var stops = Stops();
        return direction > 0
            ? stops.FirstOrDefault(s => s > offset + 0.5, stops[^1])
            : stops.LastOrDefault(s => s < offset - 0.5, 0);
    }

    Button Arrow(string glyph, string tip, int direction)
    {
        var button = Ui.IconButton(glyph, tip, () => Page(direction), ArrowSize);
        button.VerticalAlignment = VerticalAlignment.Center;
        Ui.Paint(button, Ui.Look.Clear);
        button.Visibility = Visibility.Collapsed;
        button.IsTabStop = false; // the categories themselves are reachable with Tab
        return button;
    }

    /// <summary>Arrow: about most of a view further, ending on an item edge.</summary>
    void Page(int direction)
    {
        var stops = Stops();
        var goal = offset + direction * viewport.ActualWidth * 0.7;
        var target = direction > 0
            ? stops.LastOrDefault(s => s <= goal + 0.5 && s > offset + 0.5, NextStop(1))
            : stops.FirstOrDefault(s => s >= goal - 0.5 && s < offset - 0.5, NextStop(-1));
        Glide(target);
    }

    void OnWheel(object sender, PointerRoutedEventArgs e)
    {
        if (!Overflows) return;
        var properties = e.GetCurrentPoint(viewport).Properties;
        // Same direction as the vertical lists: the wheel turn that scrolls a list down (negative) moves this row toward
        // its end; a tilt right (positive) does too.
        var delta = properties.IsHorizontalMouseWheel ? properties.MouseWheelDelta : -properties.MouseWheelDelta;
        e.Handled = true;
        if (Math.Abs(delta) >= Notch && delta % Notch == 0)
        {
            // A mouse: one item per notch, gliding.
            settle.Stop();
            for (var i = 0; i < Math.Abs(delta) / Notch; i++) Glide(NextStop(Math.Sign(delta)));
        }
        else
        {
            // A touchpad (small, smooth steps): follow it, settle on an item when it stops.
            Follow(offset + delta);
            settle.Stop();
            settle.Start();
        }
    }

    /// <summary>Scrolls just enough for <paramref name="element"/> (inside the row) to be fully visible.</summary>
    public void Reveal(FrameworkElement element)
    {
        if (!Overflows || element.XamlRoot == null) return;
        var start = element.TransformToVisual(items).TransformPoint(default).X;
        var end = start + element.ActualWidth;
        if (start < offset) Glide(Stops().LastOrDefault(s => s <= start + 0.5, 0));
        else if (end > offset + viewport.ActualWidth)
            Glide(Stops().FirstOrDefault(s => s >= end - viewport.ActualWidth - 0.5, End));
    }

    /// <summary>Moves with the input, no animation (touch, touchpad).</summary>
    void Follow(double target)
    {
        StopAnimation();
        offset = Math.Clamp(target, 0, End);
        shift.X = -offset;
        UpdateArrows();
    }

    /// <summary>Animates to <paramref name="target"/>, starting from wherever the row is shown now.</summary>
    void Glide(double target)
    {
        target = Math.Clamp(target, 0, End);
        offset = target;
        UpdateArrows();
        var from = StopAnimation();
        if (Math.Abs(from + target) < 0.5)
        {
            shift.X = -target;
            return;
        }
        var animation = new DoubleAnimation
        {
            From = from,
            To = -target,
            Duration = new Duration(TimeSpan.FromMilliseconds(240)),
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut },
        };
        Storyboard.SetTarget(animation, shift);
        Storyboard.SetTargetProperty(animation, "X");
        var storyboard = new Storyboard();
        storyboard.Children.Add(animation);
        storyboard.Completed += (_, _) =>
        {
            if (running != storyboard) return;
            running = null;
            storyboard.Stop();
            shift.X = -offset; // the animation's end value becomes the plain value
        };
        running = storyboard;
        storyboard.Begin();
    }

    /// <summary>Stops a running animation where it is (an animation's value would win over later assignments).</summary>
    double StopAnimation()
    {
        var current = shift.X;
        if (running != null)
        {
            var storyboard = running;
            running = null;
            storyboard.Pause();
            current = shift.X;
            storyboard.Stop();
        }
        shift.X = current;
        return current;
    }

    void Update()
    {
        // Both arrows take their place as soon as the row overflows and keep it while scrolling.
        var arrows = Overflows ? Visibility.Visible : Visibility.Collapsed;
        left.Visibility = arrows;
        right.Visibility = arrows;
        viewport.Clip = new RectangleGeometry { Rect = new Windows.Foundation.Rect(0, 0, viewport.ActualWidth, viewport.ActualHeight) };
        if (!Overflows) Follow(0);
        else if (offset > End + 0.5) Follow(End);
        UpdateArrows();
    }

    void UpdateArrows()
    {
        Set(left, offset > 0.5);
        Set(right, offset < End - 0.5);

        static void Set(Button button, bool enabled)
        {
            button.IsEnabled = enabled;
            button.Opacity = enabled ? 1 : 0.3;
        }
    }
}
