import {
  QUALITIES, accentColor, describe, fetchFormats, isAppRunning, isDownloadable, isVideoPage, sendStream,
  sendToApp, streamLabel,
} from "./app.js";

const status = document.getElementById("status");
const statusText = document.getElementById("status-text");
const intercept = document.getElementById("intercept");
const video = document.getElementById("video");
const videoTitle = document.getElementById("video-title");
const qualities = document.getElementById("qualities");
const sendPage = document.getElementById("send-page");
const streams = document.getElementById("streams");
const streamList = document.getElementById("stream-list");
const message = document.getElementById("message");

function showMessage(text, kind) {
  message.textContent = text;
  message.dataset.kind = kind ?? "";
}

function formatSize(bytes) {
  if (!bytes) return "";
  const mb = bytes / 1048576;
  return mb >= 1024 ? `~${(mb / 1024).toFixed(1).replace(".", ",")} GB` : `~${Math.round(mb)} MB`;
}

// video: adres bilinen bir video sitesi olmasa da yt-dlp ile video olarak indirilsin.
async function send(url, quality, video) {
  const ok = await sendToApp([await describe(url, { referrer: url, quality, video })]);
  showMessage(ok ? "KD Download Manager'a gönderildi." : "Uygulamaya ulaşılamadı.", ok ? "ok" : "error");
  return ok;
}

// Kalite düğmelerini çizer; uygulama listeyi veremezse sabit liste kullanılır.
function renderQualities(url, options, video) {
  qualities.replaceChildren();
  for (const option of options) {
    const button = document.createElement("button");
    if (option.quality === "auto") button.classList.add("recommended");
    const title = document.createElement("span");
    title.textContent = option.title;
    const size = document.createElement("span");
    size.className = "size";
    size.textContent = formatSize(option.size);
    button.append(title, size);
    button.addEventListener("click", async () => {
      qualities.querySelectorAll("button").forEach((b) => { b.disabled = true; });
      const ok = await send(url, option.quality, video);
      if (ok) setTimeout(() => window.close(), 900);
      else qualities.querySelectorAll("button").forEach((b) => { b.disabled = false; });
    });
    qualities.append(button);
  }
}

async function showVideo(url) {
  video.hidden = false;
  const fallback = QUALITIES.map((q) => ({ quality: q.id, title: q.title, size: null }));
  const formats = await fetchFormats(url);
  if (formats?.options?.length) {
    videoTitle.textContent = formats.title;
    renderQualities(url, formats.options.map((o) => ({ ...o, title: o.quality === "auto" ? "Otomatik (önerilen)" : o.title })));
  } else {
    videoTitle.textContent = "Kalite seçin";
    renderQualities(url, fallback);
  }
}

// Video sitesi olmayan sayfa: yt-dlp sayfada video bulabilirse kaliteleri gösterilir, bulamazsa
// "Bu sayfayı indir" düğmesi. Sayfa oynatırken yakalanan akışlar ayrıca listelenir.
async function showAnyPage(tab) {
  video.hidden = false;
  videoTitle.textContent = "Video aranıyor…";
  const [formats] = await Promise.all([fetchFormats(tab.url), showStreams(tab)]);
  if (formats?.options?.length) {
    videoTitle.textContent = formats.title;
    renderQualities(tab.url, formats.options.map((o) => ({ ...o, title: o.quality === "auto" ? "Otomatik (önerilen)" : o.title })), true);
    return;
  }
  video.hidden = true;
  sendPage.hidden = false;
  sendPage.addEventListener("click", async () => {
    sendPage.disabled = true;
    await send(tab.url);
    sendPage.disabled = false;
  });
}

async function showStreams(tab) {
  const key = `streams:${tab.id}`;
  const found = (await chrome.storage.session.get(key))[key] ?? [];
  if (found.length === 0) return;
  streams.hidden = false;
  streamList.replaceChildren();
  for (const stream of found) {
    const label = streamLabel(stream);
    const button = document.createElement("button");
    const text = document.createElement("span");
    text.className = "stream";
    const kind = document.createElement("span");
    kind.textContent = label.kind + label.size;
    const name = document.createElement("span");
    name.textContent = label.name;
    text.append(kind, name);
    button.title = stream.url;
    button.append(text);
    button.addEventListener("click", async () => {
      button.disabled = true;
      const ok = await sendStream(stream, { pageUrl: tab.url, pageTitle: tab.title });
      showMessage(ok ? "KD Download Manager'a gönderildi." : "Uygulamaya ulaşılamadı.", ok ? "ok" : "error");
      if (ok) setTimeout(() => window.close(), 900);
      else button.disabled = false;
    });
    streamList.append(button);
  }
}

async function init() {
  const stored = await chrome.storage.local.get("intercept");
  intercept.checked = stored.intercept !== false;
  intercept.addEventListener("change", () => {
    chrome.storage.local.set({ intercept: intercept.checked });
  });

  const running = await isAppRunning();
  // Uygulamada seçilen vurgu rengi.
  document.documentElement.style.setProperty("--accent", await accentColor());
  status.dataset.state = running ? "connected" : "offline";
  statusText.textContent = running ? "Uygulamaya bağlı" : "Uygulama çalışmıyor";
  if (!running) {
    showMessage("KD Download Manager'ı açın. Açılana kadar indirmeleri tarayıcı yapar.");
  }

  // Açılır pencere açıldığında activeTab izniyle sekmenin adresi okunabiliyor.
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab?.url || !isDownloadable(tab.url) || !running) return;
  if (isVideoPage(tab.url)) {
    showVideo(tab.url);
  } else {
    showAnyPage(tab);
  }
}

init();
