#!/usr/bin/env python3
"""PNG katmanlarından Windows .ico dosyası üretir (PNG gömülü ICO, Vista ve sonrası).

    swift scripts/render-icon.swift windows /tmp/kd-icon
    python3 Windows/scripts/make-ico.py /tmp/kd-icon Windows/KDDownloadManager/Assets/app.ico
"""
import pathlib, struct, sys

src, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
images = sorted(((int(p.stem[4:]), p.read_bytes()) for p in src.glob("icon*.png")), key=lambda x: x[0])
header = struct.pack("<HHH", 0, 1, len(images))
offset = 6 + 16 * len(images)
entries, blobs = b"", b""
for size, data in images:
    edge = 0 if size >= 256 else size
    entries += struct.pack("<BBBBHHII", edge, edge, 0, 0, 1, 32, len(data), offset + len(blobs))
    blobs += data
out.write_bytes(header + entries + blobs)
print(f"{out}: {', '.join(str(s) for s, _ in images)}")
