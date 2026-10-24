// YouTube dışındaki sitelerde, fare bir videonun üzerine gelince sağ üst köşesinde "İndir" butonu
// gösterir. Menüde iki yol var: yt-dlp'nin sayfadan bulduğu kaliteler (~1.800 site tanınıyor) ve
// sayfa oynatırken ağ trafiğinden yakalanan akışlar (HLS/DASH listeleri, doğrudan video dosyaları).
// Buton oynatıcının içine değil sayfanın üstüne konuyor (oynatıcıların kendi düzenini bozmamak için);
// sayfanın stilleri butonu bozmasın diye her şey gölge DOM'da.
(() => {
  // Önizleme ve reklam gibi küçük videolarda buton çıkmasın.
  const MIN_WIDTH = 240;
  const MIN_HEIGHT = 135;
  const HIDE_DELAY = 1500;

  const videos = document.getElementsByTagName("video");
  let host = null;
  let shadow = null;
  let target = null; // Butonun bağlı olduğu <video>.
  let hideTimer = null;
  let lastMove = 0;
  let formatsCache = { url: null, promise: null };

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
    :host { all: initial; position: fixed; z-index: 2147483000; }
    :host([hidden]) { display: none; }
    * { box-sizing: border-box; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
    .button {
      display: flex; align-items: center; gap: 6px;
      padding: 7px 12px 7px 10px; border: 0; border-radius: 999px;
      background: var(--accent); color: #fff; font-size: 13px; font-weight: 600; line-height: 1.2;
      cursor: pointer; box-shadow: 0 2px 8px rgba(0, 0, 0, 0.35); opacity: 0.92;
    }
    .button:hover, .button[aria-expanded="true"] { opacity: 1; }
    .button:focus-visible { outline: 2px solid #fff; outline-offset: 2px; }
    .button svg { width: 16px; height: 16px; }
    .menu {
      position: absolute; top: calc(100% + 6px); right: 0; width: 270px; max-height: 340px; overflow-y: auto;
      padding: 6px; border-radius: 12px; background: rgba(28, 28, 28, 0.96); color: #f1f1f1;
      box-shadow: 0 6px 24px rgba(0, 0, 0, 0.45); font-size: 13px; line-height: 1.3;
    }
    .menu[hidden] { display: none; }
    .title { padding: 6px 8px 8px; font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    .heading { padding: 8px 8px 4px; color: #aaa; font-size: 11px; font-weight: 600; text-transform: uppercase; }
    .note { padding: 6px 8px; color: #aaa; line-height: 1.35; }
    .note.error { color: #ff8a80; }
    .note.ok { color: #81c995; }
    .option {
      display: flex; justify-content: space-between; align-items: center; gap: 8px; width: 100%;
      padding: 8px; border: 0; border-radius: 8px; background: transparent; color: inherit;
      font-size: 13px; text-align: left; cursor: pointer;
    }
    .option:hover, .option:focus-visible { background: rgba(255, 255, 255, 0.12); outline: none; }
    .option.recommended { color: var(--accent); font-weight: 600; }
    .option .size { flex: none; color: #aaa; font-size: 12px; }
    .option .name { min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .option:disabled { opacity: 0.5; cursor: default; }
  `;

  // Phosphor "download-simple" ikonu.
  const DOWNLOAD_PATH = "M224 144v64a8 8 0 0 1-8 8H40a8 8 0 0 1-8-8v-64a8 8 0 0 1 16 0v56h160v-56a8 8 0 0 1 16 0Zm-101.66 5.66a8 8 0 0 0 11.32 0l40-40a8 8 0 0 0-11.32-11.32L136 124.69V32a8 8 0 0 0-16 0v92.69L93.66 98.34a8 8 0 0 0-11.32 11.32Z";

  // Bazı siteler "Trusted Types" uyguladığı için innerHTML yerine öğeler tek tek oluşturuluyor.
  function createHost() {
    host = document.createElement("div");
    host.hidden = true;
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
    // Sayfanın kendi tıklama/klavye işleyicileri (oynat/durdur, kısayollar) tetiklenmesin.
    for (const type of ["click", "dblclick", "mousedown", "mouseup", "pointerdown", "pointerup", "keydown", "wheel"]) {
      host.addEventListener(type, (event) => event.stopPropagation());
    }
    button.addEventListener("click", toggleMenu);
    // Kalite listesi yt-dlp ile birkaç saniye sürüyor; fare üzerine gelince başlat ki menü hazır açılsın.
    button.addEventListener("pointerenter", () => loadFormats(location.href));
    host.addEventListener("pointerenter", () => clearTimeout(hideTimer));
    shadow.addEventListener("keydown", (event) => {
      if (event.key === "Escape") closeMenu();
    });
    document.addEventListener("click", (event) => {
      if (!event.composedPath().includes(host)) closeMenu();
    }, true);
    send({ type: "video-status" }).then((status) => {
      host.style.setProperty("--accent", status?.accent ?? "#FF8500");
    });
  }

  const menu = () => shadow.querySelector(".menu");
  const menuOpen = () => shadow && !menu().hidden;

  function closeMenu() {
    if (!menuOpen()) return;
    menu().hidden = true;
    shadow.querySelector(".button").setAttribute("aria-expanded", "false");
  }

  function note(text, kind = "") {
    const element = document.createElement("div");
    element.className = `note ${kind}`;
    element.textContent = text;
    return element;
  }

  function element(className, text) {
    const div = document.createElement("div");
    div.className = className;
    div.textContent = text;
    return div;
  }

  function loadFormats(url) {
    if (formatsCache.url !== url) {
      const promise = send({ type: "video-formats", url }).then((data) => {
        if (!data && formatsCache.promise === promise) formatsCache = { url: null, promise: null };
        return data;
      });
      formatsCache = { url, promise };
    }
    return formatsCache.promise;
  }

  // Menüde bir seçenek; tıklanınca mesajı arka plana gönderip sonucu gösterir.
  function option(name, size, message, recommended = false) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "option" + (recommended ? " recommended" : "");
    button.setAttribute("role", "menuitem");
    button.append(element("name", name), element("size", size));
    button.addEventListener("click", async () => {
      const panel = menu();
      panel.querySelectorAll(".option").forEach((b) => { b.disabled = true; });
      const ok = await send(message);
      panel.replaceChildren(
        ok ? note("KD Download Manager'a gönderildi.", "ok") : note("Uygulamaya ulaşılamadı.", "error"),
      );
      if (ok) setTimeout(closeMenu, 1500);
    });
    return button;
  }

  // Oynatılan videonun doğrudan adresi (blob: değilse): yakalanan akışlarda yoksa o da listelenir.
  function directStream(video) {
    const src = video?.currentSrc || video?.src || "";
    if (!/^https?:/i.test(src)) return null;
    if (/\.m3u8(\?|$)/i.test(src)) return { kind: "hls", url: src };
    if (/\.mpd(\?|$)/i.test(src)) return { kind: "dash", url: src };
    const extension = src.match(/\.(mp4|webm|m4v|mov|mkv)(\?|$)/i)?.[1]?.toLowerCase() ?? "mp4";
    return { kind: "file", url: src, extension };
  }

  function streamName(stream) {
    let name;
    try {
      name = decodeURIComponent(new URL(stream.url).pathname.split("/").pop() || "");
    } catch {
      name = "";
    }
    const kind = { hls: "HLS akışı", dash: "DASH akışı", file: "Video dosyası" }[stream.kind];
    return name ? `${kind} · ${name}` : kind;
  }

  async function toggleMenu() {
    if (menuOpen()) {
      closeMenu();
      return;
    }
    const panel = menu();
    const video = target;
    const pageUrl = location.href;
    panel.hidden = false;
    shadow.querySelector(".button").setAttribute("aria-expanded", "true");
    panel.replaceChildren(note("Video aranıyor…"));

    const status = await send({ type: "video-status" });
    if (status?.accent) host.style.setProperty("--accent", status.accent);
    if (!status?.running) {
      panel.replaceChildren(note("KD Download Manager çalışmıyor. Uygulamayı açıp tekrar deneyin.", "error"));
      return;
    }

    // Yakalanan akışlar hemen gösterilir; yt-dlp'nin kaliteleri gelince üste eklenir.
    const streams = (await send({ type: "streams" })) ?? [];
    const direct = directStream(video);
    if (direct && !streams.some((s) => s.url === direct.url)) streams.unshift(direct);

    const streamSection = [];
    if (streams.length > 0) {
      streamSection.push(element("heading", "Sayfada bulunan videolar"));
      for (const stream of streams.slice(0, 6)) {
        const size = stream.size ? formatSize(stream.size) : "";
        streamSection.push(option(streamName(stream), size, { type: "stream-download", stream }));
      }
    }
    const searching = note("Kaliteler alınıyor…");
    panel.replaceChildren(searching, ...streamSection);

    const formats = await loadFormats(pageUrl);
    if (!menuOpen() || !searching.isConnected) return; // Menü kapandı ya da bir seçenek seçildi.
    const qualitySection = [];
    if (formats?.options?.length) {
      qualitySection.push(element("title", formats.title ?? "Video"));
      for (const choice of formats.options) {
        const name = choice.quality === "auto" ? "Otomatik (önerilen)" : choice.title;
        qualitySection.push(option(name, formatSize(choice.size),
          { type: "video-download", url: pageUrl, quality: choice.quality }, choice.quality === "auto"));
      }
    }
    if (qualitySection.length === 0 && streamSection.length === 0) {
      panel.replaceChildren(note("Bu videonun adresi bulunamadı. Videoyu birkaç saniye oynatıp tekrar deneyin."));
      return;
    }
    searching.replaceWith(...qualitySection);
    panel.querySelector(".option")?.focus();
  }

  function eligible(video) {
    const rect = video.getBoundingClientRect();
    return rect.width >= MIN_WIDTH && rect.height >= MIN_HEIGHT && getComputedStyle(video).visibility !== "hidden";
  }

  // Buton videonun sağ üst köşesinde, video ekrandan taşıyorsa görünen kısmın köşesinde.
  function place() {
    if (!host || !target) return;
    if (!target.isConnected || !eligible(target)) {
      if (!menuOpen()) hide();
      return;
    }
    const rect = target.getBoundingClientRect();
    host.style.top = `${Math.max(rect.top, 0) + 12}px`;
    host.style.right = `${Math.max(document.documentElement.clientWidth - rect.right, 0) + 12}px`;
  }

  function show(video) {
    if (!host) createHost();
    // Tam ekranda yalnızca tam ekran öğesi ve içindekiler görünüyor.
    const parent = document.fullscreenElement && !(document.fullscreenElement instanceof HTMLVideoElement)
      ? document.fullscreenElement
      : document.documentElement;
    if (host.parentElement !== parent) parent.appendChild(host);
    if (target !== video) {
      closeMenu();
      target = video;
    }
    host.hidden = false;
    place();
  }

  function hide() {
    if (host) host.hidden = true;
    target = null;
  }

  function scheduleHide() {
    clearTimeout(hideTimer);
    hideTimer = setTimeout(() => {
      if (!menuOpen()) hide();
    }, HIDE_DELAY);
  }

  // Videoların üstünde çoğu zaman oynatıcının kendi katmanları olduğu için fare olayının hedefine
  // değil konumuna bakılıyor.
  function onPointerMove(event) {
    if (videos.length === 0) return;
    const now = performance.now();
    if (now - lastMove < 100) return;
    lastMove = now;
    if (host && event.composedPath().includes(host)) return;
    for (const video of videos) {
      const rect = video.getBoundingClientRect();
      const inside = event.clientX >= rect.left && event.clientX <= rect.right
        && event.clientY >= rect.top && event.clientY <= rect.bottom;
      if (inside && eligible(video)) {
        clearTimeout(hideTimer);
        show(video);
        return;
      }
    }
    if (target && !menuOpen()) scheduleHide();
  }

  document.addEventListener("pointermove", onPointerMove, { passive: true, capture: true });
  addEventListener("scroll", () => {
    if (target) place();
  }, { passive: true, capture: true });
  addEventListener("resize", () => {
    if (target) place();
  }, { passive: true });
  document.addEventListener("fullscreenchange", () => {
    if (target) show(target);
  });
})();
