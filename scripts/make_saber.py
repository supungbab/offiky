"""광선검 다섯 장(휘두르는 네 장, 든 채 겨눈 한 장)을 가로로 붙인 스트립. 칸마다 손(22, 34)이 같다.
계단이 고른 각도(0·45·63·90·135도)만 쓰고, 칼날은 심·빛·번짐 3겹이다"""
import math, sys
from PIL import Image

W, H, P = 56, 44, (22, 34)          # 칸 크기와 손 위치
LENGTH = 24
# 칼날 방향(가로, 세로 위로), 휘두른 자리 궤적(시작 각도, 끝 각도)
FRAMES = [((-1, 1), None), ((0, 1), None), ((1, 1), (95, 45)), ((1, 0), (90, 0)), ((1, 2), None)]

OUTLINE = (34, 34, 46, 255)
HILT_HI, HILT, HILT_LO = (222, 226, 236, 255), (156, 162, 180, 255), (96, 100, 120, 255)
GRIP, BUTTON = (44, 44, 58, 255), (232, 64, 64, 255)
CORE, GLOW, HALO = (255, 255, 255, 255), (120, 206, 255, 255), (60, 140, 255, 120)
TRAIL_IN, TRAIL_OUT = (200, 238, 255, 230), (140, 204, 255, 150)

N4 = [(1, 0), (-1, 0), (0, 1), (0, -1)]


def line(dx, dy, a, b):
    """손에서 a~b 만큼 떨어진 구간의 화소. dy 는 위가 +"""
    n = math.hypot(dx, dy)
    ux, uy = dx / n, -dy / n
    pts = []
    for k in range(int(a * 8), int(b * 8) + 1):
        t = k / 8
        p = (P[0] + round(ux * t), P[1] + round(uy * t))
        if p not in pts: pts.append(p)
    return pts


def grow(pts, by=N4):
    s = set(pts)
    return {(x + ox, y + oy) for x, y in s for ox, oy in by} - s


def frame(n):
    (dx, dy), sweep = FRAMES[n]
    im = Image.new("RGBA", (W, H))
    px = im.load()
    put = lambda pts, c: [px.__setitem__(p, c) for p in pts if 0 <= p[0] < W and 0 <= p[1] < H]
    if sweep:
        hi, lo = (math.radians(d) for d in sweep)
        for y in range(H):
            for x in range(W):
                vx, vy = x - P[0], P[1] - y
                r, ang = math.hypot(vx, vy), math.atan2(vy, vx)
                if lo <= ang <= hi and LENGTH - 7 <= r <= LENGTH + 1.5:
                    near = (ang - lo) / (hi - lo)
                    if near < .5 and r >= LENGTH - 4: put([(x, y)], TRAIL_IN)
                    elif near < .8 and r >= LENGTH - 7 + near * 6: put([(x, y)], TRAIL_OUT)
    core = line(dx, dy, 4, LENGTH - 1)
    glow = grow(core) | set(line(dx, dy, LENGTH, LENGTH))
    halo = grow(set(core) | glow)
    put(halo, HALO); put(glow, GLOW); put(core, CORE)
    hilt = line(dx, dy, -4, 3)
    body = set(hilt) | grow(hilt, [(1, 0), (0, 1)] if dx * dy else [(1, 0)] if dx == 0 else [(0, 1)])
    put(grow(body, N4 + [(1, 1), (-1, -1), (1, -1), (-1, 1)]) - set(core) - glow, OUTLINE)
    put(body - set(hilt), HILT)
    put(hilt, HILT_HI)
    put([hilt[0]] + [q for q in body if q in grow([hilt[0]])], HILT_LO)
    put([hilt[2]] + [q for q in body - set(hilt) if q in grow([hilt[2]])], GRIP)
    put([hilt[3]] + [q for q in body - set(hilt) if q in grow([hilt[3]])], GRIP)
    put([hilt[5]], BUTTON)
    return im


sheet = Image.new("RGBA", (W * 5, H))
for n in range(5):
    sheet.paste(frame(n), (W * n, 0))
sheet.save(sys.argv[1] if len(sys.argv) > 1 else "offiky/Assets.xcassets/lightsaber.imageset/lightsaber.png")
