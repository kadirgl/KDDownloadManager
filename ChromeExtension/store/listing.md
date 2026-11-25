# Chrome Web Mağazası kaydı — doldurulacak metinler

Geliştirici Panosu'ndaki alanlara buradan kopyalayıp yapıştırın. Adım adım sıra için [REHBER.md](REHBER.md).
Varsayılan dil **English**; Türkçe, **Store listing > Add localization > Türkçe** ile eklenir.

---

## 1. Store listing (Mağaza kaydı)

**Name (paketten gelir):** KD Download Manager

**Category:** Tools (Araçlar) · **Language:** English (+ Türkçe yerelleştirme)

**Homepage URL:** https://github.com/kadirgl/KDDownloadManager
**Support URL:** https://github.com/kadirgl/KDDownloadManager/issues

### English

**Summary** (paketteki `extDescription`; en fazla 132 karakter):

> Sends downloads, magnet links and videos to KD Download Manager.

**Description:**

```
KD Download Manager's browser extension sends what you download in Chrome to the free KD Download Manager desktop app on your computer, which downloads it faster, in parallel chunks, and resumes where it left off.

What it does
• Takes over Chrome's downloads: when a download starts, the link goes to the app and Chrome's copy is cancelled. If the app isn't running or can't download the link, Chrome simply continues.
• Download any video in the quality you want: the popup and the Download button above videos list the available qualities (from 4K down to audio-only MP3) with estimated sizes.
• Catches the video streams a page plays (HLS, DASH and direct video files) so you can download them too.
• Sends magnet links to the app.
• Right-click menu: download a link, an image, a media file, or the video on the page in a chosen quality.
• Sites that need you to be signed in keep working: the extension passes the site's cookies along with the link to the app.

Requirements
The extension needs the KD Download Manager app running on the same computer: https://github.com/kadirgl/KDDownloadManager/releases/latest (macOS 14 or later; a Windows version is on the way).

Privacy
The extension talks only to the app on your own computer (127.0.0.1). It has no servers, no analytics and no ads, and it never sends anything to the developer or third parties. Privacy policy: https://github.com/kadirgl/KDDownloadManager/blob/main/ChromeExtension/store/privacy-policy.md

Works in Chrome and other Chromium-based browsers (Edge, Brave, Arc, Vivaldi, Opera). Available in English and Turkish.
```

### Türkçe

**Summary:**

> İndirmeleri, magnet linklerini ve videoları KD Download Manager'a gönderir.

**Description:**

```
KD Download Manager tarayıcı eklentisi, Chrome'da indirdiklerini bilgisayarındaki ücretsiz KD Download Manager uygulamasına gönderir; uygulama dosyaları parça parça, daha hızlı indirir ve kaldığı yerden devam ettirir.

Neler yapar
• Chrome'un indirmelerini devralır: bir indirme başlayınca link uygulamaya gider, Chrome'unki iptal edilir. Uygulama çalışmıyorsa ya da linki indiremiyorsa Chrome indirmeye devam eder.
• Videoları istediğin kalitede indir: açılır pencere ve videoların üstündeki İndir butonu, sunulan kaliteleri (4K'dan yalnızca ses MP3'e kadar) tahmini boyutlarıyla listeler.
• Sayfanın oynattığı video akışlarını (HLS, DASH ve doğrudan video dosyaları) yakalar; onları da indirebilirsin.
• Magnet linklerini uygulamaya gönderir.
• Sağ tık menüsü: linki, resmi, medya dosyasını ya da sayfadaki videoyu seçtiğin kalitede indir.
• Giriş gerektiren siteler de çalışır: eklenti linkle birlikte sitenin çerezlerini uygulamaya iletir.

Gereksinim
Eklentinin çalışması için KD Download Manager uygulamasının aynı bilgisayarda açık olması gerekir: https://github.com/kadirgl/KDDownloadManager/releases/latest (macOS 14 ve sonrası; Windows sürümü yolda).

Gizlilik
Eklenti yalnızca kendi bilgisayarındaki uygulamayla (127.0.0.1) konuşur. Sunucusu, analitiği ve reklamı yoktur; geliştiriciye ya da üçüncü taraflara hiçbir şey göndermez. Gizlilik politikası: https://github.com/kadirgl/KDDownloadManager/blob/main/ChromeExtension/store/privacy-policy.md

Chrome ve diğer Chromium tabanlı tarayıcılarda (Edge, Brave, Arc, Vivaldi, Opera) çalışır. Türkçe ve İngilizce.
```

### Görseller (`assets/`, `make-assets.sh` ile yeniden üretilir)

| Alan | Dosya |
|---|---|
| Store icon (128×128) | `assets/icon-128.png` |
| Screenshots (1280×800, en fazla 5) | `assets/screenshot-1-en.png`, `-2-en`, `-3-en` · Türkçe kayıtta `-tr` |
| Small promo tile (440×280) | `assets/promo-small-en.png` · Türkçe kayıtta `promo-small-tr.png` |
| Marquee promo tile (1400×560, isteğe bağlı) | `assets/promo-marquee-en.png` · `promo-marquee-tr.png` |

---

## 2. Privacy practices (Gizlilik uygulamaları)

### Single purpose description

```
Send the user's downloads, magnet links and videos from the browser to the KD Download Manager desktop app running on the same computer, which then downloads them.
```

### Permission justifications

**downloads**
```
To take over downloads the user starts in Chrome: the extension sees a new download, pauses it while the desktop app checks the link, then cancels and removes Chrome's copy once the app has accepted it (or resumes it if the app is not running or declines). It is also used to save images that only exist in the page (data: URLs), which the desktop app cannot fetch.
```

**contextMenus**
```
Adds right-click menu items: "Download with KD Download Manager" on links and images, on audio/video elements, and "Download the video on this page" with a choice of quality.
```

**storage**
```
Stores the extension's own settings (whether to take over downloads, sites where the Download button is turned off, the app's accent color) and, in session storage, the video streams detected in each tab until the tab navigates or closes.
```

**cookies**
```
Many downloads only work for a signed-in user, and video sites often refuse requests without the user's session. When the user downloads something, or when the popup or the in-page Download button looks up a video's available qualities, the extension reads the cookies of that site and passes them with the link to the desktop app on 127.0.0.1, which uses them only for that request (and to resume a video download the user started). Cookies are never sent to the developer or any third party.
```

**alarms**
```
Sends a once-a-minute heartbeat to the desktop app on 127.0.0.1 so the app can show whether the extension is connected.
```

**webRequest**
```
Observes, without blocking or modifying anything, the response headers of media requests in a tab to detect video streams the page plays (HLS/DASH playlists and video files). The detected stream addresses are offered for download in the popup and the in-page menu and are kept only for the current tab in session storage.
```

**Host permissions (http://*/*, https://*/*, http://127.0.0.1:47615/*)**
```
The extension works on any site the user downloads from: its content scripts add the Download button above videos and catch magnet-link clicks; host access is needed to read the active tab's address for the popup, to read the cookies of a download's site, and to detect media streams with webRequest. http://127.0.0.1:47615 is the desktop app's local endpoint that receives the links.
```

### Remote code

**No, I am not using remote code.** (Tüm betikler pakette; başka sunucudan kod yüklenmez, `eval` yok.)

### Data usage

İşaretlenecekler (dikkatli/tam beyan: veriler cihazdan çıkmasa da eklenti bunları işliyor):

- [x] **Authentication information** — indirmenin sitesinin çerezleri (yalnızca yerel uygulamaya).
- [x] **Web history** — indirilen linkler, sayfa adresleri.
- [x] **Website content** — sayfa başlığı (dosya adı için) ve sayfada bulunan video adresleri.
- [ ] Diğerleri (Personally identifiable information, Health, Financial and payment, Personal communications, Location, User activity) — işaretlenmez.

Üç onay kutusunun üçü de işaretlenir:

- [x] I do not sell or transfer user data to third parties, outside of the approved use cases
- [x] I do not use or transfer user data for purposes that are unrelated to my item's single purpose
- [x] I do not use or transfer user data to determine creditworthiness or for lending purposes

**Privacy policy URL:** https://github.com/kadirgl/KDDownloadManager/blob/main/ChromeExtension/store/privacy-policy.md

---

## 3. Test instructions (İnceleme ekibi için; varsa "Test instructions" sekmesine)

```
The extension is a companion to the free, open-source KD Download Manager desktop app and needs it running on the same computer:
1. Download the app from https://github.com/kadirgl/KDDownloadManager/releases/latest (macOS 14+, Apple Silicon), unzip it, move it to Applications and open it. It appears in the menu bar.
2. With the app running, the extension's popup shows "Connected to the app". Start any file download in Chrome: it appears in the app and Chrome's copy is cancelled. On a page with a video, open the popup or hover over the video and use the "Download" button to choose a quality.
3. Without the app, the popup shows "App isn't running" and Chrome downloads continue normally.
No account or login is needed. The extension only talks to the app at http://127.0.0.1:47615.
```

---

## 4. Distribution (Dağıtım)

- **Payments:** Free of charge
- **Visibility:** Public
- **Regions:** All regions
