#!/bin/bash
# Tarayıcı eklentisinin Chrome Web Mağazası paketi ve (isteğe bağlı) mağazaya yükleme.
#
#   scripts/chrome-store.sh package [SÜRÜM]   → dist/KDDownloadManager-Chrome-SÜRÜM.zip (mağazaya yüklenecek paket)
#                                              SÜRÜM verilmezse ChromeExtension/manifest.json'daki (release.sh onu
#                                              uygulamanın sürümüne eşitliyor).
#   scripts/chrome-store.sh set-id KİMLİK     → mağazanın verdiği eklenti kimliğini macOS ve Windows uygulamasına yazar
#   scripts/chrome-store.sh credentials       → Chrome Web Store API bilgilerini Anahtar Zinciri'ne kaydeder (bir kez)
#   scripts/chrome-store.sh upload ZIP        → paketi mağazadaki öğeye taslak olarak yükler (incelemeye göndermez)
#   scripts/chrome-store.sh publish           → yüklenen taslağı incelemeye gönderir; onaylanınca yayımlanır
#   scripts/chrome-store.sh status            → öğenin yükleme/inceleme durumu
#
# Paket depodaki eklentiden farkı: manifest'teki "key" çıkarılır (mağaza kabul etmiyor ve kimliği kendisi veriyor;
# "key" yalnızca uygulamayla gelen paketlenmemiş kopyanın kimliğini sabitliyor), mağaza malzemeleri (store/) ve
# README girmez.
#
# API bilgileri (OAuth istemci kimliği/gizli anahtarı, yenileme jetonu, yayıncı kimliği) depoya yazılmaz; Anahtar
# Zinciri'nde "KDDownloadManager Chrome Web Store" hizmetinde durur. Nasıl alınacağı: ChromeExtension/store/REHBER.md.
# Anahtar Zinciri komutları Claude Code'un Bash sandbox'ında çalışmaz.
set -euo pipefail
cd "$(dirname "$0")/.."

SERVICE="KDDownloadManager Chrome Web Store"
API="https://chromewebstore.googleapis.com"
SWIFT_ID_FILE="Sources/KDDownloadManager/Support/BrowserExtension.swift"
CS_ID_FILE="Windows/KDDownloadManager/Support/BrowserExtension.cs"

fail() { echo "✗ $*" >&2; exit 1; }

# Mağazanın verdiği kimlik (uygulamalara yazılan); yoksa boş.
store_id() {
    sed -nE 's/.*static let storeExtensionID = "([a-p]*)".*/\1/p' "$SWIFT_ID_FILE"
}

package() {
    local version="${1:-}"
    local manifest="ChromeExtension/manifest.json"
    [[ -n "$version" ]] || version="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$manifest")"
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Sürüm anlaşılamadı: '$version' (örn. 1.9.3)"

    local work zip
    work="$(mktemp -d)"
    trap 'rm -rf "$work"' RETURN
    mkdir -p dist
    zip="$PWD/dist/KDDownloadManager-Chrome-$version.zip"

    # Yalnızca eklentinin çalışırken kullandığı dosyalar.
    rsync -a --exclude 'store/' --exclude 'README.md' --exclude '.DS_Store' ChromeExtension/ "$work/extension/"
    python3 - "$work/extension/manifest.json" "$version" <<'PY'
import json, sys
path, version = sys.argv[1], sys.argv[2]
manifest = json.load(open(path))
manifest.pop("key", None)
manifest["version"] = version
with open(path, "w") as f:
    json.dump(manifest, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY
    check_package "$work/extension" "$version"

    rm -f "$zip"
    (cd "$work/extension" && COPYFILE_DISABLE=1 zip -qrX "$zip" . -x '.*')
    echo "✓ Hazır: ${zip#"$PWD/"}  (sürüm $version, $(du -h "$zip" | cut -f1 | xargs))"
}

# Mağazanın reddedeceği ya da incelemede takılacak şeyler.
check_package() {
    python3 - "$1" "$2" <<'PY'
import json, pathlib, re, sys
root, version = pathlib.Path(sys.argv[1]), sys.argv[2]
manifest = json.loads((root / "manifest.json").read_text())
problems = []
if "key" in manifest: problems.append('manifest\'te "key" var')
if manifest.get("version") != version: problems.append("sürüm tutmuyor")
if manifest.get("manifest_version") != 3: problems.append("manifest_version 3 değil")
for size, path in manifest.get("icons", {}).items():
    if not (root / path).is_file(): problems.append(f"ikon yok: {path}")
if "128" not in manifest.get("icons", {}): problems.append("128 px ikon yok")
locales = sorted(p.name for p in (root / "_locales").iterdir())
keys = {name: set(json.loads((root / "_locales" / name / "messages.json").read_text())) for name in locales}
for name in locales:
    for other in locales:
        missing = keys[other] - keys[name]
        if missing: problems.append(f"_locales/{name}: eksik anahtarlar {sorted(missing)}")
# Uzaktan kod: başka bir sunucudan betik yükleme ya da dizgeden kod çalıştırma (MV3'te yasak).
for js in root.rglob("*.js"):
    text = js.read_text()
    if re.search(r"\beval\s*\(|new\s+Function\s*\(|importScripts\s*\(|import\s*\(\s*['\"`]https?:", text):
        problems.append(f"{js.name}: uzaktan/dinamik kod")
for html in root.rglob("*.html"):
    if re.search(r"<script[^>]+src=['\"]https?:", html.read_text()):
        problems.append(f"{html.name}: uzaktan betik")
if problems:
    sys.exit("✗ Paket mağazaya uygun değil:\n  " + "\n  ".join(problems))
PY
}

set_id() {
    local id="${1:-}"
    [[ "$id" =~ ^[a-p]{32}$ ]] || fail "Kimlik 32 harf olmalı (a–p), örn. abcdefghijklmnopabcdefghijklmnop"
    [[ "$id" != "necbfaijhfnnoikbppjdjcpfjekefdbk" ]] || fail "Bu, paketlenmemiş kopyanın kimliği; mağazanın verdiğini girin"
    sed -i '' -E 's/(static let storeExtensionID = )"[a-p]*"/\1"'"$id"'"/' "$SWIFT_ID_FILE"
    grep -q "storeExtensionID = \"$id\"" "$SWIFT_ID_FILE" || fail "$SWIFT_ID_FILE güncellenemedi"
    if [[ -f "$CS_ID_FILE" ]]; then
        sed -i '' -E 's/(const string StoreExtensionId = )"[a-p]*"/\1"'"$id"'"/' "$CS_ID_FILE"
        grep -q "StoreExtensionId = \"$id\"" "$CS_ID_FILE" || fail "$CS_ID_FILE güncellenemedi"
    fi
    echo "✓ Mağaza kimliği yazıldı: $id"
    echo "  Mağaza sayfası: https://chromewebstore.google.com/detail/$id"
}

# --- Chrome Web Store API (v2) ----------------------------------------------------------------------

secret() {
    security find-generic-password -a "$1" -s "$SERVICE" -w 2>/dev/null \
        || fail "Anahtar Zinciri'nde '$1' yok (scripts/chrome-store.sh credentials)"
}

credentials() {
    echo "Chrome Web Store API bilgileri Anahtar Zinciri'ne ($SERVICE) kaydedilecek. Nasıl alınır: ChromeExtension/store/REHBER.md"
    local name value
    for name in client_id client_secret refresh_token publisher_id; do
        read -r -s -p "$name: " value
        echo
        [[ -n "$value" ]] || fail "$name boş olamaz"
        security add-generic-password -U -a "$name" -s "$SERVICE" -w "$value"
    done
    unset value
    echo "✓ Kaydedildi"
}

# Yenileme jetonundan kısa ömürlü erişim jetonu. Gizli bilgiler komut satırına değil curl'ün girişine verilir.
access_token() {
    local response
    response="$(printf 'client_id=%s&client_secret=%s&refresh_token=%s&grant_type=refresh_token' \
        "$(secret client_id)" "$(secret client_secret)" "$(secret refresh_token)" \
        | curl -sS --fail-with-body https://oauth2.googleapis.com/token --data @-)" \
        || fail "Erişim jetonu alınamadı: $(printf '%s' "$response" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("error_description","?"))' 2>/dev/null)"
    printf '%s' "$response" | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])'
}

item_path() {
    local id
    id="$(store_id)"
    [[ -n "$id" ]] || fail "Mağaza kimliği yazılmamış (scripts/chrome-store.sh set-id KİMLİK)"
    echo "publishers/$(secret publisher_id)/items/$id"
}

# api YÖNTEM YOL [curl seçenekleri…]: jeton başlığı da girişten okunur.
api() {
    local method="$1" url="$2"
    shift 2
    printf 'Authorization: Bearer %s' "$(access_token)" \
        | curl -sS --fail-with-body -X "$method" -H @- "$@" "$url"
}

upload() {
    local zip="${1:-}"
    [[ -f "$zip" ]] || fail "Kullanım: scripts/chrome-store.sh upload dist/KDDownloadManager-Chrome-1.9.3.zip"
    local item
    item="$(item_path)"
    echo "→ $zip yükleniyor…"
    local result state
    result="$(api POST "$API/upload/v2/$item:upload" -H 'Content-Type: application/zip' --data-binary @"$zip")"
    state="$(printf '%s' "$result" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("uploadState",""))')"
    # Büyük paketlerde yükleme işlenirken durum "sürüyor" döner; bitene kadar bakılır.
    for _ in $(seq 1 30); do
        [[ "$state" == *IN_PROGRESS* ]] || break
        sleep 2
        state="$(api GET "$API/v2/$item:fetchStatus" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("lastAsyncUploadState") or d.get("uploadState",""))')"
    done
    [[ "$state" == "SUCCEEDED" || "$state" == "UPLOAD_STATE_SUCCEEDED" ]] || fail "Yükleme başarısız: $result"
    echo "✓ Taslak yüklendi (incelemeye göndermek için: scripts/chrome-store.sh publish)"
}

publish() {
    local item
    item="$(item_path)"
    api POST "$API/v2/$item:publish" -H 'Content-Type: application/json' --data '{"publishType":"DEFAULT_PUBLISH"}' \
        | python3 -c 'import json,sys; d=json.load(sys.stdin); print("✓ İncelemeye gönderildi:", d.get("state","?")); [print("  uyarı:", w) for w in (d.get("warningInfo") or {}).get("warnings",[])]'
}

status() {
    local item
    item="$(item_path)"
    api GET "$API/v2/$item:fetchStatus" | python3 -m json.tool
}

case "${1:-}" in
package) package "${2:-}" ;;
set-id) set_id "${2:-}" ;;
credentials) credentials ;;
upload) upload "${2:-}" ;;
publish) publish ;;
status) status ;;
*) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
