#!/usr/bin/env python3
"""낚시 에셋 네 가지를 그린다. 낚싯대(손 (3, 17) 기준 한 장), 찌 두 장(뜬 것·가라앉은 것),
연못 물결 네 장(무대 타일과 같은 16x4), 물고기 여덟 장(16x12: 붕어·잉어·금붕어·복어·가오리·문어·게·장화)"""
import sys
from PIL import Image

OUT = "offiky/Assets.xcassets/%s.imageset/%s.png"
LINE = (34, 34, 46, 255)
WHITE = (240, 240, 250, 255)


def canvas(w, h):
    im = Image.new("RGBA", (w, h))
    px = im.load()
    return im, lambda pts, c: [px.__setitem__(p, c) for p in pts if 0 <= p[0] < w and 0 <= p[1] < h]


def rod():
    """손 (3, 17)에서 오른쪽 위로 뻗고 끝이 살짝 휘는 막대. 끝은 (18, 4). 낚싯줄은 코드가 긋는다"""
    im, put = canvas(24, 20)
    stick = [(3 + i, 17 - i) for i in range(10)] + [(13 + i, 7 - i // 2) for i in range(6)]
    put([(x + dx, y + dy) for x, y in stick for dx, dy in ((1, 0), (0, 1), (-1, 0), (0, -1), (1, 1))], LINE)
    put(stick, (196, 140, 84, 255))
    put(stick[:4], (120, 80, 50, 255))
    put([(3, 17), (4, 17), (3, 18), (4, 18)], (60, 44, 36, 255))
    return im


def bobber():
    """찌 두 장(6x8). 뜬 것은 위쪽에, 가라앉은 것은 아래쪽 절반만 보인다"""
    sheet = Image.new("RGBA", (12, 8))
    for n, top in enumerate((0, 4)):
        im, put = canvas(6, 8)
        body = [(x, y) for y in range(top, top + 6) for x in range(1, 5) if not ((x in (1, 4)) and y in (top, top + 5))]
        put([(x + dx, y + dy) for x, y in body for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))], LINE)
        put(body, (230, 60, 60, 255))
        put([p for p in body if p[1] >= top + 3], WHITE)
        put([(2, top + 1)], (255, 150, 150, 255))
        sheet.paste(im, (6 * n, 0))
    return sheet


def pond():
    """물결 네 장(16x4). 윗줄 밝은 반짝임이 한 장마다 4칸씩 흐른다"""
    sheet = Image.new("RGBA", (64, 4))
    for n in range(4):
        im, put = canvas(16, 4)
        put([(x, y) for x in range(16) for y in range(4)], (50, 110, 200, 255))
        put([(x, 0) for x in range(16)], (90, 160, 230, 255))
        put([(x, 3) for x in range(16)], (36, 80, 160, 255))
        put([((n * 4 + k) % 16, 0) for k in (0, 1, 8, 9)], (170, 220, 255, 255))
        put([((n * 4 + k + 5) % 16, 2) for k in (0, 1)], (80, 140, 220, 255))
        sheet.paste(im, (16 * n, 0))
    return sheet


# 물고기마다 (몸색, 배색) 과 실루엣 그리는 함수
def oval(put, x0, x1, y0, y1, body, belly):
    pts = [(x, y) for x in range(x0, x1 + 1) for y in range(y0, y1 + 1)
           if not ((x in (x0, x1)) and (y in (y0, y1)))]
    put([(x + dx, y + dy) for x, y in pts for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))], LINE)
    put(pts, body)
    put([p for p in pts if p[1] >= (y0 + y1) // 2 + 1 and x0 < p[0] < x1], belly)
    return pts


def fish_shape(put, body, belly, tall=False, eye=True):
    y0, y1 = (3, 9) if tall else (4, 8)
    oval(put, 3, 11, y0, y1, body, belly)
    tail = [(12, 5), (13, 4), (13, 5), (13, 6), (13, 7), (13, 8), (12, 7), (12, 6)]
    put([(x + dx, y + dy) for x, y in tail for dx, dy in ((1, 0), (0, 1), (0, -1))], LINE)
    put(tail, body)
    if eye: put([(5, y0 + 1), (5, y0 + 2)], LINE); put([(5, y0 + 1)], WHITE)


def crucian(put): fish_shape(put, (150, 160, 120, 255), (210, 210, 180, 255))
def carp(put): fish_shape(put, (200, 80, 60, 255), (240, 200, 180, 255), tall=True)
def goldfish(put):
    fish_shape(put, (255, 150, 40, 255), (255, 220, 120, 255))
    put([(7, 3), (8, 3), (8, 2)], (255, 150, 40, 255))


def puffer(put):
    pts = oval(put, 3, 11, 2, 10, (240, 210, 110, 255), (250, 240, 200, 255))
    put([(x, y) for x, y in pts if (x * 3 + y * 2) % 5 == 0 and y < 7 and 4 < x < 11], (170, 130, 50, 255))
    put([(2, 3), (12, 3), (1, 6), (13, 6), (2, 9), (12, 9), (5, 1), (9, 1), (7, 11)], LINE)
    put([(5, 4), (5, 5)], LINE); put([(5, 4)], WHITE)
    put([(3, 6), (4, 6)], (120, 80, 40, 255))


def ray(put):
    pts = [(x, y) for y in range(3, 9) for x in range(2 + abs(y - 5), 13 - abs(y - 5))]
    put([(x + dx, y + dy) for x, y in pts for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))], LINE)
    put(pts, (110, 100, 150, 255))
    put([(13, 5), (14, 5), (15, 4)], LINE)
    put([(5, 4), (9, 4)], LINE); put([(5, 5), (9, 5)], WHITE)


def octopus(put):
    pts = oval(put, 4, 10, 1, 6, (220, 90, 140, 255), (240, 160, 190, 255))
    legs = [(x, y) for x in (3, 5, 7, 9, 11) for y in range(7, 11) if (x + y) % 2 == 0 or y < 9]
    put([(x + dx, y + dy) for x, y in legs for dx, dy in ((1, 0), (-1, 0), (0, 1))], LINE)
    put(legs, (220, 90, 140, 255))
    put([(6, 3), (8, 3)], LINE); put([(6, 4), (8, 4)], WHITE)


def crab(put):
    oval(put, 4, 11, 4, 8, (230, 80, 50, 255), (250, 150, 110, 255))
    put([(2, 5), (2, 4), (3, 3), (13, 5), (13, 4), (12, 3)], LINE)
    put([(2, 6), (13, 6)], (230, 80, 50, 255))
    put([(3, 9), (5, 10), (10, 10), (12, 9)], LINE)
    put([(6, 2), (9, 2)], LINE); put([(6, 3), (9, 3)], WHITE)


def boot(put):
    pts = [(x, y) for x in range(5, 9) for y in range(1, 9)] + [(x, y) for x in range(5, 13) for y in range(8, 11)]
    put([(x + dx, y + dy) for x, y in pts for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))], LINE)
    put(pts, (130, 90, 50, 255))
    put([(x, 10) for x in range(5, 13)], (70, 50, 30, 255))
    put([(6, 2), (7, 2)], (180, 130, 80, 255))


def fishes():
    sheet = Image.new("RGBA", (16 * 8, 12))
    for n, draw in enumerate((crucian, carp, goldfish, puffer, ray, octopus, crab, boot)):
        im, put = canvas(16, 12)
        draw(put)
        sheet.paste(im, (16 * n, 0))
    return sheet


if __name__ == "__main__":
    base = sys.argv[1] if len(sys.argv) > 1 else OUT
    for name, draw in (("rod", rod), ("bobber", bobber), ("pond", pond), ("fish", fishes)):
        draw().save(base % (name, name) if "%s" in base else f"{base}/{name}.png")
