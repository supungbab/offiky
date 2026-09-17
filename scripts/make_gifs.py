#!/usr/bin/env python3
"""README 에 넣을 움직이는 그림을 스프라이트에서 만든다.

앱이 실제로 쓰는 값을 그대로 쓴다 — 걷기 70pt/s, 대시 180pt/s, 중력 1100,
동작마다 다른 재생 속도. 따로 흉내 내면 앱과 다른 것을 보여 주게 된다.
"""
import pathlib
from PIL import Image

SHEET = "offiky/Assets.xcassets/characters/%s.imageset/%s.png"
OUT = pathlib.Path("docs")

# Characters.swift 와 같은 값
ROW = {"idle": 0, "walk": 1, "hurt": 2, "jump": 3, "charge": 4, "dash": 5}
COUNT = {"idle": 4, "walk": 6, "hurt": 4, "jump": 3, "charge": 1, "dash": 6}
FPS = {"idle": 5, "walk": 12, "hurt": 14, "jump": 11, "charge": 1, "dash": 18}
# CharacterScene.swift 와 같은 값
WALK, DASH, GRAVITY = 70.0, 180.0, 1100.0
APEX = {"stand": 48.0, "walk": 52.0, "dash": 72.0, "air": 40.0}
CHARGE_HOLD = 0.1

SKY = (0x2b, 0x30, 0x42, 255)
GROUND = (0x8a, 0x5a, 0x38, 255)
GROUND_TOP = (0xa8, 0x70, 0x46, 255)
GROUND_DARK = (0x56, 0x36, 0x1f, 255)
STEP = 20                      # 초당 프레임. 50ms 라 GIF 가 딱 떨어진다


def frames(name):
    sheet = Image.open(SHEET % (name, name)).convert("RGBA")
    return {a: [sheet.crop((c * 24, ROW[a] * 24, c * 24 + 24, ROW[a] * 24 + 24))
                for c in range(COUNT[a])] for a in ROW}


def sprite(cut, animation, phase):
    return cut[animation][int(phase * FPS[animation]) % COUNT[animation]]


def strip(name, animation, scale=4, pad=6):
    """동작 하나를 그대로 반복한다"""
    cut = frames(name)
    size = 24 * scale + pad * 2
    out = []
    total = COUNT[animation] / FPS[animation]
    for i in range(max(2, round(total * STEP))):
        canvas = Image.new("RGBA", (size, size), SKY)
        cell = sprite(cut, animation, i / STEP).resize(
            (24 * scale, 24 * scale), Image.NEAREST)
        canvas.alpha_composite(cell, (pad, pad))
        out.append(canvas)
    return out


BURST = (0xff, 0xf6, 0x99, 255)
BURST2 = (0xff, 0xff, 0xff, 255)


def burst(canvas, cx, cy, step):
    """부딪힌 자리에 터지는 표시. 세 장으로 커졌다 사라진다"""
    spread = (3, 6, 9)[min(step, 2)]
    color = (BURST2, BURST, BURST)[min(step, 2)]
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)):
        for n in range(spread - 2, spread + 1):
            x, y = cx + dx * n, cy + dy * n
            if 0 <= x < canvas.size[0] and 0 <= y < canvas.size[1]:
                canvas.putpixel((x, y), color)


def scene(scale=3, width=300, height=186):
    """걷다가 달리는데 밖에서 누가 달려와 정면으로 부딪친다.

    스프라이트 한 칸(24)이 화면에서 48pt 이므로 1pt 는 scale/2 픽셀이다.
    점프 정점 72pt 가 키의 1.5배라 도화지가 그만큼 높다."""
    mine, other = frames("frog_green"), frames("pig_pink")
    ppt = scale / 2
    ground_h = 12
    floor_y = height - ground_h
    foot = floor_y - 24 * scale + 4
    cx = width // 2 - 12 * scale

    plan = [("idle", 0.7), ("walk", 1.4), ("jump", 0.9),
            ("charge", CHARGE_HOLD), ("dash", 6.0)]
    out = []
    phase = other_phase = 0.0
    x = 0.0                      # 내 위치(pt)
    # 상대는 한참 멀리 있다. 가까우면 걷는 동안 붙어 버려 달리기도 전에 부딪친다
    ox = 380.0
    jump_t = None
    hit = None                   # 부딪힌 프레임 번호
    for action, seconds in plan:
        for _ in range(round(seconds * STEP)):
            if hit is not None and len(out) > hit + round(1.7 * STEP):
                break
            dt = 1.0 / STEP
            phase += dt
            other_phase += dt
            lift = 0.0
            speed = {"walk": WALK, "jump": WALK,
                     "charge": DASH, "dash": DASH}.get(action, 0.0)
            if hit is None:
                x += speed * dt
                # 상대는 내가 달리기 시작할 때 같이 달려온다
                if action in ("charge", "dash"):
                    ox -= DASH * dt
            if action == "jump":
                jump_t = 0.0 if jump_t is None else jump_t + dt
                v0 = (2 * GRAVITY * APEX["walk"]) ** 0.5
                lift = max(0.0, v0 * jump_t - 0.5 * GRAVITY * jump_t ** 2)
            else:
                jump_t = None

            # 앱과 같은 판정 — 마주 보고 달리다 22pt 안으로 들어오면 둘 다 아프다
            if hit is None and action in ("charge", "dash") and ox - x < 22:
                hit = len(out)
                phase = other_phase = 0.0

            since = None if hit is None else len(out) - hit
            mine_act = ("hurt" if since is not None and since < 0.7 * STEP else
                        "idle" if since is not None else
                        "jump" if lift > 0 else action)
            # 달려오기 전에는 서 있다. 계속 달리는 자세면 제자리 뜀박질로 보인다
            other_act = (mine_act if since is not None else
                         "dash" if action in ("charge", "dash") else "idle")

            canvas = Image.new("RGBA", (width, height), SKY)
            for y in range(floor_y, height):
                color = GROUND_TOP if y < floor_y + 2 else GROUND
                for px in range(width):
                    canvas.putpixel((px, y), color)
            for px in range(width):
                if (int(px + x * ppt) // 10) % 3 == 0:
                    for y in range(floor_y + 2, floor_y + 5):
                        canvas.putpixel((px, y), GROUND_DARK)

            cell = sprite(mine, mine_act, phase).resize(
                (24 * scale, 24 * scale), Image.NEAREST)
            canvas.alpha_composite(cell, (cx, foot - round(lift * ppt)))
            ocell = sprite(other, other_act, other_phase).transpose(
                Image.FLIP_LEFT_RIGHT).resize((24 * scale, 24 * scale), Image.NEAREST)
            canvas.alpha_composite(ocell, (cx + round((ox - x) * ppt), foot))

            if since is not None and since < 3:
                burst(canvas, cx + 12 * scale + round((ox - x) * ppt / 2),
                      foot + 10 * scale, since)
            out.append(canvas)
    return out


def save(path, images):
    images[0].save(path, save_all=True, append_images=images[1:],
                   duration=1000 // STEP, loop=0, disposal=2, optimize=True)
    print("%s  %d장  %.0fKB" % (path, len(images), path.stat().st_size / 1024))


OUT.mkdir(exist_ok=True)
save(OUT / "demo.gif", scene())
