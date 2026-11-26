#!/usr/bin/env python3
"""yt-dlp'nin klasör halindeki (PyInstaller onedir) resmi sürümünü uygulamaya gömmeden önce küçültür.

    slim_onedir.py <klasör>

Hem Intel hem Apple Silicon kodu içeren her Mach-O dosyasından sadece arm64 kısmı bırakılır (uygulama zaten
sadece Apple Silicon'da çalışıyor). Her parçanın imzası ayrı olduğu için imza bozulmaz.

Tekrar eden kopyalar (Python çekirdeği üç kez geliyor) bilerek sembolik bağlantıya çevrilmiyor: uygulama zip
olarak dağıtılıyor ve bağlantıları korumayan zip açıcılar (bazı üçüncü parti araçlar) paketi bozuyordu. macOS da
o zaman uygulamaya "hasarlı" diyordu.
"""
import os
import subprocess
import sys


def is_universal(path):
    result = subprocess.run(["lipo", "-archs", path], capture_output=True, text=True)
    archs = result.stdout.split()
    return result.returncode == 0 and "arm64" in archs and len(archs) > 1


def main():
    root = sys.argv[1]
    files = []
    for directory, _, names in os.walk(root):
        for name in names:
            path = os.path.join(directory, name)
            if not os.path.islink(path):
                files.append(path)

    thinned = 0
    for path in files:
        if is_universal(path):
            subprocess.run(["lipo", path, "-thin", "arm64", "-output", path], check=True)
            thinned += 1

    print(f"{thinned} dosya arm64'e inceltildi")


if __name__ == "__main__":
    main()
