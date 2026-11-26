// YouTube'un kendi sayfasındaki biçim listesinden (oynatıcının "player response"u) kalite menüsünü çıkarır.
// Böylece YouTube'da menü, uygulamanın yt-dlp'yle birkaç saniye sürecek sorgusunu beklemeden hemen dolar.
// Kurallar uygulamadaki VideoFormats.parse'ınkiyle aynı (Mac: Engine/VideoFormats.swift, Windows:
// Engine/VideoFormats.cs); boyutlar yt-dlp'nin bulduklarıyla aynı çıkar. Sayfa bilgisi yoksa ya da eksikse
// null döner; o zaman liste yine uygulamadan istenir.
globalThis.KDFormats = (() => {
  const BUCKETS = [2160, 1440, 1080, 720, 480, 360];

  // 'video/mp4; codecs="avc1.640028"' → { kind: "video", codecs: ["avc1.640028"] }
  function describe(mimeType) {
    const [type] = String(mimeType ?? "").split(";");
    const codecs = (String(mimeType).match(/codecs="([^"]*)"/)?.[1] ?? "").split(",").map((c) => c.trim()).filter(Boolean);
    return { kind: type.split("/")[0], codecs };
  }

  // Oynatıcının biçimi → yt-dlp'nin alan adlarıyla (vcodec/acodec/width/height/filesize/tbr).
  function normalize(format, muxed) {
    const { kind, codecs } = describe(format.mimeType);
    const size = Number(format.contentLength);
    let vcodec = "none";
    let acodec = "none";
    if (muxed) [vcodec, acodec] = [codecs[0] ?? "none", codecs[1] ?? "none"];
    else if (kind === "video") vcodec = codecs[0] ?? "unknown";
    else if (kind === "audio") acodec = codecs[0] ?? "unknown";
    return {
      vcodec, acodec,
      width: Number(format.width) || null,
      height: Number(format.height) || null,
      filesize: Number.isFinite(size) && size > 0 ? size : null,
      tbr: (Number(format.bitrate) || 0) / 1000,
    };
  }

  const sizeOf = (f) => f.filesize;
  const resolution = (f) => {
    const sides = [f.width, f.height].filter((v) => v);
    return sides.length ? Math.min(...sides) : null;
  };
  const bucket = (r) => (r == null ? null : BUCKETS.find((h) => r >= Math.trunc(h * 0.9)) ?? null);
  // En yüksek bitrate'li; boyutu bilinen varsa onlar arasından.
  function best(formats) {
    const sized = formats.filter((f) => sizeOf(f) != null);
    const pool = sized.length ? sized : formats;
    return pool.reduce((a, b) => (a == null || (b.tbr ?? 0) > (a.tbr ?? 0) ? b : a), null);
  }

  // yt-dlp biçimleri → [{ quality, size }] (VideoFormats.parse'ın aynısı).
  function options(formats) {
    const videos = formats.filter((f) => f.vcodec !== "none" && resolution(f) != null);
    const audios = formats.filter((f) => f.vcodec === "none" && f.acodec !== "none");
    const audio = best(audios.filter((f) => f.acodec.startsWith("mp4a"))) ?? best(audios);
    const audioSize = audio ? sizeOf(audio) : null;

    function option(quality, candidates) {
      if (!candidates.length) return null;
      const h264 = candidates.filter((f) => f.vcodec.startsWith("avc1"));
      const pool = h264.length ? h264 : candidates;
      const videoOnly = pool.filter((f) => f.acodec === "none");
      const video = best(videoOnly.length ? videoOnly : pool);
      if (!video) return null;
      const hasAudio = video.acodec !== "none";
      const size = sizeOf(video) == null ? null : sizeOf(video) + (hasAudio ? 0 : audioSize ?? 0);
      return { quality, size };
    }

    const result = [];
    const h264 = videos.filter((f) => f.vcodec.startsWith("avc1"));
    const autoPool = h264.length ? h264 : videos;
    const top = autoPool.length ? Math.max(...autoPool.map(resolution)) : null;
    const auto = top == null ? null : option("auto", autoPool.filter((f) => resolution(f) === top));
    if (auto) result.push(auto);
    for (const height of BUCKETS) {
      const found = option(String(height), videos.filter((f) => bucket(resolution(f)) === height));
      if (found) result.push(found);
    }
    if (audios.length || !videos.length) result.push({ quality: "audio", size: audioSize });
    return result;
  }

  // Sayfadan gelen özet ({ videoId, title, lengthSeconds, formats, adaptiveFormats }) → menünün beklediği
  // { title, duration, options }. Kullanılamayacak kadar eksikse null.
  function fromPlayerResponse(data) {
    if (!data || typeof data !== "object") return null;
    const list = [
      ...(Array.isArray(data.formats) ? data.formats.map((f) => normalize(f, true)) : []),
      ...(Array.isArray(data.adaptiveFormats) ? data.adaptiveFormats.map((f) => normalize(f, false)) : []),
    ];
    const result = options(list);
    // Görüntü yoksa ya da hiçbir boyut bilinmiyorsa uygulamanın yt-dlp'si daha iyisini bulur.
    if (!result.some((o) => o.quality !== "audio") || !result.some((o) => o.size != null)) return null;
    const duration = Number(data.lengthSeconds);
    return {
      title: typeof data.title === "string" && data.title ? data.title : null,
      duration: Number.isFinite(duration) && duration > 0 ? duration : null,
      options: result,
      source: "page",
    };
  }

  return { fromPlayerResponse, options, normalize };
})();
