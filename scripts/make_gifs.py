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


def scene(name, scale=3, width=210, height=78):
    """걷다가 달리고 뛰어오른다. 바닥이 흘러 움직임을 보여 준다"""
    cut = frames(name)
    ground_h = 10
    floor_y = height - ground_h
    cx = width // 2 - 12 * scale

    plan = [("idle", 1.2), ("walk", 2.0), ("charge", CHARGE_HOLD),
            ("dash", 1.6), ("jump", 0.95), ("dash", 0.7), ("idle", 1.2)]
    out, phase, scroll, t = [], 0.0, 0.0, 0.0
    jump_t = None
    for action, seconds in plan:
        for _ in range(round(seconds * STEP)):
            dt = 1.0 / STEP
            phase += dt
            speed = {"walk": WALK, "charge": DASH, "dash": DASH}.get(action, 0.0)
            scroll += speed * dt
            lift = 0.0
            shown = action
            if action == "jump":
                jump_t = 0.0 if jump_t is None else jump_t + dt
                v0 = (2 * GRAVITY * APEX["dash"]) ** 0.5
                lift = max(0.0, v0 * jump_t - 0.5 * GRAVITY * jump_t * jump_t)
                scroll += DASH * dt
            else:
                jump_t = None

            canvas = Image.new("RGBA", (width, height), SKY)
            for y in range(floor_y, height):
                color = GROUND_TOP if y < floor_y + 2 else GROUND
                for x in range(width):
                    canvas.putpixel((x, y), color)
            # 바닥 눈금이 흘러 속도를 보여 준다. 흐릿하면 걷는지 서 있는지 모른다
            for x in range(width):
                if (int(x + scroll) // 10) % 3 == 0:
                    for y in range(floor_y + 2, floor_y + 5):
                        canvas.putpixel((x, y), GROUND_DARK)
            cell = sprite(cut, shown, phase).resize(
                (24 * scale, 24 * scale), Image.NEAREST)
            canvas.alpha_composite(cell, (cx, floor_y - 24 * scale + 4 - round(lift * scale / 12)))
            out.append(canvas)
            t += dt
    return out


def save(path, images):
    images[0].save(path, save_all=True, append_images=images[1:],
                   duration=1000 // STEP, loop=0, disposal=2, optimize=True)
    print("%s  %d장  %.0fKB" % (path, len(images), path.stat().st_size / 1024))


OUT.mkdir(exist_ok=True)
save(OUT / "demo.gif", scene("frog_green"))
for animation in ("walk", "dash", "jump", "hurt"):
    save(OUT / f"{animation}.gif", strip("frog_green", animation))
