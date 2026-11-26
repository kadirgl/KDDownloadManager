# KD Download Manager

*[English](README.en.md)*

macOS menü çubuğunda yaşayan, hızlı ve sade bir indirme yöneticisi. Dosyaları parçalı indirir (aria2),
YouTube ve ~1.800 sitedeki videoları istenen kalitede indirir (yt-dlp + ffmpeg), torrent ve magnet
linklerini açar. Chromium tabanlı tarayıcılar (Chrome, Edge, Brave, Arc, Vivaldi, Opera) için eklentisiyle
tarayıcıdaki indirmeleri ve videoları doğrudan uygulamaya gönderir.

- Parçalı (çok bağlantılı) indirme, duraklat/sürdür, uygulama kapansa da kaldığı yerden devam
- Video kalitesi seçimi (4K'ya kadar, tahmini boyutlarıyla) ve yalnızca ses (MP3)
- Torrent ve magnet linkleri
- Genel ve indirmeye özel hız sınırı, aynı anda en fazla indirme sayısı
- Kategoriler, arama, bildirimler, açık/koyu tema ve vurgu rengi
- Türkçe ve İngilizce arayüz (sistem dilini izler; **Ayarlar › Görünüm › Dil** ile değiştirilebilir)
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
indirmeler uygulama yeniden açılınca kaldıkları yerden devam eder. Chrome Web Mağazası'ndan kurulan tarayıcı
eklentisini tarayıcı günceller; geliştirici modunda yüklenen kopya uygulamayla birlikte yenilenir.
Video indirici (yt-dlp) ayrıca kendi resmi sürümlerinden güncel tutulur.

## Kaynaktan derleme

```bash
swift build                      # geliştirme sürümü (.build/debug/KDDownloadManager)
scripts/package-app.sh           # dist/KDDownloadManager.app + .zip
scripts/package-app.sh --install # ayrıca /Applications'a kurup açar
```

Tarayıcı eklentisi [ChromeExtension](ChromeExtension) klasöründe ([ayrıntılar](ChromeExtension/README.md)).

### Arayüz dili

Koddaki metinler Türkçe ve aynı zamanda çeviri anahtarı; İngilizceleri
`Sources/KDDownloadManager/Resources/Localizable.xcstrings`'te (Xcode'un String Catalog düzenleyicisiyle de
açılır). Metin ekleyip değiştirdikten sonra:

```bash
scripts/strings.sh sync    # yeni metinleri kataloğa ekler, İngilizcesi eksik olanları listeler
```

`package-app.sh` kataloğu `en.lproj`/`tr.lproj` olarak pakete koyar; yayımlanan sürümde eksik çeviri varsa
durur. Sistem dili Türkçe değilse uygulama İngilizce açılır. Geliştirme sürümünü İngilizce denemek için:

```bash
swift build && scripts/strings.sh compile .build/debug
.build/debug/KDDownloadManager -AppleLanguages '(en)'
```

Eklentinin metinleri `ChromeExtension/_locales/{tr,en}/messages.json`'da; tarayıcının dilini izler.

### Testler

Mac uygulaması, Windows uygulaması (mantık katmanı Mac'te de çalışır) ve Chrome eklentisi için testler
[Tests](Tests) klasöründe ([ağaç ve ayrıntılar](Tests/README.md)):

```bash
scripts/test.sh                          # hepsi
scripts/test.sh mac                      # ya da: windows, extension
git config core.hooksPath scripts/hooks  # bir kez: her git push'tan önce testler çalışsın
```

Yayın betikleri de testler geçmeden sürüm çıkarmaz.

## Sürüm yayımlama

Bir kez: `scripts/update-key.sh` imza anahtarını oluşturur. Gizli anahtar yalnızca Anahtar Zinciri'nde durur
(`scripts/update-key.sh --export` ile yedekleyin; kaybolursa kullanıcılara uygulama içinden güncelleme
gönderilemez), açık anahtar `scripts/update-public-key.txt`'te.

```bash
scripts/release.sh 1.6.0               # notlar son sürümden beri commit başlıklarından
scripts/release.sh 1.6.0 notlar.md     # notlar dosyadan
```

Betik uygulamayı paketler, zip'i imzalar, `v1.6.0` etiketini gönderir ve GitHub sürümünü oluşturur.

## Windows

[Windows](Windows) klasöründe yerel bir Windows sürümü var: WinUI 3 (Windows App SDK 1.8) ve .NET 10, self-contained
(.NET ya da Windows App SDK kurmak gerekmez). Windows 10 1809 ve sonrası, Windows 11; arm64 ve x64. macOS sürümünün
Swift kaynakları örnek alındı; davranışı aynı:

- Bildirim alanında ikon (inerken ilerleme halkası, hatada kırmızı nokta, bitince onay); tıklayınca ikonun yanında
  açılan akrilik panel. Panel açıkken ikona tıklamak paneli kapatır.
- Devam Eden / Tamamlanan listeleri, kategoriler, arama, Link ekle (bağlantı denetimiyle), Ayarlar, Windows bildirimleri
  (Windows App SDK bildirimleri kullanılamıyorsa bildirim alanı ikonunun bildirimleriyle).
- aria2c ile parçalı indirme ve torrent/magnet, yt-dlp + ffmpeg ile video; uygulamanın içinde gelir.
- Tarayıcı eklentisi köprüsü: aynı port (47615), aynı uç noktalar ve aynı `Origin` denetimi; [ChromeExtension](ChromeExtension)
  hiç değişmeden çalışır. Uygulama eklentiyi `%LOCALAPPDATA%\KDDownloadManager\BrowserExtension`'a kopyalar.
- Türkçe ve İngilizce arayüz (Ayarlar › Dil, yeniden başlatınca).
- GitHub Releases'ten güncelleme; macOS ile aynı Ed25519 anahtarı ve imza biçimi.

### Kurulum

Son sürümden `KDDownloadManager-Windows-x64-<sürüm>-Setup.exe` (çoğu bilgisayar) ya da
`KDDownloadManager-Windows-arm64-<sürüm>-Setup.exe` (ARM işlemcili bilgisayarlar) dosyasını indirip çalıştırın.
Kurulum yönetici izni istemez; uygulamayı kullanıcıya özel olarak `%LOCALAPPDATA%\Programs\KD Download Manager`'a
kurar, Başlat menüsüne (isteğe bağlı masaüstüne de) kısayol koyar ve Ayarlar › Uygulamalar'a kaldırma kaydı ekler.
Türkçe ve İngilizce; açık olan uygulamayı kapatıp üzerine kurar. Ayarlar › Başlangıç'tan oturum açınca başlatılabilir,
Ayarlar › Torrent'ten magnet linkleri ve `.torrent` dosyaları bu uygulamayla açılır. Notlar:

- Kurulum kod imzalı olmadığı için Windows SmartScreen uyarabilir ("Windows bilgisayarınızı korudu"):
  **Ek bilgi › Yine de çalıştır**.
- Kurmadan kullanmak için aynı sürümün `KDDownloadManager-Windows-<arm64|x64>-<sürüm>.zip` dosyasını açıp
  `KDDownloadManager.exe`'yi çalıştırın. Böyle bir kopya ilk uygulama içi güncellemede bulunduğu klasöre kurulur.
- Kaldırırken ayarların ve indirme listesinin de silinip silinmeyeceği sorulur; indirilen dosyalara dokunulmaz.
- İlk torrent'te Windows Güvenlik Duvarı aria2c için gelen bağlantı izni sorar. İzin vermeden de iner; izin verilirse
  eşler size de bağlanabildiği için genelde daha hızlıdır.
- Yeni ikonlar Windows 11'de taşma alanına (^) konur; görev çubuğu ayarlarından görünür yapılabilir.

### Derleme ve paketleme (Windows'ta)

Gerekenler: .NET 10 SDK (`dotnet` PATH'te ya da `C:\kd\dotnet`).

```powershell
powershell -ExecutionPolicy Bypass -File Windows\scripts\package.ps1                         # arm64 ve x64
powershell -ExecutionPolicy Bypass -File Windows\scripts\package.ps1 -Arch arm64 -Version 1.9.3
```

Gerekenler arasında Inno Setup 6 de var (`ISCC.exe` PATH'te, `C:\kd\inno`'da ya da olağan kurulum klasöründe; ya da
`-Iscc <yol>`). Sonuç `Windows\dist\KDDownloadManager-Windows-<mimari>-<sürüm>-Setup.exe` (kurulum betiği:
[Windows/installer/KDDownloadManager.iss](Windows/installer/KDDownloadManager.iss)) ve aynı adla `.zip`. Yardımcı programları
`Windows\scripts\bundle-tools.ps1` resmi sürümlerinden indirir ve doğrular (yt-dlp `SHA2-256SUMS`, ffmpeg
BtbN `checksums.sha256`, aria2 ve QuickJS betiğe sabitlenmiş SHA-256). Arayüzün İngilizce metinleri macOS'un
`Localizable.xcstrings` dosyasından ve yalnızca Windows'a özgü metinler için [Windows/strings.en.json](Windows/strings.en.json)'dan
üretilir; metin ekleyince `python3 Windows/scripts/strings.py` çalıştırın (çevirisi eksik olanları listeler).

Mac'ten, UTM'deki bir Windows sanal makinesinde derlemek için `Windows/scripts/utm-sync.sh '<komut>'` kaynakları QEMU
misafir ajanıyla `C:\kd\src`'ye kopyalayıp komutu orada çalıştırır (paylaşılan klasör ya da SSH gerekmez).

### Windows sürümünü yayımlama

macOS sürümü `scripts/release.sh` ile yayımlandıktan sonra:

```bash
scripts/release-windows.sh 1.9.3
```

Betik `Windows/dist`'teki kurulumları ve zip'leri (yoksa UTM'deki Windows'ta üretip) Anahtar Zinciri'ndeki aynı gizli
anahtarla imzalar, imzaları denetler ve `KDDownloadManager-Windows-<mimari>-<sürüm>-Setup.exe`,
`KDDownloadManager-Windows-<mimari>-<sürüm>.zip` ve `.sig` dosyalarını aynı GitHub sürümüne ekler. Uygulama içi
güncelleme kurulumu indirip imzasını denetler ve sessizce uygulamanın kendi klasörüne kurar; 1.9.3 ve öncesi yalnızca
zip'i tanıdığı için zip'ler de yayımlanır.
macOS uygulaması yalnızca kendi zip'ine baktığı için bu dosyalar onu etkilemez. Paketin imzasını Windows'ta da
denetlemek için: `KDDownloadManager.exe --verify-update <zip> <zip.sig>` (geçerliyse çıkış kodu 0).
