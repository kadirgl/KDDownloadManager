using System.ComponentModel;
using KDDownloadManager.Models;
using KDDownloadManager.Store;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Windows.ApplicationModel.DataTransfer;

namespace KDDownloadManager.Views;

/// <summary>
/// One download in the list (macOS: DownloadRow): category tile, name / percent / bar / status, and buttons.
/// The pause/resume (retry) button is always visible; speed limit and delete appear on hover or selection.
/// </summary>
public sealed class RowView : UserControl
{
    readonly DownloadStore store;
    public DownloadItem Item { get; }

    readonly Border card = new();
    readonly Border tile = new();
    readonly TextBlock name = Ui.Text("", 14, FontWeights.SemiBold);
    readonly TextBlock percent = Ui.Text("", 13, FontWeights.Medium, Theme.SecondaryText);
    readonly Bar bar = new();
    readonly StackPanel status = new() { Orientation = Orientation.Horizontal, Spacing = 8 };
    readonly StackPanel actions = new() { Orientation = Orientation.Horizontal, Spacing = 6, VerticalAlignment = VerticalAlignment.Center };
    bool hovering;
    bool selected;

    public RowView(DownloadStore store, DownloadItem item)
    {
        this.store = store;
        Item = item;
        card.CornerRadius = new CornerRadius(Theme.CardRadius);
        card.BorderThickness = new Thickness(1);
        card.Padding = new Thickness(12, 10, 10, 10);
        Content = card;

        var grid = new Grid { ColumnSpacing = 12 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.Children.Add(tile);

        var top = new Grid { ColumnSpacing = 8 };
        top.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        top.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        name.TextTrimming = TextTrimming.CharacterEllipsis;
        top.Children.Add(name);
        Grid.SetColumn(percent, 1);
        top.Children.Add(percent);
        var middle = Ui.Column(6, top, bar, status);
        middle.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(middle, 1);
        grid.Children.Add(middle);
        Grid.SetColumn(actions, 2);
        grid.Children.Add(actions);
        card.Child = grid;

        PointerEntered += (_, _) => { hovering = true; RefreshActions(); };
        PointerExited += (_, _) => { hovering = false; RefreshActions(); };
        Tapped += (_, _) => store.Selection = item.Id;
        DoubleTapped += (_, _) => { if (item.IsCompleted && !Shell.Open(item.Destination)) Shell.Beep(); };
        RightTapped += (_, e) =>
        {
            store.Selection = item.Id;
            ContextMenu().ShowAt(this, e.GetPosition(this));
        };
        CanDrag = true;
        DragStarting += OnDragStarting;
        Loaded += (_, _) => item.PropertyChanged += OnItemChanged;
        Unloaded += (_, _) => item.PropertyChanged -= OnItemChanged;
        Refresh();
    }

    public bool Selected
    {
        get => selected;
        set
        {
            if (selected == value) return;
            selected = value;
            RefreshChrome();
            RefreshActions();
        }
    }

    void OnItemChanged(object? sender, PropertyChangedEventArgs e)
    {
        switch (e.PropertyName)
        {
            case nameof(DownloadItem.Status):
            case nameof(DownloadItem.Category):
                Refresh();
                break;
            default:
                RefreshText();
                break;
        }
    }

    void Refresh()
    {
        tile.Child = Ui.CategoryIcon(Item.Category, 40);
        RefreshChrome();
        RefreshText();
        RefreshActions();
    }

    void RefreshChrome()
    {
        card.Background = Item.IsFailed ? Theme.Brush(Theme.Error, 0.08) : Theme.CardBackground;
        card.BorderBrush = Item.IsFailed ? Theme.Brush(Theme.Error, 0.55) : selected ? Theme.AccentBrush(0.8) : Theme.CardStroke;
        card.BorderThickness = new Thickness(selected && !Item.IsFailed ? 1.5 : 1);
    }

    void RefreshText()
    {
        name.Text = Item.FileName;
        ToolTipService.SetToolTip(name, Item.FileName);
        var completed = Item.IsCompleted;
        percent.Visibility = completed ? Visibility.Collapsed : Visibility.Visible;
        percent.Text = L.Percent(Item.Progress);
        bar.Visibility = completed ? Visibility.Collapsed : Visibility.Visible;
        bar.Value = Item.Progress;
        bar.Fill = Item.Status.Kind switch
        {
            StatusKind.Failed => Theme.Brush(Theme.Error),
            StatusKind.Paused or StatusKind.Queued => Theme.TertiaryText,
            _ => Theme.AccentBrush(),
        };
        status.Children.Clear();
        void Add(string text, bool strong = false, Microsoft.UI.Xaml.Media.Brush? brush = null)
        {
            var block = Ui.Text(text, 12, strong ? FontWeights.SemiBold : FontWeights.Normal, brush ?? (strong ? Theme.PrimaryText : Theme.SecondaryText));
            status.Children.Add(block);
        }
        void Total() { if (Item.TotalBytes > 0) Add(ByteFormat.Size(Item.TotalBytes)); }
        switch (Item.Status.Kind)
        {
            case StatusKind.Downloading:
                if (Item.Speed > 0)
                {
                    var parts = new[] { ByteFormat.Speed(Item.Speed), Item.RemainingSeconds is { } r ? ByteFormat.Remaining(r) : "" }.Where(p => p.Length > 0);
                    Add(string.Join(" · ", parts), strong: true);
                }
                else Add(L.T("Bağlanıyor…"));
                Total();
                break;
            case StatusKind.Queued:
                Add(L.T("Sırada"));
                Total();
                break;
            case StatusKind.Processing:
                Add(L.T("Birleştiriliyor…"));
                Total();
                break;
            case StatusKind.Paused:
                Add(L.T("Duraklatıldı"));
                Add(Item.TotalBytes > 0 ? $"{ByteFormat.Size(Item.DownloadedBytes)} / {ByteFormat.Size(Item.TotalBytes)}" : ByteFormat.Size(Item.DownloadedBytes), strong: true);
                break;
            case StatusKind.Completed:
                if (Item.TotalBytes > 0) Add(ByteFormat.Size(Item.TotalBytes), strong: true);
                if (Item.CompletedAt is { } date) Add(ByteFormat.Finished(date));
                else if (DownloadSources.Host(Item.Url) is { } host) Add(host.Replace("www.", ""));
                break;
            case StatusKind.Failed:
                var message = Item.Status.Message ?? "";
                var error = Ui.Text(message, 12, brush: Theme.Brush(Theme.Error));
                ToolTipService.SetToolTip(error, message);
                status.Children.Add(error);
                break;
        }
        if (Item.SpeedLimit is { } limit && !completed)
        {
            var badge = new Border
            {
                CornerRadius = new CornerRadius(9),
                Padding = new Thickness(6, 1, 6, 1),
                Background = Theme.AccentBrush(0.14),
                Child = Ui.Row(3, Ui.Icon("", 10, Theme.AccentBrush()), Ui.Text(ByteFormat.Speed(limit), 10.5, FontWeights.SemiBold, Theme.AccentBrush())),
            };
            ToolTipService.SetToolTip(badge, L.T("Bu indirmeye özel hız sınırı"));
            status.Children.Add(badge);
        }
    }

    void RefreshActions()
    {
        actions.Children.Clear();
        var showSecondary = hovering || selected;
        if (Item.IsCompleted)
        {
            if (!showSecondary) return;
            actions.Children.Add(Ui.IconButton("", L.T("Klasörde göster"), () => DownloadStore.Reveal(Item)));
            actions.Children.Add(Ui.IconButton("", L.T("Listeden kaldır (dosya diskte kalır)"), () => store.RemoveFromList(Item)));
            return;
        }
        if ((showSecondary || Item.SpeedLimit != null) && !Item.IsFailed)
        {
            Microsoft.UI.Xaml.Controls.Button? limit = null;
            limit = Ui.IconButton("", Item.SpeedLimit is { } l ? L.F("Hız sınırı: %@", ByteFormat.Speed(l)) : L.T("Hız sınırı"), () =>
            {
                Ui.SpeedLimitMenu(L.T("Bu indirme için hız sınırı"), Item.SpeedLimit, value => store.SetSpeedLimit(value, Item)).ShowAt(limit!);
            }, tint: Item.SpeedLimit == null ? null : Theme.AccentBrush());
            actions.Children.Add(limit);
        }
        if (showSecondary) actions.Children.Add(Ui.IconButton("", L.T("İndirmeyi sil"), () => store.Delete(Item)));
        var (glyph, help) = Item.Status.Kind switch
        {
            StatusKind.Paused => ("", L.T("Devam et")),
            StatusKind.Failed => ("", L.T("Tekrar dene")),
            _ => ("", L.T("Duraklat")),
        };
        actions.Children.Add(Ui.IconButton(glyph, help, () => store.TogglePause(Item)));
    }

    MenuFlyout ContextMenu()
    {
        var menu = new MenuFlyout();
        void Item_(string text, Action action, string? glyph = null)
        {
            var entry = new MenuFlyoutItem { Text = text };
            if (glyph != null) entry.Icon = new FontIcon { Glyph = glyph, FontFamily = Ui.Icons };
            entry.Click += (_, _) => action();
            menu.Items.Add(entry);
        }
        if (Item.IsCompleted)
        {
            if (Item.Destination != null) Item_(L.T("Aç"), () => Shell.Open(Item.Destination), "");
        }
        else
        {
            Item_(Item.Status.Kind is StatusKind.Paused or StatusKind.Failed ? (Item.IsFailed ? L.T("Tekrar dene") : L.T("Devam et")) : L.T("Duraklat"),
                () => store.TogglePause(Item), Item.Status.Kind == StatusKind.Paused ? "" : "");
            var limits = new MenuFlyoutSubItem { Text = L.T("Hız sınırı") };
            foreach (var (title, limit) in Ui.SpeedOptions)
            {
                var option = new ToggleMenuFlyoutItem { Text = title, IsChecked = Item.SpeedLimit == limit };
                var captured = limit;
                option.Click += (_, _) => store.SetSpeedLimit(captured, Item);
                limits.Items.Add(option);
            }
            menu.Items.Add(limits);
        }
        Item_(L.T("Klasörde göster"), () => DownloadStore.Reveal(Item), "");
        Item_(L.T("Linki kopyala"), () => Shell.Copy(Item.Url), "");
        menu.Items.Add(new MenuFlyoutSeparator());
        if (Item.IsCompleted)
        {
            Item_(L.T("Listeden kaldır"), () => store.RemoveFromList(Item), "");
            Item_(L.T("Geri Dönüşüm Kutusuna taşı"), () => store.Delete(Item), "");
        }
        else Item_(L.T("İndirmeyi sil"), () => store.Delete(Item), "");
        return menu;
    }

    /// <summary>A completed file can be dragged to File Explorer or another app.</summary>
    async void OnDragStarting(UIElement sender, DragStartingEventArgs args)
    {
        if (!Item.IsCompleted || Item.Destination is not { } path || !File.Exists(path))
        {
            args.Cancel = true;
            return;
        }
        var deferral = args.GetDeferral();
        try
        {
            var file = await Windows.Storage.StorageFile.GetFileFromPathAsync(path);
            args.Data.SetStorageItems([file]);
            args.Data.RequestedOperation = DataPackageOperation.Copy;
        }
        catch { args.Cancel = true; }
        finally { deferral.Complete(); }
    }
}
