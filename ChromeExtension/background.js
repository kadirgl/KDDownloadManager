import {
  QUALITIES, VIDEO_HOSTS, accentColor, describe, fetchFormats, flashBadge, isAppRunning, isDownloadable,
  isVideoPage, sayHello, sendToApp,
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
  chrome.contextMenus.create({
    id: MENU_LINK,
    title: "KD Download Manager ile indir",
    contexts: ["link"],
  });
  chrome.contextMenus.create({
    id: MENU_MEDIA,
    title: "Bu medyayı KD Download Manager ile indir",
    contexts: ["video", "audio"],
  });

  // Video sitelerinde kalite seçerek indirme: sayfanın kendisi ve video linkleri (örn. küçük resimler).
  chrome.contextMenus.create({
    id: MENU_PAGE,
    title: "Bu videoyu KD Download Manager ile indir",
    contexts: ["page"],
    documentUrlPatterns: VIDEO_PATTERNS,
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
      url = info.linkUrl;
      break;
    case MENU_MEDIA:
      // Video sitelerinde oynatıcı genelde blob: adresi kullanır; o zaman sayfanın kendisini gönder (yt-dlp çözer).
      url = isDownloadable(info.srcUrl) ? info.srcUrl : info.pageUrl;
      break;
    case MENU_PAGE:
      url = info.pageUrl;
      break;
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

// YouTube sayfasındaki "İndir" butonu: uygulama durumu, kalite listesi ve indirme.
// İçerik betikleri sayfanın kökeninde çalıştığı için uygulamaya istekleri arka plan yapıyor.
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  const handlers = {
    "video-status": async () => ({ running: await isAppRunning(), accent: await accentColor() }),
    "video-formats": async () => (isVideoPage(message.url) ? fetchFormats(message.url) : null),
    "video-download": async () => {
      if (!isVideoPage(message.url)) return false;
      const ok = await sendToApp([await describe(message.url, { referrer: sender.tab?.url, quality: message.quality })]);
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
chrome.downloads.onCreated.addListener(async (download) => {
  const { intercept } = await chrome.storage.local.get("intercept");
  if (intercept === false || !shouldTake(download)) return;

  const url = download.finalUrl || download.url;
  const filename = download.filename ? download.filename.split(/[\\/]/).pop() : undefined;
  const ok = await sendToApp([await describe(url, { referrer: download.referrer, filename })]);
  if (!ok) return;

  try {
    await chrome.downloads.cancel(download.id);
    await chrome.downloads.erase({ id: download.id });
  } catch {
    // İndirme bu arada bitmiş ya da kullanıcı iptal etmiş olabilir.
  }
  flashBadge(true);
});

function shouldTake(download) {
  return download.state === "in_progress"
    && !download.incognito // Gizli pencerede indirilenler uygulamanın listesine düşmesin.
    && isDownloadable(download.finalUrl || download.url);
}
