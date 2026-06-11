"""TechoOS default wallpaper: 'Angkor Dawn' — original 4K artwork drawn in code."""
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

W, H = 3840, 2160
HORIZON = int(H * 0.70)  # water line

# ---------------------------------------------------------------- sky gradient
def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

stops = [
    (0.00, (9, 10, 38)),      # deep indigo night
    (0.30, (38, 22, 70)),     # violet
    (0.55, (110, 40, 80)),    # plum
    (0.78, (196, 84, 52)),    # burnt orange
    (0.95, (244, 168, 64)),   # gold
    (1.00, (252, 206, 110)),  # bright horizon
]
sky = np.zeros((HORIZON, W, 3), dtype=np.uint8)
for y in range(HORIZON):
    t = y / (HORIZON - 1)
    for i in range(len(stops) - 1):
        if stops[i][0] <= t <= stops[i + 1][0]:
            span = stops[i + 1][0] - stops[i][0]
            tt = (t - stops[i][0]) / span
            sky[y, :] = lerp(stops[i][1], stops[i + 1][1], tt)
            break

img = Image.new("RGB", (W, H))
img.paste(Image.fromarray(sky), (0, 0))
draw = ImageDraw.Draw(img, "RGBA")

# ------------------------------------------------------------------- sun glow
cx, sun_y = W // 2, HORIZON - 10
glow = Image.new("L", (W, H), 0)
gd = ImageDraw.Draw(glow)
for r, a in [(1150, 26), (900, 36), (640, 52), (430, 74), (260, 105), (150, 165)]:
    gd.ellipse([cx - r, sun_y - r, cx + r, sun_y + r], fill=a)
glow = glow.filter(ImageFilter.GaussianBlur(60))
gold = Image.new("RGB", (W, H), (255, 214, 130))
img = Image.composite(gold, img, glow)
draw = ImageDraw.Draw(img, "RGBA")
# sun disc
draw.ellipse([cx - 120, sun_y - 120, cx + 120, sun_y + 120], fill=(255, 236, 178, 235))

# ---------------------------------------------------------------------- stars
rng = np.random.default_rng(7)
for _ in range(220):
    x = rng.integers(0, W); y = rng.integers(0, int(HORIZON * 0.45))
    fade = 1 - y / (HORIZON * 0.45)
    a = int(30 + 170 * fade * rng.random())
    s = rng.choice([1, 1, 1, 2])
    draw.ellipse([x, y, x + s, y + s], fill=(255, 245, 220, a))

# ------------------------------------------------------- Angkor Wat silhouette
SIL = (12, 8, 22, 255)

def tower(d, x, base_y, base_w, height):
    """Lotus-bud prang: tapering stacked tiers + finial."""
    tiers = 9
    y = base_y
    w = base_w
    for i in range(tiers):
        th = height * (0.16 if i < 3 else 0.10)
        shrink = 0.86 if i < 4 else 0.80
        nw = w * shrink
        d.polygon([(x - w/2, y), (x + w/2, y), (x + nw/2, y - th), (x - nw/2, y - th)], fill=SIL)
        # tier lip
        d.rectangle([x - w/2 - w*0.05, y - th*0.18, x + w/2 + w*0.05, y], fill=SIL)
        y -= th; w = nw
    # finial
    d.polygon([(x - w/2, y), (x + w/2, y), (x, y - height * 0.16)], fill=SIL)
    d.line([(x, y - height*0.16), (x, y - height*0.16 - 26)], fill=SIL, width=6)

base_y = HORIZON
# long gallery walls
draw.rectangle([cx - 1450, base_y - 95, cx + 1450, base_y], fill=SIL)
draw.rectangle([cx - 1450, base_y - 130, cx - 1300, base_y], fill=SIL)
draw.rectangle([cx + 1300, base_y - 130, cx + 1450, base_y], fill=SIL)
# roofline teeth on the galleries
for gx in range(int(cx - 1440), int(cx + 1440), 26):
    draw.polygon([(gx, base_y - 95), (gx + 13, base_y - 108), (gx + 26, base_y - 95)], fill=SIL)
# corner pavilions
for px in (cx - 1380, cx + 1380):
    tower(draw, px, base_y - 110, 150, 230)
# raised central platform
draw.rectangle([cx - 760, base_y - 200, cx + 760, base_y], fill=SIL)
draw.rectangle([cx - 560, base_y - 290, cx + 560, base_y], fill=SIL)
# quincunx towers: outer pair, inner pair, grand central
tower(draw, cx - 640, base_y - 190, 200, 360)
tower(draw, cx + 640, base_y - 190, 200, 360)
tower(draw, cx - 330, base_y - 280, 230, 460)
tower(draw, cx + 330, base_y - 280, 230, 460)
tower(draw, cx,        base_y - 290, 300, 640)
# causeway
draw.polygon([(cx - 90, base_y), (cx + 90, base_y), (cx + 60, H), (cx - 60, H)], fill=(16, 11, 30, 255))

# ------------------------------------------------------------ sugar palms
def palm(d, x, y, h, lean=0.0):
    top_x = x + int(h * lean)
    d.line([(x, y), (top_x, y - h)], fill=SIL, width=max(10, h // 22))
    for ang in np.linspace(-3.05, -0.09, 13):
        fx = top_x + int(np.cos(ang) * h * 0.32)
        fy = (y - h) + int(np.sin(ang) * h * 0.20) + h * 0.10
        mx = top_x + int(np.cos(ang) * h * 0.17)
        my = (y - h) + int(np.sin(ang) * h * 0.13) - h * 0.03
        d.line([(top_x, y - h), (mx, my)], fill=SIL, width=11)
        d.line([(mx, my), (fx, fy)], fill=SIL, width=7)

palm(draw, 240, HORIZON, 520, 0.06)
palm(draw, 430, HORIZON, 380, -0.04)
palm(draw, W - 280, HORIZON, 560, -0.06)
palm(draw, W - 470, HORIZON, 400, 0.05)

# ----------------------------------------------------------------------- birds
for bx, by, s in [(cx - 700, 520, 26), (cx - 610, 560, 20), (cx + 540, 470, 24),
                  (cx + 660, 520, 18), (cx - 200, 380, 22)]:
    draw.arc([bx - s, by - s//2, bx, by + s//2], 200, 340, fill=(15, 10, 28, 220), width=7)
    draw.arc([bx, by - s//2, bx + s, by + s//2], 200, 340, fill=(15, 10, 28, 220), width=7)

# ----------------------------------------------------------- water reflection
top = img.crop((0, 0, W, HORIZON))
refl = top.transpose(Image.FLIP_TOP_BOTTOM).resize((W, H - HORIZON))
refl = refl.filter(ImageFilter.GaussianBlur(7))
refl = Image.eval(refl, lambda p: int(p * 0.62))
img.paste(refl, (0, HORIZON))
draw = ImageDraw.Draw(img, "RGBA")
# ripple highlights
for _ in range(420):
    x = rng.integers(0, W); y = rng.integers(HORIZON + 8, H - 4)
    ln = rng.integers(20, 160); a = int(14 + 60 * rng.random())
    near_sun = max(0.0, 1 - abs(x - cx) / 900) * max(0.0, 1 - (y - HORIZON) / (H - HORIZON))
    col = (255, 220, 150, int(a + 90 * near_sun))
    draw.line([(x, y), (x + ln, y)], fill=col, width=2)
# darken water edges
vign = Image.new("L", (W, H), 0)
vd = ImageDraw.Draw(vign)
vd.rectangle([0, HORIZON, W, H], fill=70)
vign = vign.filter(ImageFilter.GaussianBlur(120))
img = Image.composite(Image.new("RGB", (W, H), (5, 4, 16)), img, vign.point(lambda p: p // 3))

img.save("/home/claude/techoos/system_files/usr/share/backgrounds/techoos/angkor-dawn.png", optimize=True)
print("done")
