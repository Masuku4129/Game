"""Нарезка артов GPT (белый фон) -> art/valley/*.png, art/en/*.png + data-файлы. Запуск из wilds/: python3 -I tools/prep_art.py"""
import numpy as np, os
from PIL import Image
from scipy import ndimage as ndi

S = "tools/src_new/"
os.makedirs("art/valley", exist_ok=True); os.makedirs("art/en", exist_ok=True)
MIST = np.array([205, 214, 228], float)

def cells(img, cols, rows):
    w, h = img.size
    for r in range(rows):
        for c in range(cols):
            yield img.crop((c * w // cols, r * h // rows, (c + 1) * w // cols, (r + 1) * h // rows))

def solid(cell):
    a = np.asarray(cell.convert("RGB")).astype(float)
    m = a.min(2)
    mask = m < 238
    mask = ndi.binary_dilation(mask, iterations=2)
    lab, n = ndi.label(mask)
    if n == 0: return None
    sizes = ndi.sum(mask, lab, range(1, n + 1))
    keep = np.isin(lab, [i + 1 for i, s in enumerate(sizes) if s > 400])
    # объекты с мелкими отрывами (листья): склеиваем сильным расширением для выбора компонентов
    big = ndi.binary_dilation(keep, iterations=18)
    lab2, n2 = ndi.label(big)
    if n2 > 1:
        s2 = ndi.sum(keep, lab2, range(1, n2 + 1))
        keep &= (lab2 == (int(np.argmax(s2)) + 1))
    filled = ndi.binary_fill_holes(keep)
    hl, hn = ndi.label(filled & ~keep)
    for i in range(1, hn + 1):
        if (hl == i).sum() < 2500:
            keep = keep | (hl == i)
    al = ndi.gaussian_filter(keep.astype(float), 0.8)
    al = np.clip((al - 0.35) / 0.4, 0, 1)
    # цвет у края: берём ближайший внутренний цвет, чтобы не было белой каймы
    inner = ndi.binary_erosion(keep, iterations=3)
    idx = ndi.distance_transform_edt(~inner, return_distances=False, return_indices=True)
    col = a[idx[0], idx[1]]
    col = np.where(inner[..., None], a, col)
    col = col * 0.88 + MIST * 0.12 * 0.0 + (col * 0 )  # без смещения; дымку добавляет движок
    out = np.dstack([np.clip(col, 0, 255), al * 255]).astype(np.uint8)
    return out

def smoky(cell):
    a = np.asarray(cell.convert("RGB")).astype(float)
    m = a.min(2)
    al = np.clip((255 - m) / 150.0, 0, 1)
    al[al < 0.05] = 0
    safe = np.maximum(al, 1e-3)[..., None]
    col = np.clip((a - 255 * (1 - safe)) / safe, 0, 255)
    return np.dstack([col, al * 255]).astype(np.uint8)

def crop_bbox(arr, thr=12):
    ys, xs = np.where(arr[..., 3] > thr)
    return arr[ys.min():ys.max() + 1, xs.min():xs.max() + 1]

def resize(arr, f):
    im = Image.fromarray(arr)
    return im.resize((max(1, int(im.width * f)), max(1, int(im.height * f))), Image.LANCZOS)

def pivot_x(arr):
    h = arr.shape[0]
    band = arr[int(h * 0.88):, :, 3] > 100
    xs = np.where(band.any(0))[0]
    return float(xs.mean()) if len(xs) else arr.shape[1] / 2

data = {}
def put_prop(name, arr, target_h, coll=0.0, width_mode=False):
    arr = crop_bbox(arr)
    ref = arr.shape[1] if width_mode else arr.shape[0]
    im = resize(arr, target_h / ref)
    a = np.asarray(im)
    px = pivot_x(a); py = a.shape[0] - 6
    im.save("art/valley/%s.png" % name)
    data[name] = [round(px), py, round(coll)]

def grid(file, c, r): return list(cells(Image.open(S + file), c, r))

trees = grid("trees.png", 3, 3)
names = ["t_oak1", "t_oak2", "t_oak3", "t_pine1", "t_pine2", "t_pine3", "t_birch1", "t_birch2", "t_dead"]
hts = [430, 450, 420, 480, 460, 440, 450, 440, 400]
for n, c, h in zip(names, trees, hts):
    put_prop(n, solid(c), h, coll=15)

props = grid("props.png", 4, 3)
pn = ["r_1", "r_2", "r_3", "r_4", "b_1", "b_2", "b_3", "f_1", "f_2", "stump", "log", "mush"]
ph = [260, 220, 250, 200, 150, 150, 140, 135, 125, 110, 120, 95]
pc = [70, 80, 55, 65, 0, 0, 0, 0, 0, 24, 0, 0]
for n, c, h, k in zip(pn, props, ph, pc):
    arr = solid(c)
    put_prop(n, arr, 230 if n == "log" else h, coll=k, width_mode=(n == "log"))
    if n == "log": data[n][2] = 0

bl = grid("build.png", 2, 2)
put_prop("hut1", solid(bl[0]), 470, width_mode=True)
put_prop("hut2", solid(bl[1]), 420, width_mode=True)
put_prop("bridge2", solid(bl[2]), 380, width_mode=True)
put_prop("arch", solid(bl[3]), 460, width_mode=True)

def comp_slice(img, rows, n_expect, it):
    full = smoky(img)
    mask = full[..., 3] > 40
    lab, n = ndi.label(ndi.binary_dilation(mask, iterations=it))
    sizes = ndi.sum(mask, lab, range(1, n + 1))
    order = list(np.argsort(-sizes)[:n_expect])
    seeds = np.isin(lab, [i + 1 for i in order])
    dist, idx = ndi.distance_transform_edt(~seeds, return_indices=True)
    near = lab[idx[0], idx[1]]
    near[dist > 110] = 0
    H = img.height
    comps = []
    for i in order:
        ys, xs = np.where(lab == i + 1)
        comps.append((int(ys.mean() // (H / rows)), xs.mean(), i + 1))
    comps.sort()
    out = []
    for _, _, l in comps:
        a = full.copy()
        a[..., 3] = np.where(near == l, a[..., 3], 0)
        out.append(a)
    return out

def put_en(prefix, cs, names, ref_idx, ref_len, by_width=False):
    arrs = [crop_bbox(c) for c in cs]
    r = arrs[ref_idx]
    f = ref_len / (r.shape[1] if by_width else r.shape[0])
    for n, a in zip(names, arrs):
        im = resize(a, f)
        b = np.asarray(im)
        # ноги = нижняя тёмная часть, пивот по нижнему краю непрозрачных пикселей
        solid_rows = np.where((b[..., 3] > 140).any(1))[0]
        py = int(solid_rows.max()) if len(solid_rows) else b.shape[0] - 1
        band = b[max(0, py - 12):py + 1, :, 3] > 140
        xs = np.where(band.any(0))[0]
        px = float(xs.mean()) if len(xs) else b.shape[1] / 2
        im.save("art/en/%s_%s.png" % (prefix, n))
        data["en_%s_%s" % (prefix, n)] = [round(px), py, im.width, im.height]

en = comp_slice(Image.open(S + "enemies.png"), 4, 16, 10)
put_en("ch", en[:8], ["side", "front", "back", "windup", "strike", "hit", "crouch", "death"], 0, 175)
put_en("sh", en[8:], ["side", "front", "back", "charge", "shoot", "hit", "recoil", "death"], 0, 195)
hd = comp_slice(Image.open(S + "hound.png"), 2, 6, 2)
put_en("hd", hd, ["run", "front", "run2", "leap", "paw", "howl"], 0, 560, by_width=True)

with open("art/valley/art_data.gd", "w") as f:
    f.write("extends RefCounted\n# имя -> [pivot_x, pivot_y, collide_r] (для en_*: [pivot_x, pivot_y, w, h])\nconst DATA := {\n")
    for k, v in data.items():
        f.write('\t"%s": %s,\n' % (k, v))
    f.write("}\n")
print("ok", len(data))
