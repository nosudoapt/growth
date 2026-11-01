#!/usr/bin/env python3
"""Generate the launcher notification icon and the grain texture as PNGs.

Pure stdlib (zlib + struct): a minimal valid RGBA PNG writer, no PIL needed.
"""
import math
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def write_png(path: Path, w: int, h: int, pixels: bytes) -> None:
    def chunk(tag: bytes, data: bytes) -> bytes:
        c = struct.pack(">I", len(data)) + tag + data
        c += struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        return c

    header = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    raw = b"".join(
        b"\x00" + pixels[y * w * 4 : (y + 1) * w * 4] for y in range(h)
    )
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )
    path.write_bytes(png)


# ---- Launcher icon: gold square, dark rounded diamond "seed". -----------

GOLD = (245, 192, 74, 255)
DARK = (14, 13, 11, 255)


def launch_icon(size: int) -> bytes:
    px = bytearray()
    cx = (size - 1) / 2
    for y in range(size):
        for x in range(size):
            # rounded corners
            r = size * 0.18
            mx = min(x, size - 1 - x)
            my = min(y, size - 1 - y)
            if mx < r and my < r:
                dx, dy = r - mx, r - my
                if dx * dx + dy * dy > r * r:
                    px += bytes(DARK)
                    continue
            # dark diamond in the middle
            d = abs(x - cx) + abs(y - cx)
            if d < size * 0.28:
                px += bytes(DARK)
            else:
                px += bytes(GOLD)
    return bytes(px)


# ---- Notification icon: small white/gold alarm ring on transparent. -----

def notif_icon(size: int) -> bytes:
    px = bytearray()
    cx = (size - 1) / 2
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - cx, y - cx)
            if size * 0.30 < d < size * 0.42:
                px += bytes((244, 239, 230, 255))
            elif abs(d - size * 0.36) < size * 0.05 and size * 0.05 < abs(x - cx):
                px += bytes((244, 239, 230, 255))
            else:
                px += bytes((0, 0, 0, 0))
    return bytes(px)


# ---- Grain texture: monochrome low-alpha noise. -------------------------

import random

def grain(size: int = 128) -> bytes:
    rng = random.Random(20261102)
    px = bytearray()
    for _ in range(size * size):
        v = rng.randint(0, 255)
        a = rng.randint(0, 255) // 4  # very low alpha grain
        px += bytes((v, v, v, a))
    return bytes(px)


def main() -> None:
    res = ROOT / "android/app/src/main/res"
    for dp in ("mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi"):
        size = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}[dp]
        (res / f"mipmap-{dp}").mkdir(parents=True, exist_ok=True)
        write_png(res / f"mipmap-{dp}/ic_launcher.png", size, size, launch_icon(size))
    (res / "mipmap-mdpi").mkdir(parents=True, exist_ok=True)
    write_png(res / "mipmap-mdpi/ic_notification.png", 24, 24, notif_icon(24))
    write_png(res / "mipmap-hdpi/ic_notification.png", 36, 36, notif_icon(36))
    write_png(res / "mipmap-xhdpi/ic_notification.png", 48, 48, notif_icon(48))
    write_png(res / "mipmap-xxhdpi/ic_notification.png", 72, 72, notif_icon(72))
    write_png(res / "mipmap-xxxhdpi/ic_notification.png", 96, 96, notif_icon(96))

    assets = ROOT / "assets"
    assets.mkdir(parents=True, exist_ok=True)
    write_png(assets / "grain.png", 128, 128, grain())
    print("assets generated")


if __name__ == "__main__":
    main()
