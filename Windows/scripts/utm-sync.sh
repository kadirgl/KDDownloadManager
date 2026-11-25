#!/bin/bash
# Geliştirme kolaylığı (Mac'te): kaynakları UTM'deki Windows sanal makinesine kopyalar ve isteğe bağlı bir
# PowerShell komutu çalıştırır. Dosyalar ve komutlar UTM'nin QEMU misafir ajanıyla (utmctl) gider;
# misafirde paylaşılan klasör ya da SSH gerekmez. Komutlar misafirde SYSTEM olarak çalışır.
#
#   Windows/scripts/utm-sync.sh                       → kaynakları C:\kd\src'ye kopyalar
#   Windows/scripts/utm-sync.sh 'dotnet --info'       → kopyalar ve komutu C:\kd\src içinde çalıştırır
#
#   UTM_VM=Windows (varsayılan), UTM_DEST=C:\kd\src
set -euo pipefail
cd "$(dirname "$0")/../.."

VM="${UTM_VM:-Windows}"
DEST="${UTM_DEST:-C:\\kd\\src}"
UTMCTL=/Applications/UTM.app/Contents/MacOS/utmctl
ARCHIVE="$(mktemp -t kd-src).tar"
trap 'rm -f "$ARCHIVE"' EXIT

# Derleme çıktıları, üretilmiş paketler (Windows/dist; yüzlerce MB, misafir ajanıyla aktarımı çok yavaş) ve yerel dosyalar gitmez.
COPYFILE_DISABLE=1 tar -cf "$ARCHIVE" --exclude 'bin' --exclude 'obj' --exclude '.DS_Store' --exclude 'Windows/dist' \
    Windows ChromeExtension scripts/update-public-key.txt
"$UTMCTL" file push "$VM" 'C:\kd\src.tar' < "$ARCHIVE"
"$UTMCTL" exec "$VM" --cmd powershell.exe -NoProfile -Command \
    "\$ErrorActionPreference='Stop'; New-Item -ItemType Directory -Force '$DEST' | Out-Null; Get-ChildItem '$DEST' -Exclude Windows | Remove-Item -Recurse -Force; Get-ChildItem '$DEST\\Windows' -ErrorAction SilentlyContinue | Where-Object { \$_.Name -notin 'KDDownloadManager','dist' } | Remove-Item -Recurse -Force; Get-ChildItem '$DEST\\Windows\\KDDownloadManager' -ErrorAction SilentlyContinue | Where-Object { \$_.Name -notin 'bin','obj' } | Remove-Item -Recurse -Force; tar -xf C:\\kd\\src.tar -C '$DEST'; Remove-Item C:\\kd\\src.tar"

if [[ $# -gt 0 ]]; then
    "$UTMCTL" exec "$VM" --cmd powershell.exe -NoProfile -Command \
        "\$env:PATH='C:\\kd\\dotnet;'+\$env:PATH; \$env:DOTNET_CLI_TELEMETRY_OPTOUT='1'; \$env:DOTNET_NOLOGO='1'; Set-Location '$DEST'; $1"
fi
