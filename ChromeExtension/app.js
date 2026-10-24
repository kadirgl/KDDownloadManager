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

export const DEFAULT_ACCENT = "#FF8500";

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

// Uygulamaya "buradayım" der; Ayarlar'daki bağlantı göstergesi bundan beslenir.
export async function sayHello() {
  try {
    await fetch(`${APP_URL}/hello`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ browser: browserName(), version: chrome.runtime.getManifest().version }),
      signal: AbortSignal.timeout(1500),
    });
  } catch {
    // Uygulama kapalı; bir sonraki denemede.
  }
}

// Videonun sunduğu kaliteleri ve tahmini boyutları uygulamadan (yt-dlp) ister; olmazsa null.
export async function fetchFormats(url) {
  try {
    const response = await fetch(`${APP_URL}/formats`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ url }),
      signal: AbortSignal.timeout(30000),
    });
    return response.ok ? await response.json() : null;
  } catch {
    return null;
  }
}

// Bir indirme isteğini, giriş gerektiren siteler için çerez ve referrer bilgisiyle hazırlar.
export async function describe(url, { referrer, filename, quality } = {}) {
  const request = { url, userAgent: navigator.userAgent };
  if (referrer) request.referrer = referrer;
  if (filename) request.filename = filename;
  if (quality) request.quality = quality;
  if (/^https?:/i.test(url)) {
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

// İstekleri uygulamaya yollar; uygulama kabul ettiyse true döner.
export async function sendToApp(requests) {
  try {
    const response = await fetch(`${APP_URL}/add`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ links: requests }),
      signal: AbortSignal.timeout(3000),
    });
    return response.ok;
  } catch {
    return false;
  }
}

// Araç çubuğu ikonunda kısa bir sonuç işareti: ✓ gönderildi, ! uygulamaya ulaşılamadı.
export function flashBadge(ok) {
  chrome.action.setBadgeBackgroundColor({ color: ok ? "#FF8500" : "#D93025" });
  chrome.action.setBadgeText({ text: ok ? "✓" : "!" });
  setTimeout(() => chrome.action.setBadgeText({ text: "" }), 2500);
}
