# Web sitesi

Tek sayfalık tanıtım sitesi: `index.html` (derleme gerekmez), `app-icon.png` ve `favicon.png`
(uygulama ikonundan, `sips` ile).

```bash
cd site && python3 -m http.server 8765   # http://127.0.0.1:8765
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
- "macOS için indir" butonu GitHub API'sinden son sürümün zip'ini bulur; ulaşamazsa sürümler sayfasına gider.
