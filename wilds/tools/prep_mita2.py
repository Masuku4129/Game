"""Нарезка новых листов Миты (вид сбоку, вправо) -> art/m2. Запуск из wilds/: python3 -I tools/prep_mita2.py"""
import numpy as np, json
from PIL import Image
from scipy import ndimage as ndi

SHEETS = [
    ("walk", [("walk", 7, 1), ("idle", 8, 0)]),     # (имя, кадров, строка-эталон роста: 1 = эта строка задаёт масштаб)
    ("dash", [("dash", 8, 0), ("hurt", 8, 1), ("death", 8, 0)]),
    ("atk", [("a0", 12, 1), ("a1", 11, 0), ("a2", 11, 0)]),
]
REF_FRAME = {"walk": ("idle", 0), "dash": ("hurt", 7), "atk": ("a0", 0)}
data = {}

def fg_mask(a):
    mn = a.min(2)
    lab, n = ndi.label(mn >= 238)
    sizes = ndi.sum(np.ones_like(mn), lab, range(1, n + 1))
    bg = np.isin(lab, [i + 1 for i, s in enumerate(sizes) if s > 40])
    return ~bg

def split_row(fg, n):
    for sz in (41, 31, 21, 15, 11, 7, 5, 3):
        d = ndi.maximum_filter(fg.astype(np.uint8), size=sz) > 0
        l, k = ndi.label(d)
        ar = ndi.sum(fg, l, range(1, k + 1))
        idx = [i + 1 for i, s in enumerate(ar) if s > 2500]
        if len(idx) == n:
            return np.where(fg, l, 0), idx
    for it in range(1, 14):
        core = ndi.binary_erosion(fg, iterations=it)
        lc, nc = ndi.label(core)
        ar = ndi.sum(core, lc, range(1, nc + 1))
        keep = [i + 1 for i, s in enumerate(ar) if s > 1500]
        if len(keep) == n:
            lc = np.where(np.isin(lc, keep), lc, 0)
            _, (iy, ix) = ndi.distance_transform_edt(lc == 0, return_indices=True)
            print("  erosion split", it)
            return np.where(fg, lc[iy, ix], 0), keep
    raise SystemExit("split fail n=%d" % n)

for sname, rows in SHEETS:
    a = np.array(Image.open("tools/src_mita2/%s.png" % sname).convert("RGB")).astype(float)
    H, W = a.shape[:2]
    fg = fg_mask(a)
    fg = ndi.binary_closing(fg, iterations=1) & fg | fg
    proj = fg.sum(1) > 0
    # полосы строк
    bands = []
    y = 0
    while y < H:
        if proj[y]:
            y0 = y
            while y < H and proj[y]: y += 1
            if y - y0 > 60: bands.append((y0, y))
        y += 1
    if len(bands) != len(rows):
        # слить близкие полосы: берём крупные
        bands = sorted(sorted(bands, key=lambda b: b[0] - b[1])[:len(rows)])
    assert len(bands) == len(rows), (sname, bands)
    dist = ndi.distance_transform_edt(fg)
    frames = {}
    for (name, n, _), (y0, y1) in zip(rows, bands):
        y0 = max(0, y0 - 6); y1 = min(H, y1 + 6)
        l, idx = split_row(fg[y0:y1], n)
        cm = {i: ndi.center_of_mass(l == i)[1] for i in idx}
        order = sorted(idx, key=lambda i: cm[i])
        cw = W / n
        lst = []
        for k, i in enumerate(order):
            m = l == i
            ys, xs = np.where(m)
            lst.append((m, xs.min(), xs.max(), ys.min(), ys.max()))
        # опора: ступни кадра 0
        m0, x0_, x1_, ya, yb = lst[0]
        ys, xs = np.where(m0)
        lo = ys > yb - 0.12 * (yb - ya)
        foot0 = xs[lo].mean()
        ground = yb
        off = foot0 - 0.5 * cw
        frames[name] = (y0, order, lst, l, cw, off, ground)
    # масштаб по эталонному кадру листа
    rn, rk = REF_FRAME[sname]
    _, _, lst, _, _, _, _ = frames[rn]
    href = lst[rk][4] - lst[rk][3] + 1
    scale = round(120.0 / href, 4)
    print(sname, "ref", rn, rk, "h", href, "scale", scale)
    for (name, n, _), _b in zip(rows, bands):
        y0, order, lst, l, cw, off, ground = frames[name]
        for k, (m, xa, xb, ya, yb) in enumerate(lst):
            px_abs = (k + 0.5) * cw + off
            py_abs = ground
            X0 = max(0, xa - 5); X1 = min(W, xb + 6); Y0 = max(0, ya - 5); Y1 = min(y1 - y0 if False else l.shape[0], yb + 6)
            c = a[y0 + Y0:y0 + Y1, X0:X1].copy()
            mm = m[Y0:Y1, X0:X1]
            dd = dist[y0 + Y0:y0 + Y1, X0:X1]
            al = np.where(mm, 1.0, 0.0)
            band = mm & (dd <= 2.5)
            al[band] = np.clip((250 - c.min(2)[band]) / 60.0, 0, 1)
            low = band & (al < 0.95)
            for ch, vv in enumerate((16, 16, 38)):
                c[..., ch][low] = c[..., ch][low] * 0.4 + vv * 0.6
            rgba = np.dstack([c, al * 255]).clip(0, 255).astype(np.uint8)
            fn = "%s_%d" % (name, k)
            Image.fromarray(rgba, "RGBA").save("art/m2/%s.png" % fn)
            data[fn] = [float(round(px_abs - X0, 1)), float(round(py_abs - Y0, 1)), scale]
with open("art/m2/m2_data.gd", "w") as f:
    f.write("# сгенерировано tools/prep_mita2.py: имя -> [pivot_x, pivot_y, scale]\nconst DATA := " + json.dumps(data) + "\n")
print("frames", len(data))
