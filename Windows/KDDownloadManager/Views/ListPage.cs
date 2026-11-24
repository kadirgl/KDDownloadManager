using System.ComponentModel;
using KDDownloadManager.Models;
using KDDownloadManager.Store;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.System;
using DispatcherQueueTimer = Microsoft.UI.Dispatching.DispatcherQueueTimer;

namespace KDDownloadManager.Views;

/// <summary>
/// The main screen (macOS: DownloadListView): header, banners, category rail, download cards, and at the bottom
/// the Active / Completed tabs and the total speed (click for the global speed limit).
/// </summary>
public sealed class ListPage : UserControl
{
    readonly DownloadStore store;
    readonly StackPanel banners = new() { Spacing = 8 };
    readonly Grid searchHost = new();
    readonly StackPanel rail = new() { Orientation = Orientation.Horizontal, Spacing = 2 };
    readonly SideScroller railScroll;
    string railSignature = "";
    DownloadCategory? railCategory;
    readonly Border railCard;
    readonly Grid summary = new();
    readonly StackPanel rows = new() { Spacing = 8 };
    readonly ScrollViewer scroll;
    readonly Grid content = new();
    readonly Grid emptyHost = new();
    readonly StackPanel tabs = new() { Orientation = Orientation.Horizontal, Spacing = 2 };
    readonly Button speedButton = new();
    readonly Grid toastHost = new();
    readonly Dictionary<Guid, RowView> views = new();
    readonly TextBlock completedHint = Ui.Text(L.T("Çift tıkla: aç · Sürükle: Gezgin'e taşı"), 11, brush: Theme.TertiaryText);
    /// <summary>The "…" menu is open: the summary row is not rebuilt meanwhile (that would close it).</summary>
    bool summaryMenuOpen;
    TextBox? search;
    readonly DispatcherQueueTimer refreshTimer;
    readonly DispatcherQueueTimer slowTimer;
    bool refreshPending;

    public ListPage(DownloadStore store)
    {
        this.store = store;
        IsTabStop = true;
        var layout = new Grid();
        layout.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); // header
        layout.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); // banners
        layout.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); // search
        layout.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); // rail
        layout.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); // summary
        layout.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        layout.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); // bottom bar

        layout.Children.Add(Header(L.T("KD Download Manager"), null,
            Ui.IconButton("", L.T("Link ekle (Ctrl+N)"), () => store.Route = Route.AddLink, 38),
            Ui.IconButton("", L.T("Ayarlar (Ctrl+,)"), () => store.Route = Route.Settings, 38)));

        banners.Margin = new Thickness(Theme.Margin, 0, Theme.Margin, 0);
        Place(layout, banners, 1);
        searchHost.Margin = new Thickness(Theme.Margin, 0, Theme.Margin, 10);
        Place(layout, searchHost, 2);

        railScroll = new SideScroller(rail);
        railCard = new Border
        {
            Child = railScroll,
            Padding = new Thickness(3),
            CornerRadius = new CornerRadius(17),
            Background = Theme.CardBackground,
            BorderBrush = Theme.CardStroke,
            BorderThickness = new Thickness(1),
            Margin = new Thickness(Theme.Margin, 0, Theme.Margin, 10),
        };
        Place(layout, railCard, 3);
        summary.Margin = new Thickness(Theme.Margin + 2, 0, Theme.Margin, 8);
        summary.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        summary.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        Place(layout, summary, 4);

        rows.Margin = new Thickness(Theme.Margin, 2, Theme.Margin, 12);
        completedHint.HorizontalAlignment = HorizontalAlignment.Center;
        completedHint.Margin = new Thickness(0, 4, 0, 0);
        scroll = new ScrollViewer { Content = rows, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        content.Children.Add(scroll);
        content.Children.Add(emptyHost);
        content.Children.Add(toastHost);
        toastHost.VerticalAlignment = VerticalAlignment.Bottom;
        toastHost.Margin = new Thickness(Theme.Margin, 0, Theme.Margin, 8);
        Place(layout, content, 5);

        var bottom = new Grid { Margin = new Thickness(Theme.Margin - 4, 6, Theme.Margin - 4, 12) };
        bottom.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        bottom.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        bottom.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var tabCard = new Border
        {
            Child = tabs,
            Padding = new Thickness(4),
            CornerRadius = new CornerRadius(22),
            Background = Theme.CardBackground,
            BorderBrush = Theme.CardStroke,
            BorderThickness = new Thickness(1),
        };
        bottom.Children.Add(tabCard);
        speedButton.CornerRadius = new CornerRadius(22);
        speedButton.MinHeight = 46;
        speedButton.Padding = new Thickness(16, 4, 16, 4);
        speedButton.Click += (_, _) => Ui.SpeedLimitMenu(L.T("Toplam hız sınırı"), Settings.GlobalLimit, limit =>
        {
            if (limit is { } l)
            {
                Settings.Set(Settings.GlobalLimitMBKey, (double)(l / 1_048_576));
                Settings.Set(Settings.GlobalLimitEnabledKey, true);
            }
            else Settings.Set(Settings.GlobalLimitEnabledKey, false);
            store.ApplyGlobalSpeedLimit();
            RefreshBottom();
        }, showsGlobalNote: false).ShowAt(speedButton);
        Grid.SetColumn(speedButton, 2);
        bottom.Children.Add(speedButton);
        Place(layout, bottom, 6);

        Content = layout;

        var queue = Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread();
        refreshTimer = queue.CreateTimer();
        refreshTimer.Interval = TimeSpan.FromMilliseconds(60);
        refreshTimer.IsRepeating = false;
        refreshTimer.Tick += (_, _) => { refreshPending = false; if (IsLoaded) Ui.Guard(Refresh); };
        // Banners whose state comes from outside (extension connection, browser running) and the speed.
        slowTimer = queue.CreateTimer();
        slowTimer.Interval = TimeSpan.FromSeconds(5);
        slowTimer.Tick += (_, _) => { if (IsLoaded) Ui.Guard(RefreshBanners); };

        Loaded += (_, _) =>
        {
            store.ItemsChanged += ScheduleRefresh;
            store.PropertyChanged += OnStoreChanged;
            AppUpdater.Shared.Changed += ScheduleRefresh;
            slowTimer.Start();
            Refresh();
            Focus(FocusState.Programmatic);
        };
        Unloaded += (_, _) =>
        {
            store.ItemsChanged -= ScheduleRefresh;
            store.PropertyChanged -= OnStoreChanged;
            AppUpdater.Shared.Changed -= ScheduleRefresh;
            slowTimer.Stop();
            refreshTimer.Stop();
        };
    }

    static void Place(Grid grid, FrameworkElement element, int row)
    {
        Grid.SetRow(element, row);
        grid.Children.Add(element);
    }

    /// <summary>Title row used by every screen; <paramref name="onBack"/> adds a back button.</summary>
    public static Grid Header(string title, Action? onBack, params UIElement[] trailing)
    {
        var header = new Grid { Margin = new Thickness(Theme.Margin, 14, Theme.Margin - 4, 12), ColumnSpacing = 8 };
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        if (onBack != null) header.Children.Add(Ui.IconButton("", L.T("Geri (Esc)"), onBack, 36));
        var label = Ui.Text(title, 20, FontWeights.Bold);
        Grid.SetColumn(label, 1);
        header.Children.Add(label);
        var buttons = Ui.Row(6, trailing);
        Grid.SetColumn(buttons, 2);
        header.Children.Add(buttons);
        return header;
    }

    void OnStoreChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(DownloadStore.DisplaySpeed)) RefreshBottom();
        else ScheduleRefresh();
    }

    void ScheduleRefresh()
    {
        if (refreshPending) return;
        refreshPending = true;
        refreshTimer.Start();
    }

    void Refresh()
    {
        RefreshBanners();
        var tabHasItems = store.Items.Any(i => store.Tab.Includes(i.Status));
        RefreshSearch(tabHasItems);
        RefreshRail(tabHasItems);
        RefreshSummary(tabHasItems);
        RefreshRows(tabHasItems);
        RefreshBottom();
        RefreshToast();
    }

    // MARK: Banners

    void RefreshBanners()
    {
        banners.Children.Clear();
        if (AppUpdater.Shared.AvailableRelease is { } release && release.Version != Settings.Get<string?>(Settings.AppUpdateBannerDismissed, null))
            banners.Children.Add(Banner("", Theme.AccentColor, L.F("Yeni sürüm hazır: %@", release.Version),
                L.T("Güncelle"), () => store.Route = Route.Settings, () => { Settings.Set(Settings.AppUpdateBannerDismissed, release.Version); RefreshBanners(); }));
        if (ExtensionMessage() is { } message)
            banners.Children.Add(Banner("", Theme.Warning, message, L.T("Kur"), () => store.Route = Route.Onboarding,
                () => { Settings.Set(Settings.ExtensionBannerDismissed, DateTimeOffset.Now.ToUnixTimeSeconds()); RefreshBanners(); }));
        var failed = store.Items.Count(i => i.IsFailed);
        if (store.Tab == ListTab.Active && failed > 1)
            banners.Children.Add(Banner("", Theme.Error, L.F("%lld indirme tamamlanamadı", failed), L.T("Tümünü tekrar dene"), store.RetryFailed, null));
        banners.Margin = new Thickness(Theme.Margin, 0, Theme.Margin, banners.Children.Count > 0 ? 10 : 0);
    }

    string? ExtensionMessage()
    {
        var dismissed = Settings.Get(Settings.ExtensionBannerDismissed, 0L);
        if (DateTimeOffset.Now.ToUnixTimeSeconds() - dismissed < 7 * 86_400) return null;
        if (!store.ExtensionEverConnected)
            return Settings.Get(Settings.OnboardingSkipped, false) ? L.T("Tarayıcı eklentisi kurulu değil") : null;
        return ExtensionStatus.Problem(store) switch
        {
            ExtensionStatus.ProblemKind.NotInstalled => L.T("Tarayıcı eklentisi kurulu değil"),
            ExtensionStatus.ProblemKind.NotConnected => L.T("Tarayıcı eklentisi bağlı değil"),
            _ => null,
        };
    }

    static Border Banner(string glyph, Windows.UI.Color color, string text, string action, Action onAction, Action? onClose)
    {
        var grid = new Grid { ColumnSpacing = 10 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.Children.Add(Ui.Icon(glyph, 15, Theme.Brush(color)));
        var label = Ui.Text(text, 12.5, FontWeights.SemiBold);
        Grid.SetColumn(label, 1);
        grid.Children.Add(label);
        var buttons = Ui.Row(4, Ui.Pill(action, onAction, height: 26, fontSize: 12));
        if (onClose != null) buttons.Children.Add(Ui.IconButton("", L.T("Kapat"), onClose, 26));
        Grid.SetColumn(buttons, 2);
        grid.Children.Add(buttons);
        return new Border
        {
            Child = grid,
            Padding = new Thickness(14, 6, 8, 6),
            MinHeight = 42,
            CornerRadius = new CornerRadius(14),
            Background = Theme.Brush(color, 0.14),
            BorderBrush = Theme.Brush(color, 0.35),
            BorderThickness = new Thickness(1),
        };
    }

    // MARK: Search and categories

    void RefreshSearch(bool tabHasItems)
    {
        var visible = tabHasItems && store.Tab == ListTab.Completed;
        searchHost.Visibility = visible ? Visibility.Visible : Visibility.Collapsed;
        if (!visible || search != null) return;
        search = new TextBox
        {
            PlaceholderText = L.T("Tamamlananlarda ara") + "  (Ctrl+F)",
            Text = store.SearchText,
            CornerRadius = new CornerRadius(17),
        };
        search.TextChanged += (_, _) => store.SearchText = search.Text;
        searchHost.Children.Add(search);
    }

    void RefreshRail(bool tabHasItems)
    {
        railCard.Visibility = tabHasItems ? Visibility.Visible : Visibility.Collapsed;
        if (!tabHasItems)
        {
            rail.Children.Clear();
            railSignature = "";
            return;
        }
        var counts = store.Items.Where(i => store.Tab.Includes(i.Status)).GroupBy(i => i.Category).ToDictionary(g => g.Key, g => g.Count());
        var total = counts.Values.Sum();
        var shown = DownloadCategories.All.Where(c => c == DownloadCategory.All || counts.ContainsKey(c) || c == store.Category).ToList();
        // Rebuilt only when something on it changed: the list refreshes on every progress tick, and rebuilding then
        // would get in the way of scrolling or clicking the row.
        var signature = $"{store.Category}|{Theme.AccentHex}|{Theme.IsDark}|" + string.Join(",", shown.Select(c => $"{c}:{(c == DownloadCategory.All ? total : counts.GetValueOrDefault(c))}"));
        if (signature == railSignature) return;
        railSignature = signature;
        var categoryChanged = railCategory != store.Category;
        railCategory = store.Category;
        rail.Children.Clear();
        foreach (var category in shown)
        {
            var count = category == DownloadCategory.All ? total : counts.GetValueOrDefault(category);
            var selected = store.Category == category;
            var foreground = selected ? Theme.Brush(Theme.OnAccent) : Theme.PrimaryText;
            var chip = new Button
            {
                Content = Ui.Row(5, Ui.Text(category.Title(), 12.5, selected ? FontWeights.SemiBold : FontWeights.Medium, foreground),
                    Ui.Text(count.ToString(), 11, FontWeights.Medium, foreground)),
                Height = 30,
                Padding = new Thickness(12, 0, 12, 0),
                CornerRadius = new CornerRadius(15),
                Opacity = count == 0 && !selected ? 0.45 : 1,
            };
            Ui.Paint(chip, selected ? Ui.Look.Accent : Ui.Look.Clear);
            Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(chip, L.F("%@, %lld dosya", category.Title(), count));
            var captured = category;
            chip.Click += (_, _) => store.Category = captured;
            rail.Children.Add(chip);
            // Keep the selected category visible (for example after it was chosen with the keyboard or the list changed).
            if (selected && categoryChanged) chip.Loaded += (_, _) => railScroll.Reveal(chip);
        }
    }

    void RefreshSummary(bool tabHasItems)
    {
        if (summaryMenuOpen) return;
        summary.Children.Clear();
        summary.Visibility = tabHasItems ? Visibility.Visible : Visibility.Collapsed;
        if (!tabHasItems) return;
        var items = store.Items.Where(i => store.Tab.Includes(i.Status)).ToList();
        string text;
        if (store.Tab == ListTab.Active)
        {
            var parts = new List<string>();
            // Literal keys so Windows/scripts/strings.py finds them.
            void Add(int count, Func<int, string> text) { if (count > 0) parts.Add(text(count)); }
            Add(items.Count(i => i.Status.Kind is StatusKind.Downloading or StatusKind.Processing), n => L.F("%lld iniyor", n));
            Add(items.Count(i => i.Status.Kind == StatusKind.Queued), n => L.F("%lld sırada", n));
            Add(items.Count(i => i.Status.Kind == StatusKind.Paused), n => L.F("%lld duraklatıldı", n));
            Add(items.Count(i => i.IsFailed), n => L.F("%lld hata", n));
            text = string.Join(" · ", parts);
        }
        else if (store.SearchText.Trim().Length > 0)
            text = L.F("%lld sonuç · %lld dosya", store.VisibleItems.Count, items.Count);
        else
            text = L.F("%lld dosya · %@", items.Count, ByteFormat.Size(items.Sum(i => i.TotalBytes)));
        summary.Children.Add(Ui.Text(text, 12, FontWeights.Medium, Theme.SecondaryText));

        UIElement action;
        if (store.Tab == ListTab.Active)
        {
            if (!items.Any(i => !i.IsFailed)) return;
            var paused = store.AllActivePaused;
            action = Ui.Pill(paused ? L.T("Tümünü devam ettir") : L.T("Tümünü duraklat"), () => { if (paused) store.ResumeAll(); else store.PauseAll(); },
                paused ? "" : "", 26, 11.5);
        }
        else
        {
            var more = Ui.IconButton("", L.T("Diğer işlemler"), () => { }, 28);
            var menu = new MenuFlyout();
            var open = new MenuFlyoutItem { Text = L.T("İndirme klasörünü aç"), Icon = new FontIcon { Glyph = "", FontFamily = Ui.Icons } };
            open.Click += (_, _) => Shell.OpenFolder(Settings.DownloadFolder);
            menu.Items.Add(open);
            var sort = new MenuFlyoutSubItem { Text = L.F("Sırala: %@", store.CompletedSort.Title()) };
            foreach (var option in Enum.GetValues<CompletedSort>())
            {
                var entry = new ToggleMenuFlyoutItem { Text = option.Title(), IsChecked = store.CompletedSort == option };
                var captured = option;
                entry.Click += (_, _) => { store.CompletedSort = captured; Refresh(); };
                sort.Items.Add(entry);
            }
            menu.Items.Add(sort);
            menu.Items.Add(new MenuFlyoutSeparator());
            var clear = new MenuFlyoutItem { Text = L.T("Listeyi temizle (dosyalar diskte kalır)"), Icon = new FontIcon { Glyph = "", FontFamily = Ui.Icons } };
            clear.Click += (_, _) => store.ClearCompleted();
            menu.Items.Add(clear);
            menu.Opened += (_, _) => summaryMenuOpen = true;
            menu.Closed += (_, _) => { summaryMenuOpen = false; ScheduleRefresh(); };
            more.Flyout = menu;
            action = more;
        }
        Grid.SetColumn((FrameworkElement)action, 1);
        summary.Children.Add(action);
    }

    // MARK: Rows

    void RefreshRows(bool tabHasItems)
    {
        var visible = store.VisibleItems;
        emptyHost.Children.Clear();
        if (!tabHasItems) emptyHost.Children.Add(EmptyList());
        else if (visible.Count == 0)
            emptyHost.Children.Add(store.Tab == ListTab.Completed && store.SearchText.Trim().Length > 0 ? NoResults() : EmptyCategory());
        scroll.Visibility = visible.Count > 0 ? Visibility.Visible : Visibility.Collapsed;

        foreach (var gone in views.Keys.Where(id => !visible.Any(i => i.Id == id)).ToList()) views.Remove(gone);
        var wanted = visible.Select(item => (UIElement)(views.TryGetValue(item.Id, out var view) ? view : views[item.Id] = new RowView(store, item))).ToList();
        if (store.Tab == ListTab.Completed && wanted.Count > 0) wanted.Add(completedHint);
        // Rebuilt only when the order changes: taking a row out of the tree closes its open menu.
        if (!rows.Children.SequenceEqual(wanted))
        {
            rows.Children.Clear();
            foreach (var view in wanted) rows.Children.Add(view);
        }
        foreach (var (id, view) in views) view.Selected = store.Selection == id;
    }

    UIElement EmptyList()
    {
        var active = store.Tab == ListTab.Active;
        var circle = new Border
        {
            Width = 92,
            Height = 92,
            CornerRadius = new CornerRadius(46),
            Background = Theme.CardBackground,
            BorderBrush = Theme.CardStroke,
            BorderThickness = new Thickness(1),
            Child = Ui.Icon(active ? "" : "", 30),
            HorizontalAlignment = HorizontalAlignment.Center,
            Margin = new Thickness(0, 0, 0, 18),
        };
        var column = Ui.Column(8, circle, Centered(Ui.Text(active ? L.T("Devam eden indirme yok") : L.T("Henüz tamamlanan indirme yok"), 17, FontWeights.SemiBold)));
        if (active)
        {
            column.Children.Add(Centered(Ui.Secondary(L.T("Bir link ekle ya da Chrome'da bir dosya indir, burada görünür."), 13, wrap: true)));
            var add = Ui.AccentButton(L.T("Link ekle"), "", () => store.Route = Route.AddLink, 38);
            add.HorizontalAlignment = HorizontalAlignment.Center;
            add.Margin = new Thickness(0, 12, 0, 4);
            column.Children.Add(add);
            column.Children.Add(Centered(Ui.Secondary(L.T("ya da linki kopyalayıp Ctrl+V yap"), 11.5)));
        }
        else
        {
            var running = store.Items.Count(i => ListTab.Active.Includes(i.Status));
            column.Children.Add(Centered(Ui.Secondary(running > 0 ? L.F("%lld indirme devam ediyor.", running) : L.T("Biten indirmeler burada görünür."), 13)));
            if (running > 0)
            {
                var go = Ui.Pill(L.T("Devam edenlere git"), () => store.Tab = ListTab.Active, height: 34, fontSize: 13);
                go.HorizontalAlignment = HorizontalAlignment.Center;
                column.Children.Add(go);
            }
        }
        column.VerticalAlignment = VerticalAlignment.Center;
        column.MaxWidth = 300;
        return column;
    }

    UIElement EmptyCategory()
    {
        var icon = Ui.CategoryIcon(store.Category, 52);
        icon.Opacity = 0.6;
        icon.HorizontalAlignment = HorizontalAlignment.Center;
        var column = Ui.Column(10, icon, Centered(Ui.Text(L.T("Bu kategoride dosya kalmadı"), 15, FontWeights.SemiBold)),
            Centered(Ui.Pill(L.T("Tümünü göster"), () => store.Category = DownloadCategory.All)));
        column.VerticalAlignment = VerticalAlignment.Center;
        return column;
    }

    UIElement NoResults()
    {
        var column = Ui.Column(10, Centered(Ui.Icon("", 26)),
            Centered(Ui.Text(L.F("‘%@’ için sonuç yok", store.SearchText.Trim()), 15, FontWeights.SemiBold)),
            Centered(Ui.Pill(L.T("Aramayı temizle"), () => { store.SearchText = ""; if (search != null) search.Text = ""; })));
        column.VerticalAlignment = VerticalAlignment.Center;
        return column;
    }

    static FrameworkElement Centered(FrameworkElement element)
    {
        element.HorizontalAlignment = HorizontalAlignment.Center;
        if (element is TextBlock text) text.TextAlignment = TextAlignment.Center;
        return element;
    }

    // MARK: Bottom bar and undo toast

    void RefreshBottom()
    {
        tabs.Children.Clear();
        foreach (var tab in new[] { ListTab.Active, ListTab.Completed })
        {
            var selected = store.Tab == tab;
            var count = store.Items.Count(i => tab.Includes(i.Status));
            var foreground = selected ? Theme.Brush(Theme.OnAccent) : Theme.PrimaryText;
            var label = Ui.Row(6, Ui.Icon(tab == ListTab.Active ? "" : "", 11, foreground), Ui.Text(tab.Title(), 13, FontWeights.SemiBold, foreground));
            if (count > 0)
            {
                label.Children.Add(new Border
                {
                    CornerRadius = new CornerRadius(9),
                    Padding = new Thickness(6, 0, 6, 1),
                    Background = selected ? Theme.Brush(Microsoft.UI.Colors.White, 0.25) : Theme.SubtleFill,
                    Child = Ui.Text(count.ToString(), 11, FontWeights.SemiBold, foreground),
                });
            }
            var button = new Button
            {
                Content = label,
                Height = 38,
                Padding = new Thickness(12, 0, 12, 0),
                CornerRadius = new CornerRadius(19),
            };
            Ui.Paint(button, selected ? Ui.Look.Accent : Ui.Look.Clear);
            ToolTipService.SetToolTip(button, tab == ListTab.Active ? L.T("Devam Eden (Ctrl+1)") : L.T("Tamamlanan (Ctrl+2)"));
            var captured = tab;
            button.Click += (_, _) => store.Tab = captured;
            tabs.Children.Add(button);
        }

        var speed = Ui.Text(ByteFormat.Speed(store.DisplaySpeed), 13, FontWeights.SemiBold);
        speed.Opacity = store.DisplaySpeed > 0 ? 1 : 0.55;
        var texts = Ui.Column(0, Ui.Row(5, Ui.Icon("", 11), speed));
        if (Settings.GlobalLimitEnabled)
            texts.Children.Add(Ui.Text(L.F("Sınır %lld MB/sn", (long)Settings.GlobalLimitMB), 10.5, FontWeights.Medium, Theme.SecondaryText));
        speedButton.Content = Ui.Row(8, texts, Ui.Icon("", 13, Settings.GlobalLimitEnabled ? Theme.AccentBrush() : Theme.SecondaryText));
        ToolTipService.SetToolTip(speedButton, Settings.GlobalLimitEnabled
            ? L.F("Toplam indirme hızı · sınır %lld MB/sn — değiştirmek için tıklayın", (long)Settings.GlobalLimitMB)
            : L.T("Toplam indirme hızı — hız sınırı koymak için tıklayın"));
    }

    void RefreshToast()
    {
        toastHost.Children.Clear();
        if (store.Pending is not { } pending) return;
        var grid = new Grid { ColumnSpacing = 8 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.Children.Add(Ui.Icon("", 12, Theme.SecondaryText));
        var text = Ui.Text(L.F("%@ silindi", pending.Item.FileName), 12.5);
        Grid.SetColumn(text, 1);
        grid.Children.Add(text);
        var undo = Ui.Pill(L.T("Geri al"), store.UndoDelete, "", 28, 12);
        ToolTipService.SetToolTip(undo, L.T("Geri al (Ctrl+Z)"));
        Grid.SetColumn(undo, 2);
        grid.Children.Add(undo);
        toastHost.Children.Add(new Border
        {
            Child = grid,
            Padding = new Thickness(14, 5, 5, 5),
            CornerRadius = new CornerRadius(20),
            Background = Theme.ToastBackground,
            BorderBrush = Theme.CardStroke,
            BorderThickness = new Thickness(1),
            Shadow = new Microsoft.UI.Xaml.Media.ThemeShadow(),
            Translation = new System.Numerics.Vector3(0, 0, 16),
        });
    }

    // MARK: Keyboard

    /// <summary>Ctrl+V link from the clipboard, Ctrl+1/2 tabs, Ctrl+F search, Ctrl+Z undo, ↑/↓ selection, Enter open, Delete remove.</summary>
    public bool HandleKey(VirtualKey key, bool ctrl)
    {
        var typing = search?.FocusState is FocusState.Keyboard or FocusState.Pointer or FocusState.Programmatic;
        var selected = store.VisibleItems.FirstOrDefault(i => i.Id == store.Selection);
        if (ctrl)
        {
            switch (key)
            {
                case VirtualKey.N: store.Route = Route.AddLink; return true;
                case (VirtualKey)188: store.Route = Route.Settings; return true; // Ctrl+,
                case VirtualKey.V when !typing:
                    // After this key press is over: the new screen's text box must not receive the same Ctrl+V
                    // (the link would be pasted twice; Link ekle fills itself from the clipboard).
                    if (Shell.ClipboardText() is { } clip && DownloadStore.ParseLinks(clip).Count > 0)
                        DispatcherQueue.TryEnqueue(Microsoft.UI.Dispatching.DispatcherQueuePriority.Low, () => store.Route = Route.AddLink);
                    return true;
                case VirtualKey.Number1: store.Tab = ListTab.Active; return true;
                case VirtualKey.Number2: store.Tab = ListTab.Completed; return true;
                case VirtualKey.F:
                    store.Tab = ListTab.Completed;
                    Refresh();
                    search?.Focus(FocusState.Keyboard);
                    return true;
                case VirtualKey.Z when !typing: store.UndoDelete(); return true;
                case VirtualKey.R when selected != null: DownloadStore.Reveal(selected); return true;
                case VirtualKey.C when selected != null && !typing: Shell.Copy(selected.Url); return true;
                case VirtualKey.Delete when selected != null: store.Delete(selected); return true;
            }
            return false;
        }
        if (typing) return false;
        switch (key)
        {
            case VirtualKey.Up: case VirtualKey.Down:
            {
                var visible = store.VisibleItems;
                if (visible.Count == 0) return false;
                var index = visible.FindIndex(i => i.Id == store.Selection);
                var next = index < 0 ? (key == VirtualKey.Down ? 0 : visible.Count - 1) : Math.Clamp(index + (key == VirtualKey.Down ? 1 : -1), 0, visible.Count - 1);
                store.Selection = visible[next].Id;
                Refresh();
                views.GetValueOrDefault(visible[next].Id)?.StartBringIntoView();
                return true;
            }
            case VirtualKey.Space when selected != null && !selected.IsCompleted:
                store.TogglePause(selected);
                return true;
            case VirtualKey.Enter when selected is { IsCompleted: true }:
                if (!Shell.Open(selected.Destination)) Shell.Beep();
                return true;
            case VirtualKey.Delete when selected is { IsCompleted: true }:
                store.RemoveFromList(selected);
                return true;
        }
        return false;
    }
}
