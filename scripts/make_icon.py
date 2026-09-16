#!/usr/bin/env python3
"""앱 아이콘과 메뉴바 아이콘을 개구리 스프라이트에서 만든다.

앱 안에서 돌아다니는 그림을 그대로 쓴다. 따로 그린 그림을 두면 둘이
서로 달라지고, 캐릭터를 손볼 때 아이콘만 옛 모습으로 남는다.

32칸 도화지의 세로 절반을 개구리가 쓴다. 나머지 절반은 하늘과 땅이다.
필요한 크기가 전부 32 의 약수나 배수라 최근접 확대만 하면 어느 크기에서도
픽셀 경계가 살아 있고, 16px 도 정확히 절반이라 뭉개지지 않는다.

개구리는 17줄이라 한 줄이 남는다. 배 쪽에 위와 완전히 같은 줄이 있어
그것만 빼면 모양을 건드리지 않고 16줄이 된다.
"""
import json, pathlib, struct, zlib

SPRITE = pathlib.Path("offiky/Assets.xcassets/characters/frog_green.imageset/frog_green.png")
CELL = 32                      # 아이콘 한 칸 수
BODY = (7, 4, 10, 17)          # 대기 첫 장에서 개구리가 있는 자리 x, y, 폭, 높이
SAME_AS_ABOVE = 10             # 위와 똑같아 빼도 모양이 안 바뀌는 줄
FROG_ROWS = 16                 # 도화지의 절반
GROUND_ROWS = 8
# 단색으로 깔면 밋밋하다. 픽셀 아트에서는 부드러운 그라데이션 대신 단을 나눈다.
# 하늘은 아래로 갈수록 짙어져 개구리 뒤가 어두워지고, 땅은 윗면이 밝고 아래가 그늘진다
SKY = [(6, (0xc5, 0xe9, 0xfb, 255)), (6, (0xa9, 0xdf, 0xf7, 255)),
       (6, (0x8c, 0xcd, 0xee, 255)), (6, (0x74, 0xbc, 0xe2, 255))]
GROUND = [(2, (0xa8, 0x70, 0x46, 255)), (3, (0x8a, 0x5a, 0x38, 255)),
          (3, (0x56, 0x36, 0x1f, 255))]
BACKGROUND = SKY[0][1]
FLOOR = GROUND[0][1]


def read_png(path):
    data = path.read_bytes()
    pos, idat = 8, b""
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        tag, chunk = data[pos + 4:pos + 8], data[pos + 8:pos + 8 + length]
        if tag == b"IHDR":
            width, height, depth, kind = struct.unpack(">IIBB", chunk[:10])
            assert depth == 8 and kind == 6, "8비트 RGBA 만 읽는다"
        elif tag == b"IDAT":
            idat += chunk
        pos += 12 + length
    raw, stride = zlib.decompress(idat), width * 4
    out, previous, at = bytearray(), bytearray(stride), 0
    for _ in range(height):
        filter_type, line = raw[at], bytearray(raw[at + 1:at + 1 + stride])
        at += 1 + stride
        for i in range(stride):
            a = line[i - 4] if i >= 4 else 0
            b = previous[i]
            c = previous[i - 4] if i >= 4 else 0
            if filter_type == 1: line[i] = (line[i] + a) & 255
            elif filter_type == 2: line[i] = (line[i] + b) & 255
            elif filter_type == 3: line[i] = (line[i] + (a + b) // 2) & 255
            elif filter_type == 4:
                guess = a + b - c
                da, db, dc = abs(guess - a), abs(guess - b), abs(guess - c)
                line[i] += a if (da <= db and da <= dc) else (b if db <= dc else c)
                line[i] &= 255
        out += line
        previous = line
    return width, height, bytes(out)


def frog():
    """개구리를 줄 목록으로. 빈 칸은 None 이다"""
    width, _, pixels = read_png(SPRITE)
    x0, y0, w, h = BODY

    def at(x, y):
        i = (y * width + x) * 4
        return None if pixels[i + 3] == 0 else (pixels[i], pixels[i + 1], pixels[i + 2], 255)

    rows = [[at(x0 + c, y0 + r) for c in range(w)] for r in range(h)]
    return [row for i, row in enumerate(rows) if i != SAME_AS_ABOVE]


def canvas():
    """32x32 한 칸짜리 그림. 개구리가 바닥 위에 선다"""
    body = frog()
    cell = [[BACKGROUND] * CELL for _ in range(CELL)]

    y = 0
    for count, color in SKY:
        for _ in range(count):
            if y < CELL - GROUND_ROWS:
                for x in range(CELL):
                    cell[y][x] = color
            y += 1
    y = CELL - GROUND_ROWS
    for count, color in GROUND:
        for _ in range(count):
            if y < CELL:
                for x in range(CELL):
                    cell[y][x] = color
            y += 1
    left = (CELL - BODY[2]) // 2
    top = CELL - GROUND_ROWS - FROG_ROWS
    for r, row in enumerate(body):
        for c, color in enumerate(row):
            if color is None:
                continue
            y, x = top + r, left + c
            if 0 <= y < CELL and 0 <= x < CELL:
                cell[y][x] = color
    return cell


def write_png(path, cell, size, silhouette=False):
    """최근접으로 늘리거나 줄여 정사각 png 를 쓴다"""
    rows = []
    for y in range(size):
        row = bytearray()
        for x in range(size):
            color = cell[y * CELL // size][x * CELL // size]
            if silhouette:
                color = (0, 0, 0, 0) if color == (0, 0, 0, 0) else (0, 0, 0, 255)
            row += bytes(color)
        rows.append(bytes(row))
    raw = b"".join(b"\x00" + r for r in rows)

    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    path.write_bytes(b"\x89PNG\r\n\x1a\n"
                     + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(raw, 9))
                     + chunk(b"IEND", b""))


HEAD_ROWS = 9                  # 대기 자세에서 머리가 차지하는 줄


def menubar():
    """밝은 메뉴바에서는 색이 보이지 않으므로 템플릿 이미지로 만든다.
    macOS 가 명암을 뒤집는다.

    전신을 넣으면 16px 에서 형태가 잘게 쪼개져 뭉개진다. 얼굴만 넣어 화면을
    채우고 눈을 뚫으면 그 크기에서도 얼굴로 읽힌다."""
    head = frog()[:HEAD_ROWS]
    hollow = {(0xfb, 0xc8, 0x00, 255), (0xff, 0xf6, 0x99, 255)}   # 눈
    out = pathlib.Path("offiky/Assets.xcassets/MenuBarIcon.imageset")
    out.mkdir(parents=True, exist_ok=True)
    for old in out.glob("*.png"):
        old.unlink()

    images = []
    for scale in (1, 2, 3):
        size = 16 * scale
        cell = [[(0, 0, 0, 0)] * size for _ in range(size)]
        left, top = (size - BODY[2] * scale) // 2, (size - HEAD_ROWS * scale) // 2
        for r, row in enumerate(head):
            for c, color in enumerate(row):
                if color is None or color in hollow:
                    continue
                for dy in range(scale):
                    for dx in range(scale):
                        y, x = top + r * scale + dy, left + c * scale + dx
                        if 0 <= y < size and 0 <= x < size:
                            cell[y][x] = (0, 0, 0, 255)
        name = f"menubar{'' if scale == 1 else f'@{scale}x'}.png"
        rows = [b"".join(bytes(c) for c in row) for row in cell]
        raw = b"".join(b"\x00" + r for r in rows)

        def chunk(tag, data):
            body = tag + data
            return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

        (out / name).write_bytes(
            b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
        images.append({"filename": name, "idiom": "universal", "scale": f"{scale}x"})

    (out / "Contents.json").write_text(json.dumps(
        {"images": images, "info": {"author": "xcode", "version": 1},
         "properties": {"template-rendering-intent": "template"}}, indent=2) + "\n")
    print(f"메뉴바 아이콘 3개: {out}")


cell = canvas()
out = pathlib.Path("offiky/Assets.xcassets/AppIcon.appiconset")
out.mkdir(parents=True, exist_ok=True)
for old in out.glob("*.png"):
    old.unlink()
images = []
for base in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        name = f"icon_{base}x{base}{'@2x' if scale == 2 else ''}.png"
        write_png(out / name, cell, base * scale)
        images.append({"filename": name, "idiom": "mac",
                       "scale": f"{scale}x", "size": f"{base}x{base}"})
(out / "Contents.json").write_text(json.dumps(
    {"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
print(f"앱 아이콘 {len(images)}개: {out}")

menubar()
