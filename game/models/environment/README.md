# Taiga environment model pack

Оригинальные процедурные 3D-модели с UV и встроенными текстурами (glTF Binary, Y-up, Godot 4).
Генерация: `tools/gen_model_textures.py` (текстуры) → `tools/generate_taiga_models.py` (GLB). CI: `generate-taiga-models.yml`.

| Файл | Объект | Размер | Текстуры |
|---|---|---|---|
| `taiga_spruce.glb` | Ель | 7.8 м | bark_spruce, needle_spruce |
| `taiga_pine.glb` | Сосна | 11 м | bark_pine, needle_pine |
| `taiga_larch.glb` | Лиственница | 10 м | bark_larch, needle_larch |
| `taiga_cedar.glb` | Кедр | 9 м | bark_cedar, needle_cedar |
| `taiga_birch.glb` | Берёза | 6.6 м | bark_birch, bark_alder, leaf_birch |
| `taiga_aspen.glb` | Осина | 9 м | bark_aspen, leaf_aspen |
| `taiga_alder.glb` | Ольха | 6 м | bark_alder, leaf_alder |
| `taiga_bush.glb` | Кустарник | 1.5 м | bark_stump, leaf_bush |
| `taiga_fern.glb` | Папоротник | ~1 м | fern_frond |
| `taiga_grass.glb` | Трава | 0.75 м | grass_tuft |
| `taiga_moss.glb` | Мох | кочки ~1.8 м | moss |
| `taiga_rock.glb` | Камень | 2.7 м | rock, moss |
| `taiga_stump.glb` | Пень | 0.85 м | bark_stump, wood_end, moss |
| `taiga_fallen_log.glb` | Валежник | 3.1 м | bark_spruce, wood_end, moss |

- Геометрия объединена по материалам: 1–3 draw call на модель, 200–6700 треугольников.
- Хвоя, листва, папоротник и трава — карточки с альфа-маской (`alphaMode=MASK`), нормали направлены от центра кроны для объёмного освещения.
- Кора, камень — тайлящиеся текстуры 256×256 (+ normal map для хвойных, ольхи и камня), без растяжения: UV по окружности/длине ствола и проекция по доминирующей оси для камня.
- Исходные PNG лежат в `textures/` (папка помечена `.gdignore`, Godot её не импортирует — текстуры уже внутри GLB).

Проверка: `res://scenes/asset_gallery.tscn` (две строки: деревья и подлесок/камни/пни).
