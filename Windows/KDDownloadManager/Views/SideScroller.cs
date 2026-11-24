using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;

namespace KDDownloadManager.Views;

/// <summary>
/// A row that scrolls sideways (the category rail). Not a ScrollViewer: that one keeps the mouse wheel to itself and,
/// with vertical scrolling off, did nothing with it, so a mouse could not reach the categories past the edge. Here
/// the wheel (vertical or tilted), a touch swipe and the arrow buttons beside it all move the row, and a button
/// that gets keyboard focus is scrolled into view.
/// </summary>
public sealed class SideScroller : Grid
{
    readonly Grid viewport = new();
    readonly Canvas host = new(); // measures the row at its full width
    readonly TranslateTransform shift = new();
    Storyboard? running;
    readonly Button left, right;
    readonly UIElement content;
    double offset;

    public SideScroller(FrameworkElement content)
    {
        this.content = content;
        content.RenderTransform = shift;
        host.Children.Add(content);
        viewport.Children.Add(host);
        viewport.Background = Theme.Clear; // hit-testable everywhere, for the wheel
        viewport.ManipulationMode = ManipulationModes.TranslateX | ManipulationModes.TranslateInertia;
        viewport.ManipulationDelta += (_, e) => ScrollTo(offset - e.Delta.Translation.X, animate: false);
        viewport.PointerWheelChanged += OnWheel;
        viewport.SizeChanged += (_, _) => Update();
        content.SizeChanged += (_, _) =>
        {
            host.Height = content.ActualHeight;
            Update();
        };
        content.GettingFocus += (_, e) =>
        {
            if (e.NewFocusedElement is FrameworkElement element) DispatcherQueue.TryEnqueue(() => Reveal(element));
        };
        // Arrows get columns of their own beside the row (not on top of it), so no category is ever covered.
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

    double Max => Math.Max(0, ((FrameworkElement)content).ActualWidth - viewport.ActualWidth);

    Button Arrow(string glyph, string tip, int direction)
    {
        var button = Ui.IconButton(glyph, tip, () => ScrollTo(offset + direction * viewport.ActualWidth * 0.6), 26);
        button.VerticalAlignment = VerticalAlignment.Center;
        Ui.Paint(button, Ui.Look.Clear);
        button.Visibility = Visibility.Collapsed;
        button.IsTabStop = false; // the categories themselves are reachable with Tab
        return button;
    }

    void OnWheel(object sender, PointerRoutedEventArgs e)
    {
        if (Max <= 0) return;
        var properties = e.GetCurrentPoint(viewport).Properties;
        var delta = properties.MouseWheelDelta;
        // Same direction as the vertical lists: the wheel turn that scrolls a list down (negative) moves this row toward
        // its end; a tilt right (positive) does too.
        ScrollTo(offset + (properties.IsHorizontalMouseWheel ? delta : -delta), animate: false);
        e.Handled = true;
    }

    /// <summary>Scrolls just enough for <paramref name="element"/> (inside the row) to be fully visible.</summary>
    public void Reveal(FrameworkElement element)
    {
        if (Max <= 0 || element.XamlRoot == null) return;
        var start = element.TransformToVisual(content).TransformPoint(default).X;
        var end = start + element.ActualWidth;
        if (start < offset) ScrollTo(start - 8);
        else if (end > offset + viewport.ActualWidth) ScrollTo(end - viewport.ActualWidth + 8);
    }

    void ScrollTo(double target, bool animate = true)
    {
        target = Math.Clamp(target, 0, Max);
        offset = target;
        // An animation holds its end value, which would win over a later direct assignment: stop it first, keeping
        // the position it had reached.
        var current = shift.X;
        running?.Stop();
        running = null;
        shift.X = current;
        if (animate)
        {
            var animation = new DoubleAnimation
            {
                From = current,
                To = -target,
                Duration = new Duration(TimeSpan.FromMilliseconds(220)),
                EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut },
            };
            Storyboard.SetTarget(animation, shift);
            Storyboard.SetTargetProperty(animation, "X");
            var storyboard = new Storyboard();
            storyboard.Children.Add(animation);
            storyboard.Begin();
            running = storyboard;
        }
        else
        {
            shift.X = -target;
        }
        UpdateArrows();
    }

    void Update()
    {
        viewport.Clip = new RectangleGeometry { Rect = new Windows.Foundation.Rect(0, 0, viewport.ActualWidth, viewport.ActualHeight) };
        if (offset > Max) ScrollTo(Max, animate: false);
        UpdateArrows();
    }

    void UpdateArrows()
    {
        left.Visibility = offset > 1 ? Visibility.Visible : Visibility.Collapsed;
        right.Visibility = offset < Max - 1 ? Visibility.Visible : Visibility.Collapsed;
    }
}
