#!/usr/bin/env python3
"""characters.txt 의 도트 지도와 docs/characters.png 를 스프라이트에서 만든다.

이름은 Characters.swift 에서 읽는다. 프리셋을 더하면 이것만 실행하면 된다.
머리말은 손으로 쓴 것이라 그대로 둔다 — 첫 구분선 앞까지가 머리말이다.
"""
import pathlib
import re
from collections import Counter
from PIL import Image

SHEET = "offiky/Assets.xcassets/characters/%s.imageset/%s.png"
BAR = "=" * 60
# Characters.swift 와 같은 값
ROWS = [("대기", 4), ("걷기", 6), ("피격", 4), ("점프", 3), ("인사", 1), ("달리기", 6)]
CELL = 24
SCALE = 4                      # 대조 이미지에서 한 픽셀이 몇 점인가
MARGIN, GAP = 8, 8
BACKDROP = (0x5a, 0x60, 0x6e, 255)


def names():
    swift = pathlib.Path("offiky/Characters.swift").read_text()
    block = re.search(r"static let names = \[(.*?)\]", swift, re.S).group(1)
    return re.findall(r'"([a-z_]+)"', block)


def groups():
    """모양마다 프리셋을 모은다. Characters.groups 와 같은 차례다"""
    order, bucket = [], {}
    for name in names():
        shape = name.split("_")[0]
        if shape not in bucket:
            order.append(shape)
            bucket[shape] = []
        bucket[shape].append(name)
    return [(shape, bucket[shape]) for shape in order]


def palette(name):
    """색을 많이 쓴 차례로 번호를 매긴다"""
    image = Image.open(SHEET % (name, name)).convert("RGBA")
    pixels = image.load()
    w, h = image.size
    count = Counter(pixels[x, y] for y in range(h) for x in range(w) if pixels[x, y][3])
    return image, pixels, count, {c: i + 1 for i, (c, _) in enumerate(count.most_common())}


def section(name):
    _, pixels, count, order = palette(name)
    out = [BAR, "  " + name, BAR, "", "팔레트"]
    for color, n in count.most_common():
        out.append("  %d  #%02x%02x%02x   (%d칸)"
                   % (order[color], color[0], color[1], color[2], n))
    for row, (label, frames) in enumerate(ROWS):
        for col in range(frames):
            out += ["", "── %s %d/%d" % (label, col + 1, frames)]
            for y in range(row * CELL, (row + 1) * CELL):
                out.append("".join(
                    "." if not pixels[x, y][3] else str(order[pixels[x, y]])
                    for x in range(col * CELL, (col + 1) * CELL)))
    return "\n".join(out)


def write_map():
    path = pathlib.Path("characters.txt")
    head = path.read_text().split(BAR)[0]
    body = "\n\n".join(section(name) for _, presets in groups() for name in presets)
    path.write_text(head + body + "\n\n")
    print("%s  %d줄" % (path, len(path.read_text().split("\n"))))


def write_sheet():
    """모양 한 줄씩 대기 첫 장을 늘어놓는다. 줄마다 길이가 달라도 된다"""
    rows = groups()
    side = CELL * SCALE
    width = MARGIN * 2 + max(len(p) for _, p in rows) * (side + GAP) - GAP
    height = MARGIN * 2 + len(rows) * (side + GAP) - GAP
    canvas = Image.new("RGBA", (width, height), BACKDROP)
    for row, (_, presets) in enumerate(rows):
        for col, name in enumerate(presets):
            cell = Image.open(SHEET % (name, name)).convert("RGBA").crop((0, 0, CELL, CELL))
            canvas.alpha_composite(cell.resize((side, side), Image.NEAREST),
                                   (MARGIN + col * (side + GAP), MARGIN + row * (side + GAP)))
    path = pathlib.Path("docs/characters.png")
    canvas.save(path)
    print("%s  %dx%d  %.0fKB" % (path, width, height, path.stat().st_size / 1024))


write_map()
write_sheet()
