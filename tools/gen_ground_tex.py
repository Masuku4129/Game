"""Процедурные бесшовные текстуры земли, травы, скалы, воды и камыша. Запуск: python3 tools/gen_ground_tex.py"""
import numpy as np, os
from PIL import Image, ImageDraw, ImageFilter
rng = np.random.default_rng(7)
OUT = os.path.join(os.path.dirname(__file__), "..", "game", "textures")
N = 512

def fbm(n=N, beta=2.0, seed=None):
    r = np.random.default_rng(seed) if seed is not None else rng
    f = np.fft.fftfreq(n)[:, None] ** 2 + np.fft.fftfreq(n)[None, :] ** 2
    f[0, 0] = 1
    a = np.fft.ifft2(np.fft.fft2(r.standard_normal((n, n))) / f ** (beta / 2)).real
    a -= a.min(); a /= a.max()
    return a

def wrapped(draw_fn, x, y, m):
    for ox in (-N, 0, N):
        for oy in (-N, 0, N):
            if -m < x + ox < N + m and -m < y + oy < N + m:
                draw_fn(x + ox, y + oy)

def stamp(img, hgt, count, fn):
    d, h = ImageDraw.Draw(img), ImageDraw.Draw(hgt)
    for _ in range(count):
        x, y = rng.uniform(0, N, 2)
        fn(d, h, x, y)

def to_img(a): return Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))

def save_rgba(rgb, h, name):
    h = np.asarray(h, dtype=np.float32) / 255.0
    a = np.dstack([np.asarray(rgb, dtype=np.uint8), (np.clip(h, 0, 1) * 255).astype(np.uint8)])
    Image.fromarray(a, "RGBA").save(os.path.join(OUT, name))

def lerpc(c1, c2, t): return np.array(c1) * (1 - t) + np.array(c2) * t

# ---------- лесная подстилка ----------
n1, n2, n3 = fbm(beta=2.4), fbm(beta=1.6), fbm(beta=1.2)
base = lerpc((62, 52, 34), (88, 74, 46), n1[..., None])
base *= (0.82 + 0.36 * n3[..., None])
moss = np.clip((n2 - 0.58) * 6, 0, 1)[..., None]
base = base * (1 - moss) + lerpc((52, 70, 30), (84, 104, 44), n3[..., None]) * moss
img = to_img(np.zeros((N, N))).convert("RGB"); img = Image.fromarray(base.astype(np.uint8))
hgt = to_img(n3 * 0.4 + 0.2)
def litter(d, h, x, y):
    k = rng.random()
    if k < 0.66:  # хвоя
        a = rng.uniform(0, 6.28); L = rng.uniform(8, 20)
        col = tuple(int(c) for c in lerpc((92, 70, 44), (122, 94, 56), rng.random()) * rng.uniform(.55, .95))
        def f(px, py): d.line([px, py, px + np.cos(a) * L, py + np.sin(a) * L], fill=col, width=1); h.line([px, py, px + np.cos(a) * L, py + np.sin(a) * L], fill=int(rng.uniform(150, 200)), width=2)
        wrapped(f, x, y, 24)
    elif k < 0.80:  # сухой лист
        a = rng.uniform(0, 6.28); s = rng.uniform(5, 11)
        col = tuple(int(c) for c in lerpc((70, 48, 26), (110, 76, 36), rng.random()) * rng.uniform(.6, 0.95))
        def f(px, py):
            pts = [(px + np.cos(a + t) * s * (1 + .35 * np.cos(2 * t)), py + np.sin(a + t) * s * .55 * (1 + .2 * np.sin(3 * t))) for t in np.linspace(0, 6.28, 14)]
            d.polygon(pts, fill=col); h.polygon(pts, fill=int(rng.uniform(140, 190)))
        wrapped(f, x, y, 16)
    elif k < 0.93:  # веточка
        a = rng.uniform(0, 6.28); L = rng.uniform(26, 70)
        def f(px, py):
            d.line([px, py, px + np.cos(a) * L, py + np.sin(a) * L], fill=(46, 34, 24), width=int(rng.integers(2, 4)))
            h.line([px, py, px + np.cos(a) * L, py + np.sin(a) * L], fill=215, width=3)
        wrapped(f, x, y, 80)
    else:  # камешек
        r = rng.uniform(3, 8); g = int(rng.uniform(70, 105))
        def f(px, py):
            d.ellipse([px - r, py - r * .8, px + r, py + r * .8], fill=(g, g - 4, g - 12)); h.ellipse([px - r, py - r * .8, px + r, py + r * .8], fill=235)
        wrapped(f, x, y, 12)
stamp(img, hgt, 5200, litter)
save_rgba(img, np.asarray(hgt.filter(ImageFilter.GaussianBlur(0.6))), "ground_forest.png")

# ---------- плотная трава сверху ----------
n1, n2 = fbm(beta=2.2), fbm(beta=1.4)
base = lerpc((24, 38, 14), (44, 62, 22), n1[..., None])
img = Image.fromarray(base.astype(np.uint8)); hgt = to_img(n2 * 0.3 + 0.15)
def blade(d, h, x, y):
    a = rng.uniform(0, 6.28); L = rng.uniform(14, 34); bend = rng.uniform(-.5, .5)
    t = rng.random(); col = lerpc((52, 78, 24), (118, 142, 52), t) * rng.uniform(.75, 1.1)
    if rng.random() < .08: col = lerpc(col, (150, 140, 60), .6)
    col = tuple(int(c) for c in np.clip(col, 0, 255))
    def f(px, py):
        pts = [(px + np.cos(a + bend * s) * L * s, py + np.sin(a + bend * s) * L * s) for s in np.linspace(0, 1, 5)]
        d.line(pts, fill=col, width=int(rng.integers(2, 4))); h.line(pts, fill=int(120 + 130 * t), width=3)
    wrapped(f, x, y, 40)
stamp(img, hgt, 9000, blade)
save_rgba(img, np.asarray(hgt.filter(ImageFilter.GaussianBlur(0.8))), "ground_grass.png")

# ---------- скала: слои, трещины, лишайник ----------
yy = np.linspace(0, 1, N)[:, None]
st = np.sin(yy * 6.28 * 7 + fbm(beta=2.6) * 9) * .5 + .5
n1, n2 = fbm(beta=1.8), fbm(beta=1.2)
v = 0.38 + 0.3 * st * 0.5 + 0.3 * n1 + 0.12 * n2
rock = np.dstack([v * 150, v * 145, v * 132])
crack = (np.abs(fbm(beta=2.4, seed=21) - 0.5) < 0.006) | (np.abs(fbm(beta=2.4, seed=22) - 0.5) < 0.005)
rock[crack] *= 0.4
lich = np.clip((fbm(beta=2.0) - 0.7) * 8, 0, 1)[..., None]
rock = rock * (1 - lich * .6) + np.array([110, 120, 60]) * lich * .6
save_rgba(rock, (v * 255 * 0.9 + crack * -60).clip(0, 255), "ground_rock.png")

# ---------- нормали воды (бесшовные волны) + пена в альфа ----------
h = fbm(beta=2.6, seed=3) * 0.7 + fbm(beta=1.8, seed=4) * 0.3
gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 14
gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 14
nz = np.ones_like(h)
l = np.sqrt(gx ** 2 + gy ** 2 + nz ** 2)
nm = np.dstack([(-gx / l * .5 + .5), (-gy / l * .5 + .5), (nz / l * .5 + .5)])
foam = np.clip((fbm(beta=1.6, seed=9) - 0.45) * 5, 0, 1)
a = np.dstack([nm, foam])
Image.fromarray((a * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, "water_wave.png"))

# ---------- камыш ----------
cv = Image.new("RGBA", (128, 512), (0, 0, 0, 0)); d = ImageDraw.Draw(cv)
for i in range(11):
    x0 = 20 + i * 8 + rng.uniform(-3, 3); top = rng.uniform(20, 140); lean = rng.uniform(-18, 18)
    col = tuple(int(c) for c in lerpc((50, 78, 30), (110, 130, 56), rng.random()))
    pts = [(x0 + lean * s * s, 511 - s * (511 - top)) for s in np.linspace(0, 1, 8)]
    d.line(pts, fill=col + (255,), width=3)
    if i % 3 == 0:
        hx, hy = pts[-2]
        d.line([(hx, hy + 6), (hx + lean * .05, hy + 52)], fill=(84, 52, 30, 255), width=9)
cv.save(os.path.join(OUT, "reed.png"))
print("ok")
