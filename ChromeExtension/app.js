// KD Download Manager uygulamasıyla konuşma: uygulama 127.0.0.1:47615'te dinliyor ve
// sadece bu eklentinin kimliğinden (manifest'teki "key") gelen istekleri kabul ediyor.

export const APP_URL = "http://127.0.0.1:47615";

// Uygulamanın video motoruna (yt-dlp) giden siteler; uygulamadaki DownloadSource ile aynı liste.
export const VIDEO_HOSTS = [
  "youtube.com", "youtu.be", "vimeo.com", "dailymotion.com", "twitch.tv",
  "twitter.com", "x.com", "instagram.com", "tiktok.com", "facebook.com",
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

export async function isAppRunning() {
  try {
    const response = await fetch(`${APP_URL}/ping`, { signal: AbortSignal.timeout(1500) });
    return response.ok;
  } catch {
    return false;
  }
}

// Bir indirme isteğini, giriş gerektiren siteler için çerez ve referrer bilgisiyle hazırlar.
export async function describe(url, { referrer, filename } = {}) {
  const request = { url, userAgent: navigator.userAgent };
  if (referrer) request.referrer = referrer;
  if (filename) request.filename = filename;
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
