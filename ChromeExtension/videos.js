// YouTube dışındaki sitelerde, fare bir videonun üzerine gelince videonun hemen üstünde, sağ kenarına
// hizalı bir "İndir" butonu gösterir. Menüde iki yol var: yt-dlp'nin sayfadan bulduğu kaliteler
// (~1.800 site tanınıyor) ve sayfa oynatırken ağ trafiğinden yakalanan akışlar (HLS/DASH listeleri,
// doğrudan video dosyaları). Buton oynatıcının içine değil sayfanın üstüne konuyor (oynatıcıların kendi
// düzenini bozmamak için). Görünüm ve menü menu.js'te.
(() => {
  // Önizleme ve reklam gibi küçük videolarda buton çıkmasın.
  const MIN_WIDTH = 240;
  const MIN_HEIGHT = 135;
  const HIDE_DELAY = 1500;
  const BUTTON_HEIGHT = 34;
  const GAP = 8;

  const { create, send, note, loading, header, option, qualityRows, footer, element, formatSize } = globalThis.KDMenu;

  const videos = document.getElementsByTagName("video");
  let menu = null;
  let target = null; // Butonun bağlı olduğu <video>.
  let hideTimer = null;
  let lastMove = 0;
  let formatsCache = { url: null, promise: null, failed: false };

  function createMenu() {
    menu = create("fixed");
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

  // Buton videonun dışında: üstünde yer varsa üst kenarın, yoksa alt kenarın hemen dışında, sağa hizalı.
  // Oynatıcıların köşelerinde kendi butonları (ses, paylaş, kapat) olduğu için videonun içine yalnızca
  // dışarıda hiç yer kalmadığında (tam ekran, videoyu dolduran gömülü oynatıcı) girer.
  function place() {
    if (!menu || !target) return;
    if (!target.isConnected || !eligible(target)) {
      if (!menuOpen()) hide();
      return;
    }
    const rect = target.getBoundingClientRect();
    const viewportWidth = document.documentElement.clientWidth;
    const viewportHeight = document.documentElement.clientHeight;
    let top;
    let right = Math.max(viewportWidth - rect.right, GAP);
    if (rect.top - GAP - BUTTON_HEIGHT >= 0) {
      top = rect.top - GAP - BUTTON_HEIGHT;
    } else if (rect.bottom + GAP + BUTTON_HEIGHT <= viewportHeight) {
      top = rect.bottom + GAP;
    } else {
      top = Math.max(rect.top, 0) + 12;
      right = Math.max(viewportWidth - rect.right, 0) + 12;
    }
    menu.host.style.top = `${top}px`;
    menu.host.style.right = `${right}px`;
  }

  function show(video) {
    if (!menu) createMenu();
    // Tam ekranda yalnızca tam ekran öğesi ve içindekiler görünüyor.
    const parent = document.fullscreenElement && !(document.fullscreenElement instanceof HTMLVideoElement)
      ? document.fullscreenElement
      : document.documentElement;
    if (menu.host.parentElement !== parent) parent.appendChild(menu.host);
    if (target !== video) {
      menu.close();
      target = video;
    }
    menu.host.hidden = false;
    place();
    // Kalite listesi yt-dlp ile birkaç saniye sürüyor: buton belirir belirmez sorulur ki tıklanınca hazır
    // olsun (sayfa başına bir kez; uygulama da 10 dakika hatırlıyor).
    loadFormats(location.href);
  }

  function hide() {
    if (menu) menu.host.hidden = true;
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
    if (menu && event.composedPath().includes(menu.host)) return;
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
