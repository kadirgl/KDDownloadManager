#!/bin/bash
# Windows paketlerini (arm64, x64) imzalayıp mevcut bir GitHub sürümüne ekler; Windows uygulaması bunları
# kendisi bulup kurar (Windows/KDDownloadManager/Support/AppUpdater.cs).
#
#   scripts/release-windows.sh 1.9.4            → Windows/dist'teki paketler, yoksa VMware'deki Windows'ta üretilir
#
# Her mimari için iki paket: kurulum (KDDownloadManager-Windows-<mimari>-<sürüm>-Setup.exe; site ve yeni sürümlerin
# uygulama içi güncellemesi bunu kullanır) ve zip (KDDownloadManager-Windows-<mimari>-<sürüm>.zip; 1.9.3 ve öncesinin
# güncelleyicisi yalnızca zip'i tanır, kurulum istemeyenler de kullanır). Her birinin yanında .sig (base64).
#
# Sıra: önce scripts/release.sh 1.9.3 (macOS sürümü ve v1.9.3 etiketi), sonra bu betik.
# İmza macOS uygulamasınınkiyle aynı Ed25519 anahtarıyla atılır (Anahtar Zinciri; scripts/update-key.sh).
# Gerekenler: gh (giriş yapılmış), Anahtar Zinciri'nde imza anahtarı; paketler yoksa VMware Fusion'da SSH'si açık,
# .NET 10 SDK'sı C:\kd\dotnet'te ve Inno Setup 6 C:\kd\inno'da kurulu bir Windows sanal makinesi (Windows/scripts/vm-sync.sh).
# Paketlenmeden önce Windows testleri sanal makinede de (gerçek Windows'ta) çalışır.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
SERVICE="KDDownloadManager update signing key"
TAG="v$VERSION"

fail() { echo "✗ $*" >&2; exit 1; }

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Kullanım: scripts/release-windows.sh 1.9.4"
command -v gh >/dev/null || fail "gh yok (brew install gh)"
gh auth status >/dev/null 2>&1 || fail "gh'ye giriş yapılmamış (gh auth login)"
gh release view "$TAG" >/dev/null 2>&1 || fail "$TAG sürümü GitHub'da yok; önce scripts/release.sh $VERSION"

PRIVATE_KEY="$(security find-generic-password -a "$USER" -s "$SERVICE" -w 2>/dev/null)" \
    || fail "Gizli anahtar Anahtar Zinciri'nde yok (scripts/update-key.sh)"
PUBLIC_KEY="$(cat scripts/update-public-key.txt)"
[[ "$(printf '%s' "$PRIVATE_KEY" | swift scripts/update-signing.swift public)" == "$PUBLIC_KEY" ]] \
    || fail "Anahtar Zinciri'ndeki gizli anahtar scripts/update-public-key.txt ile eşleşmiyor"

echo "→ Windows testleri çalışıyor…"
KD_TESTS_REQUIRE_ALL=1 scripts/test.sh windows || fail "Windows testleri geçmedi; paketler yüklenmedi"

mkdir -p Windows/dist
ASSETS=()
for ARCH in arm64 x64; do
    ZIP="KDDownloadManager-Windows-$ARCH-$VERSION.zip"
    SETUP="KDDownloadManager-Windows-$ARCH-$VERSION-Setup.exe"
    if [[ ! -f "Windows/dist/$ZIP" || ! -f "Windows/dist/$SETUP" ]]; then
        if [[ -z "${SYNCED:-}" ]]; then
            echo "→ Kaynaklar sanal makineye kopyalanıyor ve Windows testleri orada çalışıyor…"
            Windows/scripts/vm-sync.sh "dotnet test Tests\\Windows --nologo -v quiet" \
                || fail "Windows sanal makinesine ulaşılamadı ya da testler orada geçmedi; Windows'ta Windows\\scripts\\package.ps1 -Version $VERSION çalıştırıp paketleri Windows/dist'e kopyalayabilirsiniz"
            SYNCED=1
        fi
        echo "→ $ARCH paketleri sanal makinedeki Windows'ta üretiliyor…"
        Windows/scripts/vm-sync.sh --run "powershell -NoProfile -ExecutionPolicy Bypass -File Windows\\scripts\\package.ps1 -Arch $ARCH -Version $VERSION" \
            || fail "$ARCH paketi üretilemedi"
        for FILE in "$ZIP" "$SETUP"; do
            Windows/scripts/vm-sync.sh --pull "C:\\kd\\src\\Windows\\dist\\$FILE" "Windows/dist/$FILE.part"
            mv "Windows/dist/$FILE.part" "Windows/dist/$FILE"
        done
    fi
    unzip -tq "Windows/dist/$ZIP" >/dev/null || fail "$ZIP bozuk"
    [[ "$(head -c 2 "Windows/dist/$SETUP")" == "MZ" ]] || fail "$SETUP bir Windows programı değil"
    for FILE in "$SETUP" "$ZIP"; do
        echo "→ $FILE imzalanıyor…"
        printf '%s' "$PRIVATE_KEY" | swift scripts/update-signing.swift sign "Windows/dist/$FILE" > "Windows/dist/$FILE.sig"
        swift scripts/update-signing.swift verify "Windows/dist/$FILE" "Windows/dist/$FILE.sig" "$PUBLIC_KEY"
        ASSETS+=("Windows/dist/$FILE" "Windows/dist/$FILE.sig")
    done
done
unset PRIVATE_KEY

echo "→ $TAG sürümüne ekleniyor…"
gh release upload "$TAG" "${ASSETS[@]}" --clobber
echo "✓ Eklendi: $(gh release view "$TAG" --json url -q .url)"
