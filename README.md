# KD Download Manager

macOS menü çubuğunda yaşayan, hızlı ve sade bir indirme yöneticisi. Dosyaları parçalı indirir (aria2),
YouTube ve ~1.800 sitedeki videoları istenen kalitede indirir (yt-dlp + ffmpeg), torrent ve magnet
linklerini açar. Chromium tabanlı tarayıcılar (Chrome, Edge, Brave, Arc, Vivaldi, Opera) için eklentisiyle
tarayıcıdaki indirmeleri ve videoları doğrudan uygulamaya gönderir.

- Parçalı (çok bağlantılı) indirme, duraklat/sürdür, uygulama kapansa da kaldığı yerden devam
- Video kalitesi seçimi (4K'ya kadar, tahmini boyutlarıyla) ve yalnızca ses (MP3)
- Torrent ve magnet linkleri
- Genel ve indirmeye özel hız sınırı, aynı anda en fazla indirme sayısı
- Kategoriler, arama, bildirimler, açık/koyu tema ve vurgu rengi
- Uygulama içinden otomatik güncelleme

## Kurulum

1. [Releases](../../releases/latest) sayfasından `KDDownloadManager-<sürüm>.zip` dosyasını indirip açın.
2. **KDDownloadManager.app**'i **Uygulamalar** klasörüne taşıyıp açın. Uygulama Apple Developer ID ile
   imzalı ve Apple'ın noter onayından geçmiş; macOS uyarı vermeden açar.
3. Uygulama ilk açılışta tarayıcı eklentisinin kurulumunu adım adım gösterir.

Gereksinimler: Apple Silicon (M1 ve sonrası), macOS 14 Sonoma veya üstü. aria2, yt-dlp, ffmpeg ve QuickJS
uygulamanın içinde gelir; Homebrew gerekmez.

## Güncellemeler

Uygulama günde bir kez GitHub'daki son sürüme bakar. Yeni sürüm varsa bildirim gönderir ve listenin
üstünde band çıkar; **Ayarlar › Uygulama güncellemesi › Güncelle ve yeniden başlat** ile kurulur.
İndirilen paket kurulmadan önce Ed25519 imzasıyla doğrulanır; imzası tutmayan paket kurulmaz. Süren
indirmeler uygulama yeniden açılınca kaldıkları yerden devam eder, tarayıcı eklentisi de kendini yeniler.
Video indirici (yt-dlp) ayrıca kendi resmi sürümlerinden güncel tutulur.

## Kaynaktan derleme

```bash
swift build                      # geliştirme sürümü (.build/debug/KDDownloadManager)
scripts/package-app.sh           # dist/KDDownloadManager.app + .zip
scripts/package-app.sh --install # ayrıca /Applications'a kurup açar
```

Tarayıcı eklentisi [ChromeExtension](ChromeExtension) klasöründe ([ayrıntılar](ChromeExtension/README.md)).

## Sürüm yayımlama

Bir kez: `scripts/update-key.sh` imza anahtarını oluşturur. Gizli anahtar yalnızca Anahtar Zinciri'nde durur
(`scripts/update-key.sh --export` ile yedekleyin; kaybolursa kullanıcılara uygulama içinden güncelleme
gönderilemez), açık anahtar `scripts/update-public-key.txt`'te.

```bash
scripts/release.sh 1.6.0               # notlar son sürümden beri commit başlıklarından
scripts/release.sh 1.6.0 notlar.md     # notlar dosyadan
```

Betik uygulamayı paketler, zip'i imzalar, `v1.6.0` etiketini gönderir ve GitHub sürümünü oluşturur.
