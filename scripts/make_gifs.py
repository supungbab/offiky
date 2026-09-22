#!/usr/bin/env python3
"""README 에 넣을 움직이는 그림을 스프라이트에서 만든다.

앱이 실제로 쓰는 값을 그대로 쓴다 — 걷기 60pt/s, 대시 180pt/s, 중력 1100,
동작마다 다른 재생 속도. 따로 흉내 내면 앱과 다른 것을 보여 주게 된다.
"""
import pathlib
from PIL import Image

SHEET = "offiky/Assets.xcassets/characters/%s.imageset/%s.png"
OUT = pathlib.Path("docs")

# Characters.swift 와 같은 값
ROW = {"idle": 0, "walk": 1, "hurt": 2, "jump": 3, "bow": 4, "dash": 5}
COUNT = {"idle": 4, "walk": 6, "hurt": 4, "jump": 3, "bow": 1, "dash": 6}
FPS = {"idle": 5, "walk": 12, "hurt": 14, "jump": 11, "bow": 1, "dash": 18}
# CharacterScene.swift 와 같은 값
WALK, DASH, GRAVITY = 60.0, 180.0, 1100.0
APEX = {"stand": 72.0, "walk": 78.0, "dash": 108.0, "air": 60.0}

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


class Actor:
    def __init__(self, cut, x, facing):
        self.cut, self.x, self.facing = cut, x, facing
        self.action, self.move, self.phase, self.lift = "idle", 0.0, 0.0, 0.0

    def step(self, dt):
        self.phase += dt
        speed = {"walk": WALK, "dash": DASH, "jump": DASH}.get(self.action, 0.0)
        self.x += speed * dt * self.move

    def draw(self, canvas, camera, cx, foot, scale, ppt):
        cell = sprite(self.cut, self.action, self.phase)
        if self.facing < 0:
            cell = cell.transpose(Image.FLIP_LEFT_RIGHT)
        cell = cell.resize((24 * scale, 24 * scale), Image.NEAREST)
        canvas.alpha_composite(
            cell, (cx + round((self.x - camera) * ppt), foot - round(self.lift * ppt)))


# 부딪힌 뒤. 동시에 꾸벅하면 로봇 같다 — 하나가 먼저 숙이고 상대가 답하고 짧게 한 번 더
# (초, 내 동작, 내 이동, 내 방향, 상대 동작, 상대 이동, 상대 방향)
AFTER = [
    (0.7, "hurt", 0, +1, "hurt", 0, -1),      # 아프다
    (0.7, "walk", +1, +1, "walk", -1, -1),    # 서로 지나쳐 몇 걸음
    (0.5, "idle", 0, -1, "idle", 0, +1),      # 멈춰 돌아본다
    (0.8, "bow", 0, -1, "idle", 0, +1),       # 내가 먼저 숙인다
    (0.4, "idle", 0, -1, "idle", 0, +1),
    (0.9, "idle", 0, -1, "bow", 0, +1),       # 상대가 답한다
    (0.3, "idle", 0, -1, "idle", 0, +1),
    (0.5, "bow", 0, -1, "bow", 0, +1),        # 아이고 아니에요, 둘이 한 번 더
    (0.6, "idle", 0, -1, "idle", 0, +1),
    (0.4, "idle", 0, +1, "idle", 0, -1),      # 다시 갈 길을 본다
]
# 무한으로 도니 끝이 처음과 이어져야 한다. 카메라가 개구리를 다시 잡고,
# 개구리가 가운데에 서 있는 채로 끝나야 첫 장면과 맞물린다
CATCHUP = 0.8                  # 멈춰 있던 화면이 개구리를 따라잡는 시간
TAIL_WALK = 0.6                # 따라잡은 뒤 더 걷는 최소 시간
TAIL_IDLE = 0.8                # 끝에 서 있는 시간. 첫 장면의 대기와 이어진다
TICK = 20.0                    # 바닥 눈금 한 주기(pt). 위상이 같아야 이음매가 없다


def scene(scale=3, width=342, height=186):
    """걷다 달리다 뛰고, 달려온 동료와 부딪쳐 인사하고 각자 간다.

    스프라이트 한 칸(24)이 화면에서 48pt 이므로 1pt 는 scale/2 픽셀이다.
    점프 정점 108pt 가 키의 2.25배라 도화지가 그만큼 높다."""
    ppt = scale / 2
    ground_h = 12
    floor_y = height - ground_h
    foot = floor_y - 24 * scale + 4
    cx = width // 2 - 12 * scale

    me = Actor(frames("frog_green"), 0.0, +1)
    you = Actor(frames("pig_pink"), 830.0, -1)
    OTHER_START = 190.0
    out, camera, hit = [], 0.0, None

    def render(step_from_hit=None):
        canvas = Image.new("RGBA", (width, height), SKY)
        for y in range(floor_y, height):
            color = GROUND_TOP if y < floor_y + 2 else GROUND
            for px in range(width):
                canvas.putpixel((px, y), color)
        for px in range(width):
            if (int(px + camera * ppt) // 10) % 3 == 0:
                for y in range(floor_y + 2, floor_y + 5):
                    canvas.putpixel((px, y), GROUND_DARK)
        for body in (me, you):
            body.draw(canvas, camera, cx, foot, scale, ppt)
        if step_from_hit is not None and step_from_hit < 3:
            burst(canvas, cx + 12 * scale + round((you.x - camera) * ppt / 2),
                  foot + 10 * scale, step_from_hit)
        out.append(canvas)

    # 부딪히기 전. 상대가 가까워지면 달려 나온다
    plan = [("idle", 0.8), ("walk", 2.0), ("dash", 1.3), ("jump", 0.9), ("dash", 4.0)]
    jump_t = None
    for action, seconds in plan:
        for _ in range(round(seconds * STEP)):
            if hit is not None:
                break
            dt = 1.0 / STEP
            me.action, me.move = ("jump" if action == "jump" else action), 1
            you.action = "dash" if you.x - me.x < OTHER_START else "idle"
            you.move = -1 if you.action == "dash" else 0
            me.step(dt)
            you.step(dt)
            camera = me.x
            if action == "jump":
                jump_t = 0.0 if jump_t is None else jump_t + dt
                v0 = (2 * GRAVITY * APEX["dash"]) ** 0.5
                me.lift = max(0.0, v0 * jump_t - 0.5 * GRAVITY * jump_t ** 2)
            else:
                me.lift = 0.0
            # 앱과 같은 판정 — 마주 보고 달리다 22pt 안으로 들어오면 둘 다 아프다
            if action == "dash" and you.x - me.x < 22:
                hit = len(out)
                me.phase = you.phase = 0.0
            render(0 if hit is not None else None)

    # 부딪힌 뒤. 화면을 고정해 둘이 같이 보이게 한다
    frame = 1
    for seconds, act, mv, face, oact, omv, oface in AFTER:
        for i in range(round(seconds * STEP)):
            dt = 1.0 / STEP
            if i == 0:
                me.phase = you.phase = 0.0
            me.action, me.move, me.facing = act, mv, face
            you.action, you.move, you.facing = oact, omv, oface
            me.step(dt)
            you.step(dt)
            render(frame if frame < 3 else None)
            frame += 1

    # 각자 간다. 멈춰 있던 화면이 개구리를 따라잡는다
    me.action, me.move, me.facing = "walk", 1, +1
    you.action, you.move, you.facing = "walk", -1, -1
    me.phase = you.phase = 0.0
    dt = 1.0 / STEP
    behind = me.x - camera
    for i in range(round(CATCHUP * STEP)):
        me.step(dt)
        you.step(dt)
        camera += WALK * dt + behind / (CATCHUP * STEP)
        render()

    # 눈금 위상이 처음과 같아질 때까지 더 걷는다. 안 맞으면 되감길 때 바닥이 튄다
    camera = me.x
    steps = 0
    while steps < round(TAIL_WALK * STEP) or abs(camera % TICK) > 0.01:
        me.step(dt)
        you.step(dt)
        camera = me.x
        render()
        steps += 1
        if steps > round((TAIL_WALK + 2.5) * STEP):
            break

    # 가운데에 서서 끝난다. 다음 바퀴의 첫 장면으로 그대로 이어진다
    me.action, me.move = "idle", 0
    you.action, you.move = "idle", 0
    me.phase = 0.0
    for _ in range(round(TAIL_IDLE * STEP)):
        me.step(dt)
        render()
    # 마지막 장은 첫 장과 똑같다. 그대로 두면 되감기는 자리에서 한 박자 멈춘다
    return out[:-1]


def save(path, images):
    images[0].save(path, save_all=True, append_images=images[1:],
                   duration=1000 // STEP, loop=0, disposal=2, optimize=True)
    print("%s  %d장  %.0fKB" % (path, len(images), path.stat().st_size / 1024))


OUT.mkdir(exist_ok=True)
save(OUT / "demo.gif", scene())
