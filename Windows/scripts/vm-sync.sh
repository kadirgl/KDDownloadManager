#!/bin/bash
# Geliştirme kolaylığı (Mac'te): kaynakları Windows sanal makinesine (VMware Fusion) SSH ile kopyalar ve isteğe bağlı
# bir PowerShell komutu çalıştırır. Sanal makinede OpenSSH Sunucusu açık ve ~/.ssh/kd_windows_vm anahtarına izinli
# olmalı (README › Windows › Mac'ten derleme).
#
#   Windows/scripts/vm-sync.sh                              → kaynakları C:\kd\src'ye kopyalar
#   Windows/scripts/vm-sync.sh 'dotnet --info'              → kopyalar ve komutu C:\kd\src içinde çalıştırır
#   Windows/scripts/vm-sync.sh --pull 'C:\kd\x.zip' dist/   → sanal makineden dosya alır (kopyalamadan)
#   Windows/scripts/vm-sync.sh --run 'dotnet --info'        → kopyalamadan yalnızca komutu çalıştırır
#
# Adres: KD_VM=kullanıcı@adres, yoksa ~/.config/kd-download-manager/vm dosyasındaki kullanıcı adıyla ve VMware'in
# DHCP kayıtlarından bulunan adresle (sanal makinenin adresi yeniden başlayınca değişebilir).
set -euo pipefail
cd "$(dirname "$0")/../.."

KEY="$HOME/.ssh/kd_windows_vm"
DEST="${KD_VM_DEST:-C:\\kd\\src}"
CONFIG="$HOME/.config/kd-download-manager/vm"
VMX="${KD_VMX:-$HOME/Virtual Machines.localized/Windows 11 64-bit Arm.vmwarevm/Windows 11 64-bit Arm.vmx}"

fail() { echo "✗ $*" >&2; exit 1; }

[[ -f "$KEY" ]] || fail "$KEY yok"
if [[ -z "${KD_VM:-}" ]]; then
    VM_USER="$(sed -n 's/^user=//p' "$CONFIG" 2>/dev/null || true)"
    [[ -n "$VM_USER" ]] || fail "Sanal makinedeki kullanıcı adı bilinmiyor: $CONFIG dosyasına user=<ad> yazın ya da KD_VM=kullanıcı@adres verin"
    MAC="$(sed -nE 's/^ethernet0\.generatedAddress = "([^"]+)"/\1/p' "$VMX" | tr 'A-F' 'a-f')"
    [[ -n "$MAC" ]] || fail "Sanal makinenin ağ adresi $VMX'te bulunamadı"
    # Son kira kaydı geçerli olan.
    IP="$(awk -v mac="$MAC" '/^lease /{ip=$2} $1=="hardware" && $3==mac";" {found=ip} END{print found}' \
        /var/db/vmware/vmnet-dhcpd-vmnet8.leases 2>/dev/null)"
    [[ -n "$IP" ]] || fail "Sanal makinenin IP adresi bulunamadı (açık mı?)"
    KD_VM="$VM_USER@$IP"
fi
SSH=(ssh -i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new "$KD_VM")
SCP=(scp -q -i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)

# PowerShell komutu: .NET'i PATH'e ekler, C:\kd\src'de çalışır; hata olursa çıkış kodu 1.
remote() {
    "${SSH[@]}" "\$ErrorActionPreference='Stop'; \$ProgressPreference='SilentlyContinue'; \$env:PATH='C:\\kd\\dotnet;'+\$env:PATH; \$env:DOTNET_CLI_TELEMETRY_OPTOUT='1'; \$env:DOTNET_NOLOGO='1'; New-Item -ItemType Directory -Force '$DEST' | Out-Null; Set-Location '$DEST'; $1; if (\$LASTEXITCODE) { exit \$LASTEXITCODE }"
}

case "${1:-}" in
--pull)
    [[ $# -eq 3 ]] || fail "Kullanım: vm-sync.sh --pull 'C:\\yol\\dosya' yerel/klasör/"
    "${SCP[@]}" "$KD_VM:${2//\\//}" "$3"
    exit 0 ;;
--run)
    remote "$2"
    exit 0 ;;
esac

ARCHIVE="$(mktemp -t kd-src).tar"
trap 'rm -f "$ARCHIVE"' EXIT
# Derleme çıktıları, üretilmiş paketler ve yerel dosyalar gitmez.
COPYFILE_DISABLE=1 tar -cf "$ARCHIVE" --exclude 'bin' --exclude 'obj' --exclude '.DS_Store' --exclude 'Windows/dist' \
    Windows ChromeExtension Tests/Windows Package.swift scripts/update-public-key.txt \
    Sources/KDDownloadManager/Support/BrowserExtension.swift Sources/KDDownloadManager/Models/DownloadItem.swift
"${SCP[@]}" "$ARCHIVE" "$KD_VM:C:/kd/src.tar" 2>/dev/null || {
    "${SSH[@]}" "New-Item -ItemType Directory -Force C:\\kd | Out-Null" && "${SCP[@]}" "$ARCHIVE" "$KD_VM:C:/kd/src.tar"
}
# Önceki kaynaklar silinir; derleme önbellekleri (bin, obj) ve Windows\dist kalır.
remote "Get-ChildItem '$DEST' -Exclude Windows,Tests | Remove-Item -Recurse -Force; Get-ChildItem '$DEST\\Windows' -ErrorAction SilentlyContinue | Where-Object { \$_.Name -notin 'KDDownloadManager','dist' } | Remove-Item -Recurse -Force; Get-ChildItem '$DEST\\Windows\\KDDownloadManager','$DEST\\Tests\\Windows' -ErrorAction SilentlyContinue | Where-Object { \$_.Name -notin 'bin','obj' } | Remove-Item -Recurse -Force; tar -xf C:\\kd\\src.tar -C '$DEST'; Remove-Item C:\\kd\\src.tar"

if [[ $# -gt 0 ]]; then
    remote "$1"
fi
