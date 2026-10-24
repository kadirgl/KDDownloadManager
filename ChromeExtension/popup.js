import { describe, isAppRunning, isDownloadable, isVideoPage, sendToApp } from "./app.js";

const status = document.getElementById("status");
const statusText = document.getElementById("status-text");
const intercept = document.getElementById("intercept");
const sendPage = document.getElementById("send-page");
const message = document.getElementById("message");

function showMessage(text, kind) {
  message.textContent = text;
  message.dataset.kind = kind ?? "";
}

async function init() {
  const stored = await chrome.storage.local.get("intercept");
  intercept.checked = stored.intercept !== false;
  intercept.addEventListener("change", () => {
    chrome.storage.local.set({ intercept: intercept.checked });
  });

  // Açılır pencere açıldığında activeTab izniyle sekmenin adresi okunabiliyor.
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (tab?.url && isDownloadable(tab.url)) {
    sendPage.hidden = false;
    sendPage.textContent = isVideoPage(tab.url) ? "Bu videoyu indir" : "Bu sayfayı indir";
    sendPage.addEventListener("click", async () => {
      sendPage.disabled = true;
      const ok = await sendToApp([await describe(tab.url, { referrer: tab.url })]);
      showMessage(ok ? "KD Download Manager'a gönderildi." : "Uygulamaya ulaşılamadı.", ok ? "ok" : "error");
      sendPage.disabled = false;
    });
  }

  const running = await isAppRunning();
  status.dataset.state = running ? "connected" : "offline";
  statusText.textContent = running ? "Uygulamaya bağlı" : "Uygulama çalışmıyor";
  if (!running) {
    showMessage("KD Download Manager'ı açın. Açılana kadar indirmeleri Chrome yapar.");
  }
}

init();
