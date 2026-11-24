using KDDownloadManager.Engine;
using KDDownloadManager.Models;
using KDDownloadManager.Store;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace KDDownloadManager.Views;

/// <summary>
/// "Link ekle" (macOS: AddLinkView): paste links and start downloads. A single link is checked first
/// (name, size, qualities) with LinkProbe; broken links, earlier downloads and missing disk space are shown.
/// </summary>
public sealed class AddLinkPage : UserControl
{
    readonly DownloadStore store;
    readonly TextBox editor = new()
    {
        AcceptsReturn = true,
        TextWrapping = TextWrapping.Wrap,
        PlaceholderText = L.T("https://… ya da magnet:?…"),
        MinHeight = 84,
        MaxHeight = 140,
        CornerRadius = new CornerRadius(12),
    };
    readonly TextBlock hint = Ui.Secondary("", 11.5, wrap: true);
    readonly StackPanel body = new() { Spacing = 14 };
    readonly Grid footer = new() { ColumnSpacing = 8 };
    readonly TextBox nameBox = new() { PlaceholderText = L.T("Dosya adı"), MinWidth = 200, CornerRadius = new CornerRadius(8) };

    VideoQuality quality = VideoQuality.Auto;
    long? speedLimit;
    bool startNow = true;
    bool filledFromClipboard;
    LinkProbe.Outcome? outcome;
    bool checking;
    bool slow;
    string? probedLink;
    CancellationTokenSource? probe;
    bool nameEdited;

    public AddLinkPage(DownloadStore store)
    {
        this.store = store;
        var layout = new Grid();
        layout.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        layout.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        layout.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        layout.Children.Add(ListPage.Header(L.T("Link ekle"), () => store.Route = Route.List));

        var paste = Ui.Pill(L.T("Yapıştır"), async () => await PasteFromClipboard(), "", 28, 12);
        paste.HorizontalAlignment = HorizontalAlignment.Right;
        var linkSection = Ui.Column(8, Ui.SectionLabel(L.T("Bağlantı")), editor, Ui.Row(8, hint), paste);
        var scrollContent = Ui.Column(16, linkSection, body);
        scrollContent.Margin = new Thickness(Theme.Margin, 0, Theme.Margin, 16);
        var scroll = new ScrollViewer { Content = scrollContent };
        Grid.SetRow(scroll, 1);
        layout.Children.Add(scroll);

        footer.Margin = new Thickness(Theme.Margin, 8, Theme.Margin, 14);
        footer.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        footer.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        Grid.SetRow(footer, 2);
        layout.Children.Add(footer);
        Content = layout;

        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(editor, L.T("Bağlantı"));
        editor.TextChanged += (_, _) => { filledFromClipboard = false; OnTextChanged(); };
        // Preview: the multi-line box would otherwise turn Ctrl+Enter into a new line.
        editor.PreviewKeyDown += (_, e) =>
        {
            var ctrl = Microsoft.UI.Input.InputKeyboardSource.GetKeyStateForCurrentThread(Windows.System.VirtualKey.Control).HasFlag(Windows.UI.Core.CoreVirtualKeyStates.Down);
            if (ctrl && e.Key == Windows.System.VirtualKey.Enter) { Download(); e.Handled = true; }
        };
        nameBox.TextChanged += (_, _) => { if (nameBox.FocusState != FocusState.Unfocused) nameEdited = true; };
        Loaded += async (_, _) =>
        {
            if (await ClipboardLinks() is { } clip)
            {
                editor.Text = clip;
                filledFromClipboard = true;
                editor.SelectionStart = clip.Length;
            }
            OnTextChanged();
            editor.Focus(FocusState.Programmatic);
        };
        Unloaded += (_, _) => probe?.Cancel();
    }

    List<string> Links => DownloadStore.ParseLinks(editor.Text);
    string? Single => Links is { Count: 1 } l ? l[0] : null;
    DownloadSource? SingleSource => Single is { } s ? DownloadSources.Detect(s) : null;
    bool HasVideoLinks => Links.Any(l => DownloadSources.Detect(l) == DownloadSource.Video);
    DownloadItem? Duplicate => Single is { } s ? store.ExistingItem(s) : null;
    bool TextIsInvalid => editor.Text.Trim().Length > 0 && Links.Count == 0;
    bool ShowsNameField => Duplicate != null || SingleSource == DownloadSource.Direct;

    string? InvalidReason
    {
        get
        {
            if (TextIsInvalid) return L.T("Adres eksik ya da hatalı görünüyor. \"https://\" ile başladığını kontrol edip tekrar dene.");
            if (outcome is LinkProbe.Outcome.Invalid invalid && Duplicate == null) return invalid.Reason;
            return null;
        }
    }

    long? ExpectedSize => Duplicate is { } d ? (d.TotalBytes > 0 ? d.TotalBytes : null) : outcome switch
    {
        LinkProbe.Outcome.File f => f.Info.Size,
        LinkProbe.Outcome.Video v => v.Formats.Options.FirstOrDefault(o => o.Quality == quality)?.Size,
        _ => null,
    };

    long? MissingSpace => ExpectedSize is { } size && Shell.FreeSpace(Settings.DownloadFolder) is { } free && size > free ? size - free : null;

    void OnTextChanged()
    {
        var single = Single;
        if (single != probedLink)
        {
            probedLink = single;
            outcome = null;
            nameEdited = false;
            nameBox.Text = "";
            probe?.Cancel();
            if (Duplicate is { } duplicate)
            {
                nameBox.Text = store.FreshName(duplicate.FileName, duplicate.Folder, duplicate.Source != DownloadSource.Video);
                checking = false;
            }
            else if (single != null) _ = Check(single);
            else checking = false;
        }
        Render();
    }

    async Task Check(string link)
    {
        var cts = probe = new CancellationTokenSource();
        checking = true;
        slow = false;
        Render();
        try
        {
            await Task.Delay(400, cts.Token);
            var slowTimer = Task.Delay(LinkProbe.Timeout, cts.Token).ContinueWith(t =>
            {
                if (!t.IsCanceled && checking && !cts.IsCancellationRequested) { slow = true; Render(); }
            }, TaskScheduler.FromCurrentSynchronizationContext());
            var result = await LinkProbe.Check(link, cts.Token);
            if (cts.IsCancellationRequested) return;
            outcome = result;
            checking = false;
            slow = false;
            if (SingleSource == DownloadSource.Direct && !nameEdited)
                nameBox.Text = result is LinkProbe.Outcome.File { Info.Name: { } found } ? found : new DownloadItem(link).FileName;
            Render();
        }
        catch (OperationCanceledException) { }
    }

    void Render()
    {
        body.Children.Clear();
        var reason = InvalidReason;
        hint.Text = reason != null ? "" : filledFromClipboard
            ? L.T("Panodaki link otomatik eklendi · dosya, video ve magnet desteklenir")
            : L.T("Her satıra bir link · dosya, video ve magnet desteklenir");
        editor.BorderBrush = reason != null ? Theme.Brush(Theme.Error) : null;

        if (reason != null)
        {
            body.Children.Add(Ui.Card(Ui.Row(10, Ui.Icon("", 16, Theme.Brush(Theme.Error)),
                Ui.Column(3, Ui.Text(L.T("Bu link açılamadı"), 13.5, FontWeights.SemiBold), Ui.Secondary(reason, 12, wrap: true))), tint: Theme.Error));
            body.Children.Add(Ui.Secondary(L.T("Desteklenenler: doğrudan dosya linkleri, magnet linkleri ve YouTube gibi video sayfaları."), 11.5, wrap: true));
        }
        else if (Duplicate is { } duplicate)
        {
            body.Children.Add(DuplicateCard(duplicate));
            body.Children.Add(Section(L.T("Yine de indirilirse"), Ui.Column(12, NameRow(),
                Ui.Secondary(L.T("Eski dosyanın üzerine yazılmaz, yeni kopya bu adla kaydedilir."), 11.5, wrap: true), Ui.Divider(), SaveRow())));
        }
        else if (Single is { } single)
        {
            body.Children.Add(checking || outcome == null ? CheckingCard() : FoundCard(single));
        }
        else if (Links.Count > 1)
        {
            var list = Ui.Column(6);
            foreach (var link in Links.Take(20))
            {
                var source = DownloadSources.Detect(link);
                var name = new DownloadItem(link).FileName;
                var row = Ui.Row(10, Ui.CategoryIcon(source == DownloadSource.Video ? (quality == VideoQuality.Audio ? DownloadCategory.Music : DownloadCategory.Video) : DownloadCategories.ForFile(name), 28),
                    Ui.Column(1, Ui.Text(name, 12.5, FontWeights.SemiBold), Ui.Secondary(DownloadSources.Host(link) ?? "", 11)));
                if (store.ExistingItem(link) != null) row.Children.Add(Ui.Secondary(L.T("Listede var"), 11));
                list.Children.Add(row);
            }
            if (Links.Count > 20) list.Children.Add(Ui.Secondary(L.F("ve %lld link daha", Links.Count - 20), 11.5));
            body.Children.Add(Ui.Card(list));
        }

        if (reason == null && Duplicate == null && Links.Count > 0)
        {
            if (HasVideoLinks) body.Children.Add(Section(L.T("Kalite"), QualityRail()));
            if (ShowsNameField) body.Children.Add(Section(L.T("Dosya"), Ui.Column(12, NameRow(), Ui.Divider(), SaveRow()), MissingSpace != null));
            var options = Ui.Column(12);
            if (!ShowsNameField) { options.Children.Add(SaveRow()); options.Children.Add(Ui.Divider()); }
            options.Children.Add(LimitRow());
            options.Children.Add(Ui.Divider());
            options.Children.Add(Ui.SettingRow(L.T("Hemen başlat"), Ui.Toggle(startNow, on => startNow = on)));
            body.Children.Add(Section(L.T("Seçenekler"), options, !ShowsNameField && MissingSpace != null));
        }
        if (reason == null)
        {
            var choose = new HyperlinkButton { Content = L.T("dosya seç"), Padding = new Thickness(0) };
            choose.Click += async (_, _) => await ChooseTorrentFiles();
            body.Children.Add(Ui.Row(4, Ui.Icon("", 11, Theme.SecondaryText), Ui.Secondary(L.T(".torrent dosyasını pencereye sürükle ya da"), 11.5), choose));
        }
        RenderFooter();
    }

    static UIElement Section(string title, UIElement content, bool warning = false) =>
        Ui.Column(8, Ui.SectionLabel(title), Ui.Card(content, tint: warning ? Theme.Error : null));

    UIElement? nameRow;
    Border? nameRowHolder;

    /// <summary>
    /// The name field keeps its text and focus across renders, so the same row is moved into each new card. It is
    /// taken out of the previous holder explicitly: Parent is null once the old card has left the tree.
    /// </summary>
    UIElement NameRow()
    {
        if (nameRow == null)
        {
            nameBox.TextAlignment = TextAlignment.Right;
            nameRow = Ui.SettingRow(L.T("Ad"), nameBox);
        }
        if (nameRowHolder != null) nameRowHolder.Child = null;
        nameRowHolder = new Border { Child = nameRow };
        return nameRowHolder;
    }

    UIElement SaveRow()
    {
        var folder = Settings.DownloadFolder;
        var label = Ui.Row(6, Ui.Icon("", 13, Theme.AccentBrush()), Ui.Text(Shell.Abbreviated(folder), 12.5));
        if (Shell.FreeSpace(folder) is { } free) label.Children.Add(Ui.Secondary("· " + L.F("%@ boş", ByteFormat.Size(free)), 12));
        label.Children.Add(Ui.Pill(L.T("Değiştir"), async () => await ChooseFolder(), height: 26, fontSize: 11.5));
        var row = Ui.Column(6, Ui.SettingRow(L.T("Kaydet"), label));
        if (MissingSpace is { } missing)
            row.Children.Add(Ui.Text(L.F("%@ daha yer gerekiyor. Başka bir disk seç ya da yer aç.", ByteFormat.Size(missing)), 11.5, brush: Theme.Brush(Theme.Error), wrap: true));
        return row;
    }

    UIElement LimitRow()
    {
        var button = Ui.MenuButton(speedLimit is { } l ? ByteFormat.Speed(l) : L.T("Sınırsız"));
        var menu = new MenuFlyout();
        foreach (var (title, limit) in Ui.SpeedOptions)
        {
            var item = new MenuFlyoutItem { Text = title };
            var captured = limit;
            item.Click += (_, _) => { speedLimit = captured; Render(); };
            menu.Items.Add(item);
        }
        button.Flyout = menu;
        return Ui.SettingRow(L.T("Hız sınırı"), button);
    }

    UIElement QualityRail()
    {
        var formats = outcome is LinkProbe.Outcome.Video v ? v.Formats : null;
        var offered = formats?.Options.Select(o => o.Quality).ToHashSet();
        var wrap = new VariableSizedWrapGrid { Orientation = Orientation.Horizontal, ItemHeight = 46, ItemWidth = 96, MaximumRowsOrColumns = 4 };
        foreach (var q in VideoQualities.All)
        {
            if (offered != null && !offered.Contains(q)) continue;
            var selected = q == quality;
            var size = formats?.Options.FirstOrDefault(o => o.Quality == q)?.Size;
            var foreground = selected ? Theme.Brush(Theme.OnAccent) : Theme.PrimaryText;
            var content = Ui.Column(0, Ui.Text(q == VideoQuality.Audio ? L.T("Ses (MP3)") : q.Title(), 12, FontWeights.SemiBold, foreground));
            if (size is { } s) content.Children.Add(Ui.Text("~" + ByteFormat.Size(s), 10.5, brush: foreground));
            var button = new Button
            {
                Content = content,
                Width = 92,
                Height = 42,
                CornerRadius = new CornerRadius(10),
                Background = selected ? Theme.AccentBrush() : null,
            };
            Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(button, q == VideoQuality.Audio ? L.T("Ses (MP3)") : q.Title());
            var captured = q;
            button.Click += (_, _) => { quality = captured; Render(); };
            wrap.Children.Add(button);
        }
        return wrap;
    }

    UIElement CheckingCard()
    {
        var head = slow
            ? Ui.Row(8, Ui.Icon("", 16, Theme.Brush(Theme.Warning)), Ui.Text(L.T("Sunucu yanıt vermiyor"), 13.5, FontWeights.SemiBold),
                Ui.Pill(L.T("Tekrar dene"), () => { probedLink = null; OnTextChanged(); }, height: 24, fontSize: 11))
            : Ui.Row(10, Ui.Spinner(18), Ui.Text(L.T("Bağlantı kontrol ediliyor…"), 13.5, FontWeights.SemiBold));
        return Ui.Card(Ui.Column(8, head, Ui.Secondary(slow
            ? L.T("İstersen beklemeden indirebilirsin; ad ve boyut indirme başlayınca öğrenilir.")
            : L.T("Dosya adı ve boyutu birkaç saniye içinde görünür. İstersen beklemeden İptal'e basabilirsin."), 11.5, wrap: true)));
    }

    UIElement FoundCard(string link)
    {
        var source = DownloadSources.Detect(link);
        string title = outcome switch
        {
            LinkProbe.Outcome.Video v => v.Formats.Title + (quality == VideoQuality.Audio ? ".mp3" : ".mp4"),
            LinkProbe.Outcome.File { Info.Name: { } n } => n,
            _ => new DownloadItem(link).FileName,
        };
        var category = source switch
        {
            DownloadSource.Video => quality == VideoQuality.Audio ? DownloadCategory.Music : DownloadCategory.Video,
            DownloadSource.Torrent => DownloadCategory.Other,
            _ => DownloadCategories.ForFile(title),
        };
        var details = new List<string> { (DownloadSources.Host(link) ?? "").Replace("www.", "") };
        switch (outcome)
        {
            case LinkProbe.Outcome.Video v:
                details.Add(L.T("Video"));
                if (v.Formats.Duration is { } d) details.Add(TimeSpan.FromSeconds(d).ToString(d >= 3600 ? @"h\:mm\:ss" : @"m\:ss"));
                break;
            case LinkProbe.Outcome.File f:
                if (source == DownloadSource.Torrent) details.Add(L.T("Torrent"));
                else if (Path.GetExtension(title) is { Length: > 1 } ext) details.Add(ext[1..].ToUpperInvariant());
                if (f.Info.Size is { } size) details.Add(ByteFormat.Size(size));
                break;
        }
        var grid = new Grid { ColumnSpacing = 12 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.Children.Add(Ui.CategoryIcon(category, 44));
        var texts = Ui.Column(2, Ui.Text(title, 14, FontWeights.SemiBold), Ui.Secondary(string.Join(" · ", details.Where(d => d.Length > 0)), 12));
        Grid.SetColumn(texts, 1);
        grid.Children.Add(texts);
        if (outcome is LinkProbe.Outcome.File or LinkProbe.Outcome.Video)
        {
            var found = Ui.Row(4, Ui.Icon("", 11, Theme.Brush(Theme.Success)), Ui.Text(L.T("Bulundu"), 12, FontWeights.SemiBold, Theme.Brush(Theme.Success)));
            Grid.SetColumn(found, 2);
            grid.Children.Add(found);
        }
        var column = Ui.Column(10, grid);
        if (outcome is LinkProbe.Outcome.File { Info.Resumable: true } && source == DownloadSource.Direct)
        {
            column.Children.Add(Ui.Divider());
            column.Children.Add(Ui.Row(14, Ui.Row(5, Ui.Icon("", 11, Theme.SecondaryText), Ui.Secondary(L.F("Parçalı indirme: %lld bağlantı", Settings.ConnectionCount), 11.5)),
                Ui.Row(5, Ui.Icon("", 11, Theme.SecondaryText), Ui.Secondary(L.T("Kaldığı yerden devam eder"), 11.5))));
        }
        if (outcome is LinkProbe.Outcome.Warning warning)
        {
            column.Children.Add(Ui.Divider());
            column.Children.Add(Ui.Row(8, Ui.Icon("", 12, Theme.Brush(Theme.Warning)), Ui.Text(warning.Message, 12, wrap: true),
                Ui.Pill(L.T("Tekrar dene"), () => { probedLink = null; OnTextChanged(); }, height: 24, fontSize: 11)));
        }
        if (outcome is LinkProbe.Outcome.VideoUnknown)
        {
            column.Children.Add(Ui.Divider());
            column.Children.Add(Ui.Secondary(L.T("Video bilgisi şimdi alınamadı; indirme sırasında yeniden denenecek."), 11.5, wrap: true));
        }
        return Ui.Card(column);
    }

    UIElement DuplicateCard(DownloadItem item)
    {
        var status = item.IsCompleted ? L.T("Bu dosya zaten indirildi") : L.T("Bu link zaten listede");
        var column = Ui.Column(8, Ui.Row(10, Ui.CategoryIcon(item.Category, 40),
            Ui.Column(2, Ui.Text(item.FileName, 13.5, FontWeights.SemiBold), Ui.Secondary(status, 12))));
        var buttons = Ui.Row(6);
        if (item.IsCompleted && item.Destination != null) buttons.Children.Add(Ui.Pill(L.T("Aç"), () => Shell.Open(item.Destination), height: 26, fontSize: 11.5));
        buttons.Children.Add(Ui.Pill(L.T("Klasörde göster"), () => DownloadStore.Reveal(item), height: 26, fontSize: 11.5));
        column.Children.Add(buttons);
        return Ui.Card(column, tint: Theme.Warning);
    }

    void RenderFooter()
    {
        footer.Children.Clear();
        var cancel = Ui.Pill(L.T("İptal"), () => store.Route = Route.List, height: 44, fontSize: 14);
        footer.Children.Add(cancel);
        Button main;
        if (MissingSpace != null) main = Ui.AccentButton(L.T("Başka klasör seç"), "", async () => await ChooseFolder(), 44);
        else
        {
            string title;
            if (Duplicate != null) title = L.T("Yine de indir");
            else if (Links.Count > 1) title = L.F("%lld dosyayı indir", Links.Count);
            else title = string.Join(" · ", new[] { L.T("İndir"), ExpectedSize is { } s ? "~" + ByteFormat.Size(s) : null }.Where(t => t != null));
            main = Ui.AccentButton(title, "", Download, 44);
            main.IsEnabled = Links.Count > 0 && InvalidReason == null && !(checking && !slow);
            ToolTipService.SetToolTip(main, L.T("İndir (Ctrl+Enter)"));
        }
        Grid.SetColumn(main, 1);
        footer.Children.Add(main);
    }

    void Download()
    {
        if (Links.Count == 0 || InvalidReason != null) return;
        var saveAs = ShowsNameField ? DownloadStore.SanitizedFileName(nameBox.Text) : null;
        store.AddLinks(editor.Text, quality, speedLimit, !startNow, saveAs);
    }

    async Task ChooseFolder()
    {
        if (await Pickers.Folder(Settings.DownloadFolder) is { } folder)
        {
            Settings.DownloadFolder = folder;
            Render();
        }
    }

    async Task ChooseTorrentFiles()
    {
        var files = await Pickers.TorrentFiles();
        if (files.Count > 0) store.AddTorrentFiles(files);
    }

    static async Task<string?> ClipboardLinks()
    {
        var text = await Shell.ClipboardTextAsync();
        if (text == null) return null;
        var found = DownloadStore.ParseLinks(text);
        return found.Count == 0 ? null : string.Join("\n", found);
    }

    async Task PasteFromClipboard()
    {
        if (await ClipboardLinks() is not { } clip) return;
        var existing = Links.ToHashSet();
        var added = clip.Split('\n').Where(l => !existing.Contains(l)).ToList();
        if (added.Count == 0) return;
        var current = editor.Text.Trim();
        editor.Text = string.Join("\n", (current.Length == 0 ? [] : new[] { current }).Concat(added));
    }
}

/// <summary>File and folder pickers; the panel stays open while they are shown.</summary>
public static class Pickers
{
    public static async Task<string?> Folder(string start)
    {
        var picker = new Windows.Storage.Pickers.FolderPicker { SuggestedStartLocation = Windows.Storage.Pickers.PickerLocationId.Downloads };
        picker.FileTypeFilter.Add("*");
        WinRT.Interop.InitializeWithWindow.Initialize(picker, App.PanelHandle);
        using var _ = App.KeepPanelOpen();
        var folder = await picker.PickSingleFolderAsync();
        return folder?.Path;
    }

    public static async Task<List<string>> TorrentFiles()
    {
        var picker = new Windows.Storage.Pickers.FileOpenPicker { SuggestedStartLocation = Windows.Storage.Pickers.PickerLocationId.Downloads };
        picker.FileTypeFilter.Add(".torrent");
        WinRT.Interop.InitializeWithWindow.Initialize(picker, App.PanelHandle);
        using var _ = App.KeepPanelOpen();
        var files = await picker.PickMultipleFilesAsync();
        return files.Select(f => f.Path).ToList();
    }
}
