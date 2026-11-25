using DispatcherQueueTimer = Microsoft.UI.Dispatching.DispatcherQueueTimer;
using KDDownloadManager.Store;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;

namespace KDDownloadManager.Views;

/// <summary>
/// First launch: installing the browser extension (macOS: OnboardingView). The extension installs from the Chrome
/// Web Store; those who can't use the store can load the bundled copy in developer mode (the only way while the
/// store ID is empty). When the extension connects for the first time a short confirmation is shown and the list
/// opens; "Şimdilik geç" stops it from opening by itself.
/// </summary>
public sealed class OnboardingPage : UserControl
{
    readonly DownloadStore store;
    readonly StackPanel waiting = new() { Orientation = Orientation.Horizontal, Spacing = 8, HorizontalAlignment = HorizontalAlignment.Center };
    readonly TextBlock error = Ui.Text("", 11.5, brush: Theme.Brush(Theme.Error), wrap: true);
    readonly DispatcherQueueTimer timer;
    readonly DateTimeOffset? initialSignal;
    bool connected;
    /// <summary>Developer-mode install chosen instead of the store.</summary>
    bool manual;

    bool UsesStore => BrowserExtension.StoreUrl != null && !manual;

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

        Render();

        timer = Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread().CreateTimer();
        timer.Interval = TimeSpan.FromSeconds(1);
        timer.Tick += (_, _) => { if (IsLoaded) Ui.Guard(CheckConnection); };
        Loaded += (_, _) => timer.Start();
        Unloaded += (_, _) => timer.Stop();
    }

    void Render()
    {
        var browser = Browser;
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
        var introText = UsesStore
            ? L.F("İndirmeleri, videoları ve magnet linklerini %@'dan tek tıkla uygulamaya gönderir. Chrome Web Mağazası'ndan kurulur, birkaç saniye sürer.", ShortName)
            : BrowserExtension.StoreUrl != null
                ? L.T("Mağazayı kullanamıyorsan uygulamayla gelen kopyayı geliştirici modundan yükleyebilirsin; 1 dakika sürer. Bu kopyayı uygulama günceller.")
                : L.F("İndirmeleri, videoları ve magnet linklerini %@'dan tek tıkla uygulamaya gönderir. Eklenti henüz Chrome Web Mağazası'nda olmadığı için geliştirici modundan yüklenir, 1 dakika sürer.", ShortName);
        var intro = Ui.Secondary(introText, 12.5, wrap: true);
        intro.TextAlignment = TextAlignment.Center;
        var column = Ui.Column(12, badge, title, intro);
        column.Margin = new Thickness(Theme.Margin, 0, Theme.Margin, 16);
        if (browser != null) column.Children.Add(UsesStore ? StoreSteps(browser) : Steps(browser));
        else column.Children.Add(Ui.Card(Ui.Secondary(L.T("Desteklenen bir tarayıcı bulunamadı (Chrome, Edge, Brave, Vivaldi, Opera)."), 12, wrap: true)));
        if (!UsesStore)
            column.Children.Add(Ui.Row(6, Ui.Icon("\uE946", 12, Theme.SecondaryText),
                Ui.Secondary(L.T("Kısayol: Gezgin'deki klasörü sürükleyip eklentiler sayfasına bırakabilirsin."), 11.5, wrap: true)));
        if (BrowserExtension.StoreUrl != null)
        {
            var other = new HyperlinkButton
            {
                Content = manual ? L.T("Chrome Web Mağazası'ndan kur") : L.T("Mağazayı kullanamıyor musun? Geliştirici modundan yükle"),
                Padding = new Thickness(0),
            };
            other.Click += (_, _) => { manual = !manual; error.Text = ""; Render(); };
            column.Children.Add(other);
        }
        if (error.Parent is Panel oldErrorParent) oldErrorParent.Children.Remove(error);
        if (waiting.Parent is Panel oldWaitingParent) oldWaitingParent.Children.Remove(waiting);
        column.Children.Add(error);
        column.Children.Add(waiting);
        RenderWaiting();

        var layout = new Grid();
        layout.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        layout.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        layout.Children.Add(new ScrollViewer { Content = column });
        var start = UsesStore
            ? Ui.AccentButton(L.T("Chrome Web Mağazası'nda aç"), "\uE719", OpenStore, 46)
            : Ui.AccentButton(L.T("Kurulumu başlat"), "\uEA86", BeginInstall, 46);
        start.IsEnabled = browser != null;
        var skip = new HyperlinkButton { Content = L.T("Şimdilik geç"), HorizontalAlignment = HorizontalAlignment.Center };
        skip.Click += (_, _) => store.SkipOnboarding();
        var footer = Ui.Column(4, start, skip);
        footer.Margin = new Thickness(Theme.Margin, 6, Theme.Margin, 12);
        Grid.SetRow(footer, 1);
        layout.Children.Add(footer);
        Content = layout;
    }

    /// <summary>Store install: open the page, add, the extension connects by itself.</summary>
    UIElement StoreSteps(BrowserExtension.Browser browser)
    {
        var copy = Ui.Pill(L.T("Linki kopyala"), () => { }, "\uE71B", 28, 12);
        copy.Click += (_, _) =>
        {
            if (BrowserExtension.StoreUrl is { } url) Shell.Copy(url);
            copy.Content = Ui.Row(6, Ui.Icon("\uE73E", 12), Ui.Text(L.T("Kopyalandı"), 12, FontWeights.SemiBold));
        };
        ToolTipService.SetToolTip(copy, L.T("Mağaza sayfası başka bir tarayıcıda açılırsa bağlantıyı istediğin tarayıcıya yapıştır."));
        var hint = browser.Name switch
        {
            "Microsoft Edge" => L.T("Edge önce “Diğer mağazalardan uzantılara izin ver”i sorar; İzin ver'e bas"),
            "Opera" => L.T("Opera'da önce “Install Chrome Extensions” eklentisi kurulmalı"),
            _ => L.T("Açılan pencerede “Uzantı ekle”yi onayla"),
        };
        return Ui.Card(Ui.Column(10,
            Step(1, L.T("Mağaza sayfasını aç"), Ui.Secondary(L.F("Aşağıdaki düğme %@'da açar", ShortName), 11.5, wrap: true), copy),
            Ui.Divider(),
            Step(2, L.T("“Chrome'a ekle”ye tıkla"), Ui.Secondary(hint, 11.5, wrap: true), null),
            Ui.Divider(),
            Step(3, L.T("Eklenti kendiliğinden bağlanır"), Ui.Secondary(L.T("Uygulama açıkken birkaç saniye içinde; mağaza eklentiyi kendisi güncel tutar"), 11.5, wrap: true), null)));
    }

    void OpenStore()
    {
        if (Browser is not { } browser) return;
        error.Text = BrowserExtension.OpenStorePage(browser) ? "" : L.T("Eklenti dosyaları hazırlanamadı.");
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
