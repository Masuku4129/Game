extends Node3D
## --- colony: разрешённая область (как «зона» в RimWorld). ---
## Палец красит по земле — где людям можно ходить и работать. Пока ничего не
## закрашено, область не задана и ходить можно везде. Каждому человеку можно
## поставить «вся карта» или «область» (unit.area_lock).
##
## Хранится клетками 2 м (как в nav.gd): байт на клетку, 1 — можно.
## Поверх рельефа рисуем мягкий покров — только пока область правят (на телефоне
## незачем держать лишние треугольники) и только рядом со взглядом.
##
## Публичное:
##   setup(col)                     — создать
##   active() -> bool               — область задана (есть закрашенное)
##   allowed(x, z) -> bool          — можно ли тут быть
##   paint(p, r, on) -> bool        — красить/стирать кистью радиуса r
##   clear()                        — снять область
##   show_overlay(on)               — показать покров
##   to_save() / from_save(d)

const CELL := 2.0
const DRAW_R := 80.0            # покров рисуем только рядом со взглядом

var main: Node3D
var colony
var dim := 0                    # клеток по стороне
var half := 0.0
var mask := PackedByteArray()
var painted := 0                # закрашенных клеток
var overlay: MeshInstance3D
var _mat := StandardMaterial3D.new()
var _dirty := false
var _built_at := Vector3(1e9, 0, 1e9)

func setup(col) -> void:
	colony = col
	main = col.main
	half = float(main.SIZE) * 0.5
	dim = int(float(main.SIZE) / CELL)
	mask.resize(dim * dim)
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.vertex_color_use_as_albedo = true
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.albedo_color = Color(1, 1, 1, 1)
	overlay = MeshInstance3D.new()
	overlay.material_override = _mat
	overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	overlay.visible = false
	add_child(overlay)

func active() -> bool:
	return painted > 0

func _idx(x: float, z: float) -> int:
	var ix := int(floor((x + half) / CELL))
	var iz := int(floor((z + half) / CELL))
	if ix < 0 or iz < 0 or ix >= dim or iz >= dim:
		return -1
	return iz * dim + ix

func allowed(x: float, z: float) -> bool:
	if painted <= 0:
		return true
	var i := _idx(x, z)
	if i < 0:
		return false
	return mask[i] == 1

## Кисть: закрасить (on) или стереть круг радиуса r. true — что-то изменилось.
func paint(p: Vector3, r: float, on: bool) -> bool:
	var n := int(r / CELL) + 1
	var ci := int(floor((p.x + half) / CELL))
	var cj := int(floor((p.z + half) / CELL))
	var changed := false
	var want := 1 if on else 0
	for jz in range(cj - n, cj + n + 1):
		for jx in range(ci - n, ci + n + 1):
			if jx < 0 or jz < 0 or jx >= dim or jz >= dim:
				continue
			var cx := -half + (float(jx) + 0.5) * CELL
			var cz := -half + (float(jz) + 0.5) * CELL
			if Vector2(cx - p.x, cz - p.z).length() > r:
				continue
			var i := jz * dim + jx
			if int(mask[i]) == want:
				continue
			mask[i] = want
			painted += 1 if on else -1
			changed = true
	painted = maxi(0, painted)
	if changed:
		_dirty = true
	return changed

func clear() -> void:
	for i in mask.size():
		mask[i] = 0
	painted = 0
	_dirty = true

func show_overlay(on: bool) -> void:
	overlay.visible = on
	if on:
		_built_at = Vector3(1e9, 0, 1e9)
		_dirty = true

func _process(_dt: float) -> void:
	if not overlay.visible:
		return
	var c: Vector3 = colony.rig.position if colony.rig != null else Vector3.ZERO
	if _dirty or Vector2(c.x - _built_at.x, c.z - _built_at.z).length() > 24.0:
		_dirty = false
		_built_at = c
		_rebuild(c)

## Покров: по квадрату на клетку, вершины сидят на рельефе (без провалов).
func _rebuild(c: Vector3) -> void:
	if painted <= 0:
		overlay.mesh = null
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col := Color(0.42, 0.78, 0.95, 0.2)
	var edge := Color(0.6, 0.92, 1.0, 0.5)
	var n := int(DRAW_R / CELL)
	var ci := int(floor((c.x + half) / CELL))
	var cj := int(floor((c.z + half) / CELL))
	var cnt := 0
	for jz in range(cj - n, cj + n + 1):
		for jx in range(ci - n, ci + n + 1):
			if jx < 0 or jz < 0 or jx >= dim or jz >= dim:
				continue
			if mask[jz * dim + jx] != 1:
				continue
			# край области подсвечиваем ярче — видно границу
			var brim := false
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var ax := jx + d.x
				var az := jz + d.y
				if ax < 0 or az < 0 or ax >= dim or az >= dim or mask[az * dim + ax] != 1:
					brim = true
			var x0 := -half + float(jx) * CELL
			var z0 := -half + float(jz) * CELL
			st.set_color(edge if brim else col)
			_quad(st, x0, z0)
			cnt += 1
			if cnt > 9000:
				break
	overlay.mesh = st.commit()

func _quad(st: SurfaceTool, x0: float, z0: float) -> void:
	var x1 := x0 + CELL
	var z1 := z0 + CELL
	var a := Vector3(x0, _y(x0, z0), z0)
	var b := Vector3(x1, _y(x1, z0), z0)
	var c := Vector3(x1, _y(x1, z1), z1)
	var d := Vector3(x0, _y(x0, z1), z1)
	st.set_normal(Vector3.UP)
	for v: Vector3 in [a, b, c, a, c, d]:
		st.add_vertex(v)

func _y(x: float, z: float) -> float:
	return maxf(main.grid_height(x, z), main.water_level(x, z) - 0.2) + 0.07

# ---------- сохранение ----------

func to_save() -> Dictionary:
	if painted <= 0:
		return {}
	return {"dim": dim, "mask": Marshalls.raw_to_base64(mask)}

func from_save(d: Dictionary) -> void:
	clear()
	if not d.has("mask") or int(d.get("dim", 0)) != dim:
		return
	var raw := Marshalls.base64_to_raw(String(d["mask"]))
	if raw.size() != mask.size():
		return
	mask = raw
	var n := 0
	for i in mask.size():
		if mask[i] == 1:
			n += 1
	painted = n
	_dirty = true
