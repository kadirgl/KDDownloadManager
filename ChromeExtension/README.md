# KD Download Manager — tarayıcı eklentisi

Tarayıcıdaki indirmeleri, magnet linklerini ve videoları KD Download Manager uygulamasına gönderir.
Chromium tabanlı tüm tarayıcılarda çalışır: Chrome, Edge, Brave, Arc, Vivaldi, Opera.

## Kurulum

En kolayı uygulamadan: **Ayarlar > Tarayıcı eklentisi > Kur**. Uygulama eklentiyi
`~/Library/Application Support/KDDownloadManager/BrowserExtension` klasörüne kopyalar, yolunu panoya
alır ve tarayıcının uzantılar sayfasını açar. Orada:

1. Sağ üstten **Geliştirici modu**nu açın.
2. **Paketlenmemiş öğe yükle**'ye tıklayın, ⌘⇧G ile yolu yapıştırıp **Seç**'e basın.

Eklenti bağlanınca Ayarlar'da "Bağlı" görünür. Uygulama güncellendiğinde o klasör de güncellenir;
tarayıcı yeni sürümü bir sonraki açılışta (ya da uzantılar sayfasında yenileyince) alır.

Eklentinin kimliği her tarayıcıda `necbfaijhfnnoikbppjdjcpfjekefdbk` olmalı (manifest'teki `key`
sayesinde sabit). Uygulama yalnızca bu kimlikten gelen istekleri kabul eder.

## Ne yapar

- **İndirmeleri yakalar:** Tarayıcı bir dosya indirmeye başlayınca linki uygulamaya yollar ve
  tarayıcının indirmesini iptal eder. Uygulama çalışmıyorsa tarayıcı normal şekilde indirir.
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
  ekranda ya da dışarıda hiç yer yokken oynatıcının sağ üst köşesine girer. yt-dlp'nin tanımadığı sitelerde de sayfa oynatırken
  açtığı akışlar (HLS `.m3u8`, DASH `.mpd`, doğrudan video dosyaları) yakalanır; araç çubuğu ikonunda
  o sekmede bulunan akış sayısı görünür, butondan ya da açılır pencereden indirilebilir. Akışlar
  sayfanın başlığıyla kaydedilir.
- **Sağ tık menüsü:** Linklerde "KD Download Manager ile indir"; sayfalarda, videolarda ve video
  linklerinde kalite seçerek indirme.

Giriş gerektiren indirmeler için linkle birlikte o sitenin çerezleri, referrer ve tarayıcı kimliği de
gönderilir. Uygulama bunları yalnızca indirme sırasında kullanır; çerezler diske yazılmaz.

## Nasıl bağlanır

Uygulama yalnızca `127.0.0.1:47615` adresini dinler (`Sources/KDDownloadManager/Bridge`).
Eklenti açılışta ve dakikada bir `/hello` ile kendini bildirir. Eklenti Chrome Web Mağazası'na
konursa mağaza farklı bir kimlik verir; o kimlik `ExtensionBridge.allowedOrigins` listesine eklenmeli.
