// YouTube sayfasından kalite listesi (ChromeExtension/formats.js). Sonuçlar uygulamanın yt-dlp'yle bulduklarıyla
// (VideoFormats.parse) aynı olmalı; Mac'teki ParsingTests.youtubeLike ile aynı girdi ve aynı beklentiler.
import { test } from "node:test";
import assert from "node:assert/strict";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "ChromeExtension");
await import(pathToFileURL(join(root, "formats.js")).href);
const { fromPlayerResponse, options } = globalThis.KDFormats;

const ytdlp = (id, vcodec, acodec = "none", width = null, height = null, filesize = null, tbr = 0) =>
  ({ id, vcodec, acodec, width, height, filesize, tbr });

test("uygulamanın VideoFormats.parse'ıyla aynı sonuç (Mac ParsingTests.youtubeLike)", () => {
  const result = options([
    ytdlp("140", "none", "mp4a.40.2", null, null, 3_000_000, 128),
    ytdlp("251", "none", "opus", null, null, 3_500_000, 160),
    ytdlp("18", "avc1.42001E", "mp4a.40.2", 640, 360, 9_000_000, 500),
    ytdlp("134", "avc1.4d401e", "none", 640, 360, 5_000_000, 300),
    ytdlp("136", "avc1.4d401f", "none", 1280, 720, 20_000_000, 1_200),
    ytdlp("137", "avc1.640028", "none", 1920, 1080, 40_000_000, 2_500),
    ytdlp("248", "vp9", "none", 1920, 1080, 30_000_000, 2_000),
    ytdlp("313", "vp9", "none", 3840, 2160, 200_000_000, 15_000),
  ]);
  assert.deepEqual(result.map((o) => o.quality), ["auto", "2160", "1080", "720", "360", "audio"]);
  const size = Object.fromEntries(result.map((o) => [o.quality, o.size]));
  assert.equal(size.auto, 43_000_000);
  assert.equal(size["1080"], 43_000_000);
  assert.equal(size["720"], 23_000_000);
  assert.equal(size["360"], 8_000_000);
  assert.equal(size.audio, 3_000_000);
});

test("dikey video (Shorts) ve ayrı ses yoksa 'sadece ses' sunulmaz (Mac ParsingTests.vertical)", () => {
  const result = options([ytdlp("a", "avc1", "none", 1080, 1920, 10, 1)]);
  assert.deepEqual(result.map((o) => o.quality), ["auto", "1080"]);
});

// Gerçek bir YouTube sayfasının oynatıcı bilgisinden (Big Buck Bunny, 2026-11-26) bir kesit. Beklenen boyutlar,
// yt-dlp 2026.11.23'ün aynı video için bulduklarıyla bayt bayt aynı.
const page = {
  videoId: "aqz-KE-bpKQ",
  title: "Big Buck Bunny 60fps 4K - Official Blender Foundation Short Film",
  lengthSeconds: "635",
  formats: [],
  adaptiveFormats: [
    [315, 'video/webm; codecs="vp9"', 3840, 2160, "1362269481", 26523399],
    [401, 'video/mp4; codecs="av01.0.12M.08"', 3840, 2160, "712445280", 17443607],
    [308, 'video/webm; codecs="vp9"', 2560, 1440, "473363704", 13250294],
    [299, 'video/mp4; codecs="avc1.64002a"', 1920, 1080, "257619653", 6933529],
    [303, 'video/webm; codecs="vp9"', 1920, 1080, "168736189", 4652291],
    [136, 'video/mp4; codecs="avc1.4d401f"', 1280, 720, "87293859", 2496430],
    [298, 'video/mp4; codecs="avc1.4d4020"', 1280, 720, "150524867", 4206005],
    [135, 'video/mp4; codecs="avc1.4d401e"', 854, 480, "28207144", 1098569],
    [134, 'video/mp4; codecs="avc1.4d401e"', 640, 360, "18294110", 643723],
    [133, 'video/mp4; codecs="avc1.4d4015"', 426, 240, "9323483", 245550],
    [140, 'audio/mp4; codecs="mp4a.40.2"', null, null, "10271496", 130992],
    [251, 'audio/webm; codecs="opus"', null, null, "10202210", 143452],
    [258, 'audio/mp4; codecs="mp4a.40.2"', null, null, "30767611", 389665],
    [380, 'audio/mp4; codecs="ac-3"', null, null, "30468809", 385273],
  ].map(([itag, mimeType, width, height, contentLength, bitrate]) => ({ itag, mimeType, width, height, contentLength, bitrate })),
};

test("YouTube sayfasından: başlık, süre ve yt-dlp'yle aynı boyutlar", () => {
  const result = fromPlayerResponse(page);
  assert.equal(result.title, page.title);
  assert.equal(result.duration, 635);
  assert.deepEqual(result.options, [
    { quality: "auto", size: 288387264 },
    { quality: "2160", size: 1393037092 },
    { quality: "1440", size: 504131315 },
    { quality: "1080", size: 288387264 },
    { quality: "720", size: 181292478 },
    { quality: "480", size: 58974755 },
    { quality: "360", size: 49061721 },
    { quality: "audio", size: 30767611 },
  ]);
});

test("sesli tek dosyalar (formats) görüntü ve ses kodeğiyle okunur", () => {
  const result = fromPlayerResponse({
    title: "Eski video", lengthSeconds: "60",
    formats: [{ itag: 18, mimeType: 'video/mp4; codecs="avc1.42001E, mp4a.40.2"', width: 640, height: 360, contentLength: "5000000", bitrate: 500000 }],
    adaptiveFormats: [],
  });
  // Ayrı ses yok, ses dosyanın içinde: boyuta ayrıca ses eklenmez.
  assert.deepEqual(result.options, [{ quality: "auto", size: 5000000 }, { quality: "360", size: 5000000 }]);
});

test("eksik ya da bozuk bilgi: null (liste uygulamadan istenir)", () => {
  assert.equal(fromPlayerResponse(null), null);
  assert.equal(fromPlayerResponse("bozuk"), null);
  assert.equal(fromPlayerResponse({ formats: [], adaptiveFormats: [] }), null);
  // Boyutların hiçbiri bilinmiyor (canlı yayın gibi).
  assert.equal(fromPlayerResponse({ adaptiveFormats: [{ mimeType: 'video/mp4; codecs="avc1"', width: 1280, height: 720, bitrate: 1 }] }), null);
  // Yalnızca ses.
  assert.equal(fromPlayerResponse({ adaptiveFormats: [{ mimeType: 'audio/mp4; codecs="mp4a.40.2"', contentLength: "10", bitrate: 1 }] }), null);
});
