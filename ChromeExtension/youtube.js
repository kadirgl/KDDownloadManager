// YouTube'da oynatıcının sağ üstüne "İndir" butonu ekler. Tıklayınca videonun kaliteleri tahmini
// boyutlarıyla listelenir, seçilen kalite KD Download Manager'a gönderilir.
// Sayfanın stilleri butonu bozmasın diye her şey gölge DOM'da; YouTube sayfa yenilemeden video
// değiştirdiği için buton saniyede bir doğru oynatıcıya ve videoya bağlı mı diye kontrol edilir.
(() => {
  const HOST_ID = "kd-download-manager-button";

  let host = null;
  let shadow = null;
  let boundUrl = null;
  // Video başına tek istek: fare butonun üzerine gelince başlar, tıklayınca aynı istek beklenir.
  let formatsCache = { url: null, promise: null };

  // İzlenen videonun adresi (/watch?v=… ya da /shorts/…); video sayfası değilse null.
  function videoUrl() {
    const url = new URL(location.href);
    if (url.pathname === "/watch" && url.searchParams.get("v")) {
      return `https://www.youtube.com/watch?v=${url.searchParams.get("v")}`;
    }
    const shorts = url.pathname.match(/^\/shorts\/([\w-]+)/);
    return shorts ? `https://www.youtube.com/shorts/${shorts[1]}` : null;
  }

  // İzleme sayfasında #movie_player; Shorts'ta ekranda görünen en büyük oynatıcı.
  function findPlayer() {
    const main = document.querySelector("#movie_player");
    if (main && location.pathname === "/watch") return main;
    let best = null;
    let bestArea = 0;
    for (const player of document.querySelectorAll(".html5-video-player")) {
      const rect = player.getBoundingClientRect();
      const visible = rect.bottom > 0 && rect.top < innerHeight && rect.width > 0;
      const area = rect.width * rect.height;
      if (visible && area > bestArea) {
        best = player;
        bestArea = area;
      }
    }
    return best;
  }

  function send(message) {
    return new Promise((resolve) => {
      try {
        chrome.runtime.sendMessage(message, (response) => {
          resolve(chrome.runtime.lastError ? null : response);
        });
      } catch {
        resolve(null); // Eklenti yeniden yüklendiyse bu sayfadaki betik eskidi.
      }
    });
  }

  function formatSize(bytes) {
    if (!bytes) return "";
    const mb = bytes / 1048576;
    return mb >= 1024 ? `~${(mb / 1024).toFixed(1).replace(".", ",")} GB` : `~${Math.round(mb)} MB`;
  }

  const STYLE = `
    :host { all: initial; position: absolute; top: 12px; right: 12px; z-index: 2147483000; }
    * { box-sizing: border-box; font-family: "YouTube Sans", Roboto, -apple-system, sans-serif; }
    .button {
      display: flex; align-items: center; gap: 6px;
      padding: 7px 12px 7px 10px; border: 0; border-radius: 999px;
      background: var(--accent); color: #fff; font-size: 13px; font-weight: 600;
      cursor: pointer; box-shadow: 0 2px 8px rgba(0, 0, 0, 0.35); opacity: 0.92;
    }
    .button:hover, .button[aria-expanded="true"] { opacity: 1; }
    .button:focus-visible { outline: 2px solid #fff; outline-offset: 2px; }
    .button svg { width: 16px; height: 16px; }
    .menu {
      position: absolute; top: calc(100% + 6px); right: 0; width: 250px;
      padding: 6px; border-radius: 12px; background: rgba(28, 28, 28, 0.96); color: #f1f1f1;
      box-shadow: 0 6px 24px rgba(0, 0, 0, 0.45); font-size: 13px;
    }
    .menu[hidden] { display: none; }
    .title { padding: 6px 8px 8px; font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    .note { padding: 6px 8px; color: #aaa; line-height: 1.35; }
    .note.error { color: #ff8a80; }
    .note.ok { color: #81c995; }
    .option {
      display: flex; justify-content: space-between; align-items: center; width: 100%;
      padding: 8px; border: 0; border-radius: 8px; background: transparent; color: inherit;
      font-size: 13px; text-align: left; cursor: pointer;
    }
    .option:hover, .option:focus-visible { background: rgba(255, 255, 255, 0.12); outline: none; }
    .option.recommended { color: var(--accent); font-weight: 600; }
    .option .size { color: #aaa; font-size: 12px; }
    .option:disabled { opacity: 0.5; cursor: default; }
  `;

  // Phosphor "download-simple" ikonu.
  const DOWNLOAD_PATH = "M224 144v64a8 8 0 0 1-8 8H40a8 8 0 0 1-8-8v-64a8 8 0 0 1 16 0v56h160v-56a8 8 0 0 1 16 0Zm-101.66 5.66a8 8 0 0 0 11.32 0l40-40a8 8 0 0 0-11.32-11.32L136 124.69V32a8 8 0 0 0-16 0v92.69L93.66 98.34a8 8 0 0 0-11.32 11.32Z";

  // YouTube "Trusted Types" uyguladığı için innerHTML yerine öğeler tek tek oluşturuluyor.
  function createHost() {
    host = document.createElement("div");
    host.id = HOST_ID;
    shadow = host.attachShadow({ mode: "closed" });

    const style = document.createElement("style");
    style.textContent = STYLE;

    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    svg.setAttribute("viewBox", "0 0 256 256");
    svg.setAttribute("fill", "currentColor");
    svg.setAttribute("aria-hidden", "true");
    const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
    path.setAttribute("d", DOWNLOAD_PATH);
    svg.append(path);

    const label = document.createElement("span");
    label.textContent = "İndir";
    const button = document.createElement("button");
    button.className = "button";
    button.type = "button";
    button.setAttribute("aria-haspopup", "menu");
    button.setAttribute("aria-expanded", "false");
    button.title = "KD Download Manager ile indir";
    button.append(svg, label);

    const panel = document.createElement("div");
    panel.className = "menu";
    panel.setAttribute("role", "menu");
    panel.hidden = true;

    shadow.append(style, button, panel);
    // Oynatıcı tıklamaları videoyu durdurup başlattığı için olaylar oynatıcıya ulaşmasın.
    for (const type of ["click", "dblclick", "mousedown", "mouseup", "pointerdown", "pointerup", "keydown"]) {
      host.addEventListener(type, (event) => event.stopPropagation());
    }
    shadow.querySelector(".button").addEventListener("click", toggleMenu);
    // Kalite listesi yt-dlp ile birkaç saniye sürüyor; fare üzerine gelince başlat ki menü hazır açılsın.
    // Her video sayfasında önceden istenmiyor: YouTube'a fazladan istek robot korumasını tetikleyebilir.
    shadow.querySelector(".button").addEventListener("pointerenter", () => {
      if (boundUrl) loadFormats(boundUrl);
    });
    shadow.addEventListener("keydown", (event) => {
      if (event.key === "Escape") closeMenu();
    });
    document.addEventListener("click", (event) => {
      if (!event.composedPath().includes(host)) closeMenu();
    });
    send({ type: "video-status" }).then((status) => {
      host.style.setProperty("--accent", status?.accent ?? "#FF8500");
    });
  }

  function menu() {
    return shadow.querySelector(".menu");
  }

  function closeMenu() {
    if (!shadow) return;
    menu().hidden = true;
    shadow.querySelector(".button").setAttribute("aria-expanded", "false");
  }

  function note(text, kind = "") {
    const element = document.createElement("div");
    element.className = `note ${kind}`;
    element.textContent = text;
    return element;
  }

  function loadFormats(url) {
    if (formatsCache.url !== url) {
      const promise = send({ type: "video-formats", url }).then((data) => {
        // Başarısız olduysa bir sonraki denemede yeniden istensin.
        if (!data && formatsCache.promise === promise) formatsCache = { url: null, promise: null };
        return data;
      });
      formatsCache = { url, promise };
    }
    return formatsCache.promise;
  }

  async function toggleMenu() {
    const panel = menu();
    if (!panel.hidden) {
      closeMenu();
      return;
    }
    const url = boundUrl;
    panel.hidden = false;
    shadow.querySelector(".button").setAttribute("aria-expanded", "true");
    panel.replaceChildren(note("Kaliteler alınıyor…"));

    const status = await send({ type: "video-status" });
    if (status?.accent) host.style.setProperty("--accent", status.accent);
    if (!status?.running) {
      panel.replaceChildren(note("KD Download Manager çalışmıyor. Uygulamayı açıp tekrar deneyin.", "error"));
      return;
    }
    const formats = await loadFormats(url);
    if (url !== boundUrl || panel.hidden) return; // Bu arada video değişti ya da menü kapandı.
    renderOptions(url, formats);
  }

  function renderOptions(url, formats) {
    const panel = menu();
    const options = formats?.options?.length
      ? formats.options
      : [
        { quality: "auto", title: "Otomatik", size: null },
        { quality: "1080", title: "1080p", size: null },
        { quality: "720", title: "720p", size: null },
        { quality: "480", title: "480p", size: null },
        { quality: "audio", title: "Sadece ses (MP3)", size: null },
      ];
    const children = [];
    const title = document.createElement("div");
    title.className = "title";
    title.textContent = formats?.title ?? "Kalite seçin";
    children.push(title);

    for (const option of options) {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "option" + (option.quality === "auto" ? " recommended" : "");
      button.setAttribute("role", "menuitem");
      const name = document.createElement("span");
      name.textContent = option.quality === "auto" ? "Otomatik (önerilen)" : option.title;
      const size = document.createElement("span");
      size.className = "size";
      size.textContent = formatSize(option.size);
      button.append(name, size);
      button.addEventListener("click", async () => {
        panel.querySelectorAll(".option").forEach((b) => { b.disabled = true; });
        const ok = await send({ type: "video-download", url, quality: option.quality });
        panel.replaceChildren(
          ok ? note("KD Download Manager'a gönderildi.", "ok") : note("Uygulamaya ulaşılamadı.", "error"),
        );
        if (ok) setTimeout(closeMenu, 1500);
      });
      children.push(button);
    }
    panel.replaceChildren(...children);
    panel.querySelector(".option")?.focus();
  }

  // Doğru oynatıcıya ve videoya bağlı tut.
  function sync() {
    const url = videoUrl();
    const player = url ? findPlayer() : null;
    if (!player) {
      host?.remove();
      boundUrl = null;
      return;
    }
    if (!host) createHost();
    if (host.parentElement !== player) player.appendChild(host);
    if (boundUrl !== url) {
      boundUrl = url;
      closeMenu();
    }
  }

  sync();
  setInterval(sync, 1000);
  document.addEventListener("yt-navigate-finish", sync);
})();
