#!/usr/bin/env python3
"""Create a modern ICNS container from the PNG layers in an iconset."""

import pathlib
import struct
import sys


if len(sys.argv) != 3:
    raise SystemExit("usage: make_icns.py ICONSET_DIR OUTPUT.icns")

iconset = pathlib.Path(sys.argv[1])
output = pathlib.Path(sys.argv[2])
layers = [
    (b"icp4", "icon_16x16.png"),
    (b"icp5", "icon_32x32.png"),
    (b"icp6", "icon_32x32@2x.png"),
    (b"ic07", "icon_128x128.png"),
    (b"ic08", "icon_256x256.png"),
    (b"ic09", "icon_512x512.png"),
    (b"ic10", "icon_512x512@2x.png"),
]

chunks = []
for kind, filename in layers:
    payload = (iconset / filename).read_bytes()
    chunks.append(kind + struct.pack(">I", len(payload) + 8) + payload)

body = b"".join(chunks)
output.write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)
