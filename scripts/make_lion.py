#!/usr/bin/env python3
"""사자 시트를 고양이(cat_cheese) 시트에서 만든다.

귀를 지우고 머리 뒤·위·턱 아래로 갈기를 두른다. 줄무늬는 한 색으로 칠하고 꼬리 끝에 털 뭉치를 단다.
머리 위치는 대기 1장의 머리를 장마다 찾아 맞춘다. 고치면 이것만 실행하고 make_characters.py 로 지도를 다시 만든다.
"""
import json
import pathlib
import sys
from PIL import Image

SRC = "offiky/Assets.xcassets/characters/cat_cheese.imageset/cat_cheese.png"
DIR = "offiky/Assets.xcassets/characters/lion_%s.imageset"
ROWS = [4, 6, 4, 3, 1, 6]
CELL = 24


def rgb(code):
    return tuple(int(code[i:i + 2], 16) for i in (0, 2, 4)) + (255,)


# 고양이 색: 테두리 O, 몸 B, 밝은 몸 L, 배 C, 번쩍임 W, 눈 E
CAT = {k: rgb(v) for k, v in zip("OBLCWE", "5a3322 c47a42 ebb07a fbf5ee ffffff f3e6cf".split())}
# 사자 색: 몸 T, 주둥이 S, 갈기 M, 갈기 그늘 D. 눈 E·테두리 O·배 C 는 없으면 고양이 색 그대로
PRESETS = {
    "gold": dict(T="e0a84e", S="f4d08a", M="c0642c", D="8f4422"),
    "white": dict(T="f1ebe0", S="fffaf2", M="e2cfa8", D="bfa47a", E="5fb4ea"),
    "black": dict(T="4a4754", S="625e6e", M="2e2c36", D="201e26", E="ffd60a", O="15141a", C="625e6e"),
}

# 대기 1장 기준 좌표. 머리는 4~10줄, 11줄은 14칸부터가 턱이다
HEAD_TOP, HEAD_BOTTOM, JAW_X = 4, 10, 14
# 갈기가 차지하는 칸(줄: 시작~끝 칸 구간들). 바깥 한 줄은 테두리가 되고, 들쭉날쭉한 끝이 털 결이 된다
MANE = {0: [(7, 8), (11, 12)], 1: [(5, 14)], 2: [(4, 15)], 3: [(3, 16)], 4: [(2, 7)], 5: [(3, 6)],
        6: [(2, 6)], 7: [(2, 6)], 8: [(3, 6)], 9: [(2, 6)], 10: [(3, 6)], 11: [(4, 13)],
        12: [(5, 13)], 13: [(6, 8), (10, 12)]}


def cells(image):
    px = image.load()
    for row, count in enumerate(ROWS):
        for col in range(count):
            yield row, col, [[px[col * CELL + x, row * CELL + y] for x in range(CELL)] for y in range(CELL)]


def head_template(frame):
    """빈 칸도 넣는다. 번쩍임 장은 모양만 맞추므로 빈 칸이 맞아야 몸통과 겹치는 자리로 잘못 가지 않는다"""
    return [(x, y, frame[y][x]) for y in range(1, 12) for x in range(7, 18)]


def find_head(frame, template):
    """머리를 가장 많이 맞추는 자리. 번쩍임 장은 색이 없어 모양만 맞춘다"""
    flash = all(v[:3] == CAT["W"][:3] for row in frame for v in row if v[3])
    best = (-1, 0, 0)
    for dy in range(-6, 8):
        for dx in range(-6, 10):
            hit = sum(1 for x, y, v in template
                      if 0 <= x + dx < CELL and 0 <= y + dy < CELL and (v[3] or flash)
                      and ((frame[y + dy][x + dx][3] > 0) == (v[3] > 0) if flash else frame[y + dy][x + dx] == v))
            best = max(best, (hit, dx, dy))
    return best[1], best[2], flash


def lion(frame, template, pal):
    dx, dy, flash = find_head(frame, template)
    out = [row[:] for row in frame]
    clear = (0, 0, 0, 0)
    face = {(x + dx, y + dy) for x, y, v in template
            if v[3] and (HEAD_TOP <= y <= HEAD_BOTTOM or (y == HEAD_BOTTOM + 1 and x >= JAW_X))}

    def inside(x, y):
        return 0 <= x < CELL and 0 <= y < CELL

    # 귀
    for y in range(0, HEAD_TOP):
        for x in range(6, 17):
            if inside(x + dx, y + dy):
                out[y + dy][x + dx] = clear

    for y in range(CELL):
        for x in range(CELL):
            v = out[y][x]
            if v in (CAT["B"], CAT["L"]):
                muzzle = (x, y) in face and y - dy >= 7 and v == CAT["L"]
                out[y][x] = pal["S"] if muzzle else pal["T"]
            # 감은 눈에는 동공이 없다. 색을 바꾸면 네모난 색 덩어리로 보여 뜬 눈만 바꾼다
            elif v == CAT["E"] and "E" in pal and pupil(frame):
                out[y][x] = pal["E"]

    mane = set()
    for y, spans in MANE.items():
        for x0, x1 in spans:
            for x in range(x0, x1 + 1):
                p = (x + dx, y + dy)
                # 귀가 기운 장은 대기 1장의 머리 자리가 비어 있다
                if inside(*p) and (p not in face or not out[p[1]][p[0]][3]):
                    mane.add(p)
    tail = tail_pixels(out, mane, dx)
    for x, y in mane:
        # 아래쪽과 맨 뒤는 그늘
        out[y][x] = CAT["W"] if flash else (pal["D"] if y - dy >= 10 or (x - dx <= 4 and y - dy >= 4) else pal["M"])
    if not flash:
        outline(out, mane)
        tuft = tip_tuft(out, tail)
        # 꼬리 끝이 갈기에 닿아 있으면 갈기와 구분되지 않는다
        if any(abs(x - a) <= 2 and abs(y - b) <= 2 for x, y in tuft for a, b in mane):
            tuft = set()
        for x, y in tuft:
            out[y][x] = pal["D"]
        outline(out, tuft)
    # 테두리·배는 마지막에 바꾼다. 그 전까지는 고양이 테두리 색으로 칸을 구분한다
    swap = {CAT[k]: pal[k] for k in "OC" if k in pal}
    return [[swap.get(v, v) for v in row] for row in out]


def pupil(frame):
    return any(frame[y][x - 1] == CAT["E"] and frame[y][x] == CAT["O"] and frame[y][x + 1] == CAT["E"]
               for y in range(CELL) for x in range(1, CELL - 1))


def outline(out, area):
    for x, y in area:
        if any(not (0 <= x + a < CELL and 0 <= y + b < CELL) or not out[y + b][x + a][3]
               for a, b in ((1, 0), (-1, 0), (0, 1), (0, -1))):
            out[y][x] = CAT["O"]


def tail_pixels(out, mane, dx):
    """머리 뒤 칸보다 왼쪽에 있는 몸 밖 픽셀. 갈기에 가린 것은 뺀다"""
    return {(x, y) for y in range(CELL) for x in range(min(7 + dx, CELL))
            if out[y][x][3] and (x, y) not in mane}


def tip_tuft(out, tail):
    """몸에 붙은 칸에서 가장 먼 꼬리 칸을 끝으로 보고, 그 둘레 3x3 을 털 뭉치로 칠한다"""
    if not tail:
        return set()
    edge = max(x for x, _ in tail)
    frontier = [p for p in tail if p[0] == edge]
    dist = {p: 0 for p in frontier}
    while frontier:
        nxt = []
        for x, y in frontier:
            for p in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if p in tail and p not in dist:
                    dist[p] = dist[(x, y)] + 1
                    nxt.append(p)
        frontier = nxt
    tx, ty = max(dist, key=lambda p: (dist[p], -p[1]))
    # 끝 칸은 테두리라 한 칸 안쪽을 가운데로 삼는다
    cx, cy = min(((x, y) for x, y in dist if out[y][x] != CAT["O"]),
                 key=lambda p: abs(p[0] - tx) + abs(p[1] - ty), default=(tx, ty))
    return {(cx + a, cy + b) for a in (-1, 0, 1) for b in (-1, 0, 1)
            if 0 <= cx + a < CELL and 0 <= cy + b < CELL}


def build(pal):
    src = Image.open(SRC).convert("RGBA")
    sheet = Image.new("RGBA", src.size, (0, 0, 0, 0))
    template = None
    for row, col, frame in cells(src):
        template = template or head_template(frame)
        for y, line in enumerate(lion(frame, template, pal)):
            for x, v in enumerate(line):
                sheet.putpixel((col * CELL + x, row * CELL + y), v)
    return sheet


if __name__ == "__main__":
    out = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else None
    for name, codes in PRESETS.items():
        sheet = build({k: rgb(v) for k, v in codes.items()})
        if out:
            sheet.save(out / f"lion_{name}.png")
            continue
        folder = pathlib.Path(DIR % name)
        folder.mkdir(parents=True, exist_ok=True)
        sheet.save(folder / f"lion_{name}.png")
        (folder / "Contents.json").write_text(json.dumps({
            "images": [{"filename": f"lion_{name}.png", "idiom": "universal"}],
            "info": {"author": "xcode", "version": 1},
            "properties": {"template-rendering-intent": "original",
                           "preserves-vector-representation": False},
        }, indent=2))
