// YouTube'da oynatıcının sağ üstüne "İndir" butonu ekler. Tıklayınca videonun kaliteleri tahmini
// boyutlarıyla listelenir, seçilen kalite KD Download Manager'a gönderilir. Görünüm ve menü menu.js'te.
// YouTube sayfa yenilemeden video değiştirdiği için buton saniyede bir doğru oynatıcıya ve videoya
// bağlı mı diye kontrol edilir.
(() => {
  const { create, send, note, header, qualityRows, footer } = globalThis.KDMenu;

  let menu = null;
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

  function createMenu() {
    menu = create("absolute");
    menu.host.id = "kd-download-manager-button";
    menu.host.style.top = "12px";
    menu.host.style.right = "12px";
    menu.button.addEventListener("click", toggleMenu);
    // Kalite listesi yt-dlp ile birkaç saniye sürüyor; fare üzerine gelince başlat ki menü hazır açılsın.
    // Her video sayfasında önceden istenmiyor: YouTube'a fazladan istek robot korumasını tetikleyebilir.
    menu.button.addEventListener("pointerenter", () => {
      if (boundUrl) loadFormats(boundUrl);
    });
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
    if (menu.open) {
      menu.close();
      return;
    }
    const url = boundUrl;
    menu.show();
    menu.panel.replaceChildren(note("Kaliteler alınıyor…"));

    const status = await send({ type: "video-status" });
    if (status?.accent) menu.accent(status.accent);
    if (!status?.running) {
      menu.panel.replaceChildren(note("KD Download Manager çalışmıyor. Uygulamayı açıp tekrar deneyin.", "error"));
      return;
    }
    const formats = await loadFormats(url);
    if (url !== boundUrl || !menu.open) return; // Bu arada video değişti ya da menü kapandı.
    const title = formats?.title ?? document.title.replace(/ - YouTube$/, "");
    menu.panel.replaceChildren(header(title, formats?.duration), ...qualityRows(menu, url, formats), footer());
    menu.panel.querySelector(".option")?.focus();
  }

  // Doğru oynatıcıya ve videoya bağlı tut.
  function sync() {
    const url = videoUrl();
    const player = url ? findPlayer() : null;
    if (!player) {
      menu?.host.remove();
      boundUrl = null;
      return;
    }
    if (!menu) createMenu();
    if (menu.host.parentElement !== player) player.appendChild(menu.host);
    if (boundUrl !== url) {
      boundUrl = url;
      menu.close();
    }
  }

  sync();
  setInterval(sync, 1000);
  document.addEventListener("yt-navigate-finish", sync);
})();
