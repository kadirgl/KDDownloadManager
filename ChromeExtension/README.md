# KD Download Manager — tarayıcı eklentisi

Tarayıcıdaki indirmeleri, magnet linklerini ve videoları KD Download Manager uygulamasına gönderir.
Chromium tabanlı tüm tarayıcılarda çalışır: Chrome, Edge, Brave, Arc, Vivaldi, Opera.

## Kurulum

Eklenti Chrome Web Mağazası'ndan kurulur: uygulamanın kurulum ekranı ve **Ayarlar > Tarayıcı eklentisi** mağaza
sayfasını açar (Edge, Brave, Arc, Vivaldi ve Opera da mağazadan kurabiliyor). Mağazadaki eklentiyi tarayıcı
kendisi günceller. Mağaza kimliği uygulamalara yazılana kadar (bkz. [store/REHBER.md](store/REHBER.md)) ve
mağazayı kullanamayanlar için yedek yol, uygulamayla gelen kopyayı geliştirici modundan yüklemek:

### Geliştirici modundan (paketlenmemiş)

Uygulamada kurulum ekranında "Geliştirici modundan yükle". Uygulama eklentiyi
`~/Library/Application Support/KDDownloadManager/BrowserExtension` klasörüne kopyalar, yolunu panoya
alır ve tarayıcının uzantılar sayfasını açar. Orada:

1. Sağ üstten **Geliştirici modu**nu açın.
2. **Paketlenmemiş öğe yükle**'ye tıklayın, ⌘⇧G ile yolu yapıştırıp **Seç**'e basın.

Windows sürümünde klasör `%LOCALAPPDATA%\KDDownloadManager\BrowserExtension`; açılan pencerede yolu "Klasör"
alanına yapıştırıp **Klasör Seç**'e basın. Eklenti iki uygulamayla da aynıdır.

Eklenti bağlanınca Ayarlar'da "Bağlı" görünür. Uygulama güncellendiğinde o klasör de güncellenir;
eklenti yeni sürümü en geç bir dakika içinde fark edip kendini yeniden yükler (`reloadIfUpdated`; yalnızca
geliştirici modunda yüklenen kopya yapar, mağaza kopyasını Chrome günceller). Eklentinin sürümü her zaman
uygulamanınkiyle aynıdır (paketlerken ve yayımlarken eşitlenir).

### Kimlikler

- Paketlenmemiş kopya: `necbfaijhfnnoikbppjdjcpfjekefdbk`, her tarayıcıda aynı (depodaki manifest'in `key`
  alanı sayesinde).
- Mağaza kopyası: mağazanın verdiği kimlik; macOS'ta `BrowserExtension.storeExtensionID`, Windows'ta
  `BrowserExtension.StoreExtensionId` (ikisini birden `scripts/chrome-store.sh set-id KİMLİK` yazar).

Uygulama yalnızca bu iki kimlikten gelen istekleri kabul eder (`ExtensionBridge.allowedOrigins`).

## Chrome Web Mağazası

- `scripts/chrome-store.sh package` mağazaya yüklenecek zip'i üretir (`dist/KDDownloadManager-Chrome-SÜRÜM.zip`):
  manifest'ten `key` çıkarılır, `store/` ve bu README girmez, mağazanın reddedeceği şeyler denetlenir.
  `scripts/release.sh` bunu her sürümde çalıştırır; `CHROME_STORE=1` ile mağazaya yükleyip incelemeye de gönderir.
- Mağaza kaydının metinleri, izin gerekçeleri ve gizlilik politikası `store/` altında; görseller
  `store/make-assets.sh` ile üretilir. İlk yayın ve API kurulumu: [store/REHBER.md](store/REHBER.md).
- İzinler bilerek dar: `activeTab` yok (sitelere erişim zaten var), siteler yalnızca `http`/`https`.

## Ne yapar

- **İndirmeleri yakalar:** Tarayıcı bir dosya indirmeye başlayınca linki uygulamaya yollar ve
  tarayıcının indirmesini iptal eder. Uygulama linki yoklarken tarayıcının indirmesi duraklatılır; böylece
  hızlı inen dosyalar (Google Drive gibi) iki yerde birden inmez. Uygulama çalışmıyorsa ya da linki
  indiremeyeceğini söylerse tarayıcı kaldığı yerden devam eder.
  Açılır pencereden kapatılabilir. Gizli pencerelerdeki indirmelere dokunmaz.
- **Magnet linklerini yakalar:** Sayfalardaki `magnet:` linklerine tıklanınca uygulamaya gönderir
  (değiştirici tuşla tıklanırsa tarayıcıya bırakır). Eklentisi olmayan tarayıcılar (Safari) için
  uygulamada **Ayarlar > Torrent > Bununla aç** kullanılabilir.
- **Video kalitesi:** Açılır pencere her sayfada video arar ve bulursa sunduğu çözünürlükleri tahmini
  boyutlarıyla listeler (uygulama yt-dlp ile öğrenir; ~1.800 site tanınıyor). Sağ tık menüsünde de
  kalite alt menüsü var.
- **Her sitede videolar:** "İndir" butonu videonun içine değil dışına konur (oynatıcıların köşelerinde
  kendi düğmeleri var): YouTube'da beğen/paylaş satırında, Shorts'ta sağdaki düğme sütununun en üstünde;
  diğer sitelerde fare videonun üzerine gelince videonun hemen üstünde, sağ kenarına hizalı. Yalnızca tam
  ekranda, dışarıda yer yokken ya da videonun hemen üstü ve altı yazı veya düğmeyle doluyken (X gibi) oynatıcının
  sağ üst köşesine girer; böylece sayfanın yazılarını kapatmaz. Butonun yanında fare üstüne gelince beliren × o
  videoda butonu gizler; ardından çıkan bildirimden "Geri al" ya da "Bu sitede kapat" seçilebilir. Kapatılan site
  açılır pencereden ("Videolarda İndir butonu") yeniden açılır. yt-dlp'nin tanımadığı sitelerde de sayfa oynatırken
  açtığı akışlar (HLS `.m3u8`, DASH `.mpd`, doğrudan video dosyaları) yakalanır; araç çubuğu ikonunda
  o sekmede bulunan akış sayısı görünür, butondan ya da açılır pencereden indirilebilir. Akışlar
  sayfanın başlığıyla kaydedilir.
- **Sağ tık menüsü:** Linklerde "KD Download Manager ile indir"; sayfalarda, videolarda ve video
  linklerinde kalite seçerek indirme.

Arayüz Türkçe ve İngilizce: metinler `_locales/tr` ve `_locales/en` altındaki `messages.json`
dosyalarında, `chrome.i18n` ile okunuyor. Tarayıcının dili Türkçe değilse İngilizce görünür
(`default_locale`). Yeni metin eklerken iki dosyaya da aynı anahtarı ekleyin.

Giriş gerektiren indirmeler için linkle birlikte o sitenin çerezleri, referrer ve tarayıcı kimliği de
gönderilir. Uygulama bunları yalnızca indirme sırasında kullanır; çerezler diske yazılmaz.

## Nasıl bağlanır

Uygulama yalnızca `127.0.0.1:47615` adresini dinler (`Sources/KDDownloadManager/Bridge`).
Eklenti açılışta ve dakikada bir `/hello` ile kendini bildirir.
