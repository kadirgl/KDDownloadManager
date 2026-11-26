# Web sitesi

Tek sayfalık tanıtım sitesi: `index.html` (derleme gerekmez), `app-icon.png` ve `favicon.png`
(uygulama ikonundan, `sips` ile).

```bash
cd docs && python3 -m http.server 8765   # http://127.0.0.1:8765
```

- Sayfa düzeni "Gradient hero – Açık – 1440" tasarımından alındı. Sağdaki animasyonun 5 sahnesi
  uygulamanın gerçek ekranlarından çizildi; uygulamada bir görünüm değişince sahneyi de güncelleyin:
  1. **Video:** eklentinin İndir butonu, × ve kalite menüsü (`ChromeExtension/menu.js`).
  2. **8 bağlantı:** liste paneli ve satır (`DownloadListView.swift`, `DownloadRow.swift`). Alttaki
     bağlantı kartı açıklama amaçlı; uygulamada böyle bir görünüm yok.
  3. **Torrent:** panele sürükle-bırak (`PanelView.swift`).
  4. **Hız sınırı:** hız göstergesi ve "Toplam hız sınırı" menüsü (1.8.7).
  5. **Menü çubuğu:** ilerleme halkalı simge (`StatusItemController.swift`) ve bildirim (`Notifier.swift`).
- Sahneler 6'şar saniye, döngü 30 saniye (`--beat`, `--loop`). Sahne içi animasyon yüzdeleri 6 saniyeye göre.
- TR/EN metinleri sayfanın sonundaki `T` nesnesinde. Tarayıcı dili Türkçe değilse EN açılır.
- İndir butonu GitHub API'sinden son 10 sürüme bakar ve her sistemin paketini onu içeren en yeni sürümden alır (yalnızca Mac için çıkan bir sürümde Windows butonları önceki sürüme gider): Windows'ta Windows zip'ini (ARM64 cihazda arm64, yoksa x64), diğerlerinde macOS zip'ini. Altındaki "Diğer sistemler" satırı üç paketin de bağlantısını verir. GitHub'a ulaşılamazsa sürümler sayfasına gider.

## Yayın

Site GitHub Pages'te, https://kddownloadmanager.com adresinde. Pages `main` dalının `docs/` klasörünü yayımlar;
buraya gelen her değişiklik birkaç dakika içinde sitede görünür. `CNAME` alan adını Pages'e bildirir, `.nojekyll`
dosyaların olduğu gibi sunulmasını sağlar. Alan adının DNS kayıtları (Hostinger) GitHub'ı gösterir: kök alan için
`185.199.108.153`, `185.199.109.153`, `185.199.110.153`, `185.199.111.153` A kayıtları; `www` için
`kadirgl.github.io` CNAME kaydı.
