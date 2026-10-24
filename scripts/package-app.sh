#!/bin/bash
# KD Download Manager'ı dist/KDDownloadManager.app olarak paketler.
#
#   scripts/package-app.sh             → dist/KDDownloadManager.app (+ .zip)
#   scripts/package-app.sh --install   → ayrıca /Applications'a kopyalayıp açar
#
# Sürüm: VERSION=1.2.0 scripts/package-app.sh (varsayılan 1.0.0; derleme numarası commit sayısı).
# aria2c, yt-dlp, ffmpeg ve QuickJS uygulamanın içine gömülür (scripts/bundle-tools.sh); hedef Mac'te
# Homebrew gerekmez ama paket sadece Apple Silicon'da çalışır.
# İmza yerel (ad-hoc): bu Mac'te sorunsuz açılır. Başka Mac'lere dağıtmak için Developer ID
# imzası ve notarization gerekir.
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="KD Download Manager"
EXECUTABLE="KDDownloadManager"
BUNDLE_ID="com.kadirgul.KDDownloadManager"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
APP="dist/$EXECUTABLE.app"

echo "→ Yardımcı programlar hazırlanıyor (aria2c, yt-dlp, ffmpeg, QuickJS)…"
scripts/bundle-tools.sh

echo "→ Release derleniyor…"
swift build -c release
BIN="$(swift build -c release --show-bin-path)"

echo "→ $APP oluşturuluyor…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/$EXECUTABLE" "$APP/Contents/MacOS/"
# İkonların kaynak paketi (Bundle.module) Bundle.main.resourceURL altında aranıyor; yoksa uygulama açılışta çöker.
cp -R "$BIN/${EXECUTABLE}_${EXECUTABLE}.bundle" "$APP/Contents/Resources/"
# Tarayıcı eklentisi: Ayarlar'daki "Kur" butonu buradan kopyalar.
cp -R ChromeExtension "$APP/Contents/Resources/BrowserExtension"
# Gömülü araçlar (her biri bundle-tools.sh'de ayrıca imzalandı); uygulama önce bunları kullanır.
mkdir -p "$APP/Contents/Helpers"
cp -R dist/tools/bin dist/tools/lib "$APP/Contents/Helpers/"

ICON_WORK="$(mktemp -d)"
trap 'rm -rf "$ICON_WORK"' EXIT
swift scripts/render-icon.swift app "$ICON_WORK/AppIcon.iconset"
iconutil -c icns "$ICON_WORK/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$NAME</string>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>tr</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <!-- Sadece menü çubuğunda; Dock'ta ve Cmd-Tab'da görünmez. -->
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <!-- Tarayıcılardaki magnet: linkleri (Ayarlar > Torrent ile varsayılan yapılabilir). -->
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>BitTorrent Magnet URL</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>magnet</string>
            </array>
        </dict>
    </array>
    <!-- Finder'dan .torrent dosyası açmak. -->
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>BitTorrent dosyası</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>org.bittorrent.torrent</string>
            </array>
        </dict>
    </array>
    <key>UTImportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>org.bittorrent.torrent</string>
            <key>UTTypeDescription</key>
            <string>BitTorrent dosyası</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.data</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>torrent</string>
                </array>
                <key>public.mime-type</key>
                <array>
                    <string>application/x-bittorrent</string>
                </array>
            </dict>
        </dict>
    </array>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null

echo "→ İmzalanıyor (ad-hoc)…"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict "$APP"

(cd dist && rm -f "$EXECUTABLE.zip" && ditto -c -k --keepParent "$EXECUTABLE.app" "$EXECUTABLE.zip")
echo "✓ Hazır: $APP  (sürüm $VERSION, derleme $BUILD_NUMBER)"

if [[ "${1:-}" == "--install" ]]; then
    TARGET="/Applications/$EXECUTABLE.app"
    # Açıksa önce kapat; yoksa eski kopya Chrome köprüsünün portunu tutar.
    pkill -f "$TARGET/Contents/MacOS/$EXECUTABLE" 2>/dev/null && sleep 1 || true
    rm -rf "$TARGET"
    cp -R "$APP" "$TARGET"
    open "$TARGET"
    echo "✓ /Applications'a kuruldu ve açıldı."
fi
