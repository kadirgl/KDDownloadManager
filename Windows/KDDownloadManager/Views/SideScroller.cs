using DispatcherQueueTimer = Microsoft.UI.Dispatching.DispatcherQueueTimer;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;

namespace KDDownloadManager.Views;

/// <summary>
/// A row that scrolls sideways (the category rail), on a ScrollViewer with its bar hidden. The ScrollViewer does the
/// scrolling, its animation and touch/touchpad panning (snapping to item edges); on its own it ignored the ordinary
/// mouse wheel, as it cannot scroll vertically, so this class turns the wheel into sideways scrolling:
/// <list type="bullet">
/// <item>A mouse wheel notch glides to the next item's left edge.</item>
/// <item>Small, smooth wheel steps (a touchpad sending wheel input) follow the fingers, then settle on the nearest item.</item>
/// <item>An item that gets keyboard focus is scrolled into view.</item>
/// </list>
/// Rest positions are item edges, so no sliver of a cut-off item is left at the left edge; the item cut off at the
/// right edge shows that there is more. There are no arrow buttons.
/// </summary>
public sealed class SideScroller : Grid
{
    const int Notch = 120; // one mouse wheel step (WHEEL_DELTA)

    readonly ScrollViewer scroll;
    readonly StackPanel items;
    readonly DispatcherQueueTimer settle;
    double? target; // where a running animation is going

    public SideScroller(StackPanel items)
    {
        this.items = items;
        scroll = new ScrollViewer
        {
            Content = items,
            HorizontalScrollMode = ScrollMode.Enabled,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Hidden,
            VerticalScrollMode = ScrollMode.Disabled,
            VerticalScrollBarVisibility = ScrollBarVisibility.Disabled,
            ZoomMode = ZoomMode.Disabled,
            IsHorizontalRailEnabled = true,
            // Touch and touchpad panning come to rest on an item's left edge (StackPanel provides the snap points).
            HorizontalSnapPointsType = SnapPointsType.Mandatory,
            HorizontalSnapPointsAlignment = SnapPointsAlignment.Near,
        };
        Children.Add(scroll);
        scroll.AddHandler(PointerWheelChangedEvent, new PointerEventHandler(OnWheel), true);
        scroll.ViewChanged += (_, e) =>
        {
            if (!e.IsIntermediate) target = null;
        };
        // Room after the last item so that the farthest position also starts on an item's edge.
        scroll.SizeChanged += (_, _) => FitEnd();
        items.SizeChanged += (_, _) => FitEnd();
        items.GettingFocus += (_, e) =>
        {
            if (e.NewFocusedElement is FrameworkElement element) DispatcherQueue.TryEnqueue(() => Reveal(element));
        };

        // A touchpad sends many small wheel steps; once they stop, settle on an item.
        settle = DispatcherQueue.CreateTimer();
        settle.Interval = TimeSpan.FromMilliseconds(160);
        settle.IsRepeating = false;
        settle.Tick += (_, _) => Ui.Guard(() => Glide(Nearest(scroll.HorizontalOffset)));
    }

    double Max => scroll.ScrollableWidth;

    /// <summary>Left edges of the items, in whole pixels.</summary>
    List<double> Stops()
    {
        var stops = new List<double> { 0 };
        foreach (var child in items.Children)
            if (child is FrameworkElement element && element.Visibility == Visibility.Visible)
                stops.Add(Math.Round(element.TransformToVisual(items).TransformPoint(default).X));
        return stops.Where(s => s <= Max + 0.5).Append(Max).Distinct().OrderBy(s => s).ToList();
    }

    double Nearest(double at) => Stops().OrderBy(s => Math.Abs(s - at)).First();

    void FitEnd()
    {
        // The padding is extra room at the right end: without it the farthest position is wherever the content ends,
        // usually in the middle of an item, which then shows as a sliver at the left edge.
        var padding = items.Padding.Right;
        var natural = items.ActualWidth - padding;
        var view = scroll.ViewportWidth;
        double needed = 0;
        if (natural > view + 0.5)
        {
            var max = natural - view;
            foreach (var child in items.Children)
            {
                if (child is not FrameworkElement element || element.Visibility != Visibility.Visible) continue;
                var start = element.TransformToVisual(items).TransformPoint(default).X;
                if (start >= max - 0.5)
                {
                    needed = Math.Ceiling(start - max);
                    break;
                }
            }
        }
        if (Math.Abs(needed - padding) > 0.5) items.Padding = new Thickness(0, 0, needed, 0);
    }

    void OnWheel(object sender, PointerRoutedEventArgs e)
    {
        if (Max <= 0) return;
        var properties = e.GetCurrentPoint(scroll).Properties;
        if (properties.IsHorizontalMouseWheel) return; // the ScrollViewer scrolls sideways for that itself
        // Same direction as the vertical lists: the wheel turn that scrolls a list down (negative) moves this row
        // toward its end.
        var delta = -properties.MouseWheelDelta;
        e.Handled = true;
        if (Math.Abs(delta) >= Notch && delta % Notch == 0)
        {
            // A mouse: one item per notch, gliding; quick notches add up.
            settle.Stop();
            var from = target ?? scroll.HorizontalOffset;
            var stops = Stops();
            for (var i = 0; i < Math.Abs(delta) / Notch; i++)
                from = delta > 0
                    ? stops.FirstOrDefault(s => s > from + 0.5, stops[^1])
                    : stops.LastOrDefault(s => s < from - 0.5, 0);
            Glide(from);
        }
        else
        {
            // A touchpad (small, smooth steps): follow it, settle on an item when it stops.
            target = null;
            scroll.ChangeView(Math.Clamp(scroll.HorizontalOffset + delta, 0, Max), null, null, true);
            settle.Stop();
            settle.Start();
        }
    }

    void Glide(double to)
    {
        to = Math.Clamp(to, 0, Max);
        if (Math.Abs(to - scroll.HorizontalOffset) < 0.5 && target == null) return;
        target = to;
        scroll.ChangeView(to, null, null, false);
    }

    /// <summary>Scrolls just enough for <paramref name="element"/> (inside the row) to be fully visible.</summary>
    public void Reveal(FrameworkElement element)
    {
        if (Max <= 0 || element.XamlRoot == null) return;
        var start = element.TransformToVisual(items).TransformPoint(default).X;
        var end = start + element.ActualWidth;
        var offset = scroll.HorizontalOffset;
        if (start < offset - 0.5) Glide(Stops().LastOrDefault(s => s <= start + 0.5, 0));
        else if (end > offset + scroll.ViewportWidth + 0.5)
            Glide(Stops().FirstOrDefault(s => s >= end - scroll.ViewportWidth - 0.5, Max));
    }
}
