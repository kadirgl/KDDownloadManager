using DispatcherQueueTimer = Microsoft.UI.Dispatching.DispatcherQueueTimer;
using KDDownloadManager.Store;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace KDDownloadManager.Views;

/// <summary>Settings (macOS: SettingsView, BrowserSettings, ToolSettings). Each section is a card.</summary>
public sealed class SettingsPage : UserControl
{
    readonly DownloadStore store;
    readonly ScrollViewer scroll = new();
    readonly DispatcherQueueTimer pendingLimit;
    readonly DispatcherQueueTimer statusTimer;
    string? launchAtLoginError;
    string? torrentError;
    Border? browserCard;

    public SettingsPage(DownloadStore store)
    {
        this.store = store;
        var layout = new Grid();
        layout.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        layout.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        layout.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        layout.Children.Add(ListPage.Header(L.T("Ayarlar"), () => store.Route = Route.List));
        Grid.SetRow(scroll, 1);
        layout.Children.Add(scroll);

        var footer = new Grid { Margin = new Thickness(Theme.Margin + 2, 8, Theme.Margin, 14) };
        footer.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        footer.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        footer.Children.Add(Ui.Secondary($"KD Download Manager {AppUpdater.CurrentVersion} · Windows {AppUpdater.Architecture}", 12));
        var quit = Ui.Pill(L.T("Çıkış"), App.Quit, "", 38, 13);
        Grid.SetColumn(quit, 1);
        footer.Children.Add(quit);
        Grid.SetRow(footer, 2);
        layout.Children.Add(footer);
        Content = layout;

        var queue = Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread();
        pendingLimit = queue.CreateTimer();
        pendingLimit.Interval = TimeSpan.FromMilliseconds(600);
        pendingLimit.IsRepeating = false;
        pendingLimit.Tick += (_, _) => Ui.Guard(store.ApplyGlobalSpeedLimit);
        statusTimer = queue.CreateTimer();
        statusTimer.Interval = TimeSpan.FromSeconds(5);
        statusTimer.Tick += (_, _) => { if (IsLoaded && browserCard != null) Ui.Guard(() => browserCard.Child = BrowserRows()); };

        void Changed() => Render();
        Loaded += (_, _) =>
        {
            AppUpdater.Shared.Changed += Changed;
            YtDlpUpdater.Shared.Changed += Changed;
            statusTimer.Start();
            Render();
        };
        Unloaded += (_, _) =>
        {
            AppUpdater.Shared.Changed -= Changed;
            YtDlpUpdater.Shared.Changed -= Changed;
            statusTimer.Stop();
        };
    }

    bool UpdateAvailable => AppUpdater.Shared.State is AppUpdater.UpdateState.Available or AppUpdater.UpdateState.Downloading or AppUpdater.UpdateState.Installing;

    void Render()
    {
        var offset = scroll.VerticalOffset;
        var column = Ui.Column(18);
        column.Margin = new Thickness(Theme.Margin, 0, Theme.Margin, 16);
        if (UpdateAvailable) column.Children.Add(AppUpdateSection());
        column.Children.Add(Section(L.T("İndirme klasörü"), FolderRow()));
        column.Children.Add(Section(L.T("Görünüm"), AppearanceRows()));
        column.Children.Add(Section(L.T("Hız"), SpeedRows()));
        browserCard = Ui.Card(BrowserRows());
        column.Children.Add(Ui.Column(8, Ui.SectionLabel(L.T("Tarayıcı eklentisi")), browserCard));
        column.Children.Add(Section(L.T("Torrent"), TorrentRows()));
        if (!UpdateAvailable) column.Children.Add(AppUpdateSection());
        column.Children.Add(Section(L.T("Video indirici (yt-dlp)"), YtDlpRows()));
        column.Children.Add(Section(L.T("Bildirimler"), Ui.Column(12,
            Ui.SettingRow(L.T("İndirme eklendiğinde"), Ui.Toggle(Settings.Enabled(Settings.NotifyOnAdd), on => Settings.Set(Settings.NotifyOnAdd, on))),
            Ui.Divider(),
            Ui.SettingRow(L.T("İndirme tamamlandığında"), Ui.Toggle(Settings.Enabled(Settings.NotifyOnFinish), on => Settings.Set(Settings.NotifyOnFinish, on))),
            Ui.Divider(),
            Ui.SettingRow(L.T("Hata olduğunda"), Ui.Toggle(Settings.Enabled(Settings.NotifyOnFail), on => Settings.Set(Settings.NotifyOnFail, on))))));
        column.Children.Add(Section(L.T("Bildirim alanı"), Ui.SettingRow(L.T("Toplam hızı göster"),
            Ui.Toggle(Settings.Get(Settings.ShowSpeedInTray, true), on => Settings.Set(Settings.ShowSpeedInTray, on)),
            L.T("İkonun üzerine gelince araç ipucunda görünür."))));
        var login = Ui.Column(8, Ui.SettingRow(L.T("Oturum açınca başlat"), Ui.Toggle(LaunchAtLogin.IsEnabled, on =>
        {
            try { LaunchAtLogin.Set(on); launchAtLoginError = null; }
            catch (Exception e) { launchAtLoginError = L.F("Ayarlanamadı: %@", e.Message); }
            Render();
        })));
        login.Children.Add(launchAtLoginError != null
            ? Ui.Text(launchAtLoginError, 11.5, brush: Theme.Brush(Theme.Error), wrap: true)
            : Ui.Secondary(L.T("Chrome eklentisinin çalışması için uygulamanın açık olması gerekir."), 11.5, wrap: true));
        column.Children.Add(Section(L.T("Başlangıç"), login));
        scroll.Content = column;
        scroll.UpdateLayout();
        scroll.ChangeView(null, offset, null, true);
    }

    static UIElement Section(string title, UIElement content) => Ui.Column(8, Ui.SectionLabel(title), Ui.Card(content));

    UIElement FolderRow()
    {
        var folder = Settings.DownloadFolder;
        var grid = new Grid { ColumnSpacing = 10 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.Children.Add(Ui.Icon("", 15, Theme.AccentBrush()));
        var path = Ui.Text(Shell.Abbreviated(folder), 13);
        ToolTipService.SetToolTip(path, folder);
        Grid.SetColumn(path, 1);
        grid.Children.Add(path);
        var change = Ui.Pill(L.T("Değiştir"), async () =>
        {
            if (await Pickers.Folder(folder) is { } chosen) { Settings.DownloadFolder = chosen; Render(); }
        });
        Grid.SetColumn(change, 2);
        grid.Children.Add(change);
        return grid;
    }

    UIElement AppearanceRows()
    {
        var language = L.Stored;
        var rows = Ui.Column(12,
            Ui.SettingRow(L.T("Tema"), Ui.Segmented(Enum.GetValues<AppThemeChoice>().Select(t => (t, t.Title())), Theme.ThemeChoice, t => Theme.ThemeChoice = t)),
            Ui.Divider(),
            Ui.SettingRow(L.T("Vurgu rengi"), AccentPicker()),
            Ui.Divider(),
            Ui.SettingRow(L.T("Dil"), Ui.Segmented(Enum.GetValues<AppLanguage>().Select(l => (l, l.Title())), language, l => { L.Store(l); Render(); })));
        if (L.Stored != L.LaunchChoice)
        {
            var grid = new Grid { ColumnSpacing = 10 };
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            grid.Children.Add(Ui.Secondary(L.T("Dil, uygulama yeniden açılınca değişir."), 11.5, wrap: true));
            var restart = Ui.Pill(L.T("Yeniden başlat"), App.Relaunch, height: 26, fontSize: 12);
            Grid.SetColumn(restart, 1);
            grid.Children.Add(restart);
            rows.Children.Add(grid);
        }
        return rows;
    }

    UIElement AccentPicker()
    {
        var row = Ui.Row(5);
        foreach (var choice in Enum.GetValues<AccentChoice>())
        {
            var selected = Theme.Accent == choice;
            var swatch = new Border
            {
                Width = 20,
                Height = 20,
                CornerRadius = new CornerRadius(10),
                Background = choice == AccentChoice.Custom
                    ? new Microsoft.UI.Xaml.Media.LinearGradientBrush
                    {
                        StartPoint = new Windows.Foundation.Point(0, 0),
                        EndPoint = new Windows.Foundation.Point(1, 1),
                        GradientStops =
                        {
                            new() { Color = Models.DownloadCategories.Hex(0xFF3B30), Offset = 0 },
                            new() { Color = Models.DownloadCategories.Hex(0xFFCC00), Offset = 0.33 },
                            new() { Color = Models.DownloadCategories.Hex(0x30B350), Offset = 0.66 },
                            new() { Color = Models.DownloadCategories.Hex(0x0A84FF), Offset = 1 },
                        },
                    }
                    : Theme.Brush(Theme.ColorOf(choice)),
            };
            if (choice == AccentChoice.System)
                swatch.Child = new Border { Width = 6, Height = 6, CornerRadius = new CornerRadius(3), Background = Theme.Brush(Microsoft.UI.Colors.White, 0.85) };
            var ring = new Border
            {
                Width = 26,
                Height = 26,
                CornerRadius = new CornerRadius(13),
                BorderThickness = new Thickness(2),
                BorderBrush = selected ? Theme.PrimaryText : null,
                Child = swatch,
            };
            var button = new Button { Content = ring, Padding = new Thickness(0), Background = null, BorderThickness = new Thickness(0), MinWidth = 0 };
            ToolTipService.SetToolTip(button, choice.Title());
            var captured = choice;
            button.Click += (_, _) =>
            {
                if (captured == AccentChoice.Custom) ShowColorPicker(button);
                else Theme.Accent = captured;
            };
            row.Children.Add(button);
        }
        return row;
    }

    static void ShowColorPicker(FrameworkElement anchor)
    {
        var picker = new ColorPicker
        {
            Color = Theme.ColorOf(AccentChoice.Custom),
            IsAlphaEnabled = false,
            IsMoreButtonVisible = false,
            IsColorSliderVisible = true,
            IsHexInputVisible = true,
        };
        var apply = Ui.Pill(L.T("Uygula"), () => { });
        var flyout = new Flyout { Content = Ui.Column(8, picker, apply) };
        apply.Click += (_, _) =>
        {
            Settings.Set(Settings.AccentCustomColor, Theme.Hex(picker.Color));
            Theme.Accent = AccentChoice.Custom;
            flyout.Hide();
        };
        flyout.ShowAt(anchor);
    }

    UIElement SpeedRows()
    {
        var rows = Ui.Column(12, Ui.SettingRow(L.T("Genel hız sınırı"), Ui.Toggle(Settings.GlobalLimitEnabled, on =>
        {
            Settings.Set(Settings.GlobalLimitEnabledKey, on);
            store.ApplyGlobalSpeedLimit();
            Render();
        })));
        if (Settings.GlobalLimitEnabled)
        {
            rows.Children.Add(Ui.SettingRow(L.T("Sınır"), Ui.Stepper((int)Settings.GlobalLimitMB, 1, 100, v => L.F("%lld MB/sn", v), v =>
            {
                Settings.Set(Settings.GlobalLimitMBKey, (double)v);
                pendingLimit.Stop();
                pendingLimit.Start();
            }), L.T("Tüm indirmelerin toplamı bunu geçmez; indirmeye özel daha yüksek sınırlar da buna göre kısıtlanır.")));
        }
        rows.Children.Add(Ui.Divider());
        rows.Children.Add(Ui.SettingRow(L.T("Aynı anda en fazla"), Ui.Stepper(Settings.MaxConcurrent, 1, 10, v => L.F("%lld indirme", v), v =>
        {
            Settings.Set(Settings.MaxConcurrentKey, v);
            store.ApplyMaxConcurrent();
        })));
        rows.Children.Add(Ui.Divider());
        rows.Children.Add(Ui.SettingRow(L.T("Bağlantı sayısı"), Ui.Stepper(Settings.ConnectionCount, 1, 16, v => v.ToString(), v => Settings.Set(Settings.ConnectionsKey, v)),
            L.T("Parçalı indirme: her dosya ve video bu kadar paralel bağlantıyla iner. Sunucu izin vermezse o indirme tek bağlantıya düşer.")));
        return rows;
    }

    UIElement BrowserRows()
    {
        var rows = Ui.Column(12, Ui.Secondary(L.T("Eklenti tarayıcıdaki indirmeleri, magnet linklerini ve videoları (kalite seçerek) uygulamaya gönderir."), 11.5, wrap: true));
        var browsers = BrowserExtension.InstalledBrowsers;
        if (browsers.Count == 0)
            rows.Children.Add(Ui.Secondary(L.T("Desteklenen bir tarayıcı bulunamadı (Chrome, Edge, Brave, Vivaldi, Opera)."), 12, wrap: true));
        foreach (var browser in browsers)
        {
            var (kind, seen) = ExtensionStatus.Of(store, browser);
            var ago = seen is { } date ? L.F(" · son bağlantı %@", L.Relative(date)) : "";
            var (text, color) = kind switch
            {
                ExtensionStatus.Kind.Connected => (L.T("Bağlı"), Theme.Success),
                ExtensionStatus.Kind.NotInstalled => (L.T("Kurulu değil"), Theme.Error),
                ExtensionStatus.Kind.Disabled => (L.T("Eklenti kapalı (devre dışı)"), Theme.Error),
                ExtensionStatus.Kind.BrowserClosed => (L.T("Tarayıcı kapalı") + ago, Microsoft.UI.Colors.Gray),
                _ => (L.T("Bağlı değil") + ago, Theme.Error),
            };
            var grid = new Grid { ColumnSpacing = 10 };
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            grid.Children.Add(Ui.Column(2, Ui.Text(browser.Name, 13.5, FontWeights.SemiBold),
                Ui.Row(5, new Border { Width = 7, Height = 7, CornerRadius = new CornerRadius(4), Background = Theme.Brush(color) }, Ui.Secondary(text, 12))));
            if (kind != ExtensionStatus.Kind.Connected)
            {
                var captured = browser;
                var install = Ui.Pill(L.T("Kur"), () =>
                {
                    store.OnboardingBrowser = captured.Name;
                    store.Route = Route.Onboarding;
                }, height: 28, fontSize: 12);
                Grid.SetColumn(install, 1);
                grid.Children.Add(install);
            }
            rows.Children.Add(grid);
        }
        return rows;
    }

    UIElement TorrentRows()
    {
        var registered = TorrentHandler.IsRegistered;
        var current = TorrentHandler.CurrentHandler();
        var grid = new Grid { ColumnSpacing = 10 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.Children.Add(Ui.Column(2, Ui.Text(L.T("Magnet linkleri ve .torrent dosyaları"), 13.5, FontWeights.SemiBold),
            Ui.Secondary(registered && current == "KD Download Manager" ? L.T("KD Download Manager ile açılıyor")
                : current != null ? L.F("Şu an %@ ile açılıyor", current) : L.T("Şu an bunları açan bir uygulama yok"), 12, wrap: true)));
        if (!(registered && current == "KD Download Manager"))
        {
            var button = Ui.Pill(L.T("Bununla aç"), () =>
            {
                try
                {
                    TorrentHandler.Register();
                    torrentError = null;
                    // Windows asks the user to confirm a new default for links in Settings.
                    if (TorrentHandler.CurrentHandler() != "KD Download Manager") Shell.OpenUrl("ms-settings:defaultapps");
                }
                catch (Exception e) { torrentError = L.F("Ayarlanamadı: %@", e.Message); }
                Render();
            }, height: 28, fontSize: 12);
            Grid.SetColumn(button, 1);
            grid.Children.Add(button);
        }
        var rows = Ui.Column(10, grid);
        if (torrentError != null) rows.Children.Add(Ui.Text(torrentError, 11.5, brush: Theme.Brush(Theme.Error), wrap: true));
        rows.Children.Add(Ui.Secondary(L.T("Diskteki .torrent dosyalarını panele sürükleyip bırakabilir ya da Link ekle ekranından seçebilirsiniz."), 11.5, wrap: true));
        return rows;
    }

    UIElement AppUpdateSection()
    {
        var updater = AppUpdater.Shared;
        var state = updater.State;
        string status = state switch
        {
            AppUpdater.UpdateState.Checking => L.T("Denetleniyor…"),
            AppUpdater.UpdateState.UpToDate => L.T("Güncel"),
            AppUpdater.UpdateState.Available a => L.F("Yeni sürüm: %@", a.Release.Version),
            AppUpdater.UpdateState.Downloading d => L.F("%@ indiriliyor… %@", d.Release.Version, L.Percent(d.Progress)),
            AppUpdater.UpdateState.Installing i => L.F("%@ kuruluyor…", i.Release.Version),
            AppUpdater.UpdateState.Failed f => f.Message,
            _ => !AppUpdater.IsAvailable ? L.T("Paketli uygulamada kullanılabilir")
                : updater.LastCheck is { } last ? L.F("Son denetim %@", L.Relative(last)) : L.T("Henüz denetlenmedi"),
        };
        var grid = new Grid { ColumnSpacing = 10 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.Children.Add(Ui.Column(2, Ui.Text($"KD Download Manager {AppUpdater.CurrentVersion}", 13.5, FontWeights.SemiBold),
            Ui.Text(status, 12, brush: state is AppUpdater.UpdateState.Failed ? Theme.Brush(Theme.Error) : Theme.SecondaryText, wrap: true)));
        UIElement? action = state switch
        {
            AppUpdater.UpdateState.Available => Ui.AccentButton(L.T("Güncelle"), "", updater.Install, 30),
            AppUpdater.UpdateState.Downloading => Ui.Pill(L.T("İptal"), updater.Cancel, height: 28, fontSize: 12),
            AppUpdater.UpdateState.Checking or AppUpdater.UpdateState.Installing => Ui.Spinner(18),
            _ when AppUpdater.IsAvailable => Ui.Pill(L.T("Şimdi denetle"), async () => await updater.Check(), height: 28, fontSize: 12),
            _ => null,
        };
        if (action is FrameworkElement element)
        {
            if (element is Button b) b.HorizontalAlignment = HorizontalAlignment.Right;
            Grid.SetColumn(element, 1);
            grid.Children.Add(element);
        }
        var rows = Ui.Column(12, grid);
        if (state is AppUpdater.UpdateState.Downloading d2)
            rows.Children.Add(new Bar { Value = d2.Progress, Fill = Theme.AccentBrush() });
        if (state is AppUpdater.UpdateState.Available av)
        {
            if (av.Release.Notes.Length > 0) rows.Children.Add(Ui.Secondary(av.Release.Notes.Length > 600 ? av.Release.Notes[..600] + "…" : av.Release.Notes, 11.5, wrap: true));
            rows.Children.Add(Ui.Secondary(L.T("Süren indirmeler uygulama yeniden açılınca kaldıkları yerden devam eder."), 11.5, wrap: true));
        }
        rows.Children.Add(Ui.Divider());
        rows.Children.Add(Ui.SettingRow(L.T("Günde bir denetle"), Ui.Toggle(Settings.Get(Settings.AppAutoUpdateCheck, true), on => Settings.Set(Settings.AppAutoUpdateCheck, on))));
        rows.Children.Add(Ui.Secondary(L.T("Yeni sürümler GitHub'dan indirilir ve kurulmadan önce imzası doğrulanır. Tarayıcı eklentisi de uygulamayla birlikte güncellenir."), 11.5, wrap: true));
        return Section(L.T("Uygulama güncellemesi"), rows);
    }

    UIElement YtDlpRows()
    {
        var updater = YtDlpUpdater.Shared;
        var status = updater.State switch
        {
            YtDlpUpdater.UpdateState.Checking => L.T("Denetleniyor…"),
            YtDlpUpdater.UpdateState.Downloading d => L.F("%@ indiriliyor…", d.Version),
            YtDlpUpdater.UpdateState.UpToDate => L.T("Güncel"),
            YtDlpUpdater.UpdateState.Updated u => L.F("%@ sürümüne güncellendi", u.Version),
            YtDlpUpdater.UpdateState.Failed f => f.Message,
            _ => (updater.IsUpdated ? L.T("Güncellenmiş") : L.T("Uygulamayla gelen"))
                 + (updater.LastCheck is { } last ? L.F(" · son denetim %@", L.Relative(last)) : L.T(" · henüz denetlenmedi")),
        };
        var grid = new Grid { ColumnSpacing = 10 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.Children.Add(Ui.Column(2, Ui.Text("yt-dlp " + updater.CurrentVersion, 13.5, FontWeights.SemiBold), Ui.Secondary(status, 12, wrap: true)));
        UIElement action = updater.State is YtDlpUpdater.UpdateState.Checking or YtDlpUpdater.UpdateState.Downloading
            ? Ui.Spinner(18)
            : Ui.Pill(L.T("Şimdi denetle"), async () => await updater.Check(), height: 28, fontSize: 12);
        Grid.SetColumn((FrameworkElement)action, 1);
        grid.Children.Add(action);
        return Ui.Column(12, grid, Ui.Divider(),
            Ui.SettingRow(L.T("Otomatik güncelle"), Ui.Toggle(Settings.Get(Settings.YtDlpAutoUpdate, true), on => Settings.Set(Settings.YtDlpAutoUpdate, on))),
            Ui.Secondary(L.T("YouTube sık değiştiği için yt-dlp güncel tutulmazsa video indirmeleri bozulabilir. Güncellemeler yt-dlp'nin resmi GitHub sürümünden alınır ve doğrulanır."), 11.5, wrap: true));
    }
}
