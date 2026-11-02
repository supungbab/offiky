#!/usr/bin/env python3
"""슬라임 시트를 코드로 그린다. 다리 없이 몸을 눌렀다 늘이며 움직인다.

몸 모양은 너비·높이·쏠림만으로 정하고, 눈·광택·테두리는 그 모양을 따라 붙는다.
프리셋은 색만 다르다. 고치면 이것만 실행하고 make_characters.py 로 지도를 다시 만든다.
"""
import json
import pathlib
from PIL import Image

DIR = "offiky/Assets.xcassets/characters/slime_%s.imageset"
# 테두리 O, 몸 G, 그늘 S, 바닥 D, 빛 L, 반짝임 W, 눈 K
PRESETS = {
    "green": "1d5532 62cf6c 3f9f52 2f8044 9cee92 ffffff 173a22",
    "water": "1a3d78 5aa8f0 3a7fd0 2c62a8 a8dcff ffffff 13284d",
    "berry": "7a2448 f47aa8 d4508a b03a70 ffc0d8 ffffff 4a1030",
    "lava":  "6a1a10 f2652e c84418 a03210 ffc24a fff2b0 3a0c06",
    "metal": "3c4250 b8c0cc 8a94a6 6c7688 e8eef6 ffffff 1e2430",
    "grape": "3e2068 a070e0 7c4cc4 6038a0 d2b4ff ffffff 26103e",
}
CX, FLOOR = 11.5, 19            # 몸 가운데, 몸이 닿는 마지막 줄


def palette(codes):
    return {k: tuple(int(v[i:i + 2], 16) for i in (0, 2, 4)) + (255,)
            for k, v in zip("OGSDLWK", codes.split())}


def body(w, h, lean, air=0, sag=0.0):
    """줄마다 몸이 차지하는 칸. 바닥에서는 꼭대기부터 바닥까지 한 곡선이라 어깨가 꺾이지 않는다.
    공중(air)이면 아래도 둥글게 오므리고, 지수가 작을수록 뾰족하다. 위로 갈수록 lean 만큼 앞으로 쏠린다"""
    rows = {}
    top = FLOOR - h + 1
    for y in range(top, FLOOR + 1):
        t = (y - top + 0.5) / h                     # 0 위 ~ 1 아래
        if not air:
            half = (w / 2) * (1 - (1 - t) ** 2.4) ** (1 / 2.4) - (0.6 if y == FLOOR else 0)
        elif t < 0.62:
            half = (w / 2) * (1 - (1 - t / 0.62) ** 2.2) ** (1 / 2.2)
        else:
            half = (w / 2) * max(0.0, 1 - ((t - 0.62) / 0.38) ** air) ** (1 / air)
        half += sag * max(0.0, min(1.0, (t - 0.35) / 0.65)) ** 2    # 아래쪽만 불룩해진다
        # 칸 가운데로 재야 좌우가 같은 칸으로 반올림된다
        xs = [x for x in range(24) if abs(x + 0.5 - (CX + lean * (1 - t))) <= half]
        if xs:
            rows[y] = (xs[0], xs[-1])
    return rows


def frame(pal, w=16, h=12, lean=0, air=0, sag=0.0, eye="open", mouth="smile", white=False, drops=()):
    im = Image.new("RGBA", (24, 24), (0, 0, 0, 0))

    def put(x, y, c):
        if 0 <= x < 24 and 0 <= y < 24:
            im.putpixel((x, y), pal[c])

    rows = body(w, h, lean, air, sag)
    top = min(rows)
    for y, (x0, x1) in rows.items():
        for x in range(x0, x1 + 1):
            put(x, y, "D" if y == FLOOR and x0 < x < x1 else "S" if y >= FLOOR - 1 or x == x1 else "G")
    # 왼쪽 위에서 빛이 든다
    for y in range(top + 1, top + 1 + max(2, h // 3)):
        if y in rows:
            x0, x1 = rows[y]
            for x in range(x0 + 1, x0 + 1 + max(2, (x1 - x0) // 3)):
                put(x, y, "L")
    gy = top + 2
    if gy in rows:
        put(rows[gy][0] + 2, gy, "W")
        put(rows[gy][0] + 3, gy - 1 if gy - 1 in rows else gy, "W")

    # 얼굴은 몸을 따라간다. 꼭대기를 따라 오르내리고, 몸이 쏠리면 앞으로 간다.
    # 눌리면 눈이 납작해지며 벌어지고, 늘어나면 모인다
    ey = top + round(h * 0.33)
    gap = 3 if w < 14 else 4 if w < 18 else 5
    fx = round(CX + 2.5 + lean * 0.8 + (w - 16) * 0.25 - gap / 2)
    for ex in (fx, fx + gap):
        out = -1 if ex == fx else 1                 # 바깥쪽
        if eye == "open":
            for i in range(1 if h <= 10 else 2):
                put(ex, ey + i, "K")
        elif eye == "slit":                         # 볼 자리부터 가로로 길게 그은 가는 눈
            for x in (ex + out, ex, ex - out):
                put(x, ey + 1, "K")
        elif eye == "x":
            for dx, dy in ((-1, -1), (1, -1), (0, 0), (-1, 1), (1, 1)):
                put(ex + dx, ey + dy, "K")
        elif eye == "squint":                       # > < 로 질끈 감은 눈
            for dx, dy in ((out, -1), (0, 0), (out, 1)):
                put(ex + dx, ey + dy, "K")
    if mouth:
        for i in range(2 if mouth == "o" else 1):
            put(fx + gap // 2, ey + 2 + i, "K")
    for x, y in drops:
        put(x, y, "G")

    src = im.copy()
    for y in range(24):
        for x in range(24):
            if not src.getpixel((x, y))[3] and any(
                    0 <= x + a < 24 and 0 <= y + b < 24 and src.getpixel((x + a, y + b))[3]
                    for a, b in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                put(x, y, "O")
    if white:
        for y in range(24):
            for x in range(24):
                if im.getpixel((x, y))[3]:
                    put(x, y, "W")
    return im


# 행: 대기4 걷기6 피격4 점프3 숙이기1 달리기6
ROWS = [
    # 대기: 젤리처럼 출렁인다. 꼭대기가 내려앉으며 아랫배가 퍼졌다가, 돌아와 조금 솟는다
    [dict(), dict(h=11, sag=1.0), dict(), dict(w=15, h=13)],
    # 걷기: 뒤로 모았다가 앞으로 늘어나며 미끄러지고, 내려앉으며 아래가 퍼진다
    [dict(w=18, h=10, lean=-1, sag=1.0), dict(w=16, h=12, lean=1), dict(w=14, h=14, lean=2),
     dict(w=15, h=13, lean=3), dict(w=17, h=11, lean=1), dict(w=18, h=10, sag=0.5)],
    # 피격: 납작하게 찌그러진다. 셋째 장은 흰 실루엣
    [dict(w=19, h=10, lean=-1, eye="squint", mouth="o"), dict(w=20, h=8, lean=-1, eye="x", mouth="o"),
     dict(w=20, h=8, lean=-1, eye="x", mouth="o", white=True), dict(w=19, h=10, lean=-1, eye="squint", mouth="o")],
    # 점프: 웅크렸다가 위로 길게 늘어나고, 내려올 때 둥글어진다. 공중에서는 바닥도 둥글다
    [dict(w=19, h=9), dict(w=12, h=16, lean=1, air=1.6, mouth="o"), dict(w=15, h=13, air=2.2)],
    # 숙이기: 납작하게 웅크리고 눈을 가늘게 뜬다
    [dict(w=20, h=8, eye="slit", mouth=None)],
    # 달리기: 앞으로 길게 쏠리고 뒤로 방울이 튄다
    [dict(w=18, h=10, lean=3, drops=((1, 12),)), dict(w=19, h=9, lean=3, drops=((0, 14), (2, 11))),
     dict(w=18, h=10, lean=4, drops=((1, 13),)), dict(w=18, h=10, lean=3, drops=((2, 12),)),
     dict(w=19, h=9, lean=3, drops=((0, 13), (2, 10))), dict(w=18, h=10, lean=4, drops=((1, 11),))],
]

if __name__ == "__main__":
    for name, codes in PRESETS.items():
        pal = palette(codes)
        sheet = Image.new("RGBA", (144, 144), (0, 0, 0, 0))
        for r, row in enumerate(ROWS):
            for c, spec in enumerate(row):
                sheet.alpha_composite(frame(pal, **spec), (c * 24, r * 24))
        folder = pathlib.Path(DIR % name)
        folder.mkdir(exist_ok=True)
        # 다른 캐릭터 에셋과 같은 내용이다. 새 프리셋도 이것만 실행하면 된다
        (folder / "Contents.json").write_text(json.dumps({
            "images": [{"filename": f"slime_{name}.png", "idiom": "universal"}],
            "info": {"author": "xcode", "version": 1},
            "properties": {"template-rendering-intent": "original", "preserves-vector-representation": False},
        }, indent=2))
        sheet.save(folder / f"slime_{name}.png")
        print(folder)
