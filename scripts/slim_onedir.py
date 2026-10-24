#!/usr/bin/env python3
"""yt-dlp'nin klasör halindeki (PyInstaller onedir) resmi sürümünü uygulamaya gömmeden önce küçültür.

    slim_onedir.py <klasör>

1. Hem Intel hem Apple Silicon kodu içeren her Mach-O dosyasından sadece arm64 kısmı bırakılır
   (uygulama zaten sadece Apple Silicon'da çalışıyor). Her parçanın imzası ayrı olduğu için imza bozulmaz.
2. Zip'te sembolik bağlantı olmadığından aynı dosya birkaç kez geliyor (Python çekirdeği üç kez);
   birebir aynı olan kopyalar ilkini gösteren göreli sembolik bağlantıyla değiştirilir.
"""
import hashlib
import os
import subprocess
import sys


def is_universal(path):
    result = subprocess.run(["lipo", "-archs", path], capture_output=True, text=True)
    archs = result.stdout.split()
    return result.returncode == 0 and "arm64" in archs and len(archs) > 1


def file_hash(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


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

    first_by_hash = {}
    linked = 0
    for path in sorted(files, key=lambda p: (p.count(os.sep), p)):
        digest = file_hash(path)
        original = first_by_hash.setdefault(digest, path)
        if original != path and os.path.getsize(path) > 64 * 1024:
            os.remove(path)
            os.symlink(os.path.relpath(original, os.path.dirname(path)), path)
            linked += 1

    print(f"{thinned} dosya arm64'e inceltildi, {linked} kopya bağlantıya çevrildi")


if __name__ == "__main__":
    main()
