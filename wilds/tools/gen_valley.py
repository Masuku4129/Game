# Процедурные «рисованные» ассеты Туманной долины -> art/valley/
# Стиль: мягкое освещение сверху-слева, тёмный фиолетовый контур (как у Миты), светлая туманная палитра.
import numpy as np, math, os, json
from PIL import Image, ImageDraw, ImageFilter

OUT = "art/valley/"
os.makedirs(OUT, exist_ok=True)
INK = np.array([40, 36, 66], float)


def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def pnoise(h, w, beta=2.0, seed=0):
    """Периодический (бесшовный) шум 0..1."""
    r = np.random.default_rng(seed)
    f = np.fft.fft2(r.standard_normal((h, w)))
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    rad = np.sqrt(fx ** 2 + fy ** 2)
    rad[0, 0] = 1.0
    f = f / rad ** (beta / 2.0)
    f[0, 0] = 0
    n = np.real(np.fft.ifft2(f))
    n = (n - n.min()) / (n.max() - n.min() + 1e-9)
    return n


def lerpc(d, l, t):
    d = np.array(d, float)
    l = np.array(l, float)
    return d[None, None, :] * (1 - t[..., None]) + l[None, None, :] * t[..., None]


class Cv:
    def __init__(s, w, h):
        s.p = np.zeros((h, w, 3))
        s.a = np.zeros((h, w))

    def over(s, rgb, alpha):
        s.p = rgb * alpha[..., None] + s.p * (1 - alpha[..., None])
        s.a = alpha + s.a * (1 - alpha)

    def save(s, name, scale=0.5):
        rgb = np.where(s.a[..., None] > 1e-3, s.p / np.maximum(s.a[..., None], 1e-3), 0)
        im = Image.fromarray(np.dstack([rgb, s.a * 255]).clip(0, 255).astype(np.uint8), "RGBA")
        if scale != 1.0:
            im = im.resize((int(im.width * scale), int(im.height * scale)), Image.LANCZOS)
        im.save(OUT + name + ".png")
        return im


def paint(cv, mask, dark, light, blur=16, outline=5, tex=0.10, seed=0, vgrad=0.18):
    H, W = cv.a.shape
    m = np.array(mask, float) / 255
    if outline > 0:
        dil = np.array(mask.filter(ImageFilter.MaxFilter(outline * 2 + 1)), float) / 255
        cv.over(np.broadcast_to(INK, (H, W, 3)), dil)
    h = np.array(mask.filter(ImageFilter.GaussianBlur(blur)), float) / 255
    gy, gx = np.gradient(h)
    lit = 0.5 - (gx * -0.55 + gy * -0.83) * blur * 2.4
    lit = lit - vgrad * (np.linspace(0, 1, H)[:, None] - 0.5)
    n = pnoise(H, W, 1.6, seed)
    lit = np.clip(lit + (n - 0.5) * tex * 2, 0, 1)
    cv.over(lerpc(dark, light, lit), m)


def speckle(cv, mask, cols, n, rmin, rmax, alpha, seed):
    H, W = cv.a.shape
    r = np.random.default_rng(seed)
    lay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    m = np.array(mask)
    for _ in range(n):
        x = int(r.uniform(0, W))
        y = int(r.uniform(0, H))
        if m[y, x] < 128:
            continue
        rad = r.uniform(rmin, rmax)
        c = cols[r.integers(len(cols))]
        d.ellipse([x - rad, y - rad * 0.7, x + rad, y + rad * 0.7], fill=tuple(c) + (int(255 * alpha),))
    a = np.array(lay).astype(float)
    cv.over(a[..., :3], a[..., 3] / 255 * (np.array(mask, float) / 255))


def mask_of(W, H):
    im = Image.new("L", (W, H), 0)
    return im, ImageDraw.Draw(im)


def blob_poly(cx, cy, rx, ry, n, seed, jag=0.18):
    r = np.random.default_rng(seed)
    pts = []
    for i in range(n):
        a = TAU * i / n
        k = 1 + r.uniform(-jag, jag)
        pts.append((cx + math.cos(a) * rx * k, cy + math.sin(a) * ry * k))
    return pts


TAU = math.pi * 2
DATA = {}


# ---------------------------------------------------------------- деревья

def trunk_mask(W, H, cx, base, top, w0, seed, lean=12.0):
    m, d = mask_of(W, H)
    L, R = [], []
    for i in range(21):
        t = i / 20
        y = base - t * (base - top)
        x = cx + math.sin(t * 3 + seed) * lean * t
        w = w0 * (1 - 0.35 * t) + w0 * 0.8 * (1 - t) ** 4
        L.append((x - w, y))
        R.append((x + w, y))
    d.polygon(L + R[::-1], fill=255)
    return m


def tree_round(name, seed, dark, light, spread=1.0, tr=((72, 62, 86), (150, 134, 150))):
    W, H = 720, 860
    r = np.random.default_rng(seed)
    cv = Cv(W, H)
    paint(cv, trunk_mask(W, H, 360, 800, 380, 34, seed), tr[0], tr[1], blur=14, outline=5, tex=0.25, seed=seed + 1, vgrad=0.1)
    fol, d = mask_of(W, H)
    for k in range(11):
        a = r.uniform(0, TAU)
        rr = r.uniform(0, 1) ** 0.6
        x = 360 + math.cos(a) * rr * 190 * spread
        y = 340 + math.sin(a) * rr * 140 * spread
        rad = r.uniform(85, 135)
        d.ellipse([x - rad, y - rad * 0.92, x + rad, y + rad * 0.92], fill=255)
    paint(cv, fol, dark, light, blur=26, outline=6, tex=0.12, seed=seed + 2, vgrad=0.30)
    lighter = tuple(int(min(255, c + 34)) for c in light)
    darker = tuple(int(c * 0.78) for c in dark)
    speckle(cv, fol, [lighter, darker], 520, 5, 12, 0.35, seed + 3)
    cv.save(name)
    DATA[name] = [180, 400, 16]


def tree_pine(name, seed):
    W, H = 640, 920
    cv = Cv(W, H)
    paint(cv, trunk_mask(W, H, 320, 850, 700, 24, seed, 4.0), (72, 62, 86), (140, 124, 140), blur=10, outline=5, tex=0.25, seed=seed, vgrad=0.1)
    halfs = [195, 170, 142, 112, 80]
    for i in range(5):
        yb = 790 - i * 118
        top = yb - 215
        hw = halfs[i]
        m, d = mask_of(W, H)
        pts = [(320, top)]
        n = 9
        for k in range(n + 1):
            x = 320 - hw + 2 * hw * k / n
            pts.append((x, yb + (16 if k % 2 == 0 else -6)))
        d.polygon(pts, fill=255)
        paint(cv, m, (46, 84, 92), (132, 172, 164), blur=20, outline=5, tex=0.12, seed=seed + i, vgrad=0.35)
        speckle(cv, m, [(170, 205, 190), (36, 66, 76)], 140, 4, 9, 0.3, seed + 10 + i)
    cv.save(name)
    DATA[name] = [160, 425, 14]


def tree_birch(name, seed):
    W, H = 680, 860
    r = np.random.default_rng(seed)
    cv = Cv(W, H)
    tm = trunk_mask(W, H, 340, 810, 330, 24, seed, 22.0)
    paint(cv, tm, (176, 174, 190), (232, 230, 240), blur=10, outline=5, tex=0.08, seed=seed, vgrad=0.1)
    lay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    for _ in range(26):
        y = r.uniform(380, 800)
        x = 340 + math.sin((810 - y) / 470 * 3 + seed) * 22 * ((810 - y) / 470) + r.uniform(-14, 14)
        d.rectangle([x - 7, y, x + 7, y + 6], fill=(54, 50, 70, 230))
    a = np.array(lay).astype(float)
    cv.over(a[..., :3], a[..., 3] / 255 * (np.array(tm, float) / 255))
    fol, d = mask_of(W, H)
    for k in range(8):
        x = 340 + r.uniform(-150, 150)
        y = 300 + r.uniform(-110, 90)
        rad = r.uniform(60, 100)
        d.ellipse([x - rad, y - rad * 0.85, x + rad, y + rad * 0.85], fill=255)
    paint(cv, fol, (110, 148, 112), (206, 222, 156), blur=22, outline=6, tex=0.14, seed=seed + 2, vgrad=0.30)
    speckle(cv, fol, [(232, 238, 176), (88, 124, 96)], 420, 4, 10, 0.35, seed + 3)
    cv.save(name)
    DATA[name] = [170, 405, 12]


# ---------------------------------------------------------------- кусты, камни

def bush(name, seed, dark=(70, 112, 104), light=(154, 198, 170), berries=True):
    W, H = 460, 340
    r = np.random.default_rng(seed)
    cv = Cv(W, H)
    m, d = mask_of(W, H)
    for k in range(6):
        x = 230 + r.uniform(-120, 120)
        y = 210 + r.uniform(-30, 30)
        rad = r.uniform(55, 85)
        d.ellipse([x - rad, y - rad * 0.85, x + rad, y + rad * 0.85], fill=255)
    paint(cv, m, dark, light, blur=18, outline=5, tex=0.14, seed=seed, vgrad=0.3)
    speckle(cv, m, [tuple(min(255, c + 30) for c in light), tuple(int(c * 0.75) for c in dark)], 220, 4, 9, 0.35, seed + 1)
    if berries:
        speckle(cv, m, [(180, 150, 230), (220, 200, 250)], 28, 5, 8, 0.95, seed + 2)
    cv.save(name)
    DATA[name] = [115, 290, 0]


def rock(name, seed, w, h, moss=True):
    W, H = w * 2, h * 2
    cv = Cv(W, H)
    m, d = mask_of(W, H)
    d.polygon(blob_poly(W / 2, H * 0.58, W * 0.42, H * 0.36, 11, seed, 0.14), fill=255)
    paint(cv, m, (112, 112, 138), (196, 196, 214), blur=22, outline=5, tex=0.2, seed=seed, vgrad=0.35)
    r = np.random.default_rng(seed)
    lay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dd = ImageDraw.Draw(lay)
    for _ in range(3):
        x = r.uniform(W * 0.3, W * 0.7)
        y = r.uniform(H * 0.35, H * 0.7)
        dd.line([x, y, x + r.uniform(-30, 30), y + r.uniform(20, 50)], fill=(*INK.astype(int), 170), width=4)
    a = np.array(lay).astype(float)
    cv.over(a[..., :3], a[..., 3] / 255 * (np.array(m, float) / 255))
    if moss:
        mm, md = mask_of(W, H)
        md.polygon(blob_poly(W * 0.45, H * 0.42, W * 0.26, H * 0.12, 9, seed + 5, 0.3), fill=255)
        mm = Image.fromarray((np.array(mm) * (np.array(m) > 128)).astype(np.uint8))
        paint(cv, mm, (70, 112, 100), (150, 196, 164), blur=8, outline=0, tex=0.2, seed=seed + 6, vgrad=0.1)
    cv.save(name)
    DATA[name] = [w, int(h * 0.9), int(w * 0.42)]


def fern(name, seed):
    W, H = 360, 280
    r = np.random.default_rng(seed)
    cv = Cv(W, H)
    m, d = mask_of(W, H)
    for k in range(9):
        ang = math.radians(-90 + (k - 4) * 17 + r.uniform(-5, 5))
        ln = r.uniform(110, 170)
        pts = []
        for i in range(10):
            t = i / 9
            pts.append((180 + math.cos(ang) * ln * t + math.sin(t * 2) * 12 * (k - 4) / 4, 250 + math.sin(ang) * ln * t + t * t * 40))
        d.line(pts, fill=255, width=16)
        for i in range(2, 9):
            px, py = pts[i]
            d.ellipse([px - 11, py - 7, px + 11, py + 7], fill=255)
    paint(cv, m, (84, 128, 108), (176, 214, 170), blur=8, outline=4, tex=0.12, seed=seed, vgrad=0.2)
    cv.save(name)
    DATA[name] = [90, 125, 0]


# ---------------------------------------------------------------- хижина и мост

def hut(name):
    W, H = 960, 820
    cv = Cv(W, H)
    # тень
    sh = Image.new("L", (W, H), 0)
    ImageDraw.Draw(sh).ellipse([90, 690, 870, 800], fill=110)
    cv.over(np.zeros((H, W, 3)), np.array(sh.filter(ImageFilter.GaussianBlur(14)), float) / 255 * 0.55)
    # каменный фундамент
    m, d = mask_of(W, H)
    d.rectangle([150, 640, 810, 740], fill=255)
    paint(cv, m, (104, 104, 128), (176, 176, 196), blur=10, outline=5, tex=0.2, seed=1, vgrad=0.3)
    # стены
    m, d = mask_of(W, H)
    d.rectangle([170, 380, 790, 650], fill=255)
    paint(cv, m, (78, 64, 88), (150, 128, 142), blur=14, outline=6, tex=0.25, seed=2, vgrad=0.2)
    lay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ld = ImageDraw.Draw(lay)
    for y in range(400, 650, 34):
        ld.line([170, y, 790, y], fill=(40, 30, 54, 190), width=4)
    r = np.random.default_rng(3)
    for y in range(380, 650, 34):
        for x in range(170 + int(r.uniform(0, 80)), 790, 120):
            ld.line([x, y, x, y + 34], fill=(40, 30, 54, 150), width=3)
    a = np.array(lay).astype(float)
    cv.over(a[..., :3], a[..., 3] / 255 * (np.array(m, float) / 255))
    # дверь
    dm, dd = mask_of(W, H)
    dd.rounded_rectangle([420, 470, 540, 650], 18, fill=255)
    paint(cv, dm, (46, 36, 58), (96, 78, 104), blur=8, outline=5, tex=0.1, seed=4, vgrad=0.1)
    # окно с тёплым светом
    wm, wd = mask_of(W, H)
    wd.rounded_rectangle([230, 460, 340, 560], 10, fill=255)
    paint(cv, wm, (230, 176, 110), (255, 238, 184), blur=14, outline=6, tex=0.04, seed=5, vgrad=0.0)
    lay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ld = ImageDraw.Draw(lay)
    ld.line([285, 460, 285, 560], fill=(60, 44, 56, 255), width=6)
    ld.line([230, 510, 340, 510], fill=(60, 44, 56, 255), width=6)
    a = np.array(lay).astype(float)
    cv.over(a[..., :3], a[..., 3] / 255)
    # крыша
    m, d = mask_of(W, H)
    d.polygon([(110, 410), (480, 130), (850, 410), (810, 440), (480, 210), (150, 440)], fill=255)
    d.polygon([(110, 410), (480, 130), (850, 410), (780, 420), (480, 190), (180, 420)], fill=255)
    paint(cv, m, (92, 92, 126), (168, 170, 204), blur=16, outline=6, tex=0.18, seed=6, vgrad=0.2)
    lay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ld = ImageDraw.Draw(lay)
    for i in range(1, 6):
        y = 130 + i * 50
        k = (y - 130) / 280
        ld.line([480 - 370 * k + 20, y + 10, 480 + 370 * k - 20, y + 10], fill=(40, 36, 66, 150), width=3)
    a = np.array(lay).astype(float)
    cv.over(a[..., :3], a[..., 3] / 255 * (np.array(m, float) / 255))
    # мох на крыше
    mm, md = mask_of(W, H)
    md.polygon(blob_poly(360, 250, 90, 22, 9, 8, 0.3), fill=255)
    md.polygon(blob_poly(620, 300, 70, 18, 9, 9, 0.3), fill=255)
    mm = Image.fromarray((np.array(mm) * (np.array(m) > 128)).astype(np.uint8))
    paint(cv, mm, (74, 114, 100), (150, 196, 164), blur=8, outline=0, tex=0.2, seed=7, vgrad=0.1)
    # труба
    cm, cd = mask_of(W, H)
    cd.rectangle([640, 130, 720, 300], fill=255)
    paint(cv, cm, (104, 104, 128), (176, 176, 196), blur=8, outline=5, tex=0.2, seed=8, vgrad=0.2)
    cv.save(name, 0.5)
    DATA[name] = [240, 365, 0]


def bridge(name):
    W, H = 1040, 340
    cv = Cv(W, H)
    sh = Image.new("L", (W, H), 0)
    ImageDraw.Draw(sh).rectangle([20, 250, 1020, 330], fill=120)
    cv.over(np.zeros((H, W, 3)), np.array(sh.filter(ImageFilter.GaussianBlur(10)), float) / 255 * 0.5)
    m, d = mask_of(W, H)
    d.rectangle([0, 90, 1040, 270], fill=255)
    paint(cv, m, (92, 76, 98), (160, 138, 150), blur=8, outline=6, tex=0.25, seed=1, vgrad=0.15)
    lay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ld = ImageDraw.Draw(lay)
    for x in range(0, 1040, 44):
        ld.line([x, 90, x, 270], fill=(40, 30, 54, 200), width=4)
    ld.line([0, 180, 1040, 180], fill=(40, 30, 54, 70), width=2)
    a = np.array(lay).astype(float)
    cv.over(a[..., :3], a[..., 3] / 255 * (np.array(m, float) / 255))
    for y0 in (90, 270):
        rm, rd = mask_of(W, H)
        rd.rectangle([0, y0 - 80, 1040, y0 - 66], fill=255)
        paint(cv, rm, (84, 68, 90), (150, 128, 140), blur=5, outline=4, tex=0.15, seed=2, vgrad=0.0)
        for x in range(30, 1040, 130):
            pm, pd = mask_of(W, H)
            pd.rectangle([x - 9, y0 - 84, x + 9, y0 + (6 if y0 == 90 else 14)], fill=255)
            paint(cv, pm, (78, 62, 84), (146, 124, 136), blur=4, outline=4, tex=0.1, seed=3, vgrad=0.0)
    cv.save(name, 0.5)
    DATA[name] = [260, 135, 0]


# ---------------------------------------------------------------- земля, река, туман

def ground():
    S = 512
    n1 = pnoise(S, S, 2.4, 11)
    n2 = pnoise(S, S, 1.5, 12)
    t = np.clip(0.55 * n1 + 0.45 * n2, 0, 1)
    t = smooth(0.25, 0.8, t)
    base = lerpc((112, 144, 138), (176, 202, 186), t)
    im = Image.fromarray(base.clip(0, 255).astype(np.uint8))
    d = ImageDraw.Draw(im)
    r = np.random.default_rng(5)
    for _ in range(1500):
        x = r.uniform(0, S)
        y = r.uniform(0, S)
        ln = r.uniform(7, 15)
        a = math.radians(-90 + r.uniform(-28, 28))
        col = (196, 222, 196) if r.random() < 0.45 else (84, 118, 112)
        for ox in (-S, 0, S):
            for oy in (-S, 0, S):
                d.line([x + ox, y + oy, x + ox + math.cos(a) * ln, y + oy + math.sin(a) * ln], fill=col, width=2)
    for _ in range(40):
        x = r.uniform(0, S)
        y = r.uniform(0, S)
        col = (236, 232, 250) if r.random() < 0.6 else (200, 180, 240)
        for ox in (-S, 0, S):
            for oy in (-S, 0, S):
                d.ellipse([x + ox - 3, y + oy - 2, x + ox + 3, y + oy + 2], fill=col)
    im.save(OUT + "grass.png")


def strip(name, col_a, col_b, edge0, edge1, pebble, seed, U=256, V=192):
    n = pnoise(V, U, 2.0, seed)
    nn = pnoise(V, U, 1.2, seed + 1)
    v = np.linspace(0, 1, V)[:, None] * np.ones((1, U))
    dd = np.abs(v - 0.5) * 2
    e = (nn - 0.5) * 0.35
    alpha = smooth(edge1, edge0, dd + e)
    t = np.clip(0.3 + n * 0.6 - dd * 0.25, 0, 1)
    rgb = lerpc(col_a, col_b, t)
    img = Image.fromarray(rgb.clip(0, 255).astype(np.uint8))
    d = ImageDraw.Draw(img)
    r = np.random.default_rng(seed)
    for _ in range(pebble):
        x = r.uniform(0, U)
        y = r.uniform(V * 0.2, V * 0.8)
        rad = r.uniform(2, 5)
        c = tuple(int(c) for c in lerpc(col_a, col_b, np.array([[r.uniform(0.6, 1.0)]]))[0, 0])
        dk = tuple(int(c * 0.7) for c in col_a)
        for ox in (-U, 0, U):
            d.ellipse([x + ox - rad, y - rad * 0.7 + 1.5, x + ox + rad, y + rad * 0.7 + 1.5], fill=dk)
            d.ellipse([x + ox - rad, y - rad * 0.7, x + ox + rad, y + rad * 0.7], fill=c)
    a = np.array(img)
    out = np.dstack([a, (alpha * 255).astype(np.uint8)])
    Image.fromarray(out, "RGBA").save(OUT + name + ".png")


def water():
    U, V = 256, 256
    nn = pnoise(V, U // 4, 2.0, 21)
    st = np.repeat(nn, 4, axis=1)
    n2 = pnoise(V, U, 1.4, 22)
    v = np.linspace(0, 1, V)[:, None] * np.ones((1, U))
    dd = np.abs(v - 0.5) * 2
    t = np.clip(0.55 - dd * 0.45 + (n2 - 0.5) * 0.3, 0, 1)
    rgb = lerpc((120, 164, 196), (176, 212, 226), t)
    hl = smooth(0.62, 0.72, st) * (1 - smooth(0.72, 0.8, st))
    rgb = rgb + hl[..., None] * np.array([70, 60, 40])
    foam = smooth(0.8, 0.96, dd + (n2 - 0.5) * 0.3)
    rgb = rgb * (1 - foam[..., None] * 0.7) + np.array([240, 246, 252]) * foam[..., None] * 0.7
    alpha = smooth(1.0, 0.86, dd + (n2 - 0.5) * 0.12)
    Image.fromarray(np.dstack([rgb.clip(0, 255), alpha * 255]).astype(np.uint8), "RGBA").save(OUT + "water.png")


def fog(name, seed):
    W, H = 512, 256
    n = pnoise(H, W, 2.2, seed)
    y, x = np.mgrid[0:H, 0:W]
    rad = np.sqrt(((x - W / 2) / (W / 2)) ** 2 + ((y - H / 2) / (H / 2)) ** 2)
    a = smooth(1.0, 0.15, rad) * smooth(0.25, 0.75, n)
    out = np.dstack([np.full((H, W), 236), np.full((H, W), 240), np.full((H, W), 250), a * 255]).astype(np.uint8)
    Image.fromarray(out, "RGBA").save(OUT + name + ".png")


def soft_patch(name, seed, col):
    W, H = 512, 384
    n = pnoise(H, W, 2.0, seed)
    y, x = np.mgrid[0:H, 0:W]
    rad = np.sqrt(((x - W / 2) / (W / 2)) ** 2 + ((y - H / 2) / (H / 2)) ** 2)
    a = smooth(1.0, 0.2, rad) * smooth(0.2, 0.7, n) * 0.55
    out = np.dstack([np.full((H, W), col[0]), np.full((H, W), col[1]), np.full((H, W), col[2]), a * 255]).astype(np.uint8)
    Image.fromarray(out, "RGBA").save(OUT + name + ".png")


def glow(name, col):
    S = 128
    y, x = np.mgrid[0:S, 0:S]
    rad = np.sqrt((x - S / 2) ** 2 + (y - S / 2) ** 2) / (S / 2)
    a = smooth(1.0, 0.0, rad) ** 1.6
    out = np.dstack([np.full((S, S), col[0]), np.full((S, S), col[1]), np.full((S, S), col[2]), a * 255]).astype(np.uint8)
    Image.fromarray(out, "RGBA").save(OUT + name + ".png")


if __name__ == "__main__":
    ground()
    strip("path", (150, 134, 142), (212, 196, 190), 0.95, 0.7, 70, 31)
    strip("bank", (150, 150, 168), (210, 208, 222), 0.97, 0.75, 90, 41)
    water()
    for i in range(3):
        fog("fog%d" % i, 50 + i)
    soft_patch("patch_dark", 61, (58, 90, 92))
    soft_patch("patch_light", 62, (214, 226, 210))
    glow("glow_warm", (255, 220, 150))
    tree_round("tree_a", 1, (64, 102, 98), (152, 192, 170))
    tree_round("tree_b", 2, (66, 100, 116), (160, 198, 198), 1.1)
    tree_pine("pine_a", 3)
    tree_pine("pine_b", 4)
    tree_birch("birch_a", 5)
    bush("bush_a", 6)
    bush("bush_b", 7, (84, 110, 124), (170, 200, 214), False)
    rock("rock_a", 8, 150, 110)
    rock("rock_b", 9, 260, 190)
    fern("fern_a", 10)
    hut("hut")
    bridge("bridge")
    with open(OUT + "valley_data.gd", "w") as f:
        f.write("# сгенерировано tools/gen_valley.py: имя -> [опора x, опора y, радиус коллизии]\nconst DATA := " + json.dumps(DATA) + "\n")
    print("ok", len(DATA))
