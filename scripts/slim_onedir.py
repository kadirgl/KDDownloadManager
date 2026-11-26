#!/usr/bin/env python3
"""yt-dlp'nin klasör halindeki (PyInstaller onedir) resmi sürümünü uygulamaya gömmeden önce küçültür.

    slim_onedir.py <klasör>

Hem Intel hem Apple Silicon kodu içeren her Mach-O dosyasından sadece arm64 kısmı bırakılır (uygulama zaten
sadece Apple Silicon'da çalışıyor). Her parçanın imzası ayrı olduğu için imza bozulmaz.

Python çekirdeği _internal/Python dışında Python.framework içinde iki üç kez daha geliyor. Bunları yt-dlp
kullanmıyor (_internal/Python'u yüklüyor), o yüzden silinir. Sembolik bağlantıya çevrilmez: uygulama zip olarak
dağıtılıyor ve bağlantıları korumayan zip açıcılar paketin imzasını bozuyordu, macOS da uygulamaya "hasarlı"
diyordu. Gerçek dosya olarak da kalamazlar, çünkü codesign Python.framework/Python'u imzalarken "bundle format
is ambiguous" hatası veriyor.
"""
import os
import subprocess
import sys


def is_universal(path):
    result = subprocess.run(["lipo", "-archs", path], capture_output=True, text=True)
    archs = result.stdout.split()
    return result.returncode == 0 and "arm64" in archs and len(archs) > 1


def same_file_content(a, b):
    if not os.path.exists(b) or os.path.getsize(a) != os.path.getsize(b):
        return False
    with open(a, "rb") as first, open(b, "rb") as second:
        while True:
            x, y = first.read(1 << 20), second.read(1 << 20)
            if x != y:
                return False
            if not x:
                return True


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

    core = os.path.join(root, "_internal", "Python")
    removed = 0
    framework = os.path.join(root, "_internal", "Python.framework")
    for directory, _, names in os.walk(framework):
        for name in names:
            path = os.path.join(directory, name)
            if name == "Python" and (os.path.islink(path) or same_file_content(path, core)):
                os.remove(path)
                removed += 1

    print(f"{thinned} dosya arm64'e inceltildi, Python çekirdeğinin {removed} fazla kopyası silindi")


if __name__ == "__main__":
    main()
