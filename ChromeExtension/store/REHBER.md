# Eklentiyi Chrome Web Mağazası'nda yayımlama — adım adım

Bu rehber, KD Download Manager eklentisini Chrome Web Mağazası'na ilk kez koymak ve sonraki sürümlerde
güncellemek içindir. Alanlara yapıştırılacak metinler [listing.md](listing.md)'de, görseller [assets/](assets)
klasöründe.

## Hazırlık (bir kez)

1. **Gizlilik politikası adresi yayında olmalı.** Mağaza bir gizlilik politikası adresi istiyor. Önerilen adres
   depodaki dosya: <https://github.com/kadirgl/KDDownloadManager/blob/main/ChromeExtension/store/privacy-policy.md>.
   Bu adres, `chrome-web-store` dalı `main`'e alınıp GitHub'a gönderildiğinde çalışmaya başlar.
   - Not: `chrome-web-store` dalı `windows-app` dalının üstünde. `main`'e alınınca Windows uygulamasının kodu da gelir.
     Bunu istemiyorsan yalnızca `ChromeExtension/store/privacy-policy.md` dosyasını `main`'e ayrı bir commit olarak
     alabilirsin.
   - Daha şık bir adres istersen GitHub Pages da olur (depo ayarlarında **Pages > main / docs**). Şimdilik gerekmez.
2. **Geliştirici hesabı.** <https://chrome.google.com/webstore/devconsole> adresinde, **Account** sekmesinde:
   - İletişim e-postasını doğrula (doğrulanmadan yayımlanmıyor).
   - **Trader / Non-trader** beyanı: ücretsiz, kişisel bir proje için **Non-trader** seçilir.
3. **Paketi üret.** Depoda:

   ```bash
   scripts/chrome-store.sh package
   ```

   Çıktı: `dist/KDDownloadManager-Chrome-1.9.2.zip`. Sürüm uygulamanınkiyle aynıdır. Bu paketin manifest'inde
   `key` alanı yoktur, çünkü mağaza bu alanı kabul etmiyor ve kimliği kendisi veriyor. Uygulamayla gelen kopyada
   `key` kalır ve kimliği `necbfaijhfnnoikbppjdjcpfjekefdbk` olarak devam eder.

## 1. Öğeyi oluştur ve paketi yükle

1. Geliştirici Panosu'nda **Items > + New item**'a tıkla.
2. `dist/KDDownloadManager-Chrome-1.9.2.zip` dosyasını seç ve yükle.
3. Taslak oluşur. **Package** sekmesinde **Item ID** görünür: 32 harflik bir kimlik, `a`–`p` harflerinden oluşur.
   Bunu bir kenara not et, sonunda bana göndereceksin.

## 2. Store listing (Mağaza kaydı) sekmesi

[listing.md](listing.md)'deki **1. Store listing** bölümünden kopyala:

1. **Description**: English metni yapıştır. **Summary** paketten gelir, değiştirmen gerekmez.
2. **Category** olarak **Tools**'u, **Language** olarak **English**'i seç.
3. **Store icon**: `assets/icon-128.png`.
4. **Screenshots**: `assets/screenshot-1-en.png`, `screenshot-2-en.png` ve `screenshot-3-en.png` (sırayla).
5. **Small promo tile**: `assets/promo-small-en.png`. **Marquee** isteğe bağlı: `assets/promo-marquee-en.png`.
6. **Homepage URL** ve **Support URL** alanlarını listing.md'deki adreslerle doldur.
7. Türkçe kayıt için sayfanın üstündeki dil seçiminden **Türkçe**'yi ekle. Türkçe açıklamayı yapıştır, `-tr`
   görsellerini yükle.
8. **Save draft**'a bas.

## 3. Privacy practices (Gizlilik) sekmesi

[listing.md](listing.md)'deki **2. Privacy practices** bölümünden kopyala:

1. **Single purpose description** alanını doldur.
2. **Permission justification** alanları her izin için ayrı çıkar: `downloads`, `contextMenus`, `storage`,
   `cookies`, `alarms`, `webRequest` ve **Host permission**. Hepsinin metni hazır.
3. **Are you using remote code?** sorusuna **No** de.
4. **Data usage** bölümünde **Authentication information**, **Web history** ve **Website content** kutularını
   işaretle. Altındaki üç beyan kutusunun üçünü de işaretle.
   - Neden bu üçü: eklenti çerezleri, linkleri ve sayfa başlıklarını işliyor. Bunlar yalnızca bilgisayarındaki
     uygulamaya gidiyor, ama eksiksiz beyan incelemede sorun çıkarmıyor. Eksik beyan ise ret sebebi.
5. **Privacy policy URL** alanına hazırlık adımındaki adresi yaz.
6. **Save draft**'a bas.

## 4. Distribution (Dağıtım) sekmesi ve test talimatı

1. Dağıtım için şunları seç: **Free of charge**, **Public**, **All regions**.
2. Panoda **Test instructions** bölümü varsa, listing.md'deki **3. Test instructions** metnini yapıştır.
   İnceleme ekibi uygulama olmadan eklentiyi deneyemez, bu metin uygulamayı nasıl kuracaklarını anlatıyor.

## 5. İncelemeye gönder

1. Sağ üstteki **Submit for review**'a bas.
2. Açılan pencerede **Publish automatically after review** seçeneği çıkar. Önerim bu seçeneği **kapatman**.
   Böylece onaydan sonra yayın anını sen seçersin ve uygulamanın güncellemesiyle aynı güne denk getirebilirsin.
3. İnceleme genelde birkaç gün sürer. Eklenti tüm sitelere erişip çerez okuduğu için ayrıntılı incelemeye
   alınabilir ve süre uzayabilir. Ret gelirse gerekçesini bana gönder, düzeltelim.

## 6. Kimliği bana gönder

**Item ID**'yi (1. adımın sonunda not ettiğin 32 harf) bana yaz. Ben de şunları yapacağım:

```bash
scripts/chrome-store.sh set-id <KİMLİK>
```

Bu komut kimliği macOS'ta `BrowserExtension.storeExtensionID`'ye, Windows'ta `BrowserExtension.StoreExtensionId`'ye
yazar. Sonrasında:

- Uygulama mağaza kimliğinden gelen istekleri de kabul eder. Paketlenmemiş kopyanın kimliği de kabul edilmeye
  devam eder, yani şu anki kullanıcılar etkilenmez.
- Kurulum ekranı ve Ayarlar kullanıcıyı mağaza sayfasına götürür. Geliştirici modundan yükleme yalnızca yedek
  yol olarak kalır.
- Paketlenmemiş kopyayı kullananlara Ayarlar'da "Mağazadan kur" önerisi çıkar. İki kopya birden kuruluysa
  eskisini kaldırmaları söylenir.

Kimliği taslak aşamasında da gönderebilirsin, ama uygulamanın bu kimlikle yayımlanan sürümü mağaza kaydı
**yayımlandıktan sonra** çıkmalı. Yoksa kurulum ekranındaki mağaza bağlantısı açılmaz.

## Sonraki sürümler

`scripts/release.sh X.Y.Z` her sürümde mağaza paketini de üretir: `dist/KDDownloadManager-Chrome-X.Y.Z.zip`.
Eklentinin kodu değişmediyse mağazayı güncellemek zorunlu değil. Mağazadaki sürüm uygulamanınkinden geride
kalsa da eklenti çalışır.

### Elle güncelleme

1. Panoda öğeyi aç, **Package > Upload new package**'a tıkla ve zip'i seç.
2. **Submit for review**'a bas.

### Otomatik güncelleme (Chrome Web Store API, isteğe bağlı)

Bir kez kurulur, sonra `CHROME_STORE=1 scripts/release.sh X.Y.Z` paketi yükleyip incelemeye kendisi gönderir.
Gizli bilgiler depoya yazılmaz, Mac'in Anahtar Zinciri'nde durur.

1. <https://console.cloud.google.com> adresinde bir proje oluştur (ör. "KD Chrome Store").
2. **APIs & Services > Library** bölümünde **Chrome Web Store API**'yi etkinleştir.
3. **OAuth consent screen** (Google Auth Platform) ayarları:
   - **External** türünü seç ve kendi e-postanı yaz.
   - Uygulamayı **In production** durumuna al. **Testing** durumunda yenileme jetonu 7 günde geçersiz oluyor.
     Doğrulama gerekmez, giriş sırasında bir "doğrulanmamış uygulama" uyarısı görürsün.
4. **Credentials > Create credentials > OAuth client ID** ile bir istemci oluştur:
   - Tür olarak **Web application** seç.
   - **Authorized redirect URI** alanına `https://developers.google.com/oauthplayground` yaz.
   - **Client ID** ve **Client secret**'ı not et.
5. <https://developers.google.com/oauthplayground> adresinde yenileme jetonunu al:
   1. Sağ üstteki dişliye tıkla, **Use your own OAuth credentials**'ı işaretle ve istemci bilgilerini gir.
   2. Kapsam olarak `https://www.googleapis.com/auth/chromewebstore` yaz, **Authorize APIs**'e tıkla ve geliştirici
      hesabınla giriş yap.
   3. **Exchange authorization code for tokens**'a tıkla ve **Refresh token**'ı not et.
6. **Publisher ID**: Geliştirici Panosu'nda **Account / Settings** sayfasında yazıyor.
7. Bilgileri Anahtar Zinciri'ne kaydet. Bu komutu kendi Terminal'inde çalıştır, değerleri sorar ve ekrana
   yazmaz:

   ```bash
   scripts/chrome-store.sh credentials
   ```

8. Denemek için şu komutu çalıştır. Öğenin yükleme ve inceleme durumunu göstermesi gerekir:

   ```bash
   scripts/chrome-store.sh status
   ```

Ayrı komutlar da var:

- `scripts/chrome-store.sh upload dist/KDDownloadManager-Chrome-X.Y.Z.zip` paketi taslak olarak yükler.
- `scripts/chrome-store.sh publish` taslağı incelemeye gönderir.

Bu bilgiler hesabına yükleme ve yayımlama yetkisi verir, kimseyle paylaşma. Jetonu iptal etmek için
<https://myaccount.google.com/permissions> adresini kullan.

## Görselleri yeniden üretmek

Arayüz değişirse görselleri şu komutla yeniden üret:

```bash
ChromeExtension/store/make-assets.sh
```

Komut uygulamanın geliştirme sürümünü örnek bir listeyle çizer, eklentinin gerçek açılır penceresini ve İndir
menüsünü sahte bir Chrome ortamında açar ve Chrome'un başsız moduyla, geçici bir profille görüntü alır. Gerçek
indirme listene ve tarayıcı profillerine dokunmaz.
