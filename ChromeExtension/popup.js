import {
  QUALITIES, accentColor, describe, fetchFormats, isAppRunning, isDownloadable, isVideoPage, sendStream,
  sendToApp, streamLabel,
} from "./app.js";

const status = document.getElementById("status");
const statusText = document.getElementById("status-text");
const intercept = document.getElementById("intercept");
const video = document.getElementById("video");
const videoTile = document.getElementById("video-tile");
const videoTitle = document.getElementById("video-title");
const videoSubtitle = document.getElementById("video-subtitle");
const qualities = document.getElementById("qualities");
const sendPage = document.getElementById("send-page");
const streams = document.getElementById("streams");
const streamList = document.getElementById("stream-list");
const message = document.getElementById("message");

// Sayfadaki menüyle aynı küçük ikonlar (24×24, dolu).
const SVG = "http://www.w3.org/2000/svg";
const PATHS = {
  download: "M12 3a1 1 0 0 1 1 1v9.59l3.3-3.3a1 1 0 1 1 1.4 1.42l-5 5a1 1 0 0 1-1.4 0l-5-5a1 1 0 1 1 1.4-1.42l3.3 3.3V4a1 1 0 0 1 1-1ZM5 19h14a1 1 0 1 1 0 2H5a1 1 0 1 1 0-2Z",
  check: "M20.7 6.3a1 1 0 0 1 0 1.4l-10 10a1 1 0 0 1-1.4 0l-5-5a1 1 0 1 1 1.4-1.4l4.3 4.29 9.3-9.3a1 1 0 0 1 1.4 0Z",
  play: "M8 5.2v13.6a1 1 0 0 0 1.5.86l11-6.8a1 1 0 0 0 0-1.72l-11-6.8A1 1 0 0 0 8 5.2z",
  note: "M19 3.5v11.25a3.25 3.25 0 1 1-2-3V7.6l-8 1.8v7.35a3.25 3.25 0 1 1-2-3V6.5a1 1 0 0 1 .78-.98l10-2.25A1 1 0 0 1 19 4.25Z",
  arrow: "M13.3 5.3a1 1 0 0 1 1.4 0l6 6a1 1 0 0 1 0 1.4l-6 6a1 1 0 0 1-1.4-1.4L17.58 13H4a1 1 0 1 1 0-2h13.58l-4.3-4.3a1 1 0 0 1 0-1.4Z",
  stream: "M4 6a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6Zm6 3.2v5.6a.6.6 0 0 0 .9.52l4.6-2.8a.6.6 0 0 0 0-1.04l-4.6-2.8a.6.6 0 0 0-.9.52Z",
};

function icon(name) {
  const svg = document.createElementNS(SVG, "svg");
  svg.setAttribute("viewBox", "0 0 24 24");
  svg.setAttribute("fill", "currentColor");
  svg.setAttribute("aria-hidden", "true");
  const path = document.createElementNS(SVG, "path");
  path.setAttribute("d", PATHS[name]);
  svg.append(path);
  return svg;
}

function element(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

const TAGS = { 2160: "4K", 1440: "2K", 1080: "HD" };

function showMessage(text, kind) {
  message.textContent = text;
  message.dataset.kind = kind ?? "";
}

function formatSize(bytes) {
  if (!bytes) return "";
  const mb = bytes / 1048576;
  return mb >= 1024 ? `~${(mb / 1024).toFixed(1).replace(".", ",")} GB` : `~${Math.round(mb)} MB`;
}

function formatDuration(seconds) {
  if (!seconds) return "";
  const total = Math.round(seconds);
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = String(total % 60).padStart(2, "0");
  return h ? `${h}:${String(m).padStart(2, "0")}:${s}` : `${m}:${s}`;
}

// Uygulamada seçilen vurgu rengi; açık renklerde düğme yazısı koyu (sayfadaki menüyle aynı kural).
function applyAccent(hex) {
  const channel = (i) => {
    const value = parseInt(hex.slice(i, i + 2), 16) / 255;
    return value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
  };
  const luminance = 0.2126 * channel(1) + 0.7152 * channel(3) + 0.0722 * channel(5);
  document.documentElement.style.setProperty("--accent", hex);
  document.documentElement.style.setProperty("--on-accent", luminance > 0.18 ? "#1D1D1F" : "#FFFFFF");
}

// video: adres bilinen bir video sitesi olmasa da yt-dlp ile video olarak indirilsin.
async function send(url, quality, video) {
  const ok = await sendToApp([await describe(url, { referrer: url, quality, video })]);
  showMessage(ok ? "KD Download Manager'a gönderildi." : "Uygulamaya ulaşılamadı.", ok ? "ok" : "error");
  return ok;
}

// Bir satır: soldaki işaret, ad (etiketiyle) ve sağda boyut. Tıklanınca `action` çalışır; başarılıysa
// pencere kapanır.
function optionRow({ name, strong, tag, detail, size, selected = false, audio = false, glyph }, action) {
  const button = element("button", "option" + (selected ? " selected" : "") + (audio ? " audio" : ""));
  button.type = "button";
  const mark = element("span", "mark");
  if (selected) mark.append(icon("check"));
  else if (audio) mark.append(icon("note"));
  else if (glyph) mark.append(icon(glyph));
  const label = element("span", "name");
  if (strong) label.append(element("strong", "", strong), document.createTextNode(name ? ` ${name}` : ""));
  else label.textContent = name;
  if (tag) label.append(element("span", "tag", tag));
  if (detail) label.append(element("small", "", detail));
  button.append(mark, label, element("span", "size", size ?? ""));
  button.addEventListener("click", async () => {
    const rows = button.parentElement.querySelectorAll(".option");
    rows.forEach((b) => { b.disabled = true; });
    const ok = await action();
    if (ok) setTimeout(() => window.close(), 900);
    else rows.forEach((b) => { b.disabled = false; });
  });
  return button;
}

function skeleton(rows) {
  return Array.from({ length: rows }, () => element("div", "skeleton"));
}

// Kalite satırlarını çizer; uygulama listeyi veremezse sabit liste kullanılır.
function renderQualities(url, options, video) {
  const rows = [];
  for (const choice of options) {
    const action = () => send(url, choice.quality, video);
    const size = formatSize(choice.size);
    if (choice.quality === "audio") {
      rows.push(element("div", "divider"));
      rows.push(optionRow({ name: "Sadece ses", tag: "MP3", size, audio: true }, action));
    } else if (choice.quality === "auto") {
      rows.push(optionRow({ strong: "Otomatik", name: "(önerilen)", size, selected: true }, action));
    } else {
      rows.push(optionRow({ name: `${choice.quality}p`, tag: TAGS[choice.quality], size }, action));
    }
  }
  const footer = element("div", "footer");
  footer.append(icon("arrow"), element("span", "", "KD Download Manager'a gönderilir"));
  qualities.replaceChildren(...rows, footer);
}

function showHeader(title, duration) {
  videoTitle.textContent = title;
  videoSubtitle.textContent = [formatDuration(duration), "Kalite seç"].filter(Boolean).join(" · ");
}

// Video sitesi: kaliteler gelene kadar iskelet; uygulama listeyi veremezse sabit liste.
async function showVideo(url, formatsRequest, title) {
  video.hidden = false;
  showHeader(title || "Video", null);
  qualities.replaceChildren(...skeleton(6));
  const formats = await formatsRequest;
  if (formats?.options?.length) {
    showHeader(formats.title, formats.duration);
    renderQualities(url, formats.options);
  } else {
    renderQualities(url, QUALITIES.map((q) => ({ quality: q.id, size: null })));
  }
}

// Video sitesi olmayan sayfa: yt-dlp sayfada video bulabilirse kaliteleri gösterilir, bulamazsa
// "Bu sayfayı indir" düğmesi. Sayfa oynatırken yakalanan akışlar ayrıca listelenir.
async function showAnyPage(tab, formatsRequest) {
  video.hidden = false;
  showHeader("Video aranıyor…", null);
  qualities.replaceChildren(...skeleton(3));
  const [formats] = await Promise.all([formatsRequest, showStreams(tab)]);
  if (formats?.options?.length) {
    showHeader(formats.title, formats.duration);
    renderQualities(tab.url, formats.options, true);
    return;
  }
  video.hidden = true;
  sendPage.hidden = false;
  sendPage.prepend(icon("download"));
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
  streamList.replaceChildren(...found.map((stream) => {
    const label = streamLabel(stream);
    const row = optionRow({ name: label.kind, detail: label.name, size: label.size.replace(" · ", "~"), glyph: "stream" },
      async () => {
        const ok = await sendStream(stream, { pageUrl: tab.url, pageTitle: tab.title });
        showMessage(ok ? "KD Download Manager'a gönderildi." : "Uygulamaya ulaşılamadı.", ok ? "ok" : "error");
        return ok;
      });
    row.title = stream.url;
    return row;
  }));
}

async function init() {
  videoTile.append(icon("play"));
  applyAccent(await accentColor());
  const stored = await chrome.storage.local.get("intercept");
  intercept.checked = stored.intercept !== false;
  intercept.addEventListener("change", () => {
    chrome.storage.local.set({ intercept: intercept.checked });
  });

  // Açılır pencere açıldığında activeTab izniyle sekmenin adresi okunabiliyor. Kalite listesi uygulamanın
  // durumu beklenmeden istenir; uygulama kapalıysa istek zaten hemen düşer.
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  const page = tab?.url && isDownloadable(tab.url) ? tab : null;
  const formatsRequest = page ? fetchFormats(page.url) : null;

  const running = await isAppRunning();
  applyAccent(await accentColor());
  status.dataset.state = running ? "connected" : "offline";
  statusText.textContent = running ? "Uygulamaya bağlı" : "Uygulama çalışmıyor";
  if (!running) {
    showMessage("KD Download Manager'ı açın. Açılana kadar indirmeleri tarayıcı yapar.");
    return;
  }
  if (!page) return;
  if (isVideoPage(page.url)) {
    showVideo(page.url, formatsRequest, page.title?.replace(/^\(\d+\)\s*/, "").replace(/ - YouTube$/, ""));
  } else {
    showAnyPage(page, formatsRequest);
  }
}

init();
