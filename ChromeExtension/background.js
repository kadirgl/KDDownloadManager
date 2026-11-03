import {
  QUALITIES, VIDEO_HOSTS, accentColor, classifyStream, describe, fetchFormats, flashBadge, isAppRunning,
  isDownloadable, isVideoPage, sayHello, sendStream, sendToApp, streamSaveAs,
} from "./app.js";

const MENU_LINK = "kd-link";
const MENU_MEDIA = "kd-media";
// Kalite alt menüleri: "kd-page:1080", "kd-video-link:audio" gibi.
const MENU_PAGE = "kd-page";
const MENU_VIDEO_LINK = "kd-video-link";
const HELLO_ALARM = "kd-hello";

const VIDEO_PATTERNS = VIDEO_HOSTS.flatMap((host) => [`*://${host}/*`, `*://*.${host}/*`]);

chrome.runtime.onInstalled.addListener(async () => {
  // Varsayılan: Chrome indirmelerini ve magnet linklerini uygulamaya devret.
  const { intercept } = await chrome.storage.local.get("intercept");
  if (intercept === undefined) {
    await chrome.storage.local.set({ intercept: true });
  }
  await createMenus();
  startHeartbeat();
});

chrome.runtime.onStartup.addListener(startHeartbeat);

// Uygulamanın Ayarlar ekranı eklentinin bağlı olduğunu bu sinyalden anlıyor.
function startHeartbeat() {
  chrome.alarms.create(HELLO_ALARM, { periodInMinutes: 1 });
  sayHello();
}

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === HELLO_ALARM) sayHello();
});

async function createMenus() {
  // Eklenti yeniden yüklendiğinde aynı kimlikle tekrar oluşturmak hata verir; önce temizle.
  await chrome.contextMenus.removeAll();
  // Linklerde ve resimlerde. Resim bir linkin içindeyse (Google Görseller gibi) linkin götürdüğü sayfa
  // değil resmin kendisi indirilir.
  chrome.contextMenus.create({
    id: MENU_LINK,
    title: "KD Download Manager ile indir",
    contexts: ["link", "image"],
  });
  chrome.contextMenus.create({
    id: MENU_MEDIA,
    title: "Bu medyayı KD Download Manager ile indir",
    contexts: ["video", "audio"],
  });

  // Herhangi bir sayfadaki videoyu kalite seçerek indirme (yt-dlp ~1.800 siteyi tanıyor) ve video
  // sitelerindeki video linkleri (örn. küçük resimler).
  chrome.contextMenus.create({
    id: MENU_PAGE,
    title: "Bu sayfadaki videoyu KD Download Manager ile indir",
    contexts: ["page"],
    documentUrlPatterns: ["http://*/*", "https://*/*"],
  });
  chrome.contextMenus.create({
    id: MENU_VIDEO_LINK,
    title: "Videoyu kalite seçerek indir",
    contexts: ["link"],
    targetUrlPatterns: VIDEO_PATTERNS,
  });
  for (const quality of QUALITIES) {
    for (const parentId of [MENU_PAGE, MENU_VIDEO_LINK]) {
      chrome.contextMenus.create({
        id: `${parentId}:${quality.id}`,
        parentId,
        title: quality.title,
        contexts: parentId === MENU_PAGE ? ["page"] : ["link"],
      });
    }
  }
}

// Sağ tık menüsü
chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  const [menu, quality] = String(info.menuItemId).split(":");
  let url;
  switch (menu) {
    case MENU_LINK:
      if (info.mediaType === "image" && info.srcUrl) {
        flashBadge(await downloadImage(info.srcUrl, { pageUrl: info.pageUrl, pageTitle: tab?.title }));
        return;
      }
      url = info.linkUrl;
      break;
    case MENU_MEDIA: {
      // Doğrudan bir dosya oynatılıyorsa onu indir; oynatıcı blob: adresi kullanıyorsa (çoğu site) ya da
      // site yt-dlp'nin özel olarak tanıdığı bir siteyse sayfanın kendisini yt-dlp'ye gönder.
      if (isDownloadable(info.srcUrl) && !isVideoPage(info.pageUrl)) {
        const extension = info.srcUrl.match(/\.(mp4|webm|m4v|mov|mkv|mp3|m4a|ogg|wav)(\?|$)/i)?.[1] ?? "mp4";
        const saveAs = streamSaveAs({ kind: "file", extension }, tab?.title);
        flashBadge(await sendToApp([await describe(info.srcUrl, { referrer: info.pageUrl, saveAs })]));
        return;
      }
      flashBadge(await sendToApp([await describe(info.pageUrl, { referrer: info.pageUrl, video: true })]));
      return;
    }
    case MENU_PAGE:
      flashBadge(await sendToApp([await describe(info.pageUrl, { referrer: info.pageUrl, video: true, quality })]));
      return;
    case MENU_VIDEO_LINK:
      url = info.linkUrl;
      break;
    default:
      return;
  }
  if (!isDownloadable(url)) {
    flashBadge(false);
    return;
  }
  const ok = await sendToApp([await describe(url, { referrer: tab?.url, quality })]);
  flashBadge(ok);
});

// --- Resim indirme ------------------------------------------------------------------------------

const IMAGE_TYPES = {
  "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp", "image/gif": "gif", "image/avif": "avif",
  "image/svg+xml": "svg", "image/bmp": "bmp", "image/tiff": "tiff", "image/heic": "heic", "image/x-icon": "ico",
};

// Sağ tıklanan resmi indirir. Adresinde uzantı yoksa (örn. "images?q=…") türü sunucudan öğrenilir ve
// ad sayfanın başlığından verilir. data:/blob: resimleri uygulama açamadığı için Chrome indirir.
async function downloadImage(src, { pageUrl, pageTitle }) {
  if (!/^https?:/i.test(src)) {
    try {
      const extension = IMAGE_TYPES[src.match(/^data:([^;,]+)/i)?.[1]?.toLowerCase()] ?? "png";
      await chrome.downloads.download({ url: src, filename: `${imageBaseName(pageTitle)}.${extension}` });
      return true;
    } catch {
      return false;
    }
  }
  const request = await describe(src, { referrer: pageUrl });
  const fromPath = decodeURIComponent(new URL(src).pathname.split("/").pop() || "");
  if (!/\.(jpe?g|png|webp|gif|avif|svg|bmp|tiff?|heic|ico)$/i.test(fromPath)) {
    request.saveAs = `${imageBaseName(pageTitle)}.${await imageExtension(src)}`;
  }
  return sendToApp([request]);
}

function imageBaseName(pageTitle) {
  const title = (pageTitle || "").replace(/[\\/:*?"<>|]+/g, " ").replace(/\s+/g, " ").trim().slice(0, 60);
  return title || "Resim";
}

async function imageExtension(src) {
  try {
    const response = await fetch(src, { method: "HEAD", signal: AbortSignal.timeout(3000) });
    const type = (response.headers.get("content-type") ?? "").split(";")[0].trim().toLowerCase();
    return IMAGE_TYPES[type] ?? "jpg";
  } catch {
    return "jpg";
  }
}

// Sayfadaki "İndir" butonları (YouTube ve diğer sitelerdeki videolar) ve açılır pencere: uygulama
// durumu, kalite listesi, yakalanan akışlar ve indirme. İçerik betikleri sayfanın kökeninde çalıştığı
// için uygulamaya istekleri arka plan yapıyor.
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  const isPage = (url) => /^https?:/i.test(url ?? "");
  const handlers = {
    "video-status": async () => ({ running: await isAppRunning(), accent: await accentColor() }),
    // yt-dlp bu sayfada video bulabiliyor mu; bulamazsa null.
    "video-formats": async () => (isPage(message.url) ? fetchFormats(message.url) : null),
    "video-download": async () => {
      if (!isPage(message.url)) return false;
      const ok = await sendToApp([await describe(message.url, {
        referrer: sender.tab?.url ?? message.url, quality: message.quality, video: true,
      })]);
      flashBadge(ok);
      return ok;
    },
    // Bu sekmede yakalanan video akışları (açılır pencere sekme kimliğini kendisi gönderiyor).
    "streams": async () => tabStreams(message.tabId ?? sender.tab?.id),
    "stream-download": async () => {
      // Gömülü oynatıcıdaki (iframe) videonun sunucusu genelde oynatıcının adresini referrer bekliyor.
      const ok = await sendStream(message.stream, {
        pageUrl: sender.url ?? sender.tab?.url ?? message.pageUrl,
        pageTitle: sender.tab?.title ?? message.pageTitle,
        quality: message.quality,
      });
      flashBadge(ok);
      return ok;
    },
  };
  const handler = handlers[message?.type];
  if (!handler) return false;
  handler().then(sendResponse, () => sendResponse(null));
  return true; // Cevap asenkron.
});

// İçerik betiğinden gelen magnet tıklamaları; cevap false ise sayfa linki normal şekilde açar.
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message?.type !== "magnet") return false;
  (async () => {
    const { intercept } = await chrome.storage.local.get("intercept");
    if (intercept === false || sender.tab?.incognito || !isDownloadable(message.url)) {
      sendResponse(false);
      return;
    }
    const ok = await sendToApp([{ url: message.url, referrer: message.referrer }]);
    if (ok) flashBadge(true);
    sendResponse(ok);
  })();
  return true; // Cevap asenkron.
});

// Chrome'un başlattığı indirmeleri yakala: uygulama kabul ederse Chrome'unkini iptal et.
// Uygulama kapalıysa ya da reddederse Chrome normal şekilde indirmeye devam eder.
const TAKE_OVER_WAIT = 15000;

const succeeds = (promise) => promise.then(() => true, () => false);

chrome.downloads.onCreated.addListener(async (download) => {
  if (!shouldTake(download)) return;
  const { intercept } = await chrome.storage.local.get("intercept");
  if (intercept === false) return;

  // Uygulama adresi yoklarken (birkaç saniye) Chrome hızlı inen dosyayı (Google Drive gibi) bitirmiş
  // oluyordu; iptal boşa gidip dosya hem Chrome'da hem uygulamada iniyordu. Önce duraklatılır; bu arada
  // bitmiş ya da iptal edilmişse Chrome'unki kalır, uygulamaya gönderilmez.
  if (!(await succeeds(chrome.downloads.pause(download.id)))) return;

  const url = download.finalUrl || download.url;
  const filename = download.filename ? download.filename.split(/[\\/]/).pop() : undefined;
  const request = await describe(url, { referrer: download.referrer, filename });
  // Uygulama adresi yoklayıp (aynı çerez ve referrer'la) yeniden indirilemiyorsa reddediyor; o zaman
  // Chrome'un indirmesi kaldığı yerden sürer. Uygulama yoklamayı TAKE_OVER_WAIT'ten önce bitiriyor; bu
  // süre ondan uzun olmalı, yoksa geç gelen "kabul" Chrome'unki sürerken uygulamada da indirme başlatır.
  request.fromBrowserDownload = true;
  if (download.mime) request.mime = download.mime;
  const ok = await sendToApp([request], { timeout: TAKE_OVER_WAIT });
  if (!ok) {
    await succeeds(chrome.downloads.resume(download.id));
    return;
  }

  await succeeds(chrome.downloads.cancel(download.id));
  await succeeds(chrome.downloads.erase({ id: download.id }));
  flashBadge(true);
});

// Dosyayı sayfanın içinde (service worker ya da şifre çözme ile) üreten siteler: adres sunucudan yeniden
// istenince dosya değil sayfa geliyor. Bunların indirmeleri hiç devralınmaz, Chrome indirir.
const IN_PAGE_DOWNLOAD_HOSTS = ["web.whatsapp.com", "web.telegram.org", "mega.nz", "mega.io", "app.element.io"];

function downloadsInPage(download) {
  const host = (url) => { try { return new URL(url).hostname; } catch { return ""; } };
  return [download.finalUrl, download.url, download.referrer].some((url) =>
    IN_PAGE_DOWNLOAD_HOSTS.some((h) => host(url) === h || host(url).endsWith("." + h)));
}

function shouldTake(download) {
  return download.state === "in_progress"
    && !download.incognito // Gizli pencerede indirilenler uygulamanın listesine düşmesin.
    && isDownloadable(download.finalUrl || download.url)
    && !downloadsInPage(download);
}

// --- Sayfalarda oynatılan video akışlarını yakalama ---------------------------------------------
// yt-dlp'nin tanımadığı sitelerde video, sayfanın açtığı HLS/DASH listesi ya da doğrudan dosya olarak
// gelir; bunlar ağ trafiğinden yakalanıp sekme başına (en fazla 15) saklanır. Araç çubuğu ikonunda o
// sekmede bulunan akış sayısı görünür.

const STREAM_LIMIT = 15;
const streamKey = (tabId) => `streams:${tabId}`;

async function tabStreams(tabId) {
  if (tabId === undefined || tabId < 0) return [];
  const stored = await chrome.storage.session.get(streamKey(tabId));
  return stored[streamKey(tabId)] ?? [];
}

// Oynatıcı ana listeyi ve kalite listelerini aynı anda ister; okuyup yazma sıraya alınmazsa biri kaybolur.
let streamQueue = Promise.resolve();

function rememberStream(tabId, stream) {
  streamQueue = streamQueue.then(() => saveStream(tabId, stream)).catch(() => {});
}

async function saveStream(tabId, stream) {
  const streams = await tabStreams(tabId);
  if (streams.some((s) => s.url === stream.url)) return;
  const updated = [stream, ...streams].slice(0, STREAM_LIMIT);
  await chrome.storage.session.set({ [streamKey(tabId)]: updated });
  chrome.action.setBadgeBackgroundColor({ tabId, color: await accentColor() });
  chrome.action.setBadgeText({ tabId, text: String(updated.length) });
}

async function forgetStreams(tabId) {
  await chrome.storage.session.remove(streamKey(tabId));
  chrome.action.setBadgeText({ tabId, text: "" }).catch(() => {});
}

chrome.webRequest.onHeadersReceived.addListener(
  (details) => {
    if (details.tabId < 0) return;
    const stream = classifyStream(details.url, details.responseHeaders);
    if (stream) rememberStream(details.tabId, { ...stream, url: details.url, time: Date.now() });
  },
  { urls: ["http://*/*", "https://*/*"], types: ["media", "xmlhttprequest", "other"] },
  ["responseHeaders"],
);

// Sayfa değişince (tek sayfalık uygulamalarda adres değişince de) eski sayfanın akışları silinir.
chrome.tabs.onUpdated.addListener((tabId, change) => {
  if (change.url) forgetStreams(tabId);
});
chrome.tabs.onRemoved.addListener((tabId) => forgetStreams(tabId));
