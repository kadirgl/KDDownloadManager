#!/usr/bin/env python3
"""Homebrew programlarını, bağlı oldukları Homebrew kütüphaneleriyle birlikte taşınabilir hale getirir.

    bundle_dylibs.py <çıktı-klasörü> <program>...

Programlar <çıktı>/bin, kütüphaneler <çıktı>/lib altına kopyalanır. Homebrew yollarını gösteren
bağlantılar "@executable_path/../lib/<ad>" olarak yeniden yazılır; böylece uygulama Homebrew
olmayan bir Mac'te de çalışır ve Homebrew olan bir Mac'te yanlışlıkla oradaki sürümleri yüklemez.
install_name_tool imzayı bozduğu için her dosya yeniden (ad-hoc) imzalanır.
"""
import os
import shutil
import subprocess
import sys

HOMEBREW = os.path.realpath(subprocess.run(
    ["brew", "--prefix"], capture_output=True, text=True).stdout.strip() or "/opt/homebrew")


def run(*args):
    subprocess.run(args, check=True, capture_output=True)


def load_commands(path):
    """otool -L çıktısındaki bağlantılar (ilk satır dosyanın kendisi, kütüphanelerde kimliği)."""
    lines = subprocess.run(["otool", "-L", path], capture_output=True, text=True, check=True).stdout.splitlines()[1:]
    names = [line.strip().split(" (")[0] for line in lines]
    own_id = subprocess.run(["otool", "-D", path], capture_output=True, text=True).stdout.splitlines()[1:]
    return [name for name in names if name not in own_id]


def rpaths(path):
    out = subprocess.run(["otool", "-l", path], capture_output=True, text=True, check=True).stdout.splitlines()
    result = []
    for i, line in enumerate(out):
        if line.strip() == "cmd LC_RPATH":
            result.append(out[i + 2].strip().split()[1])
    return result


def resolve(reference, loader):
    """Bağlantıyı gerçek dosya yoluna çevirir; Homebrew dışındakiler (sistem kütüphaneleri) için None."""
    loader_dir = os.path.dirname(os.path.realpath(loader))
    candidates = []
    if reference.startswith("@loader_path/"):
        candidates.append(os.path.join(loader_dir, reference[len("@loader_path/"):]))
    elif reference.startswith("@rpath/"):
        for rpath in rpaths(loader) + [HOMEBREW + "/lib"]:
            base = rpath.replace("@loader_path", loader_dir).replace("@executable_path", loader_dir)
            candidates.append(os.path.join(base, reference[len("@rpath/"):]))
    else:
        candidates.append(reference)
    for candidate in candidates:
        real = os.path.realpath(candidate)
        if real.startswith(HOMEBREW) and os.path.exists(real):
            return real
    return None


def main():
    out, programs = sys.argv[1], sys.argv[2:]
    bin_dir, lib_dir = os.path.join(out, "bin"), os.path.join(out, "lib")
    os.makedirs(bin_dir, exist_ok=True)
    os.makedirs(lib_dir, exist_ok=True)

    # Kopyalanacak her dosya: gerçek yol → kopyası. Kütüphaneler gerçek dosya adıyla tutulur.
    copies = {}
    queue = []
    for program in programs:
        real = os.path.realpath(program)
        target = os.path.join(bin_dir, os.path.basename(program))
        copies[real] = target
        queue.append(real)

    references = {}  # dosya → [(bağlantı metni, bağlanan gerçek yol)]
    while queue:
        current = queue.pop()
        references[current] = []
        for reference in load_commands(current):
            real = resolve(reference, current)
            if real is None:
                continue
            references[current].append((reference, real))
            if real not in copies:
                copies[real] = os.path.join(lib_dir, os.path.basename(real))
                queue.append(real)

    for real, target in copies.items():
        shutil.copy2(real, target)
        os.chmod(target, 0o755)

    for real, target in copies.items():
        args = []
        if target.startswith(lib_dir):
            args += ["-id", "@executable_path/../lib/" + os.path.basename(target)]
        for reference, dependency in references[real]:
            args += ["-change", reference, "@executable_path/../lib/" + os.path.basename(copies[dependency])]
        if args:
            run("install_name_tool", *args, target)
        run("codesign", "--force", "--sign", "-", target)

    # Hiçbir dosyada Homebrew yolu kalmamalı.
    for target in copies.values():
        leftover = [ref for ref in load_commands(target) if os.path.realpath(ref).startswith(HOMEBREW)]
        if leftover:
            sys.exit(f"{target} hâlâ Homebrew'a bağlı: {leftover}")
    print(f"{len(programs)} program, {len(copies) - len(programs)} kütüphane → {out}")


if __name__ == "__main__":
    main()
