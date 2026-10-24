import {
  QUALITIES, accentColor, describe, fetchFormats, isAppRunning, isDownloadable, isVideoPage, sendToApp,
} from "./app.js";

const status = document.getElementById("status");
const statusText = document.getElementById("status-text");
const intercept = document.getElementById("intercept");
const video = document.getElementById("video");
const videoTitle = document.getElementById("video-title");
const qualities = document.getElementById("qualities");
const sendPage = document.getElementById("send-page");
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

async function send(url, quality) {
  const ok = await sendToApp([await describe(url, { referrer: url, quality })]);
  showMessage(ok ? "KD Download Manager'a gönderildi." : "Uygulamaya ulaşılamadı.", ok ? "ok" : "error");
  return ok;
}

// Kalite düğmelerini çizer; uygulama listeyi veremezse sabit liste kullanılır.
function renderQualities(url, options) {
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
      const ok = await send(url, option.quality);
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
    sendPage.hidden = false;
    sendPage.addEventListener("click", async () => {
      sendPage.disabled = true;
      await send(tab.url);
      sendPage.disabled = false;
    });
  }
}

init();
