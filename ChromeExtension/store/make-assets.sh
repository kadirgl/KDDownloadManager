#!/bin/bash
# Chrome Web Mağazası görsellerini üretir (ChromeExtension/store/assets/):
#   icon-128.png                     → mağaza ikonu (128 px, kenarda 16 px boşluk)
#   screenshot-{1,2,3}-{tr,en}.png   → ekran görüntüleri, 1280×800
#   promo-small-{tr,en}.png          → küçük tanıtım kutusu, 440×280
#   promo-marquee-{tr,en}.png        → büyük tanıtım görseli, 1400×560 (isteğe bağlı alan)
#
# İçerik gerçek arayüzden: eklentinin açılır penceresi ve sayfa betikleri sahte bir Chrome ortamında (src/)
# çizilir, uygulama paneli geliştirme sürümünün anlık görüntü modundan (KD_SNAPSHOT_DIR) gelir. Görüntüler
# Chrome'un başsız modunda, her seferinde yeni ve geçici bir profille alınır.
#
#   ChromeExtension/store/make-assets.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT="$PWD"
STORE="$ROOT/ChromeExtension/store"
ASSETS="$STORE/assets"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
PORT="${PORT:-47680}"

[[ -x "$CHROME" ]] || { echo "✗ Chrome bulunamadı (CHROME=/yol/Google Chrome)" >&2; exit 1; }
WORK="$(mktemp -d)"
SERVER=""
cleanup() { [[ -n "$SERVER" ]] && kill "$SERVER" 2>/dev/null; rm -rf "$WORK"; }
trap cleanup EXIT
mkdir -p "$ASSETS" "$WORK/root/app"

echo "→ İkonlar…"
swift scripts/render-icon.swift store "$WORK/root/assets" >/dev/null
cp "$WORK/root/assets/icon128.png" "$ASSETS/icon-128.png"

echo "→ Uygulama paneli…"
swift build -q
scripts/strings.sh compile .build/debug >/dev/null
for lang in tr en; do
    # Deneme ortamı: gerçek indirme listesine, klasörlere ve tarayıcı profillerine dokunulmaz.
    mkdir -p "$WORK/browsers"
    KD_SNAPSHOT_STORE=1 KD_SNAPSHOT_DIR="$WORK/root/app/$lang" KD_ARCHIVE="$WORK/archive.json" KD_BRIDGE_PORT=47698 \
        KD_BROWSER_DATA="$WORK/browsers" \
        .build/debug/KDDownloadManager -AppleLanguages "($lang)" -AppleLocale "$([[ $lang == tr ]] && echo tr_TR || echo en_US)" \
        -extensionBannerDismissed 99999999999 \
        -downloadFolder "$WORK/downloads" >/dev/null 2>&1
done

ln -s "$ROOT/ChromeExtension" "$WORK/root/ext"
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$WORK/root" >/dev/null 2>&1 &
SERVER=$!
for _ in $(seq 1 50); do curl -sf "http://127.0.0.1:$PORT/ext/manifest.json" >/dev/null && break; sleep 0.1; done

shoot() { # shoot ÇIKTI GENİŞLİK YÜKSEKLİK SAYFA
    "$CHROME" --headless=new --user-data-dir="$WORK/profile" --no-first-run --disable-extensions --hide-scrollbars \
        --force-device-scale-factor=1 --window-size="$2,$3" --virtual-time-budget=4000 \
        --screenshot="$1" "http://127.0.0.1:$PORT/$4" >/dev/null 2>&1
    [[ "$(sips -g pixelWidth -g pixelHeight "$1" | awk '/pixel/ {print $2}' | xargs)" == "$2 $3" ]] \
        || { echo "✗ $1 boyutu $2×$3 değil" >&2; exit 1; }
}

echo "→ Ekran görüntüleri ve tanıtım görselleri…"
for lang in tr en; do
    n=1
    for shot in popup inpage app; do
        shoot "$ASSETS/screenshot-$n-$lang.png" 1280 800 "ext/store/src/shot.html?shot=$shot&lang=$lang"
        n=$((n + 1))
    done
    shoot "$ASSETS/promo-small-$lang.png" 440 280 "ext/store/src/promo.html?size=small&lang=$lang"
    shoot "$ASSETS/promo-marquee-$lang.png" 1400 560 "ext/store/src/promo.html?size=marquee&lang=$lang"
done
echo "✓ Hazır: ${ASSETS#"$ROOT/"}"
ls -1 "$ASSETS"
