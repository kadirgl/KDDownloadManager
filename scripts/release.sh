#!/bin/bash
# Yeni sürümü GitHub Releases'te yayımlar; kullanıcıların uygulaması bunu kendisi bulup kurar (AppUpdater).
#
#   scripts/release.sh 1.6.0               → notlar son sürümden beri commit başlıklarından
#   scripts/release.sh 1.6.0 notlar.md     → notlar dosyadan
#
# Adımlar: tarayıcı eklentisinin sürümünü uygulamanınkiyle eşitler, paketler (package-app.sh), zip'i Anahtar Zinciri'ndeki gizli anahtarla imzalar, imzayı denetler,
# v1.6.0 etiketini ve main'i gönderir, zip + imzayla GitHub sürümünü oluşturur.
# Gerekenler: gh (giriş yapılmış), temiz çalışma ağacı, scripts/update-key.sh ile oluşturulmuş anahtar.
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

# Uygulama ve tarayıcı eklentisi hep aynı sürümde: depodaki manifest de bu sürüme çekilip commit'lenir.
MANIFEST="ChromeExtension/manifest.json"
sed -i '' -E 's/"version": "[^"]*"/"version": "'"$VERSION"'"/' "$MANIFEST"
grep -q "\"version\": \"$VERSION\"" "$MANIFEST" || fail "Eklentinin sürümü ayarlanamadı"
if [[ -n "$(git status --porcelain "$MANIFEST")" ]]; then
    git commit -q -m "Sürüm $VERSION" -- "$MANIFEST"
fi

VERSION="$VERSION" scripts/package-app.sh
ASSET="dist/KDDownloadManager-$VERSION.zip"
cp dist/KDDownloadManager.zip "$ASSET"

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
**Kurulum:** \`KDDownloadManager-$VERSION.zip\` dosyasını indirip açın, uygulamayı **Uygulamalar** klasörüne taşıyın.
İlk açılışta macOS "geliştirici doğrulanamadı" derse: Sistem Ayarları › Gizlilik ve Güvenlik › **Yine de Aç**.
Kurulu uygulama yeni sürümleri kendisi bulur (Ayarlar › Uygulama güncellemesi). Apple Silicon (M1 ve sonrası), macOS 14+.
NOTES

echo "→ $TAG gönderiliyor…"
git tag -a "$TAG" -m "KD Download Manager $VERSION"
git push origin main "$TAG"
gh release create "$TAG" "$ASSET" "$ASSET.sig" --title "KD Download Manager $VERSION" --notes-file "$NOTES"
echo "✓ Yayımlandı: $(gh release view "$TAG" --json url -q .url)"
