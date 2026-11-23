"""Нарезка листов персонажа на спрайты.
Вход:  art/source/mita_views.png  (5 видов в ряд: спереди, спереди-3/4, сбоку, сзади-3/4, сзади)
       art/source/mita_walk.png   (верхний ряд: ходьба сбоку x4; нижний: спереди x4 и сзади x4)
Выход: art/*.png (прозрачный фон, общий масштаб, высота ~320 px) и art/sprite_data.gd
Запуск из папки wilds: python tools/prep_sprites.py   (нужны rembg, pillow, numpy, scipy)"""
import numpy as np
from PIL import Image
from scipy import ndimage as ndi
from rembg import new_session, remove

TARGET_H = 320
sess = new_session("isnet-anime")


def cut(path):
    out = remove(Image.open(path).convert("RGB"), session=sess)
    return out, np.asarray(out)[:, :, 3] > 20


def components(a, min_px=3000):
    lab, _ = ndi.label(ndi.binary_dilation(a, iterations=14))
    res = []
    for i, sl in enumerate(ndi.find_objects(lab)):
        if (a[sl] & (lab[sl] == i + 1)).sum() >= min_px:
            res.append((sl[0].start, sl[0].stop, sl[1].start, sl[1].stop))
    return sorted(res, key=lambda c: (c[0] // 450, c[2]))


def split4(a, box):
    """Делит слипшуюся группу из 4 кадров по трём самым пустым вертикальным провалам."""
    y0, y1, x0, x1 = box
    prof = a[y0:y1, x0:x1].sum(axis=0).astype(float)
    prof = np.convolve(prof, np.ones(9) / 9, mode="same")
    w = x1 - x0
    cuts = []
    for k in (1, 2, 3):
        c = w * k // 4
        lo, hi = max(c - w // 10, 1), min(c + w // 10, w - 1)
        cuts.append(x0 + lo + int(np.argmin(prof[lo:hi])))
    xs = [x0] + cuts + [x1]
    return [(y0, y1, xs[i], xs[i + 1]) for i in range(4)]


def defringe(im):
    """Убирает белую кайму на тонких прядях: выбиваем почти белое и вычитаем подмешанный белый фон."""
    arr = np.asarray(im.convert("RGBA")).astype(np.float32)
    white = arr[:, :, :3].min(axis=2)
    arr[:, :, 3] *= np.clip((238.0 - white) / 38.0, 0.0, 1.0)
    al = arr[:, :, 3:4] / 255.0
    fg = (arr[:, :, :3] - (1.0 - al) * 255.0) / np.maximum(al, 0.05)
    fg = np.clip(fg, 0, 255)
    fg = np.where(al < 0.999, fg, arr[:, :, :3])
    # полупрозрачные пряди красим в тёмный: светлые остатки белого фона не нужны
    dark = np.array([16.0, 16.0, 38.0], dtype=np.float32)
    t = np.clip((al - 0.85) / 0.15, 0.0, 1.0)
    arr[:, :, :3] = dark * (1.0 - t) + fg * t
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def resize(im, size):
    return im.convert("RGBa").resize(size, Image.LANCZOS).convert("RGBA")


def crop(img, a, box):
    y0, y1, x0, x1 = box
    sub = a[y0:y1, x0:x1]
    ys, xs = np.where(sub)
    return defringe(img.crop((x0 + xs.min(), y0 + ys.min(), x0 + xs.max() + 1, y0 + ys.max() + 1)))


views_img, va = cut("art/source/mita_views.png")
walk_img, wa = cut("art/source/mita_walk.png")

named = {}
vboxes = components(va)
assert len(vboxes) == 5, vboxes
for n, b in zip(["idle_s", "idle_se", "idle_e", "idle_ne", "idle_n"], vboxes):
    named[n] = crop(views_img, va, b)
k_views = TARGET_H / named["idle_s"].height

wboxes = components(wa)
assert len(wboxes) == 6, wboxes
rows = {"walk_e": wboxes[:4], "walk_s": split4(wa, wboxes[4]), "walk_n": split4(wa, wboxes[5])}
static_for = {"walk_e": "idle_e", "walk_s": "idle_s", "walk_n": "idle_n"}
walk = {}
for name, boxes in rows.items():
    frames = [crop(walk_img, wa, b) for b in boxes]
    med = float(np.median([f.height for f in frames]))
    want = named[static_for[name]].height * k_views
    kw = want / med
    for i, f in enumerate(frames):
        walk[f"{name}_{i}"] = (f, kw)

final = {}
for n, im in named.items():
    final[n] = resize(im, (round(im.width * k_views), round(im.height * k_views)))
for n, (im, kw) in walk.items():
    final[n] = resize(im, (round(im.width * kw), round(im.height * kw)))

lines = ["# Автоматически создано tools/prep_sprites.py. Имя: [центр стоп X, высота] в пикселях.",
         "extends RefCounted", "", "const DATA := {"]
for n, im in final.items():
    a = np.asarray(im)[:, :, 3] > 20
    h = im.height
    band = a[int(h * 0.88):, :]
    fx = float(np.where(band)[1].mean())
    im.save(f"art/{n}.png")
    lines.append(f'\t"{n}": [{fx:.1f}, {h}],')
lines.append("}")
open("art/sprite_data.gd", "w").write("\n".join(lines) + "\n")
print(len(final), "спрайтов")
