#!/usr/bin/env python3
"""Procedural, tileable textures for Taiga environment GLB models.

Writes PNGs to game/models/environment/textures/. Everything is generated from
noise (no third-party images). Bark/rock/moss/wood textures tile in both axes;
leaf/needle/fern/grass textures are RGBA cards (alpha = silhouette).
"""
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "game" / "models" / "environment" / "textures"
OUT.mkdir(parents=True, exist_ok=True)
RNG = np.random.default_rng(20261127)


def _fbm(size_x, size_y, base=4, octaves=5, seed=0, stretch=(1, 1), persistence=.5):
    """Tileable fractal value noise in [0,1]. stretch=(sx, sy) scales frequency per axis."""
    rng = np.random.default_rng(seed)
    out = np.zeros((size_y, size_x), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        fx = max(1, int(round(base * stretch[0] * 2 ** o)))
        fy = max(1, int(round(base * stretch[1] * 2 ** o)))
        grid = rng.random((fy, fx)).astype(np.float32)
        # bicubic-ish smooth upsample with wrap -> tileable
        ys = (np.arange(size_y) / size_y) * fy
        xs = (np.arange(size_x) / size_x) * fx
        y0 = np.floor(ys).astype(int); x0 = np.floor(xs).astype(int)
        ty = ys - y0; tx = xs - x0
        ty = ty * ty * (3 - 2 * ty); tx = tx * tx * (3 - 2 * tx)
        y0m, y1m = y0 % fy, (y0 + 1) % fy
        x0m, x1m = x0 % fx, (x0 + 1) % fx
        a = grid[np.ix_(y0m, x0m)]; b = grid[np.ix_(y0m, x1m)]
        c = grid[np.ix_(y1m, x0m)]; d = grid[np.ix_(y1m, x1m)]
        top = a * (1 - tx)[None, :] + b * tx[None, :]
        bot = c * (1 - tx)[None, :] + d * tx[None, :]
        out += amp * (top * (1 - ty)[:, None] + bot * ty[:, None])
        tot += amp; amp *= persistence
    return out / tot


def _norm(a):
    a = a - a.min()
    return a / max(a.max(), 1e-6)


def _ramp(t, stops):
    """Map t in [0,1] through color stops [(pos, (r,g,b)), ...] -> HxWx3 float 0..255."""
    t = np.clip(t, 0, 1)
    pos = np.array([s[0] for s in stops]); cols = np.array([s[1] for s in stops], np.float32)
    out = np.zeros(t.shape + (3,), np.float32)
    for k in range(3):
        out[..., k] = np.interp(t, pos, cols[:, k])
    return out


def _save(name, rgb, alpha=None):
    rgb = np.clip(rgb, 0, 255).astype(np.uint8)
    if alpha is None:
        img = Image.fromarray(rgb, "RGB")
    else:
        img = Image.fromarray(np.dstack([rgb, np.clip(alpha, 0, 255).astype(np.uint8)]), "RGBA")
    img.save(OUT / name, optimize=True)
    print("texture", name, img.size, img.mode)


# ---------------------------------------------------------------- bark ---
def bark(name, size, dark, mid, light, ridge_freq, ridge_depth, crack, seed, plate=0.0, horiz=0.0):
    """Vertical furrowed bark. u = around trunk (x), v = along trunk (y)."""
    h = w = size
    broad = _fbm(w, h, 3, 4, seed, stretch=(ridge_freq / 3, 1.0))
    fine = _fbm(w, h, 8, 4, seed + 1, stretch=(ridge_freq / 4, 0.5))
    x = np.arange(w)[None, :] / w
    warp = (_fbm(w, h, 3, 3, seed + 2) - .5) * .12
    ridges = np.abs(np.sin((x + warp) * np.pi * ridge_freq)) ** 0.8
    height = ridges * ridge_depth + broad * (1 - ridge_depth) + fine * .15
    if plate > 0:  # scaly plates (pine/larch)
        cell = _fbm(w, h, 5, 2, seed + 3, stretch=(1.0, 2.2))
        height = height * (1 - plate) + np.abs(cell - .5) * 2 * plate
    if horiz > 0:  # birch lenticels / aspen scars
        scar = _fbm(w, h, 2, 3, seed + 4, stretch=(1.0, 9.0))
        height = height - np.clip((scar - .62) * 5, 0, 1) * horiz
    height = _norm(height)
    crackmask = np.clip((.30 - height) * crack, 0, 1)
    col = _ramp(height, [(0, dark), (.45, mid), (1, light)])
    col *= (1 - crackmask[..., None] * .55)
    # tiny grain
    col *= (.94 + .12 * _fbm(w, h, 64, 1, seed + 5))[..., None]
    return col, height


def bark_normal_from_height(name, height, strength=3.0):
    gy, gx = np.gradient(height)
    # wrap-around gradient for tiling
    gx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) * .5
    gy = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) * .5
    n = np.dstack([-gx * strength * 8, -gy * strength * 8, np.ones_like(height)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    _save(name, (n * .5 + .5) * 255)


def make_barks():
    S = 256
    specs = {
        "bark_spruce": dict(dark=(48, 34, 26), mid=(96, 66, 46), light=(138, 98, 68), ridge_freq=14, ridge_depth=.55, crack=2.2, seed=10, plate=.35),
        "bark_pine": dict(dark=(60, 38, 26), mid=(142, 82, 48), light=(190, 118, 70), ridge_freq=9, ridge_depth=.5, crack=2.6, seed=20, plate=.55),
        "bark_larch": dict(dark=(52, 32, 26), mid=(112, 66, 46), light=(160, 96, 64), ridge_freq=11, ridge_depth=.65, crack=3.0, seed=30, plate=.25),
        "bark_cedar": dict(dark=(58, 40, 32), mid=(108, 78, 58), light=(150, 112, 84), ridge_freq=18, ridge_depth=.7, crack=1.6, seed=40, plate=.1),
        "bark_aspen": dict(dark=(98, 104, 82), mid=(170, 176, 150), light=(205, 208, 184), ridge_freq=4, ridge_depth=.25, crack=1.0, seed=50, horiz=.45),
        "bark_alder": dict(dark=(44, 40, 36), mid=(96, 86, 74), light=(142, 130, 112), ridge_freq=8, ridge_depth=.4, crack=1.5, seed=60, plate=.4),
        "bark_stump": dict(dark=(40, 30, 24), mid=(92, 66, 48), light=(128, 98, 72), ridge_freq=10, ridge_depth=.6, crack=3.2, seed=70, plate=.2),
    }
    for n, s in specs.items():
        col, h = bark(n, S, **s)
        _save(n + ".png", col)
        if n in ("bark_spruce", "bark_pine", "bark_larch", "bark_cedar", "bark_alder"):
            bark_normal_from_height(n + "_n.png", h, 3.0)
    # birch: white paper bark with black lenticels
    h = w = S
    fine = _fbm(w, h, 6, 4, 80, stretch=(.6, 3))
    base = _ramp(fine, [(0, (196, 192, 176)), (.5, (232, 230, 218)), (1, (246, 245, 238))])
    len_noise = _fbm(w, h, 3, 3, 81, stretch=(1.0, 8.0))
    len_x = _fbm(w, h, 6, 2, 82, stretch=(3.0, 1.0))
    dark = np.clip((len_noise - .60) * 6, 0, 1) * np.clip((len_x - .35) * 5, 0, 1)
    base = base * (1 - dark[..., None] * .92) + np.array([22, 20, 18]) * dark[..., None] * .92
    peel = np.clip((_fbm(w, h, 2, 3, 83, stretch=(1.0, 14.0)) - .66) * 5, 0, 1)
    base = base * (1 - peel[..., None] * .2) + np.array([150, 120, 90]) * peel[..., None] * .2
    _save("bark_birch.png", base)


# ------------------------------------------------------------- end grain ---
def make_wood_end():
    S = 256
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    cx, cy = S / 2 + 6, S / 2 - 4
    r = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / (S / 2)
    r = r + (_fbm(S, S, 3, 3, 90) - .5) * .10
    rings = (np.sin(r * 38 + (_fbm(S, S, 2, 2, 91) - .5) * 3) * .5 + .5)
    col = _ramp(rings * .8 + .1, [(0, (150, 108, 66)), (.5, (196, 152, 98)), (1, (222, 184, 128))])
    rays = np.clip(np.sin(np.arctan2(yy - cy, xx - cx) * 28) * .5 + .5, 0, 1) * .06
    col *= (1 - rays[..., None])
    edge = np.clip((r - .86) * 9, 0, 1)
    col = col * (1 - edge[..., None] * .55) + np.array([70, 48, 30]) * edge[..., None] * .55
    crack = np.clip((_fbm(S, S, 4, 3, 92, stretch=(.3, 3)) - .72) * 8, 0, 1) * np.clip(1.2 - r, 0, 1)
    col *= (1 - crack[..., None] * .5)
    _save("wood_end.png", col)


# --------------------------------------------------------------- foliage ---
def _paint_ellipse(alpha, cx, cy, rx, ry, rot):
    h, w = alpha.shape
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    c, s = np.cos(rot), np.sin(rot)
    dx, dy = xx - cx, yy - cy
    u = (dx * c + dy * s) / rx
    v = (-dx * s + dy * c) / ry
    m = (u * u + v * v) <= 1.0
    alpha[m] = 1.0
    return m


def _leaf_card(name, size, n_leaves, leaf_len, leaf_w, base_cols, seed, shape="ellipse", vein=True):
    rng = np.random.default_rng(seed)
    S = size
    alpha = np.zeros((S, S), np.float32)
    col = np.zeros((S, S, 3), np.float32)
    # twig
    twig = np.zeros_like(alpha)
    for i in range(S):
        x = S * .5 + np.sin(i / S * 3.1) * S * .06
        twig[i, int(x) - 1:int(x) + 2] = 1
    order = []
    for k in range(n_leaves):
        cx = rng.uniform(.12, .88) * S
        cy = rng.uniform(.08, .92) * S
        rot = rng.uniform(0, np.pi * 2)
        order.append((cx, cy, rot, rng.uniform(.75, 1.15)))
    for cx, cy, rot, sc in order:
        m = np.zeros_like(alpha)
        _paint_ellipse(m, cx, cy, leaf_len * sc * S, leaf_w * sc * S, rot)
        if shape == "round":
            _paint_ellipse(m, cx, cy, leaf_len * sc * S * .9, leaf_w * 1.25 * sc * S, rot)
        t = rng.uniform(0, 1)
        c = np.array(base_cols[0]) * (1 - t) + np.array(base_cols[1]) * t
        # vein: lighter midline
        yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
        v = (-(xx - cx) * np.sin(rot) + (yy - cy) * np.cos(rot))
        shade = np.ones_like(alpha) * 1.0
        if vein:
            shade -= np.exp(-(v / (S * .006)) ** 2) * -.25
        col[m > 0] = (c[None, :] * shade[m > 0][:, None])
        alpha = np.maximum(alpha, m)
    tw = (twig > 0) & (alpha == 0)
    col[tw] = (88, 62, 40)
    alpha = np.maximum(alpha, twig)
    # edge darkening / inner AO (distance-based cheap blur)
    from scipy.ndimage import gaussian_filter, binary_erosion
    blur = gaussian_filter(alpha, S * .012)
    col *= (.72 + .38 * blur)[..., None]
    col *= (.92 + .16 * _fbm(S, S, 14, 3, seed + 3))[..., None]
    # bleed colour outside the alpha to avoid dark halos under mipmaps
    from scipy.ndimage import distance_transform_edt
    inside = alpha > 0
    idx = distance_transform_edt(~inside, return_distances=False, return_indices=True)
    col = col[idx[0], idx[1]]
    _save(name, col, alpha * 255)


def make_foliage():
    # needle sprays: dense short needles around a twig (spruce / fir)
    for name, cols, seed, n, ln in (
        ("needle_spruce.png", ((22, 58, 36), (52, 100, 56)), 100, 420, .055),
        ("needle_pine.png", ((38, 78, 44), (96, 132, 62)), 110, 260, .11),
        ("needle_larch.png", ((98, 140, 58), (150, 178, 80)), 120, 520, .07),
        ("needle_cedar.png", ((34, 74, 62), (74, 120, 92)), 130, 300, .13),
    ):
        _needle_card(name, 256, n, ln, cols, seed)
    _leaf_card("leaf_birch.png", 256, 26, .085, .055, ((70, 118, 44), (120, 160, 60)), 200, "ellipse")
    _leaf_card("leaf_aspen.png", 256, 20, .10, .095, ((72, 126, 58), (130, 168, 74)), 210, "round")
    _leaf_card("leaf_alder.png", 256, 20, .105, .075, ((38, 84, 38), (78, 120, 50)), 220, "ellipse")
    _leaf_card("leaf_bush.png", 256, 36, .07, .045, ((44, 96, 46), (96, 140, 58)), 230, "ellipse")
    make_fern()
    make_grass()


def _needle_card(name, S, n, ln, cols, seed):
    rng = np.random.default_rng(seed)
    from PIL import ImageDraw
    img = Image.new("RGBA", (S * 2, S * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # central twig
    d.line([(S, S * 2 - 4), (S, 6)], fill=(84, 60, 40, 255), width=int(S * .02))
    for k in range(n):
        y = rng.uniform(.04, .96)
        side = rng.choice([-1, 1])
        base_ang = np.deg2rad(rng.uniform(30, 80)) * side
        L = ln * S * 2 * rng.uniform(.8, 1.4) * (1.0 - abs(y - .5) * .5)
        x0 = S + rng.uniform(-3, 3)
        y0 = y * S * 2
        x1 = x0 + np.sin(base_ang) * L
        y1 = y0 - np.cos(base_ang) * L
        t = rng.uniform(0, 1)
        c = tuple(int(cols[0][i] * (1 - t) + cols[1][i] * t) for i in range(3)) + (255,)
        d.line([(x0, y0), (x1, y1)], fill=c, width=max(2, int(S * .014)))
    img = img.resize((S, S), Image.LANCZOS)
    a = np.asarray(img).astype(np.float32)
    rgb, alpha = a[..., :3], a[..., 3]
    rgb *= (.9 + .2 * _fbm(S, S, 12, 3, seed + 1))[..., None]
    from scipy.ndimage import distance_transform_edt
    idx = distance_transform_edt(alpha < 8, return_distances=False, return_indices=True)
    rgb = rgb[idx[0], idx[1]]
    _save(name, rgb, np.where(alpha > 40, 255, 0))


def make_fern():
    from PIL import ImageDraw
    S = 512
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx = S // 2
    d.line([(cx, S - 4), (cx, 20)], fill=(70, 110, 44, 255), width=5)
    n = 30
    for i in range(n):
        t = i / (n - 1)
        y = S - 30 - t * (S - 60)
        ln = (S * .44) * np.sin(np.pi * (.08 + .92 * (1 - t) ** .8)) * .95 + 14
        for side in (-1, 1):
            ang = np.deg2rad(62 - 14 * t)
            x1 = cx + side * ln * np.sin(ang)
            y1 = y - ln * np.cos(ang) * .55
            g = int(78 + 44 * (1 - t))
            d.line([(cx, y), (x1, y1)], fill=(40, g, 30, 255), width=max(3, int(8 - 5 * t)))
            # pinnules
            m = 7
            for k in range(1, m):
                u = k / m
                px = cx + (x1 - cx) * u; py = y + (y1 - y) * u
                pl = (1 - u) * 20 + 6
                d.line([(px, py), (px + side * 2, py - pl)], fill=(52, min(160, g + 16), 34, 255), width=4)
                d.line([(px, py), (px - side * 1, py + pl * .35)], fill=(38, g - 10, 28, 255), width=3)
    a = np.asarray(img).astype(np.float32)
    rgb, alpha = a[..., :3], a[..., 3]
    from scipy.ndimage import distance_transform_edt
    idx = distance_transform_edt(alpha < 8, return_distances=False, return_indices=True)
    rgb = rgb[idx[0], idx[1]] * (.92 + .16 * _fbm(S, S, 10, 3, 301))[..., None]
    _save("fern_frond.png", rgb, np.where(alpha > 40, 255, 0))


def make_grass():
    from PIL import ImageDraw
    rng = np.random.default_rng(401)
    S = 256
    img = Image.new("RGBA", (S * 2, S * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for k in range(34):
        x = rng.uniform(.1, .9) * S * 2
        h = rng.uniform(.45, .98) * S * 2
        lean = rng.uniform(-.28, .28) * h
        w0 = rng.uniform(8, 16)
        t = rng.uniform(0, 1)
        c = (int(70 + 40 * t), int(110 + 50 * t), int(40 + 14 * t), 255)
        pts = [(x - w0, S * 2), (x + lean * .5, S * 2 - h * .55), (x + lean, S * 2 - h), (x + lean * .5 + 2, S * 2 - h * .55), (x + w0, S * 2)]
        d.polygon(pts, fill=c)
    img = img.resize((S, S), Image.LANCZOS)
    a = np.asarray(img).astype(np.float32)
    rgb, alpha = a[..., :3], a[..., 3]
    from scipy.ndimage import distance_transform_edt
    idx = distance_transform_edt(alpha < 8, return_distances=False, return_indices=True)
    rgb = rgb[idx[0], idx[1]]
    yy = np.linspace(1, .72, S)[:, None, None]
    rgb *= yy * 0 + np.linspace(1.12, .72, S)[:, None, None]
    _save("grass_tuft.png", rgb, np.where(alpha > 40, 255, 0))


# ------------------------------------------------------------ ground/rock ---
def make_rock_moss():
    S = 256
    base = _fbm(S, S, 4, 5, 500)
    cracks = np.abs(_fbm(S, S, 6, 4, 501) - .5)
    layer = _fbm(S, S, 3, 4, 502, stretch=(1.0, 4.0))
    h = _norm(base * .6 + layer * .4)
    rock = _ramp(h, [(0, (62, 62, 58)), (.5, (112, 110, 102)), (1, (160, 156, 146))])
    rock *= (1 - np.clip(.04 - cracks, 0, 1)[..., None] * 14 * .5)
    lichen = np.clip((_fbm(S, S, 9, 3, 503) - .62) * 6, 0, 1)
    rock = rock * (1 - lichen[..., None] * .35) + np.array([138, 150, 96]) * lichen[..., None] * .35
    _save("rock.png", rock)
    bark_normal_from_height("rock_n.png", h, 2.0)
    m = _fbm(S, S, 6, 5, 510)
    m2 = _fbm(S, S, 24, 3, 511)
    moss = _ramp(m * .7 + m2 * .3, [(0, (36, 72, 30)), (.5, (72, 118, 44)), (1, (122, 160, 66))])
    _save("moss.png", moss)


def main():
    make_barks()
    make_wood_end()
    make_foliage()
    make_rock_moss()
    print("done ->", OUT)


if __name__ == "__main__":
    main()
