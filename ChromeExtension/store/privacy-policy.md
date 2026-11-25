# KD Download Manager — Privacy Policy / Gizlilik Politikası

*Last updated / Son güncelleme: 25 November 2026*

[English](#english) · [Türkçe](#türkçe)

## English

This policy covers the **KD Download Manager browser extension** (Chrome Web Store and the copy bundled with the
app) and the **KD Download Manager desktop app**, an open-source project:
https://github.com/kadirgl/KDDownloadManager

### Summary

The extension exists to hand your downloads over to the KD Download Manager app **on your own computer**. It sends
data only to that app, at `http://127.0.0.1:47615`, which is not reachable from the network. The developer runs
no servers, receives no data, and uses no analytics, advertising or tracking.

### What the extension handles and why

| Data | When | Purpose | Where it goes |
|---|---|---|---|
| Download links, the page address (referrer) and the file name | When you start a download, click a magnet link, or use the popup, the Download button or the right-click menu | So the app can download the file | The app on your computer |
| Cookies of the site of that download or video | Same as above, and when the popup or the Download button looks up a video's qualities | So downloads that need you to be signed in work | The app on your computer, used only for that request; not written to disk |
| Your browser's user agent | With each download | So the site serves the same file it would serve your browser | The app on your computer |
| The page title | When downloading a video or an image | To name the file | The app on your computer |
| Addresses of video streams the page plays (from network response headers) | While you browse | To offer them for download | Kept in the browser's session storage for that tab only, deleted when the tab navigates or closes |
| Your settings (take over downloads on/off, sites where the Download button is off) | When you change them | To remember your choices | The browser's local extension storage |
| Browser name and extension version | Once a minute | So the app can show the extension is connected | The app on your computer |

The extension does not read your browsing history, does not record the pages you visit, and does not read cookies
of sites you are not downloading from. Downloads in incognito windows are left to the browser.

### What the app does with it

The app uses the links, cookies and headers only to download the files you asked for, from the sites they come
from. Your download list (links, file names, folders) is saved on your computer so it survives restarts. The app
contacts GitHub to check for its own updates and to update its video component (yt-dlp); those requests contain
no personal data.

### Sharing

No data is sold, shared with or transferred to the developer or any third party. Data is used only for the
extension's single purpose: sending your downloads to the KD Download Manager app.

### Your control

You can turn off download takeover in the extension's popup, turn off the Download button per site, remove the
extension at any time, and clear the app's download list. Uninstalling the extension deletes its stored settings.

### Changes and contact

Changes to this policy are published at this address, with the date above. Questions:
https://github.com/kadirgl/KDDownloadManager/issues

## Türkçe

Bu politika **KD Download Manager tarayıcı eklentisini** (Chrome Web Mağazası'ndaki ve uygulamayla gelen kopya)
ve **KD Download Manager masaüstü uygulamasını** kapsar; ikisi de açık kaynaklıdır:
https://github.com/kadirgl/KDDownloadManager

### Özet

Eklentinin amacı indirmelerini **kendi bilgisayarındaki** KD Download Manager uygulamasına devretmektir. Veri
yalnızca o uygulamaya, ağdan erişilemeyen `http://127.0.0.1:47615` adresine gider. Geliştiricinin sunucusu
yoktur, hiçbir veri almaz; analitik, reklam ya da izleme kullanılmaz.

### Eklentinin işlediği veriler ve nedeni

| Veri | Ne zaman | Amaç | Nereye gider |
|---|---|---|---|
| İndirme linkleri, sayfa adresi (referrer) ve dosya adı | Bir indirme başlattığında, magnet linkine tıkladığında ya da açılır pencereyi, İndir butonunu veya sağ tık menüsünü kullandığında | Uygulamanın dosyayı indirebilmesi | Bilgisayarındaki uygulama |
| O indirmenin ya da videonun sitesinin çerezleri | Yukarıdakilerle aynı; ayrıca açılır pencere ya da İndir butonu bir videonun kalitelerini sorduğunda | Giriş gerektiren indirmelerin çalışması | Bilgisayarındaki uygulama; yalnızca o istek için kullanılır, diske yazılmaz |
| Tarayıcının kimlik bilgisi (user agent) | Her indirmede | Sitenin tarayıcına vereceği dosyanın aynısını vermesi | Bilgisayarındaki uygulama |
| Sayfa başlığı | Video ya da resim indirirken | Dosyaya ad vermek | Bilgisayarındaki uygulama |
| Sayfanın oynattığı video akışlarının adresleri (ağ yanıtı başlıklarından) | Gezinirken | İndirmeye sunmak | Tarayıcının oturum deposunda yalnızca o sekme için; sekme başka sayfaya geçince ya da kapanınca silinir |
| Ayarların (indirmeleri devralma açık/kapalı, İndir butonunun kapalı olduğu siteler) | Değiştirdiğinde | Seçimlerini hatırlamak | Tarayıcının yerel eklenti deposu |
| Tarayıcı adı ve eklenti sürümü | Dakikada bir | Uygulamanın eklentinin bağlı olduğunu gösterebilmesi | Bilgisayarındaki uygulama |

Eklenti gezinme geçmişini okumaz, ziyaret ettiğin sayfaları kaydetmez ve indirme yapmadığın sitelerin çerezlerini
okumaz. Gizli pencerelerdeki indirmeler tarayıcıya bırakılır.

### Uygulama bunlarla ne yapar

Uygulama linkleri, çerezleri ve başlıkları yalnızca istediğin dosyaları geldikleri sitelerden indirmek için
kullanır. İndirme listen (linkler, dosya adları, klasörler) yeniden açılışta kaybolmasın diye bilgisayarında
saklanır. Uygulama kendi güncellemelerini denetlemek ve video bileşenini (yt-dlp) güncellemek için GitHub'a
bağlanır; bu isteklerde kişisel veri yoktur.

### Paylaşım

Hiçbir veri satılmaz, geliştiriciyle ya da üçüncü taraflarla paylaşılmaz veya onlara aktarılmaz. Veriler yalnızca
eklentinin tek amacı için kullanılır: indirmelerini KD Download Manager uygulamasına göndermek.

### Kontrol sende

İndirmeleri devralmayı eklentinin açılır penceresinden kapatabilir, İndir butonunu site site kapatabilir,
eklentiyi istediğin zaman kaldırabilir ve uygulamadaki indirme listesini temizleyebilirsin. Eklenti kaldırılınca
kayıtlı ayarları da silinir.

### Değişiklikler ve iletişim

Bu politikadaki değişiklikler bu adreste, yukarıdaki tarihle yayımlanır. Sorular için:
https://github.com/kadirgl/KDDownloadManager/issues
