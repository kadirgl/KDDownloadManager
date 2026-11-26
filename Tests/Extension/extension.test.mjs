// Chrome eklentisinin testleri (Mac ve Windows uygulaması aynı eklentiyi kullanıyor).
// Çalıştırma: scripts/test.sh extension  ya da  node --test Tests/Extension
import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "ChromeExtension");
const read = (file) => readFileSync(join(root, file), "utf8");
const manifest = JSON.parse(read("manifest.json"));
const locales = Object.fromEntries(readdirSync(join(root, "_locales")).map((lang) =>
  [lang, JSON.parse(read(`_locales/${lang}/messages.json`))]));

// app.js modül olarak yüklenirken chrome.i18n'i çağırıyor; Node'da sahte bir chrome nesnesi.
globalThis.chrome = {
  i18n: { getMessage: (key) => locales.en[key]?.message ?? "" },
  runtime: { getManifest: () => manifest, id: "test" },
};
const app = await import(pathToFileURL(join(root, "app.js")).href);

test("manifest: MV3, sürüm biçimi, Chrome'un istediği alanlar", () => {
  assert.equal(manifest.manifest_version, 3);
  assert.match(manifest.version, /^\d+(\.\d+){0,3}$/);
  assert.ok(manifest.key, "paketlenmemiş kopyanın sabit kimliği için 'key' gerekli");
  assert.ok(locales[manifest.default_locale], "default_locale klasörü yok");
  assert.ok(manifest.host_permissions.includes("http://127.0.0.1:47615/*"), "uygulamanın portuna izin yok");
});

test("manifest'te adı geçen her dosya pakette var", () => {
  const files = [
    manifest.background.service_worker,
    manifest.action.default_popup,
    ...Object.values(manifest.icons),
    ...Object.values(manifest.action.default_icon),
    ...manifest.content_scripts.flatMap((script) => [...(script.js ?? []), ...(script.css ?? [])]),
    ...(manifest.web_accessible_resources ?? []).flatMap((entry) => entry.resources),
  ];
  for (const file of files) assert.ok(existsSync(join(root, file)), `eksik: ${file}`);
  // popup.html'in yüklediği betik ve stil dosyaları da.
  const popup = read(manifest.action.default_popup);
  for (const [, file] of popup.matchAll(/(?:src|href)="([^":]+)"/g)) assert.ok(existsSync(join(root, file)), `popup'ta eksik: ${file}`);
});

test("diller aynı anahtarlara sahip, hiçbir metin boş değil", () => {
  const [base, ...others] = Object.keys(locales);
  const keys = Object.keys(locales[base]).sort();
  for (const lang of others) assert.deepEqual(Object.keys(locales[lang]).sort(), keys, `${lang} ile ${base} farklı`);
  for (const [lang, messages] of Object.entries(locales)) {
    for (const [key, value] of Object.entries(messages)) assert.ok(value.message?.trim(), `${lang}/${key} boş`);
  }
  // Mağaza sınırları: ad 75, açıklama 132 karakter.
  for (const messages of Object.values(locales)) {
    assert.ok(messages.extName.message.length <= 75);
    assert.ok(messages.extDescription.message.length <= 132);
  }
});

test("kodda kullanılan her metin anahtarı dil dosyalarında var", () => {
  const used = new Set();
  for (const file of readdirSync(root).filter((f) => /\.(js|html|json)$/.test(f))) {
    // Yorum satırlarındaki örnekler (// data-i18n="anahtar") sayılmaz.
    const code = read(file).split("\n").filter((line) => !line.trim().startsWith("//")).join("\n");
    for (const pattern of [/\bt\("([A-Za-z0-9_]+)"/g, /getMessage\("([A-Za-z0-9_]+)"/g, /__MSG_([A-Za-z0-9_]+)__/g, /data-i18n(?:-[a-z]+)?="([A-Za-z0-9_]+)"/g]) {
      for (const [, key] of code.matchAll(pattern)) used.add(key);
    }
  }
  assert.ok(used.size > 10, "metin anahtarları bulunamadı (desen değişmiş olabilir)");
  for (const [lang, messages] of Object.entries(locales)) {
    const missing = [...used].filter((key) => !(key in messages));
    assert.deepEqual(missing, [], `${lang} dosyasında eksik`);
  }
});

test("video siteleri ve indirilebilir adresler", () => {
  assert.ok(app.isVideoPage("https://www.youtube.com/watch?v=1"));
  assert.ok(app.isVideoPage("https://m.youtube.com/watch?v=1"));
  assert.ok(!app.isVideoPage("https://notyoutube.com/a"));
  assert.ok(!app.isVideoPage("bozuk"));
  assert.equal(app.videoSite("https://youtu.be/x"), "youtube.com");
  assert.equal(app.videoSite("https://www.vimeo.com/1"), "vimeo.com");
  assert.equal(app.videoSite("https://example.com/"), null);
  assert.equal(app.hostSite("https://www.example.com/a"), "example.com");
  for (const url of ["https://a/b.zip", "http://a", "ftp://a/b", "magnet:?xt=urn:btih:1"]) assert.ok(app.isDownloadable(url), url);
  for (const url of ["blob:https://a/1", "data:text/plain,x", "file:///etc/passwd", "javascript:1", "", undefined]) {
    assert.ok(!app.isDownloadable(url), String(url));
  }
});

test("kalite listesi uygulamanın tanıdığı değerler", () => {
  assert.deepEqual(app.QUALITIES.map((q) => q.id), ["auto", "2160", "1440", "1080", "720", "480", "360", "audio"]);
});

test("sayfada yakalanan akışların sınıflandırılması", () => {
  const h = (pairs) => Object.entries(pairs).map(([name, value]) => ({ name, value }));
  assert.deepEqual(app.classifyStream("https://cdn.x/master.m3u8"), { kind: "hls" });
  assert.deepEqual(app.classifyStream("https://cdn.x/play", h({ "Content-Type": "application/vnd.apple.mpegurl" })), { kind: "hls" });
  assert.deepEqual(app.classifyStream("https://cdn.x/manifest.mpd"), { kind: "dash" });
  assert.deepEqual(app.classifyStream("https://cdn.x/film.webm", h({ "Content-Length": String(5 * 1048576) })),
    { kind: "file", size: 5 * 1048576, extension: "webm" });
  assert.deepEqual(app.classifyStream("https://cdn.x/v", h({ "Content-Type": "video/mp4", "Content-Range": "bytes 0-1/9000000" })),
    { kind: "file", size: 9000000, extension: "mp4" });
  // Parçalar, küçük dosyalar, YouTube'un kendi akışı ve http olmayanlar sayılmaz.
  assert.equal(app.classifyStream("https://cdn.x/seg-1.ts"), null);
  assert.equal(app.classifyStream("https://cdn.x/a.mp4", h({ "Content-Length": "1000" })), null);
  assert.equal(app.classifyStream("https://r1.googlevideo.com/videoplayback"), null);
  assert.equal(app.classifyStream("blob:https://x/1"), null);
  assert.equal(app.classifyStream("https://x/page.html", h({ "Content-Type": "text/html" })), null);
});

test("yakalanan akışın kayıt adı sayfa başlığından, dosya adında olamayan karakterler olmadan", () => {
  assert.equal(app.streamSaveAs({ kind: "hls" }, 'Maç: "Özet" / 2026'), "Maç Özet 2026");
  assert.equal(app.streamSaveAs({ kind: "file", extension: "mp4" }, "Konferans"), "Konferans.mp4");
  assert.ok(app.streamSaveAs({ kind: "hls" }, "x".repeat(500)).length <= 120);
});
