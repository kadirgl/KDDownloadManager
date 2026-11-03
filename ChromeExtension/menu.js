// YouTube'daki ve diğer sitelerdeki "İndir" butonunun ortak parçaları: cam görünüm (Liquid Glass),
// kalite menüsü ve arka planla konuşma. youtube.js ve videos.js'ten önce yüklenir; ikisi aynı sayfada
// hiç birlikte çalışmaz. Sayfanın stilleri bozmasın diye her şey gölge DOM'da; bazı siteler "Trusted
// Types" uyguladığı için innerHTML yerine öğeler tek tek oluşturuluyor.
globalThis.KDMenu = (() => {
  const SVG = "http://www.w3.org/2000/svg";

  const STYLE = `
    :host { all: initial; z-index: 2147483000; color-scheme: light dark; }
    :host([hidden]) { display: none; }
    * { box-sizing: border-box; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", Roboto, sans-serif; }
    .button {
      display: flex; align-items: center; gap: 6px;
      height: 34px; padding: 0 10px 0 12px; border: 0; border-radius: 999px;
      background: color-mix(in srgb, var(--accent) 88%, transparent); color: var(--on-accent);
      font-size: 13px; font-weight: 600; cursor: pointer;
      -webkit-backdrop-filter: blur(24px) saturate(180%); backdrop-filter: blur(24px) saturate(180%);
      box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.45), 0 6px 18px color-mix(in srgb, var(--accent) 45%, transparent);
      transition: transform 0.12s ease, filter 0.12s ease;
    }
    .button:hover { filter: brightness(1.05); }
    .button:active { transform: scale(0.94); }
    .button:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
    .button svg { width: 15px; height: 15px; flex: none; }
    .button .chevron { width: 10px; height: 10px; opacity: 0.8; }
    .menu {
      position: absolute; top: calc(100% + 8px); right: 0; width: 300px; max-height: 380px; overflow-y: auto;
      padding: 6px; border-radius: 18px; font-size: 13px; line-height: 1.3;
      background: rgba(24, 22, 30, 0.55); color: #fff;
      -webkit-backdrop-filter: blur(36px) saturate(190%); backdrop-filter: blur(36px) saturate(190%);
      border: 1px solid rgba(255, 255, 255, 0.10);
      box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.28), 0 24px 60px rgba(0, 0, 0, 0.45);
      --secondary: rgba(255, 255, 255, 0.72); --tertiary: rgba(255, 255, 255, 0.55);
      --hover: rgba(255, 255, 255, 0.10); --selected: rgba(255, 255, 255, 0.14); --tag: rgba(255, 255, 255, 0.18);
      --divider: rgba(255, 255, 255, 0.08); --ok: #4ADE80; --error: #FF8A8A;
    }
    @media (prefers-color-scheme: light) {
      .menu {
        background: rgba(255, 255, 255, 0.72); color: #1D1D1F;
        border-color: rgba(0, 0, 0, 0.06);
        box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.95), 0 24px 60px rgba(40, 30, 80, 0.22);
        --secondary: rgba(0, 0, 0, 0.62); --tertiary: rgba(0, 0, 0, 0.55);
        --hover: rgba(0, 0, 0, 0.05); --selected: rgba(0, 0, 0, 0.07); --tag: rgba(0, 0, 0, 0.07);
        --divider: rgba(0, 0, 0, 0.08); --ok: #16A34A; --error: #B42318;
      }
    }
    .menu[hidden] { display: none; }
    :host([data-up]) .menu { top: auto; bottom: calc(100% + 8px); }
    .header { display: flex; align-items: center; gap: 10px; padding: 8px 8px 10px; }
    .tile {
      flex: none; width: 28px; height: 28px; border-radius: 7px; display: grid; place-items: center;
      background: linear-gradient(#B48CF0, #8150D6);
      box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.4), 0 1px 3px rgba(0, 0, 0, 0.3);
    }
    .tile svg { width: 14px; height: 14px; fill: #fff; }
    .header-text { min-width: 0; }
    .title { font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    .subtitle { color: var(--secondary); font-size: 11.5px; margin-top: 1px; }
    .heading { padding: 10px 10px 4px; color: var(--tertiary); font-size: 11px; font-weight: 600; letter-spacing: 0.8px; text-transform: uppercase; }
    .note { padding: 8px 10px; color: var(--secondary); line-height: 1.35; }
    .note.error { color: var(--error); }
    .note.ok { color: var(--ok); }
    .option {
      display: flex; align-items: center; gap: 8px; width: 100%; min-height: 34px;
      padding: 0 10px; border: 0; border-radius: 10px; background: transparent; color: inherit;
      font-size: 13px; text-align: left; cursor: pointer; transition: background 0.1s ease;
    }
    .option:hover, .option:focus-visible { background: var(--hover); outline: none; }
    .option.selected { background: var(--selected); }
    .option:active { transform: scale(0.98); }
    .option:disabled { opacity: 0.35; cursor: default; }
    .mark { flex: none; width: 14px; display: grid; place-items: center; }
    .mark svg { width: 12px; height: 12px; }
    .option.selected .mark { color: var(--accent-text); }
    .audio .mark { color: #F57A9A; }
    .name { flex: 1; min-width: 0; font-weight: 500; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .name strong { color: var(--accent-text); font-weight: 600; }
    .tag {
      display: inline-block; margin-left: 6px; padding: 1px 5px; border-radius: 5px; vertical-align: 1px;
      background: var(--tag); font-size: 10px; font-weight: 700; letter-spacing: 0.3px;
    }
    .size { flex: none; color: var(--secondary); font-size: 12px; font-variant-numeric: tabular-nums; }
    .divider { height: 1px; margin: 6px 10px; background: var(--divider); }
    .footer { display: flex; align-items: center; justify-content: center; gap: 6px; padding: 8px 10px 6px; color: var(--tertiary); font-size: 11.5px; }
    .footer svg { width: 11px; height: 11px; }
  `;

  // SF Symbols'e benzeyen küçük ikonlar (24×24, dolu).
  const PATHS = {
    download: "M12 3a1 1 0 0 1 1 1v9.59l3.3-3.3a1 1 0 1 1 1.4 1.42l-5 5a1 1 0 0 1-1.4 0l-5-5a1 1 0 1 1 1.4-1.42l3.3 3.3V4a1 1 0 0 1 1-1ZM5 19h14a1 1 0 1 1 0 2H5a1 1 0 1 1 0-2Z",
    chevron: "M6.3 9.3a1 1 0 0 1 1.4 0L12 13.58l4.3-4.3a1 1 0 1 1 1.4 1.42l-5 5a1 1 0 0 1-1.4 0l-5-5a1 1 0 0 1 0-1.42Z",
    check: "M20.7 6.3a1 1 0 0 1 0 1.4l-10 10a1 1 0 0 1-1.4 0l-5-5a1 1 0 1 1 1.4-1.4l4.3 4.29 9.3-9.3a1 1 0 0 1 1.4 0Z",
    play: "M8 5.2v13.6a1 1 0 0 0 1.5.86l11-6.8a1 1 0 0 0 0-1.72l-11-6.8A1 1 0 0 0 8 5.2z",
    note: "M19 3.5v11.25a3.25 3.25 0 1 1-2-3V7.6l-8 1.8v7.35a3.25 3.25 0 1 1-2-3V6.5a1 1 0 0 1 .78-.98l10-2.25A1 1 0 0 1 19 4.25Z",
    arrow: "M13.3 5.3a1 1 0 0 1 1.4 0l6 6a1 1 0 0 1 0 1.4l-6 6a1 1 0 0 1-1.4-1.4L17.58 13H4a1 1 0 1 1 0-2h13.58l-4.3-4.3a1 1 0 0 1 0-1.4Z",
    stream: "M4 6a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6Zm6 3.2v5.6a.6.6 0 0 0 .9.52l4.6-2.8a.6.6 0 0 0 0-1.04l-4.6-2.8a.6.6 0 0 0-.9.52Z",
  };

  function icon(name, className = "") {
    const svg = document.createElementNS(SVG, "svg");
    svg.setAttribute("viewBox", "0 0 24 24");
    svg.setAttribute("fill", "currentColor");
    svg.setAttribute("aria-hidden", "true");
    if (className) svg.setAttribute("class", className);
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

  function formatDuration(seconds) {
    if (!seconds) return "";
    const total = Math.round(seconds);
    const h = Math.floor(total / 3600);
    const m = Math.floor((total % 3600) / 60);
    const s = String(total % 60).padStart(2, "0");
    return h ? `${h}:${String(m).padStart(2, "0")}:${s}` : `${m}:${s}`;
  }

  // Vurgu zeminindeki yazı: açık vurgu renklerinde koyu (turuncu üstünde beyaz yazı okunmuyordu).
  function applyAccent(host, accent) {
    const hex = /^#[0-9a-f]{6}$/i.test(accent ?? "") ? accent : "#F08A2E";
    const channel = (i) => {
      const value = parseInt(hex.slice(i, i + 2), 16) / 255;
      return value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
    };
    const luminance = 0.2126 * channel(1) + 0.7152 * channel(3) + 0.0722 * channel(5);
    const dark = matchMedia("(prefers-color-scheme: dark)").matches;
    host.style.setProperty("--accent", hex);
    host.style.setProperty("--on-accent", luminance > 0.18 ? "#1D1D1F" : "#FFFFFF");
    host.style.setProperty("--accent-text", `color-mix(in srgb, ${hex} ${dark ? 65 : 62}%, ${dark ? "white" : "black"})`);
  }

  // Kapsül "İndir" butonu ve altındaki menü. `position` gölge kökünün (host) konumu: absolute ya da fixed.
  function create(position) {
    const host = document.createElement("div");
    host.style.setProperty("position", position, "important");
    const shadow = host.attachShadow({ mode: "closed" });
    const style = element("style");
    style.textContent = STYLE + `:host { position: ${position}; }`;

    const button = element("button", "button");
    button.type = "button";
    button.setAttribute("aria-haspopup", "menu");
    button.setAttribute("aria-expanded", "false");
    button.title = "KD Download Manager ile indir";
    button.append(icon("download"), element("span", "", "İndir"), icon("chevron", "chevron"));

    const panel = element("div", "menu");
    panel.setAttribute("role", "menu");
    panel.hidden = true;
    shadow.append(style, button, panel);

    // Sayfanın kendi tıklama/klavye işleyicileri (oynat/durdur, kısayollar) tetiklenmesin.
    for (const type of ["click", "dblclick", "mousedown", "mouseup", "pointerdown", "pointerup", "keydown", "wheel"]) {
      host.addEventListener(type, (event) => event.stopPropagation());
    }
    applyAccent(host);
    send({ type: "video-status" }).then((status) => applyAccent(host, status?.accent));

    const menu = {
      host, button, panel,
      get open() { return !panel.hidden; },
      show() {
        panel.hidden = false;
        button.setAttribute("aria-expanded", "true");
      },
      close() {
        if (panel.hidden) return;
        panel.hidden = true;
        button.setAttribute("aria-expanded", "false");
      },
      accent(value) { applyAccent(host, value); },
    };
    shadow.addEventListener("keydown", (event) => {
      if (event.key === "Escape") menu.close();
    });
    document.addEventListener("click", (event) => {
      if (!event.composedPath().includes(host)) menu.close();
    }, true);
    return menu;
  }

  function note(text, kind = "") {
    return element("div", `note ${kind}`, text);
  }

  function header(title, duration) {
    const row = element("div", "header");
    const tile = element("div", "tile");
    tile.append(icon("play"));
    const text = element("div", "header-text");
    text.append(
      element("div", "title", title || "Video"),
      element("div", "subtitle", [formatDuration(duration), "Kalite seç"].filter(Boolean).join(" · ")),
    );
    row.append(tile, text);
    return row;
  }

  // Menüde bir satır; tıklanınca mesajı arka plana gönderip sonucu gösterir.
  function option(menu, { name, strong, tag, size, selected = false, audio = false, glyph }, message) {
    const button = element("button", "option" + (selected ? " selected" : "") + (audio ? " audio" : ""));
    button.type = "button";
    button.setAttribute("role", "menuitem");
    const mark = element("span", "mark");
    if (selected) mark.append(icon("check"));
    else if (audio) mark.append(icon("note"));
    else if (glyph) mark.append(icon(glyph));
    const label = element("span", "name");
    if (strong) label.append(element("strong", "", strong), document.createTextNode(name ? ` ${name}` : ""));
    else label.textContent = name;
    if (tag) label.append(element("span", "tag", tag));
    button.append(mark, label, element("span", "size", size ?? ""));
    button.addEventListener("click", async () => {
      menu.panel.querySelectorAll(".option").forEach((b) => { b.disabled = true; });
      const ok = await send(message);
      menu.panel.replaceChildren(
        ok ? note("KD Download Manager'a gönderildi.", "ok") : note("Uygulamaya ulaşılamadı.", "error"),
      );
      if (ok) setTimeout(() => menu.close(), 1500);
    });
    return button;
  }

  const FALLBACK = [
    { quality: "auto", size: null },
    { quality: "1080", title: "1080p", size: null },
    { quality: "720", title: "720p", size: null },
    { quality: "480", title: "480p", size: null },
    { quality: "audio", size: null },
  ];

  const TAGS = { 2160: "4K", 1440: "2K", 1080: "HD" };

  // Kalite satırları: Otomatik (seçili, önerilen), çözünürlükler, çizgiyle ayrılmış "Sadece ses".
  function qualityRows(menu, url, formats) {
    const options = formats?.options?.length ? formats.options : FALLBACK;
    const rows = [];
    for (const choice of options) {
      const message = { type: "video-download", url, quality: choice.quality };
      if (choice.quality === "audio") {
        rows.push(element("div", "divider"));
        rows.push(option(menu, { name: "Sadece ses", tag: "MP3", size: formatSize(choice.size), audio: true }, message));
      } else if (choice.quality === "auto") {
        rows.push(option(menu, { strong: "Otomatik", name: "(önerilen)", size: formatSize(choice.size), selected: true }, message));
      } else {
        rows.push(option(menu, { name: `${choice.quality}p`, tag: TAGS[choice.quality], size: formatSize(choice.size) }, message));
      }
    }
    return rows;
  }

  function footer() {
    const row = element("div", "footer");
    row.append(icon("arrow"), element("span", "", "KD Download Manager'a gönderilir"));
    return row;
  }

  return { create, send, note, header, option, qualityRows, footer, element, formatSize };
})();
