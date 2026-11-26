#!/bin/bash
# Mac kurulum diskini (DMG) üretir: açılınca solda uygulama, sağda Uygulamalar klasörü ve aralarında bir ok
# görünür; kullanıcı uygulamayı klasörün üstüne sürükler. Uygulama diskin içinden açılırsa kendini
# Uygulamalar'a taşımayı önerir (ApplicationsMover).
#
#   scripts/make-dmg.sh                    → dist/KDDownloadManager.dmg (dist/KDDownloadManager.app'ten)
#   VERSION=1.9.6 scripts/make-dmg.sh      → dist/KDDownloadManager-1.9.6.dmg
#   NOTARIZE=1 scripts/make-dmg.sh         → ayrıca Developer ID ile imzalar, noter onayı alıp iliştirir
#                                            (release.sh böyle çağırır; package-app.sh'taki ayarların aynısı)
#
# Önce scripts/package-app.sh çalışmış olmalı. Pencere düzeni Finder'a AppleScript ile kurdurulur; ilk seferde
# macOS, Terminal'in (ya da Claude'un) Finder'ı yönetmesine izin isteyebilir.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "✗ $*" >&2; exit 1; }

EXECUTABLE="KDDownloadManager"
APP="dist/$EXECUTABLE.app"
VOLUME="KD Download Manager"
VERSION="${VERSION:-}"
OUT="dist/$EXECUTABLE${VERSION:+-$VERSION}.dmg"
NOTARIZE="${NOTARIZE:-0}"
NOTARY_PROFILE="${NOTARY_PROFILE:-KDNotary}"
SIGN_IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -nE 's/.*"(Developer ID Application: [^"]+)".*/\1/p' | head -1)}"
# Pencere: 640×400'lük arka plan (scripts/render-dmg-background.swift) ve ikon merkezleri onunla aynı.
WINDOW_LEFT=200; WINDOW_TOP=120; WIDTH=640; HEIGHT=400; TITLE_BAR=28
APP_X=170; APP_Y=170; APPLICATIONS_X=470; APPLICATIONS_Y=170; ICON_SIZE=128

[[ -d "$APP" ]] || fail "$APP yok; önce scripts/package-app.sh"
[[ "$NOTARIZE" != "1" || -n "$SIGN_IDENTITY" ]] || fail "Noter onayı için Developer ID Application sertifikası gerekli"
[[ ! -e "/Volumes/$VOLUME" ]] || fail "\"$VOLUME\" adlı bir disk zaten bağlı; önce çıkarın (hdiutil detach \"/Volumes/$VOLUME\")"

WORK="$(mktemp -d)"
MOUNT=""
cleanup() {
    [[ -n "$MOUNT" ]] && hdiutil detach -quiet -force "$MOUNT" 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT

echo "→ Arka plan çiziliyor…"
swift scripts/render-dmg-background.swift "$WORK/background"
# Retina ve normal ekran için tek dosya.
tiffutil -cathidpicheck "$WORK/background/background.png" "$WORK/background/background@2x.png" \
    -out "$WORK/background.tiff" 2>/dev/null

echo "→ Disk hazırlanıyor…"
SIZE_MB=$(( $(du -sm "$APP" | cut -f1) + 40 ))
hdiutil create -quiet -size "${SIZE_MB}m" -fs HFS+ -volname "$VOLUME" -ov "$WORK/rw.dmg"
MOUNT="$(hdiutil attach -readwrite -noverify -noautoopen "$WORK/rw.dmg" 2>/dev/null | sed -nE 's#^/dev/[^[:space:]]+[[:space:]]+Apple_HFS[[:space:]]+(.*)$#\1#p' | head -1)"
[[ "$MOUNT" == "/Volumes/$VOLUME" ]] || fail "Disk beklenen yere bağlanmadı: ${MOUNT:-?}"

ditto "$APP" "$MOUNT/$EXECUTABLE.app"
ln -s /Applications "$MOUNT/Applications"
mkdir "$MOUNT/.background"
cp "$WORK/background.tiff" "$MOUNT/.background/background.tiff"
# Diskin kendi ikonu: uygulamanınki.
cp "$APP/Contents/Resources/AppIcon.icns" "$MOUNT/.VolumeIcon.icns"
SetFile -c icnC "$MOUNT/.VolumeIcon.icns"
SetFile -a C "$MOUNT"
# Gizli dosyaları gösteren Finder'larda da görünmesinler.
SetFile -a V "$MOUNT/.background"
SetFile -a V "$MOUNT/.VolumeIcon.icns"

echo "→ Pencere düzeni kuruluyor (Finder)…"
osascript <<APPLESCRIPT || fail "Finder pencere düzenini kuramadı (Sistem Ayarları › Gizlilik › Otomasyon'da Finder iznini verin)"
tell application "Finder"
    tell disk "$VOLUME"
        open
        delay 1
        set theWindow to container window
        set current view of theWindow to icon view
        set toolbar visible of theWindow to false
        set statusbar visible of theWindow to false
        set sidebar width of theWindow to 0
        set options to the icon view options of theWindow
        set arrangement of options to not arranged
        set icon size of options to $ICON_SIZE
        set text size of options to 13
        set label position of options to bottom
        set shows item info of options to false
        set shows icon preview of options to true
        set background picture of options to file ".background:background.tiff"
        set position of item "$EXECUTABLE.app" of theWindow to {$APP_X, $APP_Y}
        set position of item "Applications" of theWindow to {$APPLICATIONS_X, $APPLICATIONS_Y}
        -- Gizli dosyaları gösteren Finder'larda pencerenin dışında kalsınlar.
        try
            set position of item ".background" of theWindow to {$((WIDTH + 200)), 100}
        end try
        try
            set position of item ".VolumeIcon.icns" of theWindow to {$((WIDTH + 200)), 250}
        end try
        -- Boyut en son: Finder ilk açılışta kendi varsayılanına dönebiliyor.
        set the bounds of theWindow to {$WINDOW_LEFT, $WINDOW_TOP, $((WINDOW_LEFT + WIDTH)), $((WINDOW_TOP + HEIGHT + TITLE_BAR))}
        delay 1
        set the bounds of theWindow to {$WINDOW_LEFT, $WINDOW_TOP, $((WINDOW_LEFT + WIDTH)), $((WINDOW_TOP + HEIGHT + TITLE_BAR))}
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

# Finder'ın .DS_Store'u yazmasını bekle.
for _ in {1..20}; do [[ -f "$MOUNT/.DS_Store" ]] && break; sleep 0.5; done
[[ -f "$MOUNT/.DS_Store" ]] || fail "Finder pencere düzenini kaydetmedi"
chmod -Rf go-w "$MOUNT" 2>/dev/null || true
rm -rf "$MOUNT/.fseventsd" "$MOUNT/.Trashes"
sync
hdiutil detach -quiet "$MOUNT" || { sleep 2; hdiutil detach -quiet -force "$MOUNT"; }
MOUNT=""

echo "→ Sıkıştırılıyor…"
rm -f "$OUT"
hdiutil convert -quiet "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$OUT"

if [[ -n "$SIGN_IDENTITY" ]]; then
    echo "→ İmzalanıyor ($SIGN_IDENTITY)…"
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$OUT" || fail "Disk imzalanamadı"
    codesign --verify --strict "$OUT" || fail "Diskin imzası doğrulanamadı"
fi

if [[ "$NOTARIZE" == "1" ]]; then
    echo "→ Disk Apple'ın noter onayına gönderiliyor…"
    xcrun notarytool submit "$OUT" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$WORK/notary.json" || true
    STATUS="$(plutil -extract status raw -o - "$WORK/notary.json" 2>/dev/null || echo "?")"
    if [[ "$STATUS" != "Accepted" ]]; then
        cat "$WORK/notary.json" >&2
        ID="$(plutil -extract id raw -o - "$WORK/notary.json" 2>/dev/null || true)"
        [[ -n "$ID" ]] && xcrun notarytool log "$ID" --keychain-profile "$NOTARY_PROFILE" >&2 || true
        fail "Diskin noter onayı alınamadı ($STATUS)"
    fi
    xcrun stapler staple -q "$OUT" || fail "Noter onayı diske iliştirilemedi"
    spctl --assess --type open --context context:primary-signature "$OUT" 2>/dev/null || fail "Gatekeeper diski kabul etmedi"
    echo "  Noter onayı alındı ve diske iliştirildi."
fi

echo "✓ Hazır: $OUT ($(du -h "$OUT" | cut -f1 | tr -d ' '))"
