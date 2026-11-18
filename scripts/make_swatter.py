"""파리채 다섯 장(휘두르는 네 장, 든 채 겨눈 한 장)을 가로로 붙인 스트립. 칸마다 손(20, 26)이 같다.
초록 손잡이 끝에 진한 줄무늬가 있고, 빨간 머리는 목에서 넓어져 끝이 평평하다"""
import math, sys
from PIL import Image

W, H, P = 46, 32, (20, 26)          # 칸 크기와 손 위치
HANDLE, GRIP, HEAD, NECK, WIDTH = 12, 4, 9, 3, 9
# 손잡이 방향(가로, 세로 위로), 휘두른 자리 궤적(시작 각도, 끝 각도)
FRAMES = [((-1, 1), None), ((0, 1), None), ((1, 1), (95, 45)), ((1, 0), (90, 0)), ((1, 2), None)]

OUTLINE = (42, 26, 30, 255)
GREEN, GREEN_LO = (95, 208, 74, 255), (47, 138, 46, 255)
RIM, FACE, HOLE = (196, 42, 48, 255), (228, 64, 62, 255), (245, 138, 128, 255)
TRAIL_IN, TRAIL_OUT = (255, 252, 230, 230), (214, 228, 240, 170)
N4 = [(1, 0), (-1, 0), (0, 1), (0, -1)]
TIP = HANDLE + HEAD


def part(u, v):
    """손에서 u 만큼, 옆으로 v 만큼 떨어진 곳이 머리·손잡이 중 어디인가. 머리 끝은 모서리까지 네모다"""
    if HANDLE - .5 <= u <= TIP - .5 and abs(v) <= min(WIDTH, NECK + 2 * (u - HANDLE + .5)) / 2:
        return "head"
    if -2.5 <= u < HANDLE - .5 and abs(v) <= .5:
        return "grip" if u < GRIP - .5 and round(u) % 2 else "handle"
    return None


def frame(n):
    (dx, dy), sweep = FRAMES[n]
    norm = math.hypot(dx, dy)
    ux, uy = dx / norm, dy / norm
    im = Image.new("RGBA", (W, H))
    px = im.load()
    if sweep:
        hi, lo = (math.radians(d) for d in sweep)
        for y in range(H):
            for x in range(W):
                vx, vy = x - P[0], P[1] - y
                r, ang = math.hypot(vx, vy), math.atan2(vy, vx)
                if lo <= ang <= hi and HANDLE - 1 <= r <= TIP + 1:
                    near = (ang - lo) / (hi - lo)
                    if near < .5 and r >= TIP - HEAD / 2: px[x, y] = TRAIL_IN
                    elif near < .8 and r >= HANDLE - 1 + near * 6: px[x, y] = TRAIL_OUT
    local = lambda x, y: (x * ux + y * uy, -x * uy + y * ux)
    sub = [(i + .5) / 4 - .5 for i in range(4)]
    kind = {}
    for y in range(H):
        for x in range(W):
            vx, vy = x - P[0], P[1] - y
            k = part(*local(vx, vy))
            # 머리는 칸을 절반 넘게 덮을 때만 칠해 기울어도 테두리가 고르다
            head = sum(part(*local(vx + a, vy - b)) == "head" for a in sub for b in sub)
            k = "head" if head >= 8 else None if k == "head" else k
            if k: kind[x, y] = k
    head = {p for p, k in kind.items() if k == "head"}
    for (x, y), k in kind.items():
        if k == "head":
            rim = any((x + ox, y + oy) not in head for ox, oy in N4)
            # 구멍은 화면 격자에 맞춰 어느 각도에서도 고르게 보이게 한다
            px[x, y] = RIM if rim else HOLE if x % 2 == 0 and y % 2 == 0 else FACE
        else:
            px[x, y] = GREEN_LO if k == "grip" else GREEN
    edge = {(x + ox, y + oy) for x, y in kind for ox, oy in N4} - set(kind)
    # 세운 장·눕힌 장은 머리 끝 두 모서리까지 윤곽을 채워 네모로 보이게 한다
    if dx * dy == 0:
        edge |= {(P[0] + round(TIP * ux - s * uy), P[1] - round(TIP * uy + s * ux)) for s in (-(WIDTH + 1) / 2, (WIDTH + 1) / 2)}
    for x, y in edge:
        if 0 <= x < W and 0 <= y < H: px[x, y] = OUTLINE
    return im


sheet = Image.new("RGBA", (W * 5, H))
for n in range(5):
    sheet.paste(frame(n), (W * n, 0))
sheet.save(sys.argv[1] if len(sys.argv) > 1 else "offiky/Assets.xcassets/swatter.imageset/swatter.png")
