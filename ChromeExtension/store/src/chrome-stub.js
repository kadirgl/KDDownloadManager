// Mağaza görselleri için sahte Chrome eklenti ortamı: eklentinin kendi açılır penceresi ve sayfa betikleri
// (menu.js, videos.js) değiştirilmeden, gerçek metinleri ve stilleriyle normal bir sayfada çizilsin diye.
// Yalnızca store/make-assets.sh kullanıyor; mağaza paketine girmiyor. Dil: ?lang=tr|en.
(() => {
  const lang = new URLSearchParams(location.search).get("lang") === "tr" ? "tr" : "en";
  const tr = lang === "tr";

  const request = new XMLHttpRequest();
  request.open("GET", `/ext/_locales/${lang}/messages.json`, false);
  request.send();
  const messages = JSON.parse(request.responseText);

  function getMessage(key, substitutions) {
    if (key === "@@ui_locale") return lang;
    const entry = messages[key];
    if (!entry) return "";
    const subs = substitutions == null ? [] : [].concat(substitutions);
    return entry.message
      .replace(/\$([A-Za-z0-9_]+)\$/g, (match, name) => entry.placeholders?.[name.toLowerCase()]?.content ?? match)
      .replace(/\$(\d)/g, (match, n) => subs[n - 1] ?? "");
  }

  const MB = 1048576;
  const PAGE = {
    url: "https://videos.example.com/watch/mountain-timelapse",
    title: tr ? "Dağlarda gün doğumu — 4K zaman atlamalı" : "Sunrise over the mountains — 4K timelapse",
  };
  const FORMATS = {
    title: PAGE.title,
    duration: 754,
    options: [
      { quality: "auto", size: 2150 * MB },
      { quality: "2160", size: 2150 * MB },
      { quality: "1440", size: 1240 * MB },
      { quality: "1080", size: 640 * MB },
      { quality: "720", size: 318 * MB },
      { quality: "480", size: 162 * MB },
      { quality: "audio", size: 12 * MB },
    ],
  };
  const ACCENT = "#F08A2E";
  window.KD_PAGE = PAGE;

  // Menülerin gölge kökü kapalı; görsel düzeneği düğmeye tıklayabilsin diye açık oluşturulur.
  const attachShadow = Element.prototype.attachShadow;
  Element.prototype.attachShadow = function (init) {
    return attachShadow.call(this, { ...init, mode: "open" });
  };

  const area = (initial) => {
    const data = { ...initial };
    return {
      async get(keys) {
        if (keys == null) return { ...data };
        const list = typeof keys === "string" ? [keys] : Array.isArray(keys) ? keys : Object.keys(keys);
        return Object.fromEntries(list.filter((k) => k in data).map((k) => [k, data[k]]));
      },
      async set(values) { Object.assign(data, values); },
      async remove(keys) { [].concat(keys).forEach((k) => delete data[k]); },
    };
  };
  const event = () => ({ addListener() {}, removeListener() {} });

  // Arka plan betiğinin içerik betiklerine verdiği cevaplar (background.js'teki onMessage).
  const replies = {
    "video-status": () => ({ running: true, accent: ACCENT }),
    "video-formats": () => FORMATS,
    streams: () => [],
  };

  window.chrome = {
    i18n: { getMessage, getUILanguage: () => lang },
    runtime: {
      id: "storeassets",
      lastError: undefined,
      getManifest: () => ({ version: "1.9.2" }),
      sendMessage(message, callback) {
        const reply = replies[message?.type]?.() ?? null;
        const delayed = new Promise((resolve) => setTimeout(() => resolve(reply), 120));
        if (callback) delayed.then(callback);
        return delayed;
      },
      onMessage: event(),
    },
    storage: {
      local: area({ intercept: true, accent: ACCENT, hiddenSites: [] }),
      session: area({}),
      onChanged: event(),
    },
    tabs: { query: async () => [{ id: 1, ...PAGE }] },
    action: { setBadgeText() {}, setBadgeBackgroundColor() {} },
  };

  // Uygulamanın yerel kapısı (127.0.0.1:47615): çalışıyor ve kaliteleri biliyor.
  const realFetch = window.fetch.bind(window);
  window.fetch = async (url, options) => {
    const target = String(url);
    if (!target.startsWith("http://127.0.0.1:47615")) return realFetch(url, options);
    const path = new URL(target).pathname;
    const body = { "/ping": { app: "KD Download Manager", accent: ACCENT }, "/formats": FORMATS }[path] ?? {};
    await new Promise((resolve) => setTimeout(resolve, 150));
    return new Response(JSON.stringify(body), { status: 200, headers: { "Content-Type": "application/json" } });
  };
})();
