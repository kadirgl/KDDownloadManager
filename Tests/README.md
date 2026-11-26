# Testler

Mac uygulaması, Windows uygulaması ve iki uygulamanın da kullandığı Chrome eklentisi için testler. Hepsi tek komutla
çalışır:

```bash
scripts/test.sh
```

Derleme hazırsa yaklaşık 15 saniye sürer. Bir test başarısız olursa çıkış kodu 1 olur ve ayrıntısı ekrana yazılır.

## Ne zaman çalışır

| Ne zaman | Ne yapar |
| --- | --- |
| `git push` | `scripts/hooks/pre-push` testleri çalıştırır; biri geçmezse push yapılmaz. Yalnızca belge ya da site (`docs/`, `*.md`) değiştiyse atlanır. Acil durumda: `git push --no-verify`. |
| `scripts/release.sh` | Paketlemeden önce testlerin hepsi çalışır. Biri geçmezse, ya da .NET veya node yoksa, sürüm çıkmaz. |
| `scripts/release-windows.sh` | Windows testleri geçmeden paketler GitHub'a yüklenmez. |

Kanca depoyla gelir ama her klonda bir kez açılmalı:

```bash
git config core.hooksPath scripts/hooks
```

## Ağaç

```
Tests/
├── Mac/                          swift test · Swift Testing · @testable import KDDownloadManager
│   ├── Support/                  ortak parçalar
│   │   ├── TestEnvironment       geçici klasörler, ayarların yönlendirilmesi, bekleme yardımcısı
│   │   ├── TestHTTPServer        127.0.0.1'de sahte sunucu (Range/206, Content-Disposition, yavaş gönderim)
│   │   └── RecordingEngine       ağsız sahte indirme motoru
│   ├── Unit/                     saf mantık, ağ yok
│   │   ├── LinkTests             link → motor (video/torrent/dosya), satır adı, kategori, ilerleme
│   │   ├── FileNameTests         ad temizleme/kısaltma, Content-Disposition (Broadcom), biçimler, sürüm karşılaştırma
│   │   ├── ParsingTests          köprünün HTTP ayrıştırıcısı, eklenti isteği, JSON, hata metinleri, hız paylaşımı,
│   │   │                         yt-dlp biçim seçimi, video kaliteleri
│   │   ├── FileTests             dosya imzası, çerez dosyası (0600), listenin diske kaydı/bozuk kayıt
│   │   └── StoreTests            liste: ekleme, "(1)" adları, tekrarlar, duraklat/devam, sil/geri al, filtre/sıralama
│   └── Integration/              yerel sunucu ve gerçek araçlarla
│       ├── LinkProbeTests        Link ekle denetimi, Chrome indirmesini devralma kararı
│       ├── Aria2DownloadTests    gerçek aria2c ile uçtan uca indirme (aria2c yoksa atlanır)
│       ├── BridgeTests           eklenti kapısı: Origin denetimi, /add, /hello, /cookies
│       ├── UpdaterTests          GitHub sürüm bilgisi, imzası tutmayan paketin reddi
│       └── ConsistencyTests      eklenti kimliği = manifest anahtarı; Mac, Windows ve eklenti aynı değerlerde
├── Windows/                      dotnet test · xUnit · Mac'te de çalışır
│   ├── KDDownloadManager.Tests.csproj   Windows/KDDownloadManager'ın mantık katmanını doğrudan derler
│   ├── Shims/                    WinUI, bildirim, kabuk ve Çöp Kutusu yerine geçenler
│   ├── Support/                  geçici klasörler, sahte sunucu, sahte motor, [WindowsFact]
│   ├── Unit/                     Mac'tekilerin karşılığı + her metnin İngilizce çevirisi var mı
│   └── Integration/              link denetimi, köprü, güncelleyici (Setup > zip, mimari, yalnızca Mac'e çıkan sürüm),
│                                 gerçek aria2c.exe (yalnızca Windows'ta)
└── Extension/                    node --test
    └── extension.test.mjs        manifest, paket dosyaları, dil dosyaları, video siteleri, akış yakalama
```

## Güvenlik

Testler gerçek indirme listesine, ayarlara, indirme klasörüne, `~/Library/Application Support/KDDownloadManager`'a ve
kurulu uygulamanın portuna (47615) dokunmaz:

- Her çalıştırma kendi geçici klasöründe olur (`KD_TEST_ROOT`). İş bitince silinir.
- Mac'te ayarlar diske yazılmayan bir alana konur. Uygulama klasörü `KD_SUPPORT_DIR` ile yönlendirilir.
- Köprü testleri 47690 (Mac) ve 47691 (Windows) portlarında çalışır.
- Güncelleme testleri GitHub yerine yerel sunucuyu ve testte üretilen anahtarı kullanır. Gerçek imza anahtarı
  Anahtar Zinciri'nden hiç okunmaz.
- İnternete çıkılmaz. Tüm "sunucular" 127.0.0.1'de çalışır.

## Bir kısmını çalıştırmak

```bash
scripts/test.sh mac
```

```bash
scripts/test.sh windows extension
```

```bash
KD_TEST_FILTER=StoreTests scripts/test.sh mac windows
```

```bash
swift test --filter StoreTests
```

```bash
dotnet test Tests/Windows --filter FullyQualifiedName~BridgeTests
```

## Gerekenler

- Mac testleri için Xcode. Gerçek indirme testleri için aria2c (`brew install aria2`); yoksa bu testler atlanır.
- Windows testleri için .NET 10 SDK. Mac'e sudo gerekmeden kurulur:

  ```bash
  curl -fsSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel 10.0
  ```

  `scripts/test.sh` onu `~/.dotnet`'te kendisi bulur. Windows arayüzü (WinUI) ve gerçek `aria2c.exe` testleri
  yalnızca Windows'ta çalışır. Sanal makinede `dotnet test Tests\Windows` komutuyla çalıştırılır.
- Eklenti testleri için Node.js 18 ya da sonrası.

## Yeni test eklerken

- Bir hata düzeltildiyse, önce onu yakalayan testi yazın. Broadcom'un "index.html" hatası `broadcomName` (Mac)
  ve `BrowserNameGoesToAria2` (Windows) ile korunuyor.
- Mac'te bir test grubu `@Suite` ve `@MainActor` ile başlar. Her test `TestEnvironment.prepare()` çağırır ya da
  `TestEnvironment.scratch()` ile kendi klasörünü alır.
- Ağ gerektiren bir davranış için `TestHTTPServer` (Mac) ya da `TestServer` (Windows) kullanın.
- Mac ile Windows'ta aynı davranış iki tarafta da test edilmeli: aynı adlı testi iki tarafa da yazın.
