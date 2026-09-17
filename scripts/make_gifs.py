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


def scene(scale=2, width=336, height=132):
    """둘이 마주 보고 달려와 부딪친다. 앱에서 피격이 생기는 방식 그대로다.

    스프라이트 한 칸(24)이 화면에서 48pt 이므로 1pt 는 scale/2 픽셀이다."""
    left, right = frames("frog_green"), frames("pig_pink")
    px_per_pt = scale / 2
    ground_h = 12
    floor_y = height - ground_h
    foot = floor_y - 24 * scale + 4

    class Body:
        def __init__(self, cut, x, facing):
            self.cut, self.x, self.facing = cut, x, facing
            self.phase, self.lift, self.jump_t, self.hurt = 0.0, 0.0, None, 0.0
            self.stopped = False

        def draw(self, canvas):
            action = ("hurt" if self.hurt > 0 else
                      "jump" if self.lift > 0 else
                      self.action)
            cell = sprite(self.cut, action, self.phase)
            if self.facing < 0:
                cell = cell.transpose(Image.FLIP_LEFT_RIGHT)
            cell = cell.resize((24 * scale, 24 * scale), Image.NEAREST)
            canvas.alpha_composite(
                cell, (round(self.x * px_per_pt) - 12 * scale,
                       foot - round(self.lift * px_per_pt)))

    a = Body(left, 20, 1)
    b = Body(right, 316 / px_per_pt, -1)
    plan = [("idle", 0.7), ("walk", 1.0), ("jump", 0.9), ("dash", 9.0)]
    out, done, hurt_at = [], False, None
    for action, seconds in plan:
        for _ in range(round(seconds * STEP)):
            if done:
                break
            dt = 1.0 / STEP
            for body in (a, b):
                body.action = "idle" if action == "jump" else action
                body.phase += dt
                if body.hurt > 0:
                    body.hurt -= dt
                    continue
                # 부딪히고 나면 멈춰 선다. 앱에서도 대시가 끊긴다
                if body.stopped:
                    body.action = "idle"
                    continue
                speed = {"walk": WALK, "dash": DASH}.get(body.action, 0.0)
                if action == "jump":
                    speed = WALK
                body.x += speed * dt * body.facing

            if action == "jump":                       # 개구리만 뛴다
                a.jump_t = 0.0 if a.jump_t is None else a.jump_t + dt
                v0 = (2 * GRAVITY * APEX["walk"]) ** 0.5
                a.lift = max(0.0, v0 * a.jump_t - 0.5 * GRAVITY * a.jump_t ** 2)
            else:
                a.lift = 0.0

            # 앱과 같은 판정 — 마주 보고 달리다 22pt 안으로 들어오면 둘 다 아프다
            if hurt_at is None and action == "dash" and abs(a.x - b.x) < 22:
                hurt_at = len(out)
                a.hurt = b.hurt = 0.7
                a.stopped = b.stopped = True
                a.phase = b.phase = 0.0
            if hurt_at is not None and len(out) > hurt_at + round(1.6 * STEP):
                done = True

            canvas = Image.new("RGBA", (width, height), SKY)
            for y in range(floor_y, height):
                color = GROUND_TOP if y < floor_y + 2 else GROUND
                for x in range(width):
                    canvas.putpixel((x, y), color)
            for x in range(width):
                if (x // 10) % 3 == 0:
                    for y in range(floor_y + 2, floor_y + 5):
                        canvas.putpixel((x, y), GROUND_DARK)
            for body in (a, b):
                body.draw(canvas)
            out.append(canvas)
    return out


def save(path, images):
    images[0].save(path, save_all=True, append_images=images[1:],
                   duration=1000 // STEP, loop=0, disposal=2, optimize=True)
    print("%s  %d장  %.0fKB" % (path, len(images), path.stat().st_size / 1024))


OUT.mkdir(exist_ok=True)
save(OUT / "demo.gif", scene())
