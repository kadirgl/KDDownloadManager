import { VIDEO_HOSTS, describe, flashBadge, isDownloadable, sendToApp } from "./app.js";

const MENU_LINK = "kd-link";
const MENU_MEDIA = "kd-media";
const MENU_PAGE = "kd-page";

const VIDEO_PAGE_PATTERNS = VIDEO_HOSTS.flatMap((host) => [`*://${host}/*`, `*://*.${host}/*`]);

chrome.runtime.onInstalled.addListener(async () => {
  // Varsayılan: Chrome indirmelerini uygulamaya devret.
  const { intercept } = await chrome.storage.local.get("intercept");
  if (intercept === undefined) {
    await chrome.storage.local.set({ intercept: true });
  }

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
  chrome.contextMenus.create({
    id: MENU_PAGE,
    title: "Bu sayfadaki videoyu KD Download Manager ile indir",
    contexts: ["page"],
    documentUrlPatterns: VIDEO_PAGE_PATTERNS,
  });
});

// Sağ tık menüsü
chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  let url;
  switch (info.menuItemId) {
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
    default:
      return;
  }
  if (!isDownloadable(url)) {
    flashBadge(false);
    return;
  }
  const ok = await sendToApp([await describe(url, { referrer: tab?.url })]);
  flashBadge(ok);
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
