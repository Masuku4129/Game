"""Нарезка листа анимаций персонажа (белый фон) и листа эффектов (чёрный фон).
Лист персонажа: сетка ROWS x COLS кадров. Белый фон выбивается по белизне, границы кадров
уточняются по провалам плотности, у каждого кадра сохраняется точка опоры (центр ячейки,
линия стоп ряда), чтобы смещения тела внутри анимации сохранялись.
Запуск из папки wilds: python tools/prep_anim.py <имя> <ROWS> <COLS>"""
import sys, json
import numpy as np
from PIL import Image

name, ROWS, COLS = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
im = Image.open(f"art/source/{name}.png").convert("RGB")
W, H = im.size
arr = np.asarray(im).astype(np.float32)
white = arr.min(axis=2)
alpha = np.clip((238.0 - white) / 38.0, 0.0, 1.0)
dark = np.array([16.0, 16.0, 38.0], dtype=np.float32)
fg = np.clip((arr - (1.0 - alpha[..., None]) * 255.0) / np.maximum(alpha[..., None], 0.05), 0, 255)
t = np.clip((alpha - 0.85) / 0.15, 0.0, 1.0)[..., None]
rgba = np.dstack([dark * (1 - t) + fg * t, alpha * 255]).astype(np.uint8)
sheet = Image.fromarray(rgba, "RGBA")
mask = alpha > 0.1

pitch = W / COLS
meta = {"rows": []}
rowh = H / ROWS
preview = []
for r in range(ROWS):
    y0, y1 = int(r * rowh), int((r + 1) * rowh)
    band = mask[y0:y1]
    prof = np.convolve(band.sum(axis=0).astype(float), np.ones(5) / 5, mode="same")
    cuts = [0]
    for c in range(1, COLS):
        ideal = int(c * pitch)
        lo, hi = max(ideal - int(pitch * 0.3), cuts[-1] + 10), min(ideal + int(pitch * 0.3), W - 10)
        cuts.append(lo + int(np.argmin(prof[lo:hi])))
    cuts.append(W)
    ys, xs = np.where(band)
    base = int(np.percentile([np.where(band[:, cuts[i]:cuts[i + 1]])[0].max()
                              for i in range(COLS) if band[:, cuts[i]:cuts[i + 1]].any()], 60)) + y0
    frames = []
    for c in range(COLS):
        x0, x1 = cuts[c], cuts[c + 1]
        cell = sheet.crop((x0, y0, x1, y1))
        fn = f"art/anim/{name}_r{r}_{c:02d}.png"
        cell.save(fn)
        cx = (c + 0.5) * pitch - x0          # центр ячейки относительно левого края кадра
        frames.append({"file": fn.replace("art/", ""), "px": round(cx, 1), "py": base - y0, "h": y1 - y0})
    meta["rows"].append(frames)
json.dump(meta, open(f"art/anim/{name}.json", "w"), indent=1)
print("ok", name, ROWS, COLS)

# данные для игры: файл-константа (JSON в экспортированном APK читать ненадёжно)
f0 = Image.open("art/" + meta["rows"][0][0]["file"])
bb = f0.getchannel("A").point(lambda v: 255 if v > 25 else 0).getbbox()
stand_h = bb[3] - bb[1]
lines = ["# Автоматически создано tools/prep_anim.py: [файл, опора X, опора Y] по рядам.",
         "extends RefCounted", "", f"const SCALE := {120.0 / stand_h:.4f}   # единиц мира на пиксель кадра", "const ROWS := ["]
for row in meta["rows"]:
    lines.append("\t[" + ", ".join(f'["{f["file"].split("/")[-1]}", {f["px"]}, {f["py"]}]' for f in row) + "],")
lines.append("]")
open("art/anim/anim_data.gd", "w").write("\n".join(lines) + "\n")
print("stand_h", stand_h)
