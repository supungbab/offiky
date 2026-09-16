#!/usr/bin/env python3
"""앱 아이콘을 16x16 픽셀 아트에서 만든다.

필요한 크기가 전부 16 의 배수라 최근접 확대만 하면 어느 크기에서도
픽셀 경계가 살아 있다. 앱 안의 캐릭터를 같은 방식으로 그리는 것과 맞춘다.
"""
import json, pathlib, struct, zlib

ART = [
    "  BBBBBBBBBBBB  ",
    " BBBBBBBBBBBBBB ",
    "BBBBBBBBBBBBBBBB",
    "BBBBBWBBBBWBBBBB",
    "BBBBWWWWWWWWBBBB",
    "BBBBWWEWWEWWBBBB",
    "BBBBWWWWWWWWBBBB",
    "BBBBSWWWWWWSBBBB",
    "BBBBBWWWWWWBBBBB",
    "BBBBWWWWWWWWBBBB",
    "BBBBWWWWWWWWBBBB",
    "BBBBBWWBBWWBBBBB",
    "BBBBBWWBBWWBBBBB",
    "GGGGGGGGGGGGGGGG",
    " GGGGGGGGGGGGGG ",
    "  GGGGGGGGGGGG  ",
]
PALETTE = {
    " ": (0, 0, 0, 0),
    "B": (78, 92, 191, 255),      # 배경
    "G": (51, 60, 122, 255),      # 바닥
    "W": (247, 235, 211, 255),    # 몸
    "S": (211, 190, 152, 255),    # 몸 그늘
    "E": (43, 47, 74, 255),       # 눈
}

def write_png(path, size):
    scale = size // len(ART)
    rows = []
    for line in ART:
        row = bytearray()
        for char in line:
            row += bytes(PALETTE[char]) * scale
        rows += [bytes(row)] * scale
    raw = b"".join(b"\x00" + r for r in rows)

    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    header = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    path.write_bytes(b"\x89PNG\r\n\x1a\n"
                     + chunk(b"IHDR", header)
                     + chunk(b"IDAT", zlib.compress(raw, 9))
                     + chunk(b"IEND", b""))

out = pathlib.Path("offiky/Assets.xcassets/AppIcon.appiconset")
out.mkdir(parents=True, exist_ok=True)
for old in out.glob("*.png"):
    old.unlink()

images = []
for base in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        name = f"icon_{base}x{base}{'@2x' if scale == 2 else ''}.png"
        write_png(out / name, base * scale)
        images.append({"filename": name, "idiom": "mac",
                       "scale": f"{scale}x", "size": f"{base}x{base}"})

(out / "Contents.json").write_text(json.dumps(
    {"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
print(f"{len(images)}개 생성: {out}")
