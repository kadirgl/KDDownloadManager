// KD Download Manager uygulamasıyla konuşma: uygulama 127.0.0.1:47615'te dinliyor ve
// sadece bu eklentinin kimliğinden (manifest'teki "key") gelen istekleri kabul ediyor.

export const APP_URL = "http://127.0.0.1:47615";

// Uygulamanın video motoruna (yt-dlp) giden siteler; uygulamadaki DownloadSource ile aynı liste.
export const VIDEO_HOSTS = [
  "youtube.com", "youtu.be", "vimeo.com", "dailymotion.com", "twitch.tv",
  "twitter.com", "x.com", "instagram.com", "tiktok.com", "facebook.com",
];

// Video kalite seçenekleri; uygulamadaki VideoQuality ile aynı değerler.
export const QUALITIES = [
  { id: "auto", title: "Otomatik (önerilen)" },
  { id: "2160", title: "2160p (4K)" },
  { id: "1440", title: "1440p" },
  { id: "1080", title: "1080p" },
  { id: "720", title: "720p" },
  { id: "480", title: "480p" },
  { id: "360", title: "360p" },
  { id: "audio", title: "Sadece ses (MP3)" },
];

export function isVideoPage(url) {
  try {
    const host = new URL(url).hostname;
    return VIDEO_HOSTS.some((h) => host === h || host.endsWith("." + h));
  } catch {
    return false;
  }
}

// Uygulamanın indirebileceği linkler (blob:, data:, file: gibi tarayıcıya özel adresler değil).
export function isDownloadable(url) {
  return /^(https?|ftp):\/\//i.test(url ?? "") || /^magnet:/i.test(url ?? "");
}

export const DEFAULT_ACCENT = "#F08A2E";

// Uygulama çalışıyor mu; çalışıyorsa uygulamada seçilen vurgu rengini de saklar (açılır pencere ve
// YouTube butonu aynı rengi kullanıyor).
export async function isAppRunning() {
  try {
    // GET olursa Chrome Origin başlığını göndermiyor ve uygulama isteği reddediyor; POST kullan.
    const response = await fetch(`${APP_URL}/ping`, { method: "POST", signal: AbortSignal.timeout(1500) });
    if (!response.ok) return false;
    const info = await response.json().catch(() => ({}));
    if (/^#[0-9A-F]{6}$/i.test(info.accent ?? "")) {
      await chrome.storage.local.set({ accent: info.accent });
    }
    return true;
  } catch {
    return false;
  }
}

export async function accentColor() {
  const { accent } = await chrome.storage.local.get("accent");
  return accent ?? DEFAULT_ACCENT;
}

// Uygulamanın Ayarlar ekranında görünen ad (Google Chrome, Microsoft Edge, Brave…).
export function browserName() {
  if (navigator.brave) return "Brave";
  const brand = (navigator.userAgentData?.brands ?? [])
    .map((b) => b.brand)
    .find((name) => !/not.?a.?brand|chromium/i.test(name));
  return brand ?? "Chromium tabanlı tarayıcı";
}

// Eklentinin sürümü uygulamanınkiyle aynı gider. Uygulama güncellenince eklentinin klasörü de yenileniyor;
// tarayıcı eski dosyaları kullanmaya devam etmesin diye eklenti, klasördeki sürüm kendisininkinden farklıysa
// kendini yeniden yükler. Eklenti başka bir klasörden yüklendiyse yeniden yükleme sürümü değiştirmez;
// döngüye girmemek için her sürüm için yalnızca bir kez denenir.
async function reloadIfUpdated(available) {
  const current = chrome.runtime.getManifest().version;
  if (typeof available !== "string" || !/^\d+(\.\d+)*$/.test(available) || available === current) return false;
  const { reloadedFor } = await chrome.storage.local.get("reloadedFor");
  if (reloadedFor === available) return false;
  await chrome.storage.local.set({ reloadedFor: available });
  chrome.runtime.reload();
  return true;
}

// Uygulamaya "buradayım" der; Ayarlar'daki bağlantı göstergesi bundan beslenir.
// Uygulama cevapta çereze ihtiyaç duyduğu video sitelerini bildirir (örn. panelden eklenen ya da
// yeniden açılışta devam eden bir YouTube indirmesi); o sitelerin çerezleri hemen gönderilir.
export async function sayHello() {
  try {
    const response = await fetch(`${APP_URL}/hello`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ browser: browserName(), version: chrome.runtime.getManifest().version }),
      signal: AbortSignal.timeout(1500),
    });
    const { wantsCookies = [], extensionVersion } = await response.json().catch(() => ({}));
    if (await reloadIfUpdated(extensionVersion)) return;
    for (const site of wantsCookies.filter((s) => VIDEO_HOSTS.includes(s))) {
      await fetch(`${APP_URL}/cookies`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ site, cookieJar: await siteCookies(site) }),
        signal: AbortSignal.timeout(3000),
      });
    }
  } catch {
    // Uygulama kapalı; bir sonraki denemede.
  }
}

// Video sitelerinin ana alan adı (www.youtube.com → youtube.com); video sitesi değilse null.
export function videoSite(url) {
  try {
    const host = new URL(url).hostname;
    const site = VIDEO_HOSTS.find((h) => host === h || host.endsWith("." + h)) ?? null;
    return site === "youtu.be" ? "youtube.com" : site; // Kısa linklerin çerezleri youtube.com'da.
  } catch {
    return null;
  }
}

// Bir sitenin tüm çerezleri, yt-dlp'nin istediği ayrıntılarla. YouTube çerezsiz isteklere sık sık
// "robot olmadığınızı doğrulayın" diyor; tarayıcıdaki oturumun çerezleriyle bu aşılıyor.
export async function siteCookies(site) {
  try {
    const cookies = await chrome.cookies.getAll({ domain: site });
    return cookies.map((c) => ({
      domain: c.domain, path: c.path, name: c.name, value: c.value, secure: c.secure,
      httpOnly: c.httpOnly, hostOnly: c.hostOnly, expirationDate: c.expirationDate,
    }));
  } catch {
    return [];
  }
}

// Videonun sunduğu kaliteleri ve tahmini boyutları uygulamadan (yt-dlp) ister; olmazsa null.
export async function fetchFormats(url) {
  try {
    const response = await fetch(`${APP_URL}/formats`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ url, cookieJar: await siteCookies(videoSite(url) ?? hostSite(url)) }),
      signal: AbortSignal.timeout(30000),
    });
    return response.ok ? await response.json() : null;
  } catch {
    return null;
  }
}

// Bir indirme isteğini, giriş gerektiren siteler için çerez ve referrer bilgisiyle hazırlar.
export async function describe(url, { referrer, filename, quality, video, saveAs } = {}) {
  const request = { url, userAgent: navigator.userAgent };
  if (referrer) request.referrer = referrer;
  if (filename) request.filename = filename;
  if (quality) request.quality = quality;
  if (video) request.video = true;
  if (saveAs) request.saveAs = saveAs;
  const site = videoSite(url);
  if (site || video) {
    // yt-dlp'ye gidecek: video sitesinin (ya da akışın ve bulunduğu sayfanın) tüm çerezleri.
    const sites = new Set([site ?? hostSite(url), referrer && hostSite(referrer)].filter(Boolean));
    request.cookieJar = (await Promise.all([...sites].map(siteCookies))).flat();
  } else if (/^https?:/i.test(url)) {
    try {
      const cookies = await chrome.cookies.getAll({ url });
      if (cookies.length > 0) {
        request.cookies = cookies.map((c) => `${c.name}=${c.value}`).join("; ");
      }
    } catch {
      // Çerez okunamazsa çerezsiz gönder.
    }
  }
  return request;
}

// Adresin alan adı (www. olmadan): çerezleri o alan ve alt alanları için okumak için.
export function hostSite(url) {
  try {
    return new URL(url).hostname.replace(/^www\./, "");
  } catch {
    return null;
  }
}

// --- Sayfalarda oynatılan video akışlarını yakalama -------------------------------------------

const MIN_VIDEO_FILE = 1024 * 1024;

// Bir ağ yanıtı indirilebilir bir video akışı mı: HLS/DASH listesi ya da doğrudan video dosyası.
// Akışın parçaları (.ts, .m4s), altyazılar ve küçük dosyalar (önizleme, reklam) sayılmaz.
// YouTube'un kendi parçalı adresleri (googlevideo) zaten yt-dlp ile indiriliyor.
export function classifyStream(url, headers = []) {
  let parsed;
  try {
    parsed = new URL(url);
  } catch {
    return null;
  }
  if (!/^https?:$/.test(parsed.protocol)) return null;
  if (/(^|\.)googlevideo\.com$/.test(parsed.hostname)) return null;
  const path = parsed.pathname.toLowerCase();
  if (/\.(ts|m4s|m4a|aac|mp3|vtt|webvtt|srt|key|jpg|png|webp)$/.test(path)) return null;

  const header = (name) => headers.find((h) => h.name.toLowerCase() === name)?.value ?? "";
  const type = header("content-type").split(";")[0].trim().toLowerCase();
  if (path.endsWith(".m3u8") || type === "application/vnd.apple.mpegurl" || type === "application/x-mpegurl") {
    return { kind: "hls" };
  }
  if (path.endsWith(".mpd") || type === "application/dash+xml") {
    return { kind: "dash" };
  }
  if (type.startsWith("video/") || /\.(mp4|webm|m4v|mov|mkv)$/.test(path)) {
    // Parça parça (Range) istenen dosyada toplam boyut Content-Range'te: "bytes 0-1/12345678".
    const total = Number(header("content-range").split("/")[1]) || Number(header("content-length")) || 0;
    if (total < MIN_VIDEO_FILE) return null;
    const extension = path.match(/\.(mp4|webm|m4v|mov|mkv)$/)?.[1]
      ?? { "video/webm": "webm", "video/quicktime": "mov", "video/x-matroska": "mkv" }[type] ?? "mp4";
    return { kind: "file", size: total, extension };
  }
  return null;
}

// Yakalanan akışın kaydedileceği ad: sayfanın başlığı (akış adresleri "index.m3u8" gibi anlamsız).
export function streamSaveAs(stream, pageTitle) {
  const title = (pageTitle || "Video").replace(/[\\/:*?"<>|]+/g, " ").replace(/\s+/g, " ").trim().slice(0, 120);
  return stream.kind === "file" ? `${title}.${stream.extension}` : title;
}

// Yakalanan akışı uygulamaya gönderir: HLS/DASH yt-dlp ile, doğrudan dosya parçalı aria2 ile iner.
export async function sendStream(stream, { pageUrl, pageTitle, quality } = {}) {
  const request = await describe(stream.url, {
    referrer: pageUrl,
    video: stream.kind !== "file",
    quality,
    saveAs: streamSaveAs(stream, pageTitle),
  });
  return sendToApp([request]);
}

export function streamLabel(stream) {
  const name = decodeURIComponent(new URL(stream.url).pathname.split("/").pop() || "akış");
  const kind = { hls: "HLS akışı", dash: "DASH akışı", file: "Video dosyası" }[stream.kind];
  const size = stream.size ? ` · ${(stream.size / 1048576).toFixed(0)} MB` : "";
  return { kind, name: name.length > 40 ? `${name.slice(0, 37)}…` : name, size };
}

// İstekleri uygulamaya yollar; uygulama kabul ettiyse true döner.
// `timeout`: Chrome'dan devralınan indirmelerde uygulama adresi önce yokluyor, biraz daha bekle.
export async function sendToApp(requests, { timeout = 3000 } = {}) {
  try {
    const response = await fetch(`${APP_URL}/add`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ links: requests }),
      signal: AbortSignal.timeout(timeout),
    });
    return response.ok;
  } catch {
    return false;
  }
}

// Araç çubuğu ikonunda kısa bir sonuç işareti: ✓ gönderildi, ! uygulamaya ulaşılamadı.
export function flashBadge(ok) {
  chrome.action.setBadgeBackgroundColor({ color: ok ? DEFAULT_ACCENT : "#D93025" });
  chrome.action.setBadgeText({ text: ok ? "✓" : "!" });
  setTimeout(() => chrome.action.setBadgeText({ text: "" }), 2500);
}
