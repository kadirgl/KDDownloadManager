#!/bin/bash
# Yeni sürümü GitHub Releases'te yayımlar; kullanıcıların uygulaması bunu kendisi bulup kurar (AppUpdater).
#
#   scripts/release.sh 1.6.0               → notlar son sürümden beri commit başlıklarından
#   scripts/release.sh 1.6.0 notlar.md     → notlar dosyadan
#   CHROME_STORE=1 scripts/release.sh 1.6.0 → ayrıca eklentiyi Chrome Web Mağazası'na yükleyip incelemeye gönderir
#                                            (API bilgileri Anahtar Zinciri'nde; bkz. scripts/chrome-store.sh)
#
# Adımlar: testleri çalıştırır (scripts/test.sh), tarayıcı eklentisinin sürümünü uygulamanınkiyle eşitler, paketler (package-app.sh),
# sürükle-bırak kurulum diskini üretip noter onayından geçirir (make-dmg.sh), zip'i Anahtar Zinciri'ndeki gizli anahtarla imzalar, imzayı denetler,
# v1.6.0 etiketini ve main'i gönderir, zip + imzayla GitHub sürümünü oluşturur. Eklentinin mağaza paketi de
# (dist/KDDownloadManager-Chrome-1.6.0.zip) her sürümde üretilir; CHROME_STORE=1 değilse mağazaya elle yüklenir.
# Gerekenler: gh (giriş yapılmış), temiz çalışma ağacı, scripts/update-key.sh ile oluşturulmuş anahtar,
# Anahtar Zinciri'nde "Developer ID Application" sertifikası ve noter onayı profili (KDNotary; bkz. package-app.sh).
# Paket Developer ID ile imzalanıp Apple'ın noter onayından geçmeden sürüm yayımlanmaz.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
NOTES_FILE="${2:-}"
SERVICE="KDDownloadManager update signing key"
TAG="v$VERSION"

fail() { echo "✗ $*" >&2; exit 1; }

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Kullanım: scripts/release.sh 1.6.0 [notlar.md]"
command -v gh >/dev/null || fail "gh yok (brew install gh)"
gh auth status >/dev/null 2>&1 || fail "gh'ye giriş yapılmamış (gh auth login)"
[[ -z "$(git status --porcelain)" ]] || fail "Çalışma ağacında commit'lenmemiş değişiklik var"
[[ "$(git branch --show-current)" == "main" ]] || fail "main dalında değilsiniz"
[[ -f scripts/update-public-key.txt ]] || fail "Açık anahtar yok (scripts/update-key.sh)"
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && fail "$TAG etiketi zaten var"

LATEST="$(gh release view --json tagName -q .tagName 2>/dev/null || true)"
if [[ -n "$LATEST" ]]; then
    NEWEST="$(printf '%s\n%s\n' "${LATEST#v}" "$VERSION" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)"
    [[ "$NEWEST" == "$VERSION" && "${LATEST#v}" != "$VERSION" ]] || fail "$VERSION, yayımlanan son sürümden ($LATEST) yeni değil"
fi

PRIVATE_KEY="$(security find-generic-password -a "$USER" -s "$SERVICE" -w 2>/dev/null)" \
    || fail "Gizli anahtar Anahtar Zinciri'nde yok (scripts/update-key.sh)"
PUBLIC_KEY="$(cat scripts/update-public-key.txt)"
[[ "$(printf '%s' "$PRIVATE_KEY" | swift scripts/update-signing.swift public)" == "$PUBLIC_KEY" ]] \
    || fail "Anahtar Zinciri'ndeki gizli anahtar scripts/update-public-key.txt ile eşleşmiyor"

# yt-dlp yalnızca uygulamayla güncelleniyor (uygulama içinden ayrıca indirilmez): pakete yt-dlp'nin son sürümü
# girmeli. Bilerek eski bir sürümle yayımlamak için: YTDLP_ALLOW_OLD=1.
YTDLP_PINNED="$(sed -nE 's/^YTDLP_VERSION="\$\{YTDLP_VERSION:-([0-9.]+)\}"$/\1/p' scripts/bundle-tools.sh)"
YTDLP_LATEST="$(gh api repos/yt-dlp/yt-dlp/releases/latest --jq .tag_name 2>/dev/null || true)"
[[ -n "$YTDLP_PINNED" ]] || fail "scripts/bundle-tools.sh'ta yt-dlp sürümü okunamadı"
if [[ -n "$YTDLP_LATEST" && "$YTDLP_LATEST" != "$YTDLP_PINNED" && -z "${YTDLP_ALLOW_OLD:-}" ]]; then
    fail "yt-dlp'nin son sürümü $YTDLP_LATEST, pakete $YTDLP_PINNED girecek. scripts/bundle-tools.sh ve Windows/scripts/bundle-tools.ps1'deki sürümü güncelleyin (ya da YTDLP_ALLOW_OLD=1)"
fi
echo "→ yt-dlp $YTDLP_PINNED pakete girecek."

# Testler (Mac, Windows, eklenti) geçmeden paketleme bile başlamaz; hiçbiri araç eksikliğinden atlanamaz.
echo "→ Testler çalışıyor…"
KD_TESTS_REQUIRE_ALL=1 scripts/test.sh || fail "Testler geçmedi; sürüm yayımlanmadı"

# Uygulama ve tarayıcı eklentisi hep aynı sürümde: depodaki manifest de bu sürüme çekilip commit'lenir.
MANIFEST="ChromeExtension/manifest.json"
sed -i '' -E 's/"version": "[^"]*"/"version": "'"$VERSION"'"/' "$MANIFEST"
grep -q "\"version\": \"$VERSION\"" "$MANIFEST" || fail "Eklentinin sürümü ayarlanamadı"
if [[ -n "$(git status --porcelain "$MANIFEST")" ]]; then
    git commit -q -m "Sürüm $VERSION" -- "$MANIFEST"
fi
# Sürüm commit'i yalnızca manifest'teki sürümü değiştirdi: push öncesi kanca testleri yeniden çalıştırmasın.
export KD_TESTS_PASSED="$(git rev-parse HEAD)"

# Mağaza paketi yayımlamadan önce: eklentide mağazanın reddedeceği bir şey varsa sürüm hiç çıkmasın.
scripts/chrome-store.sh package "$VERSION"
STORE_ZIP="dist/KDDownloadManager-Chrome-$VERSION.zip"
if [[ "${CHROME_STORE:-}" == "1" ]]; then
    security find-generic-password -a refresh_token -s "KDDownloadManager Chrome Web Store" >/dev/null 2>&1 \
        || fail "CHROME_STORE=1 ama API bilgileri Anahtar Zinciri'nde yok (scripts/chrome-store.sh credentials)"
fi

VERSION="$VERSION" NOTARIZE=1 scripts/package-app.sh
ASSET="dist/KDDownloadManager-$VERSION.zip"
cp dist/KDDownloadManager.zip "$ASSET"
# Kurulum diski (site ve yeni kullanıcılar): imzalı ve noter onaylı. Uygulama içi güncelleme zip'i kullanır.
VERSION="$VERSION" NOTARIZE=1 scripts/make-dmg.sh
DMG="dist/KDDownloadManager-$VERSION.dmg"
[[ -f "$DMG" ]] || fail "$DMG üretilemedi"

echo "→ İmzalanıyor…"
printf '%s' "$PRIVATE_KEY" | swift scripts/update-signing.swift sign "$ASSET" > "$ASSET.sig"
unset PRIVATE_KEY
swift scripts/update-signing.swift verify "$ASSET" "$ASSET.sig" "$PUBLIC_KEY"

NOTES="$(mktemp)"
trap 'rm -f "$NOTES"' EXIT
if [[ -n "$NOTES_FILE" ]]; then
    cat "$NOTES_FILE" > "$NOTES"
else
    RANGE="${LATEST:+$LATEST..}HEAD"
    { echo "## Değişiklikler"; echo; git log --no-merges --format='- %s' "$RANGE"; } > "$NOTES"
fi
cat >> "$NOTES" <<NOTES

---
**macOS:** \`KDDownloadManager-$VERSION.dmg\` dosyasını indirip açın, uygulamayı yanındaki **Uygulamalar** klasörüne sürükleyin. Apple Silicon (M1 ve sonrası), macOS 14+. (Zip, uygulama içi güncelleme içindir.)
**Windows:** \`KDDownloadManager-Windows-x64-$VERSION-Setup.exe\` (çoğu bilgisayar) ya da \`KDDownloadManager-Windows-arm64-$VERSION-Setup.exe\` (ARM işlemcili bilgisayarlar) dosyasını indirip çalıştırın; yönetici izni istemez. Windows "bilgisayarınızı korudu" derse **Ek bilgi › Yine de çalıştır**'a tıklayın. Kurulum istemeyenler için aynı sürümün zip'i de var. Windows 10 (1809) ve 11.
Kurulu uygulama yeni sürümleri kendisi bulur (Ayarlar › Uygulama güncellemesi).
NOTES

echo "→ $TAG gönderiliyor…"
git tag -a "$TAG" -m "KD Download Manager $VERSION"
git push origin main "$TAG"
gh release create "$TAG" "$DMG" "$ASSET" "$ASSET.sig" --title "KD Download Manager $VERSION" --notes-file "$NOTES"
echo "✓ Yayımlandı: $(gh release view "$TAG" --json url -q .url)"

# Chrome Web Mağazası: uygulamanın kendi güncellemesinden bağımsız; mağaza incelemesi birkaç gün sürebilir ve
# eklenti uygulamayla aynı sürümde olmasa da çalışır.
if [[ "${CHROME_STORE:-}" == "1" ]]; then
    scripts/chrome-store.sh upload "$STORE_ZIP"
    scripts/chrome-store.sh publish
else
    echo "→ Chrome Web Mağazası: $STORE_ZIP dosyasını Geliştirici Panosu > öğe > Paket > Yeni paket yükle ile yükleyip"
    echo "  incelemeye gönderin (ya da: scripts/chrome-store.sh upload $STORE_ZIP && scripts/chrome-store.sh publish)."
fi
