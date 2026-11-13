// YouTube dışındaki sitelerde, fare bir videonun üzerine gelince videonun hemen üstünde, sağ kenarına
// hizalı bir "İndir" butonu gösterir. Menüde iki yol var: yt-dlp'nin sayfadan bulduğu kaliteler
// (~1.800 site tanınıyor) ve sayfa oynatırken ağ trafiğinden yakalanan akışlar (HLS/DASH listeleri,
// doğrudan video dosyaları). Buton oynatıcının içine değil sayfanın üstüne konuyor (oynatıcıların kendi
// düzenini bozmamak için). Görünüm ve menü menu.js'te.
//
// Buton sayfadaki yazıların ya da düğmelerin üstüne gelmesin diye önce videonun üstünde, sonra altında boş
// yer aranır; ikisi de doluysa videonun sağ üst köşesine girer. Yine de istenmeyen bir yerde çıkarsa
// yanındaki × ile o videoda gizlenir; ardından çıkan bildirimden "Bu sitede kapat" seçilebilir (açılır
// pencereden geri açılır).
(() => {
  // Önizleme ve reklam gibi küçük videolarda buton çıkmasın.
  const MIN_WIDTH = 240;
  const MIN_HEIGHT = 135;
  const HIDE_DELAY = 1500;
  const BUTTON_HEIGHT = 34;
  const GAP = 8;

  const { create, send, note, loading, header, option, qualityRows, footer, element, formatSize } = globalThis.KDMenu;

  // Bu sürelerden sık olmamak üzere butonun yerinin boş olup olmadığına yeniden bakılır.
  const ROOM_CHECK_INTERVAL = 800;

  const videos = document.getElementsByTagName("video");
  // × ile butonu gizlenen videolar (sayfa yenilenene kadar).
  const dismissed = new WeakSet();
  // Videonun üstündeki ve altındaki yer dolu mu (yazı, link, düğme); her videonun son ölçümü.
  const room = new WeakMap();
  let siteHidden = false;
  let menu = null;
  let target = null; // Butonun bağlı olduğu <video>.
  let hideTimer = null;
  let lastMove = 0;
  let formatsCache = { url: null, promise: null, failed: false };

  // Kullanıcının "bu site" dediği yer: gömülü oynatıcılarda (iframe) da üstteki sayfanın adresi.
  function siteName() {
    const origins = location.ancestorOrigins;
    const top = origins?.length ? origins[origins.length - 1] : location.origin;
    try {
      return new URL(top).hostname.replace(/^www\./, "");
    } catch {
      return location.hostname.replace(/^www\./, "");
    }
  }

  const site = siteName();

  async function loadSiteSetting() {
    try {
      const { hiddenSites = [] } = await chrome.storage.local.get("hiddenSites");
      siteHidden = hiddenSites.includes(site);
    } catch {
      siteHidden = false; // Eklenti yeniden yüklendiyse bu betik eskidi.
    }
    // "Bu sitede kapat"ın onay bildirimi kendisi kapanınca butonu gizler.
    if (siteHidden && !menu?.toasting) hide();
  }

  async function hideOnSite() {
    siteHidden = true;
    try {
      const { hiddenSites = [] } = await chrome.storage.local.get("hiddenSites");
      if (!hiddenSites.includes(site)) await chrome.storage.local.set({ hiddenSites: [...hiddenSites, site] });
    } catch {
      // Eklenti yeniden yüklendiyse kalıcı olarak kaydedilemedi; bu sayfada yine de gizli kalır.
    }
  }

  // ×: bu videoda gizle; birkaç saniye "Geri al" ve "Bu sitede kapat" seçenekleri.
  function dismiss() {
    const video = target;
    if (!video) return;
    dismissed.add(video);
    menu.toast("Bu videoda gizlendi", [
      {
        label: "Geri al",
        run: () => {
          dismissed.delete(video);
          show(video);
        },
      },
      {
        label: "Bu sitede kapat",
        run: () => {
          hideOnSite();
          menu.toast(`${site} için kapatıldı. Eklenti penceresinden açabilirsiniz.`, [], { duration: 3500, onEnd: hide });
        },
      },
    ], { onEnd: hide });
  }

  function createMenu() {
    menu = create("fixed", { onDismiss: dismiss });
    menu.host.hidden = true;
    menu.button.addEventListener("click", toggleMenu);
    menu.host.addEventListener("pointerenter", () => clearTimeout(hideTimer));
  }

  const menuOpen = () => menu?.open ?? false;

  // Sayfa başına tek istek. Başarısız olduysa fare hareketleriyle değil, yalnızca menü açılınca
  // (`retry`) yeniden sorulur.
  function loadFormats(url, { retry = false } = {}) {
    if (formatsCache.url !== url || (retry && formatsCache.failed)) {
      const entry = { url, failed: false };
      entry.promise = send({ type: "video-formats", url }).then((data) => {
        if (!data) entry.failed = true;
        return data;
      });
      formatsCache = entry;
    }
    return formatsCache.promise;
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
      menu.close();
      return;
    }
    const video = target;
    const pageUrl = location.href;
    // Hepsi aynı anda başlar: kalite listesi (çoğu zaman buton belirdiğinde başlamış olur), uygulamanın
    // durumu ve yakalanan akışlar. Menü beklemeden iskeletiyle açılır.
    const formatsRequest = loadFormats(pageUrl, { retry: true });
    const searching = loading("Kaliteler alınıyor…");
    menu.show();
    menu.panel.replaceChildren(header(document.title), searching);

    const [status, captured] = await Promise.all([send({ type: "video-status" }), send({ type: "streams" })]);
    if (!menuOpen()) return;
    if (status?.accent) menu.accent(status.accent);
    if (!status?.running) {
      menu.panel.replaceChildren(note("KD Download Manager çalışmıyor. Uygulamayı açıp tekrar deneyin.", "error"));
      return;
    }

    // Yakalanan akışlar hemen gösterilir; yt-dlp'nin kaliteleri gelince üste eklenir.
    const streams = captured ?? [];
    const direct = directStream(video);
    if (direct && !streams.some((s) => s.url === direct.url)) streams.unshift(direct);

    const streamSection = [];
    if (streams.length > 0) {
      streamSection.push(element("div", "heading", "Sayfada bulunan videolar"));
      for (const stream of streams.slice(0, 6)) {
        streamSection.push(option(menu, { name: streamName(stream), size: formatSize(stream.size), glyph: "stream" },
          { type: "stream-download", stream }));
      }
      // Akışlar varken iskelet kısa tutulur; asıl seçenekler zaten görünüyor.
      searching.querySelectorAll(".skeleton").forEach((row, index) => { if (index > 0) row.remove(); });
      menu.panel.replaceChildren(header(document.title), searching, ...streamSection, footer());
    }

    const formats = await formatsRequest;
    if (!menuOpen() || !searching.isConnected) return; // Menü kapandı ya da bir seçenek seçildi.
    if (!formats?.options?.length && streamSection.length === 0) {
      menu.panel.replaceChildren(note("Bu videonun adresi bulunamadı. Videoyu birkaç saniye oynatıp tekrar deneyin."));
      return;
    }
    if (formats?.options?.length) {
      menu.panel.replaceChildren(
        header(formats.title ?? document.title, formats.duration),
        ...qualityRows(menu, pageUrl, formats),
        ...streamSection,
        footer(),
      );
    } else {
      searching.remove();
    }
    menu.panel.querySelector(".option")?.focus();
  }

  function eligible(video) {
    const rect = video.getBoundingClientRect();
    return rect.width >= MIN_WIDTH && rect.height >= MIN_HEIGHT && getComputedStyle(video).visibility !== "hidden";
  }

  // Bir noktada sayfanın yazısı var mı: imlecin o noktaya düşeceği metnin satır kutuları noktayı içeriyorsa.
  function textAt(x, y) {
    const range = document.caretRangeFromPoint?.(x, y);
    const node = range?.startContainer;
    if (!node || node.nodeType !== Node.TEXT_NODE || !node.data.trim()) return false;
    const lines = document.createRange();
    lines.selectNodeContents(node);
    for (const box of lines.getClientRects()) {
      if (x >= box.left - 2 && x <= box.right + 2 && y >= box.top - 2 && y <= box.bottom + 2) return true;
    }
    return false;
  }

  // Bir noktada tıklanabilir bir şey (link, düğme, alan) var mı; videoyu da içine alan link sayılmaz
  // (bazı sitelerde bütün kart bir link).
  function controlAt(x, y, video) {
    const hit = document.elementFromPoint(x, y)?.closest("a, button, input, select, textarea, [role=button], [role=link]");
    return Boolean(hit && !hit.contains(video));
  }

  // Butonun kaplayacağı alanda (çevresinde biraz pay bırakarak) yazı ya da düğme var mı; 5×4 noktaya
  // bakılır. Ölçerken buton tıklamaları almasın ki kendisini "dolu" saymasın.
  const CLEARANCE = 6;
  function occupied(box, video) {
    const left = box.left - CLEARANCE;
    const width = box.right - box.left + 2 * CLEARANCE;
    const top = box.top - CLEARANCE;
    const height = box.bottom - box.top + 2 * CLEARANCE;
    const xs = [0, 0.25, 0.5, 0.75, 1].map((f) => left + f * width);
    const ys = [0, 1 / 3, 2 / 3, 1].map((f) => top + f * height);
    menu.host.style.pointerEvents = "none";
    try {
      return xs.some((x) => ys.some((y) => textAt(x, y) || controlAt(x, y, video)));
    } finally {
      menu.host.style.pointerEvents = "";
    }
  }

  // Videonun üstü ve altı dolu mu; ölçüm pahalı olmasın diye en fazla ROOM_CHECK_INTERVAL'da bir ve yalnızca
  // fare hareketinde (kaydırırken eski ölçüm kullanılır).
  function measureRoom(video, rect, width, viewportWidth) {
    const known = room.get(video);
    const now = performance.now();
    if (known && now - known.at < ROOM_CHECK_INTERVAL) return known;
    const right = viewportWidth - Math.max(viewportWidth - rect.right, GAP);
    const box = (top) => ({ left: right - width, right, top, bottom: top + BUTTON_HEIGHT });
    const measured = {
      at: now,
      above: occupied(box(rect.top - GAP - BUTTON_HEIGHT), video),
      below: occupied(box(rect.bottom + GAP), video),
    };
    room.set(video, measured);
    return measured;
  }

  // Buton videonun dışında, sağa hizalı: üstünde boş yer varsa üst kenarın, yoksa alt kenarın hemen dışında.
  // Oynatıcıların köşelerinde kendi butonları (ses, paylaş, kapat) olduğu için videonun içine yalnızca
  // dışarıda yer kalmadığında ya da dışarısı yazı/düğmeyle doluysa girer (sağ üst köşe).
  function place({ measure = false } = {}) {
    if (!menu || !target) return;
    if (!target.isConnected || !eligible(target)) {
      if (!menuOpen() && !menu.toasting) hide();
      return;
    }
    const rect = target.getBoundingClientRect();
    const viewportWidth = document.documentElement.clientWidth;
    const viewportHeight = document.documentElement.clientHeight;
    const width = menu.host.getBoundingClientRect().width || 90;
    const fitsAbove = rect.top - GAP - BUTTON_HEIGHT >= 0;
    const fitsBelow = rect.bottom + GAP + BUTTON_HEIGHT <= viewportHeight;
    const busy = measure && (fitsAbove || fitsBelow)
      ? measureRoom(target, rect, width, viewportWidth)
      : room.get(target) ?? { above: false, below: false };
    let top;
    let right = Math.max(viewportWidth - rect.right, GAP);
    if (fitsAbove && !busy.above) {
      top = rect.top - GAP - BUTTON_HEIGHT;
    } else if (fitsBelow && !busy.below) {
      top = rect.bottom + GAP;
    } else {
      top = Math.max(rect.top, 0) + 12;
      right = Math.max(viewportWidth - rect.right, 0) + 12;
    }
    menu.host.style.top = `${top}px`;
    menu.host.style.right = `${right}px`;
  }

  function show(video) {
    if (siteHidden || dismissed.has(video)) return;
    if (!menu) createMenu();
    // Tam ekranda yalnızca tam ekran öğesi ve içindekiler görünüyor.
    const parent = document.fullscreenElement && !(document.fullscreenElement instanceof HTMLVideoElement)
      ? document.fullscreenElement
      : document.documentElement;
    if (menu.host.parentElement !== parent) parent.appendChild(menu.host);
    if (target !== video) {
      menu.close();
      menu.clearToast();
      target = video;
    }
    menu.host.hidden = false;
    place({ measure: true });
    // Kalite listesi yt-dlp ile birkaç saniye sürüyor: buton belirir belirmez sorulur ki tıklanınca hazır
    // olsun (sayfa başına bir kez; uygulama da 10 dakika hatırlıyor).
    loadFormats(location.href);
  }

  function hide() {
    if (menu) {
      menu.close();
      menu.clearToast();
      menu.host.hidden = true;
    }
    target = null;
  }

  function scheduleHide() {
    clearTimeout(hideTimer);
    hideTimer = setTimeout(() => {
      if (!menuOpen() && !menu?.toasting) hide();
    }, HIDE_DELAY);
  }

  // Videoların üstünde çoğu zaman oynatıcının kendi katmanları olduğu için fare olayının hedefine
  // değil konumuna bakılıyor.
  function onPointerMove(event) {
    if (videos.length === 0 || siteHidden) return;
    const now = performance.now();
    if (now - lastMove < 100) return;
    lastMove = now;
    if (menu && event.composedPath().includes(menu.host)) return;
    for (const video of videos) {
      const rect = video.getBoundingClientRect();
      const inside = event.clientX >= rect.left && event.clientX <= rect.right
        && event.clientY >= rect.top && event.clientY <= rect.bottom;
      if (inside && eligible(video) && !dismissed.has(video)) {
        clearTimeout(hideTimer);
        // Gizleme bildirimi dururken başka videoya geçilmesin; bildirim kendi kapanır.
        if (!menu?.toasting) show(video);
        return;
      }
    }
    if (target && !menuOpen() && !menu?.toasting) scheduleHide();
  }

  loadSiteSetting();
  // Açılır pencereden bu site için yeniden açılır ya da kapatılırsa hemen uygulanır.
  chrome.storage.onChanged.addListener((changes, area) => {
    if (area === "local" && changes.hiddenSites) loadSiteSetting();
  });

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
