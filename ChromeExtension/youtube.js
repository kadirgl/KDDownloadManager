// YouTube'da "İndir" butonu ekler. Tıklayınca videonun kaliteleri tahmini boyutlarıyla listelenir, seçilen
// kalite KD Download Manager'a gönderilir. Görünüm ve menü menu.js'te.
// Buton videonun içine konmuyor (oynatıcının köşelerinde YouTube'un kendi düğmeleri var): izleme sayfasında
// beğen/paylaş satırına, Shorts'ta sağdaki düğme sütununun en üstüne yerleşir. Yalnızca tam ekranda ya da
// bu yerler bulunamazsa oynatıcının sağ üst köşesine girer.
// YouTube sayfa yenilemeden video değiştirdiği için buton saniyede bir doğru yerde ve doğru videoya
// bağlı mı diye kontrol edilir.
(() => {
  const { create, send, note, header, qualityRows, footer } = globalThis.KDMenu;

  // Yer başına bir buton: satırda kapsül, Shorts sütununda yuvarlak, oynatıcının içinde kapsül.
  const menus = {};
  let menu = null; // Şu an sayfada olan.
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

  const shown = (element) => element && element.getBoundingClientRect().width > 0;

  // Sayfa açılırken düğme satırı oynatıcıdan birkaç saniye sonra geliyor; o arada buton oynatıcının
  // içinde belirip kaybolmasın diye bu kadar beklenir. Satır hiç gelmezse (YouTube düzeni değişti) içeri girer.
  const ROW_WAIT = 6000;
  let rowMissingSince = 0;

  // Butonun gireceği yer: { mode, parent, before }; henüz yoksa null.
  function findSpot(player) {
    if (document.fullscreenElement) return { mode: "overlay", parent: player, before: null };
    if (location.pathname === "/watch") {
      // Beğen, paylaş, kaydet… düğmelerinin sonunda, "⋯" (diğer) düğmesinden önce.
      const row = document.querySelector("ytd-watch-metadata #actions ytd-menu-renderer");
      if (shown(row)) {
        rowMissingSince = 0;
        const more = [...row.children].reverse().find((child) => child !== menus.row?.host && shown(child));
        return { mode: "row", parent: row, before: more ?? null };
      }
    } else {
      const bar = player.closest("ytd-reel-video-renderer")?.querySelector("reel-action-bar-view-model");
      if (shown(bar)) {
        rowMissingSince = 0;
        const first = [...bar.children].find((child) => child !== menus.column?.host);
        return { mode: "column", parent: bar, before: first ?? null };
      }
    }
    rowMissingSince ||= performance.now();
    if (performance.now() - rowMissingSince < ROW_WAIT) return null;
    return { mode: "overlay", parent: player, before: null };
  }

  function menuFor(mode) {
    if (menus[mode]) return menus[mode];
    const created = mode === "overlay" ? create("absolute") : create("relative", { compact: mode === "column" });
    created.host.id = `kd-download-manager-${mode}`;
    if (mode === "overlay") {
      created.host.style.top = "12px";
      created.host.style.right = "12px";
    } else if (mode === "row") {
      created.host.style.setProperty("--kd-height", "36px");
      created.host.style.marginLeft = "8px";
      created.host.style.alignSelf = "center";
    } else {
      created.host.style.marginBottom = "16px";
    }
    created.button.addEventListener("click", toggleMenu);
    // Kalite listesi yt-dlp ile birkaç saniye sürüyor; fare üzerine gelince başlat ki menü hazır açılsın.
    // Her video sayfasında önceden istenmiyor: YouTube'a fazladan istek robot korumasını tetikleyebilir.
    created.button.addEventListener("pointerenter", () => {
      if (boundUrl) loadFormats(boundUrl);
    });
    menus[mode] = created;
    return created;
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
    const current = menu;
    if (current.open) {
      current.close();
      return;
    }
    const url = boundUrl;
    current.show();
    current.panel.replaceChildren(note("Kaliteler alınıyor…"));

    const status = await send({ type: "video-status" });
    if (status?.accent) current.accent(status.accent);
    if (!status?.running) {
      current.panel.replaceChildren(note("KD Download Manager çalışmıyor. Uygulamayı açıp tekrar deneyin.", "error"));
      return;
    }
    const formats = await loadFormats(url);
    if (url !== boundUrl || !current.open) return; // Bu arada video değişti ya da menü kapandı.
    const title = formats?.title ?? document.title.replace(/ - YouTube$/, "");
    current.panel.replaceChildren(header(title, formats?.duration), ...qualityRows(current, url, formats), footer());
    current.panel.querySelector(".option")?.focus();
  }

  // Doğru yerde ve doğru videoya bağlı tut.
  function sync() {
    const url = videoUrl();
    const player = url ? findPlayer() : null;
    const spot = player ? findSpot(player) : null;
    if (!spot) {
      menu?.close();
      menu?.host.remove();
      menu = null;
      if (!player) boundUrl = null;
      return;
    }
    const next = menuFor(spot.mode);
    if (menu && menu !== next) {
      menu.close();
      menu.host.remove();
    }
    menu = next;
    if (spot.mode === "column") {
      // Etiket rengi YouTube'un temasına (açık/koyu) uysun; komşu düğmelerin etiketleriyle aynı.
      const dark = document.documentElement.hasAttribute("dark");
      menu.host.style.setProperty("--kd-caption", dark ? "#F1F1F1" : "#0F0F0F");
    }
    if (menu.host.parentElement !== spot.parent || (spot.before && menu.host.nextElementSibling !== spot.before)) {
      spot.parent.insertBefore(menu.host, spot.before);
    }
    if (boundUrl !== url) {
      boundUrl = url;
      menu.close();
    }
  }

  sync();
  setInterval(sync, 1000);
  document.addEventListener("yt-navigate-finish", sync);
  document.addEventListener("fullscreenchange", sync);
})();
