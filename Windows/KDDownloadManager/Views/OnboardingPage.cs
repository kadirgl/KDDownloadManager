using DispatcherQueueTimer = Microsoft.UI.Dispatching.DispatcherQueueTimer;
using KDDownloadManager.Store;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;

namespace KDDownloadManager.Views;

/// <summary>
/// First launch: installing the browser extension (macOS: OnboardingView). When the extension connects for the
/// first time a short confirmation is shown and the list opens; "Şimdilik geç" stops it from opening by itself.
/// </summary>
public sealed class OnboardingPage : UserControl
{
    readonly DownloadStore store;
    readonly StackPanel waiting = new() { Orientation = Orientation.Horizontal, Spacing = 8, HorizontalAlignment = HorizontalAlignment.Center };
    readonly TextBlock error = Ui.Text("", 11.5, brush: Theme.Brush(Theme.Error), wrap: true);
    readonly DispatcherQueueTimer timer;
    readonly DateTimeOffset? initialSignal;
    bool connected;

    BrowserExtension.Browser? Browser
    {
        get
        {
            var browsers = BrowserExtension.InstalledBrowsers;
            return browsers.FirstOrDefault(b => b.Name == store.OnboardingBrowser)
                ?? browsers.FirstOrDefault(b => b.Name == "Google Chrome")
                ?? browsers.FirstOrDefault();
        }
    }

    string ShortName => Browser?.Name.Replace("Google ", "") ?? "Chrome";

    public OnboardingPage(DownloadStore store)
    {
        this.store = store;
        var browser = Browser;
        initialSignal = browser != null ? ExtensionStatus.LastSignal(store, browser) : null;

        var badge = new Image
        {
            Source = new BitmapImage(new Uri(Path.Combine(AppFolders.AppDir, "Assets", "app256.png"))),
            Width = 76,
            Height = 76,
            HorizontalAlignment = HorizontalAlignment.Center,
            Margin = new Thickness(0, 18, 0, 14),
        };
        var title = Ui.Text(L.F("%@ eklentisini kur", ShortName), 20, FontWeights.Bold);
        title.HorizontalAlignment = HorizontalAlignment.Center;
        var intro = Ui.Secondary(L.F("İndirmeleri, videoları ve magnet linklerini %@'dan tek tıkla uygulamaya gönderir. Eklenti henüz Chrome Web Mağazası'nda olmadığı için geliştirici modundan yüklenir, 1 dakika sürer.", ShortName), 12.5, wrap: true);
        intro.TextAlignment = TextAlignment.Center;
        var column = Ui.Column(12, badge, title, intro);
        column.Margin = new Thickness(Theme.Margin, 0, Theme.Margin, 16);
        if (browser != null) column.Children.Add(Steps(browser));
        else column.Children.Add(Ui.Card(Ui.Secondary(L.T("Desteklenen bir tarayıcı bulunamadı (Chrome, Edge, Brave, Vivaldi, Opera)."), 12, wrap: true)));
        column.Children.Add(Ui.Row(6, Ui.Icon("", 12, Theme.SecondaryText),
            Ui.Secondary(L.T("Kısayol: Gezgin'deki klasörü sürükleyip eklentiler sayfasına bırakabilirsin."), 11.5, wrap: true)));
        column.Children.Add(error);
        column.Children.Add(waiting);
        RenderWaiting();

        var layout = new Grid();
        layout.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        layout.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        layout.Children.Add(new ScrollViewer { Content = column });
        var start = Ui.AccentButton(L.T("Kurulumu başlat"), "", BeginInstall, 46);
        start.IsEnabled = browser != null;
        var skip = new HyperlinkButton { Content = L.T("Şimdilik geç"), HorizontalAlignment = HorizontalAlignment.Center };
        skip.Click += (_, _) => store.SkipOnboarding();
        var footer = Ui.Column(4, start, skip);
        footer.Margin = new Thickness(Theme.Margin, 6, Theme.Margin, 12);
        Grid.SetRow(footer, 1);
        layout.Children.Add(footer);
        Content = layout;

        timer = Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread().CreateTimer();
        timer.Interval = TimeSpan.FromSeconds(1);
        timer.Tick += (_, _) => { if (IsLoaded) Ui.Guard(CheckConnection); };
        Loaded += (_, _) => timer.Start();
        Unloaded += (_, _) => timer.Stop();
    }

    UIElement Steps(BrowserExtension.Browser browser)
    {
        var copy = Ui.Pill(L.T("Kopyala"), () => { }, "", 28, 12);
        copy.Click += (_, _) =>
        {
            Shell.Copy(browser.ExtensionsPage);
            copy.Content = Ui.Row(6, Ui.Icon("", 12), Ui.Text(L.T("Kopyalandı"), 12, FontWeights.SemiBold));
        };
        ToolTipService.SetToolTip(copy, L.T("Tarayıcılar chrome:// adreslerinin dışarıdan açılmasını engelleyebiliyor; adres çubuğuna yapıştırın."));
        var toggle = new Border
        {
            Width = 36,
            Height = 20,
            CornerRadius = new CornerRadius(10),
            Background = Theme.AccentBrush(),
            Child = new Border { Width = 14, Height = 14, CornerRadius = new CornerRadius(7), Background = Theme.Brush(Microsoft.UI.Colors.White), HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(3) },
        };
        var reveal = Ui.Pill(L.T("Gezgin'de göster"), () =>
        {
            if (!BrowserExtension.RefreshFolder()) { error.Text = L.T("Eklenti dosyaları hazırlanamadı."); return; }
            Shell.Reveal(BrowserExtension.Folder, BrowserExtension.Folder);
        }, height: 28, fontSize: 12);
        var folder = Ui.Row(5, Ui.Icon("", 11, Theme.AccentBrush()), Ui.Secondary(Shell.Abbreviated(BrowserExtension.Folder), 11.5));
        ToolTipService.SetToolTip(folder, BrowserExtension.Folder);
        return Ui.Card(Ui.Column(10,
            Step(1, L.T("Eklentiler sayfasını aç"), Ui.Secondary(L.F("%@'da %@", ShortName, browser.ExtensionsPage), 11.5), copy),
            Ui.Divider(),
            Step(2, L.T("Geliştirici modunu aç"), Ui.Secondary(L.T("Sayfadaki \"Geliştirici modu\" anahtarı"), 11.5), toggle),
            Ui.Divider(),
            Step(3, L.T("“Paketlenmemiş öğe yükle”ye tıkla"), Ui.Secondary(L.T("Geliştirici modu açılınca çıkar"), 11.5), null),
            Ui.Divider(),
            Step(4, L.T("Eklenti klasörünü seç"), folder, reveal)));
    }

    static UIElement Step(int number, string title, UIElement detail, UIElement? trailing)
    {
        var grid = new Grid { ColumnSpacing = 12 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.Children.Add(new Border
        {
            Width = 26,
            Height = 26,
            CornerRadius = new CornerRadius(13),
            Background = Theme.AccentBrush(0.16),
            Child = new TextBlock { Text = number.ToString(), FontWeight = FontWeights.Bold, FontSize = 12.5, Foreground = Theme.AccentBrush(), HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center },
            VerticalAlignment = VerticalAlignment.Center,
        });
        var texts = Ui.Column(3, Ui.Text(title, 13.5, FontWeights.SemiBold, wrap: true), detail);
        Grid.SetColumn(texts, 1);
        grid.Children.Add(texts);
        if (trailing is FrameworkElement element)
        {
            Grid.SetColumn(element, 2);
            grid.Children.Add(element);
        }
        return grid;
    }

    void RenderWaiting()
    {
        waiting.Children.Clear();
        if (connected)
        {
            waiting.Children.Add(Ui.Icon("", 14, Theme.Brush(Theme.Success)));
            waiting.Children.Add(Ui.Text(L.T("Eklenti bağlandı"), 12.5, FontWeights.SemiBold));
        }
        else
        {
            waiting.Children.Add(Ui.Spinner(14));
            waiting.Children.Add(Ui.Secondary(L.T("Eklenti bekleniyor…"), 12.5));
        }
    }

    async void CheckConnection()
    {
        if (connected || Browser is not { } browser) return;
        var seen = ExtensionStatus.LastSignal(store, browser);
        if (seen == null || seen == initialSignal) return;
        connected = true;
        RenderWaiting();
        await Task.Delay(1400);
        store.OnboardingBrowser = null;
        store.Route = Route.List;
    }

    void BeginInstall()
    {
        if (Browser is not { } browser) return;
        error.Text = BrowserExtension.BeginInstall(browser) ? "" : L.T("Eklenti dosyaları hazırlanamadı.");
    }
}
