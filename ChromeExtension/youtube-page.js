// YouTube sayfasının kendi dünyasında (MAIN) çalışır; yalnızca okur. Eklentinin youtube.js'i bir video için
// biçim listesi isteyince, oynatıcının bildiği biçimleri (çözünürlük, kodek, boyut) özetleyip geri yollar.
// Eklentinin diğer betikleri sayfanın değişkenlerini göremediği için bu köprü gerekiyor. Ağ isteği yapmaz,
// sayfaya hiçbir şey yazmaz; yanıtta yalnızca kalite menüsü için gereken alanlar var.
(() => {
  const REQUEST = "kd-dm-formats-request";
  const RESPONSE = "kd-dm-formats-response";

  // İstenen videonun oynatıcı bilgisi: izleme sayfasında #movie_player, Shorts'ta ekrandaki oynatıcılar.
  function playerResponse(videoId) {
    const candidates = [document.getElementById("movie_player"), ...document.querySelectorAll(".html5-video-player")];
    for (const player of candidates) {
      try {
        const response = player?.getPlayerResponse?.();
        if (response?.videoDetails?.videoId === videoId) return response;
      } catch {}
    }
    const initial = globalThis.ytInitialPlayerResponse;
    return initial?.videoDetails?.videoId === videoId ? initial : null;
  }

  const pick = (format) => ({
    itag: format.itag,
    mimeType: format.mimeType,
    width: format.width,
    height: format.height,
    contentLength: format.contentLength,
    bitrate: format.bitrate,
  });

  window.addEventListener("message", (event) => {
    if (event.source !== window || event.data?.type !== REQUEST || typeof event.data.videoId !== "string") return;
    const response = playerResponse(event.data.videoId);
    const streaming = response?.streamingData;
    const data = response && {
      videoId: event.data.videoId,
      title: response.videoDetails?.title,
      lengthSeconds: response.videoDetails?.lengthSeconds,
      formats: (streaming?.formats ?? []).map(pick),
      adaptiveFormats: (streaming?.adaptiveFormats ?? []).map(pick),
    };
    window.postMessage({ type: RESPONSE, id: event.data.id, data: data ?? null }, location.origin);
  });
})();
