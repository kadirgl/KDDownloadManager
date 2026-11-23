#!/bin/bash
# Arayüz metinleri: Türkçe kaynak koddaki metinler anahtar, İngilizcesi
# Sources/KDDownloadManager/Resources/Localizable.xcstrings dosyasında (Xcode'da da düzenlenebilir).
#
#   scripts/strings.sh sync           → kodu derleyip metinleri çıkarır, katalogu günceller (yeni anahtarlar
#                                       eklenir, kullanılmayanlar "stale" işaretlenir) ve çevirisi eksikleri listeler
#   scripts/strings.sh check          → çevirisi eksik anahtar varsa hata verir
#   scripts/strings.sh compile KLASÖR → KLASÖR/en.lproj ve KLASÖR/tr.lproj'u üretir (package-app.sh .app'in
#                                       Resources'ına, geliştirme denemelerinde .build/debug'a)
#
# Geliştirme sürümünü İngilizce denemek:
#   swift build && scripts/strings.sh compile .build/debug && .build/debug/KDDownloadManager -AppleLanguages '(en)'
set -euo pipefail
cd "$(dirname "$0")/.."

CATALOG="Sources/KDDownloadManager/Resources/Localizable.xcstrings"
RESOURCES="Sources/KDDownloadManager/Resources"

missing() {
    python3 - "$CATALOG" <<'PY'
import json, sys
strings = json.load(open(sys.argv[1]))["strings"]
for key, entry in sorted(strings.items()):
    if entry.get("shouldTranslate") is False or entry.get("extractionState") == "stale":
        continue
    en = entry.get("localizations", {}).get("en", {})
    unit = en.get("stringUnit", {})
    if not en or (unit and unit.get("state") != "translated"):
        print(key)
PY
}

case "${1:-}" in
sync)
    WORK="$(mktemp -d)"
    trap 'rm -rf "$WORK"' EXIT
    # Ayrı bir derleme klasörü: tüm dosyalar yeniden derlensin ki her dosyanın metinleri çıksın.
    swift build --scratch-path "$WORK/build" \
        -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$WORK/strings" >/dev/null
    xcrun xcstringstool sync "$CATALOG" --stringsdata "$WORK"/strings/*.stringsdata
    # Xcode'un yazdığı biçimle aynı kalsın (sıralı anahtarlar, 2 boşluk girinti).
    python3 - "$CATALOG" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path))
with open(path, "w") as f:
    json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=True)
    f.write("\n")
PY
    MISSING="$(missing)"
    if [[ -n "$MISSING" ]]; then
        echo "İngilizcesi eksik metinler:"
        echo "$MISSING" | sed 's/^/  /'
    else
        echo "✓ Tüm metinlerin İngilizcesi var."
    fi
    ;;
check)
    MISSING="$(missing)"
    [[ -z "$MISSING" ]] || { echo "✗ İngilizcesi eksik metinler:" >&2; echo "$MISSING" | sed 's/^/  /' >&2; exit 1; }
    ;;
compile)
    DEST="${2:?Hedef klasör gerekli}"
    mkdir -p "$DEST"
    rm -rf "$DEST/en.lproj" "$DEST/tr.lproj"
    xcrun xcstringstool compile "$CATALOG" --output-directory "$DEST" --serialization-format binary
    cp "$RESOURCES/en.lproj/InfoPlist.strings" "$DEST/en.lproj/"
    # Türkçe metinler koddaki anahtarların kendisi. Yine de her anahtar tabloda olmalı: tabloda bulunmayan
    # metin için Foundation geliştirme bölgesinin (en) tablosuna düşüyor ve Türkçe arayüzde İngilizce çıkıyor.
    mkdir -p "$DEST/tr.lproj"
    python3 - "$CATALOG" "$DEST/tr.lproj/Localizable.strings" <<'PY'
import json, plistlib, sys
strings = json.load(open(sys.argv[1]))["strings"]
table = {key: key for key, entry in strings.items() if key and entry.get("extractionState") != "stale"}
with open(sys.argv[2], "wb") as f:
    plistlib.dump(table, f, fmt=plistlib.FMT_BINARY)
PY
    ;;
*)
    sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
