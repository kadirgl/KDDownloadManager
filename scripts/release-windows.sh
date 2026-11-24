#!/bin/bash
# Windows paketlerini (arm64, x64) imzalayıp mevcut bir GitHub sürümüne ekler; Windows uygulaması bunları
# kendisi bulup kurar (Windows/KDDownloadManager/Support/AppUpdater.cs).
#
#   scripts/release-windows.sh 1.9.3            → Windows/dist'teki zip'ler, yoksa UTM'deki Windows VM'de üretilir
#
# Sıra: önce scripts/release.sh 1.9.3 (macOS sürümü ve v1.9.3 etiketi), sonra bu betik.
# İmza macOS uygulamasınınkiyle aynı Ed25519 anahtarıyla atılır (Anahtar Zinciri; scripts/update-key.sh).
# Zip'ler: KDDownloadManager-Windows-<mimari>-<sürüm>.zip ve .zip.sig (base64).
# Gerekenler: gh (giriş yapılmış), Anahtar Zinciri'nde imza anahtarı; zip'ler yoksa UTM'de "Windows" adlı,
# .NET 10 SDK'sı C:\kd\dotnet'te kurulu bir sanal makine (Windows/scripts/utm-sync.sh).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
SERVICE="KDDownloadManager update signing key"
TAG="v$VERSION"
UTMCTL=/Applications/UTM.app/Contents/MacOS/utmctl
VM="${UTM_VM:-Windows}"

fail() { echo "✗ $*" >&2; exit 1; }

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Kullanım: scripts/release-windows.sh 1.9.3"
command -v gh >/dev/null || fail "gh yok (brew install gh)"
gh auth status >/dev/null 2>&1 || fail "gh'ye giriş yapılmamış (gh auth login)"
gh release view "$TAG" >/dev/null 2>&1 || fail "$TAG sürümü GitHub'da yok; önce scripts/release.sh $VERSION"

PRIVATE_KEY="$(security find-generic-password -a "$USER" -s "$SERVICE" -w 2>/dev/null)" \
    || fail "Gizli anahtar Anahtar Zinciri'nde yok (scripts/update-key.sh)"
PUBLIC_KEY="$(cat scripts/update-public-key.txt)"
[[ "$(printf '%s' "$PRIVATE_KEY" | swift scripts/update-signing.swift public)" == "$PUBLIC_KEY" ]] \
    || fail "Anahtar Zinciri'ndeki gizli anahtar scripts/update-public-key.txt ile eşleşmiyor"

mkdir -p Windows/dist
ASSETS=()
for ARCH in arm64 x64; do
    ZIP="Windows/dist/KDDownloadManager-Windows-$ARCH-$VERSION.zip"
    if [[ ! -f "$ZIP" ]]; then
        [[ -x "$UTMCTL" ]] || fail "$ZIP yok; Windows'ta Windows\\scripts\\package.ps1 -Version $VERSION çalıştırıp buraya kopyalayın"
        echo "→ $ARCH paketi UTM'deki Windows'ta üretiliyor…"
        Windows/scripts/utm-sync.sh "powershell -NoProfile -ExecutionPolicy Bypass -File Windows\\scripts\\package.ps1 -Arch $ARCH -Version $VERSION"
        "$UTMCTL" file pull "$VM" "C:\\kd\\src\\Windows\\dist\\KDDownloadManager-Windows-$ARCH-$VERSION.zip" > "$ZIP.part"
        mv "$ZIP.part" "$ZIP"
    fi
    unzip -tq "$ZIP" >/dev/null || fail "$ZIP bozuk"
    echo "→ $ZIP imzalanıyor…"
    printf '%s' "$PRIVATE_KEY" | swift scripts/update-signing.swift sign "$ZIP" > "$ZIP.sig"
    swift scripts/update-signing.swift verify "$ZIP" "$ZIP.sig" "$PUBLIC_KEY"
    ASSETS+=("$ZIP" "$ZIP.sig")
done
unset PRIVATE_KEY

echo "→ $TAG sürümüne ekleniyor…"
gh release upload "$TAG" "${ASSETS[@]}" --clobber
echo "✓ Eklendi: $(gh release view "$TAG" --json url -q .url)"
