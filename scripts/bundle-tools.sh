#!/bin/bash
# Uygulamanın Homebrew olmadan çalışması için yardımcı programları dist/tools altına hazırlar:
#   aria2c, ffmpeg, ffprobe, qjs → bu Mac'teki Homebrew kurulumundan, kütüphaneleriyle birlikte
#                                  (sadece Apple Silicon; Homebrew'daki ikililer arm64)
#   yt-dlp                       → resmi GitHub sürümünün klasör hali; SHA-256 doğrulanır, dist/cache'te
#                                  saklanır, arm64'e inceltilir
# package-app.sh bunu kendisi çağırır; sonuç .app içinde Contents/Helpers'a kopyalanır.
#
# Gerekenler: brew install aria2 ffmpeg quickjs
# yt-dlp sürümünü değiştirmek için: YTDLP_VERSION=2026.11.01 scripts/package-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

YTDLP_VERSION="${YTDLP_VERSION:-2026.10.21}"
OUT=dist/tools
CACHE="dist/cache/yt-dlp-$YTDLP_VERSION"
BREW="$(brew --prefix 2>/dev/null || echo /opt/homebrew)"

programs=()
for tool in aria2c ffmpeg ffprobe qjs; do
    if [[ ! -x "$BREW/bin/$tool" ]]; then
        echo "✗ $tool bulunamadı. Kurmak için: brew install aria2 ffmpeg quickjs" >&2
        exit 1
    fi
    programs+=("$BREW/bin/$tool")
done

rm -rf "$OUT"
mkdir -p "$OUT/bin"
python3 scripts/bundle_dylibs.py "$OUT" "${programs[@]}"

# yt-dlp: Homebrew'daki sürüm Homebrew'un Python'una bağlı; resmi sürümün klasör hali (onedir) kullanılıyor.
# Tek dosyalık sürüm her çalıştırılışta kendini açtığı için ~4,5 sn bekletiyordu; klasör hali ~0,2 sn.
release="https://github.com/yt-dlp/yt-dlp/releases/download/$YTDLP_VERSION"
if [[ ! -f "$CACHE/yt-dlp_macos.zip" ]]; then
    echo "→ yt-dlp $YTDLP_VERSION indiriliyor…"
    mkdir -p "$CACHE"
    curl -fsSL -o "$CACHE/SHA2-256SUMS" "$release/SHA2-256SUMS"
    curl -fsSL -o "$CACHE/yt-dlp_macos.zip.part" "$release/yt-dlp_macos.zip"
    mv "$CACHE/yt-dlp_macos.zip.part" "$CACHE/yt-dlp_macos.zip"
fi
expected="$(awk '$2 == "yt-dlp_macos.zip" { print $1 }' "$CACHE/SHA2-256SUMS")"
actual="$(shasum -a 256 "$CACHE/yt-dlp_macos.zip" | cut -d' ' -f1)"
if [[ -z "$expected" || "$expected" != "$actual" ]]; then
    rm -rf "$CACHE"
    echo "✗ yt-dlp_macos.zip SHA-256 doğrulanamadı; dosya silindi." >&2
    exit 1
fi
ditto -x -k "$CACHE/yt-dlp_macos.zip" "$OUT/yt-dlp"
# Sadece arm64 kodu ve tekrar eden kopyalar yerine bağlantılar: 123 MB → ~46 MB.
python3 scripts/slim_onedir.py "$OUT/yt-dlp"
# Uygulama, içindeki sürümü güncellemeyle indirileninkiyle karşılaştırırken bunu okur.
echo "$YTDLP_VERSION" > "$OUT/yt-dlp.version"

echo "✓ Araçlar hazır: $(du -sh "$OUT" | cut -f1) ($OUT)"
