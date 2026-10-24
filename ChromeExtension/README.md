# KD Download Manager — Chrome eklentisi

Chrome'daki indirmeleri ve video linklerini KD Download Manager uygulamasına gönderir.

## Kurulum

1. Chrome'da `chrome://extensions` adresini açın.
2. Sağ üstten **Geliştirici modu**nu açın.
3. **Paketlenmemiş öğe yükle**'ye tıklayıp bu `ChromeExtension` klasörünü seçin.
4. Eklentinin kimliği `necbfaijhfnnoikbppjdjcpfjekefdbk` olmalı (manifest'teki `key` sayesinde sabit).
   Uygulama yalnızca bu kimlikten gelen istekleri kabul eder.

## Ne yapar

- **İndirmeleri yakalar:** Chrome bir dosya indirmeye başlayınca linki uygulamaya yollar ve
  Chrome'un indirmesini iptal eder. Uygulama çalışmıyorsa Chrome normal şekilde indirir.
  Açılır pencereden kapatılabilir. Gizli pencerelerdeki indirmelere dokunmaz.
- **Sağ tık menüsü:** Linklerde "KD Download Manager ile indir"; video sitelerinde (YouTube vb.)
  sayfanın kendisi için "Bu sayfadaki videoyu … indir".
- **Açılır pencere:** Uygulamaya bağlı olup olmadığını gösterir; bulunulan sayfayı tek tıkla gönderir.

Giriş gerektiren indirmeler için linkle birlikte o sitenin çerezleri, referrer ve tarayıcı kimliği de
gönderilir. Uygulama bunları yalnızca indirme sırasında kullanır; çerezler diske yazılmaz.

## Nasıl bağlanır

Uygulama yalnızca `127.0.0.1:47615` adresini dinler (`Sources/KDDownloadManager/Bridge`).
Eklenti Chrome Web Mağazası'na konursa mağaza farklı bir kimlik verir; o kimlik
`ExtensionBridge.allowedOrigins` listesine eklenmeli.
