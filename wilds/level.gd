extends Node2D
## Уровень «Руины»: площадь, зал, коридоры, библиотека, камеры, пропасть с мостами,
## восточный двор, лестницы на верхнюю террасу и выходы наружу.
## Схема собирается из прямоугольников, стены вырастают сами вокруг проходимых клеток.

const G := preload("res://geo.gd")
const Chunk := preload("res://floor_chunk.gd")
const WallRun := preload("res://wall_run.gd")
const Decals := preload("res://decals.gd")
const Deco := preload("res://deco.gd")
const Prop := preload("res://prop.gd")

var kind := PackedInt32Array()
var zone := PackedInt32Array()
var la := PackedFloat32Array()      # подъём в начале ячейки лестницы (доля LIFT)
var lb := PackedFloat32Array()      # подъём в конце
var sdx := PackedInt32Array()       # направление подъёма лестницы
var sdy := PackedInt32Array()
var lift_cell := PackedFloat32Array()
var decals := []
var origin := Vector2.ZERO
var spawn_cell := Vector2(45.0, 33.5)
var world: Node2D
var rng := RandomNumberGenerator.new()


func build(world_node: Node2D) -> void:
	world = world_node
	rng.seed = 20261123
	var n := G.GW * G.GH
	kind.resize(n)
	zone.resize(n)
	la.resize(n)
	lb.resize(n)
	sdx.resize(n)
	sdy.resize(n)
	lift_cell.resize(n)
	_layout()
	_make_walls()
	_compute_lift()
	origin = -Vector2(spawn_cell.x * G.W, spawn_cell.y * G.H)
	position = origin
	_make_decals()
	for cy in range(0, G.GH, Chunk.SPAN):
		for cx in range(0, G.GW, Chunk.SPAN):
			var c = Chunk.new()
			c.lv = self
			c.cx0 = cx
			c.cy0 = cy
			add_child(c)
	var dn = Decals.new()
	dn.lv = self
	add_child(dn)
	_build_wall_runs()
	_build_solids()
	_place_props()


# ------------------------------------------------------------------ данные

func kind_at(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= G.GW or y >= G.GH:
		return G.VOID
	return kind[y * G.GW + x]


func cell_lift(x: int, y: int) -> float:
	if x < 0 or y < 0 or x >= G.GW or y >= G.GH:
		return 0.0
	return lift_cell[y * G.GW + x]


func lift_at(wp: Vector2) -> float:
	var p := wp - origin
	var cx := int(floorf(p.x / G.W))
	var cy := int(floorf(p.y / G.H))
	if cx < 0 or cy < 0 or cx >= G.GW or cy >= G.GH:
		return 0.0
	var i := cy * G.GW + cx
	if kind[i] == G.RAISED:
		return G.LIFT
	if kind[i] == G.STAIRS:
		var lx := p.x / G.W - float(cx)
		var ly := p.y / G.H - float(cy)
		var t := 0.0
		if sdy[i] == -1:
			t = 1.0 - ly
		elif sdy[i] == 1:
			t = ly
		elif sdx[i] == 1:
			t = lx
		else:
			t = 1.0 - lx
		return lerpf(la[i], lb[i], t) * G.LIFT
	return 0.0


func _rect(x0: int, y0: int, x1: int, y1: int, k: int, z: int) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var i := y * G.GW + x
			kind[i] = k
			zone[i] = z


func _stairs(x0: int, y0: int, x1: int, y1: int, dir: Vector2i, z: int) -> void:
	var n := (y1 - y0 + 1) if dir.y != 0 else (x1 - x0 + 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var j := 0
			if dir.y == -1:
				j = y1 - y
			elif dir.y == 1:
				j = y - y0
			elif dir.x == 1:
				j = x - x0
			else:
				j = x1 - x
			var i := y * G.GW + x
			kind[i] = G.STAIRS
			zone[i] = z
			la[i] = float(j) / n
			lb[i] = float(j + 1) / n
			sdx[i] = dir.x
			sdy[i] = dir.y


# ------------------------------------------------------------------ схема

func _layout() -> void:
	# центр: площадь, ковровая дорожка на север в тронный зал
	_rect(34, 26, 55, 40, G.FLOOR, G.Z_PLAZA)
	_rect(43, 16, 46, 25, G.FLOOR, G.Z_CORR)
	_rect(30, 4, 59, 15, G.FLOOR, G.Z_HALL)
	# запад: архив, библиотека, камеры
	_rect(22, 9, 29, 11, G.FLOOR, G.Z_CORR)
	_rect(8, 6, 21, 15, G.FLOOR, G.Z_LIB)
	_rect(14, 16, 16, 25, G.FLOOR, G.Z_CORR)
	_rect(8, 26, 21, 40, G.FLOOR, G.Z_LIB)
	_rect(22, 32, 33, 34, G.FLOOR, G.Z_CORR)
	_rect(14, 41, 16, 47, G.FLOOR, G.Z_CORR)
	_rect(6, 48, 22, 58, G.FLOOR, G.Z_CELL)
	for px in [9, 13, 17]:
		for py in range(55, 59):
			var wi: int = py * G.GW + px
			kind[wi] = G.WALL
			zone[wi] = G.Z_CELL
	_rect(23, 52, 24, 54, G.FLOOR, G.Z_CORR)
	# юг: ворота и пустошь снаружи
	_rect(43, 41, 46, 48, G.FLOOR, G.Z_CORR)
	_rect(25, 49, 75, 62, G.FLOOR, G.Z_OUT)
	# восток: пропасть с двумя мостами, двор, выход наружу
	_rect(56, 32, 62, 34, G.FLOOR, G.Z_CORR)
	_rect(63, 22, 74, 50, G.CHASM, G.Z_CORR)
	_rect(63, 32, 74, 34, G.BRIDGE, G.Z_CORR)
	_rect(63, 42, 69, 42, G.BRIDGE, G.Z_CORR)
	_rect(75, 26, 87, 40, G.FLOOR, G.Z_PLAZA)
	_rect(88, 29, 94, 37, G.FLOOR, G.Z_OUT)
	# верхняя терраса: лестница со двора и лестница из зала
	_stairs(80, 22, 83, 25, Vector2i(0, -1), G.Z_TERR)
	_rect(72, 6, 87, 21, G.RAISED, G.Z_TERR)
	_rect(60, 9, 67, 11, G.FLOOR, G.Z_CORR)
	_stairs(68, 9, 71, 11, Vector2i(1, 0), G.Z_CORR)


func _make_walls() -> void:
	var add := []
	for y in G.GH:
		for x in G.GW:
			if kind[y * G.GW + x] != G.VOID:
				continue
			var best := -1
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var k := kind_at(x + dx, y + dy)
					if G.walkable(k) or k == G.CHASM:
						var zz: int = zone[(y + dy) * G.GW + (x + dx)]
						if best == -1 or zz == G.Z_OUT:
							best = zz
			if best != -1:
				add.append([x, y, best])
	for a in add:
		var i: int = a[1] * G.GW + a[0]
		kind[i] = G.WALL
		zone[i] = a[2]


func _compute_lift() -> void:
	for y in G.GH:
		for x in G.GW:
			var i := y * G.GW + x
			if kind[i] == G.RAISED:
				lift_cell[i] = 1.0
			elif kind[i] == G.STAIRS:
				lift_cell[i] = (la[i] + lb[i]) * 0.5
	for y in G.GH:
		for x in G.GW:
			var i := y * G.GW + x
			if kind[i] != G.WALL:
				continue
			var m := 0.0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var k := kind_at(x + dx, y + dy)
					if k == G.RAISED or k == G.STAIRS:
						m = maxf(m, cell_lift(x + dx, y + dy))
			lift_cell[i] = m


func _make_decals() -> void:
	var W := G.W
	var H := G.H
	# ковёр от трона до центра площади
	decals.append(["rect", Rect2(43.0 * W, 4.0 * H, 4.0 * W, 29.0 * H), Color(0.12, 0.05, 0.20, 0.95)])
	decals.append(["line", Vector2(43.0 * W + 9.0, 4.0 * H), Vector2(43.0 * W + 9.0, 33.0 * H), Color(0.5, 0.4, 0.95, 0.5), 3.0])
	decals.append(["line", Vector2(47.0 * W - 9.0, 4.0 * H), Vector2(47.0 * W - 9.0, 33.0 * H), Color(0.5, 0.4, 0.95, 0.5), 3.0])
	for r in range(5, 33, 2):
		decals.append(["line", Vector2(43.0 * W + 9.0, r * H), Vector2(47.0 * W - 9.0, r * H), Color(0.5, 0.4, 0.95, 0.18), 2.0])
	# знак на площади
	var c := Vector2(45.0 * W, 33.5 * H)
	for rr in [150.0, 215.0, 285.0]:
		decals.append(["ering", c, rr, rr * 0.75, Color(0.45, 0.5, 1.0, 0.33), 3.0])
	for s in 8:
		var a := TAU * float(s) / 8.0
		decals.append(["line", c + Vector2(cos(a) * 150.0, sin(a) * 112.0), c + Vector2(cos(a) * 285.0, sin(a) * 214.0), Color(0.45, 0.5, 1.0, 0.25), 2.0])
	# руническое кольцо на террасе (поднято на LIFT)
	var t := Vector2(80.0 * W, 13.5 * H - G.LIFT)
	for rr in [120.0, 175.0, 235.0]:
		decals.append(["ering", t, rr, rr * 0.75, Color(0.55, 0.5, 1.0, 0.45), 3.0])
	decals.append(["ering", t, 235.0, 176.0, Color(0.55, 0.5, 1.0, 0.12), 14.0])
	# верёвки главного моста
	var xs := []
	for k in range(0, 13, 2):
		xs.append((63.5 + float(k)) * W)
	for k in range(xs.size() - 1):
		decals.append(["rope", Vector2(xs[k], 32.16 * H - 46.0), Vector2(xs[k + 1], 32.16 * H - 46.0)])
		decals.append(["rope", Vector2(xs[k], 34.86 * H - 46.0), Vector2(xs[k + 1], 34.86 * H - 46.0)])


# ------------------------------------------------------------------ геометрия

func _pos(cx: float, cy: float) -> Vector2:
	return Vector2(cx * G.W, cy * G.H) + origin


func _build_wall_runs() -> void:
	for y in G.GH:
		var x := 0
		while x < G.GW:
			var i := y * G.GW + x
			if kind[i] != G.WALL:
				x += 1
				continue
			var z: int = zone[i]
			var lf: float = lift_cell[i]
			var n := 1
			while x + n < G.GW:
				var j := y * G.GW + x + n
				if kind[j] == G.WALL and zone[j] == z and absf(lift_cell[j] - lf) < 0.001:
					n += 1
				else:
					break
			var w = WallRun.new()
			w.lv = self
			w.cell_x = x
			w.cell_y = y
			w.count = n
			w.zone = z
			w.lift = lf * G.LIFT
			w.position = _pos(float(x), float(y + 1))
			world.add_child(w)
			x += n


func _build_solids() -> void:
	# пропасть непроходима: прямоугольники по строкам
	var body := StaticBody2D.new()
	add_child(body)
	for y in G.GH:
		var x := 0
		while x < G.GW:
			if kind[y * G.GW + x] != G.CHASM:
				x += 1
				continue
			var n := 1
			while x + n < G.GW and kind[y * G.GW + x + n] == G.CHASM:
				n += 1
			var cs := CollisionShape2D.new()
			var sh := RectangleShape2D.new()
			sh.size = Vector2(n * G.W, G.H)
			cs.shape = sh
			cs.position = Vector2((float(x) + n * 0.5) * G.W, (float(y) + 0.5) * G.H)
			body.add_child(cs)
			x += n


# ------------------------------------------------------------------ расстановка

func _deco(k: int, cx: float, cy: float, cw := 2.0, lf := 0.0, v := 1.0) -> void:
	var d = Deco.new()
	d.kind = k
	d.cells_w = cw
	d.lift = lf
	d.variant = v
	d.position = _pos(cx, cy)
	world.add_child(d)


func _prop(k: int, cx: float, cy: float, v := 1.0) -> void:
	var p = Prop.new()
	p.kind = k
	p.variant = v
	p.flip = rng.randf() < 0.5
	p.position = _pos(cx, cy)
	world.add_child(p)


func _place_props() -> void:
	# площадь: сломанные колонны, статуи, обломки
	for q in [[36.5, 28.5], [53.5, 28.5], [36.5, 38.5], [53.5, 38.5], [40.0, 27.4], [50.0, 27.4]]:
		_prop(Prop.PILLAR, q[0], q[1], rng.randf_range(0.9, 1.2))
	for q in [[38.0, 35.0], [52.0, 31.0], [41.0, 39.2], [49.5, 29.6], [35.5, 33.0], [54.0, 36.0]]:
		_prop(Prop.ROCK, q[0], q[1], rng.randf_range(0.7, 1.0))
	_deco(Deco.STATUE, 40.5, 30.0, 1.0, 0.0, 1.0)
	_deco(Deco.STATUE, 49.5, 30.0, 1.0, 0.0, 1.3)

	# тронный зал
	for px in [33.5, 37.5, 41.0, 49.0, 52.5, 56.5]:
		for py in [7.5, 13.5]:
			_prop(Prop.PILLAR, px, py, 1.15)
	_deco(Deco.STATUE, 41.5, 5.8, 1.0, 0.0, 1.0)
	_deco(Deco.STATUE, 48.5, 5.8, 1.0, 0.0, 1.0)
	for tx in [33.0, 37.0, 53.0, 57.0]:
		_deco(Deco.TORCH, tx, 4.45)

	# жаровни в коридорах
	for ty in [18.0, 22.5]:
		_deco(Deco.TORCH, 43.35, ty)
		_deco(Deco.TORCH, 46.65, ty)
	for ty in [43.0, 46.5]:
		_deco(Deco.TORCH, 43.35, ty)
		_deco(Deco.TORCH, 46.65, ty)
	for tx in [25.0, 29.5]:
		_deco(Deco.TORCH, tx, 32.35)
		_deco(Deco.TORCH, tx, 34.65)
		_deco(Deco.TORCH, tx + 0.5, 9.4)
		_deco(Deco.TORCH, tx + 0.5, 11.6)
	for tx in [57.5, 61.0]:
		_deco(Deco.TORCH, tx, 32.35)
		_deco(Deco.TORCH, tx, 34.65)

	# архив и библиотека: полки у северной стены
	for sx in [10.0, 12.0, 14.0, 16.0, 18.0, 20.0]:
		_deco(Deco.SHELF, sx, 7.0, 2.0)
	for sx in [10.0, 12.0, 18.0, 20.0]:
		_deco(Deco.SHELF, sx, 27.0, 2.0)
	_deco(Deco.TORCH, 9.4, 14.2)
	_deco(Deco.TORCH, 20.6, 14.2)
	_deco(Deco.TORCH, 9.4, 39.2)
	_deco(Deco.TORCH, 20.6, 39.2)
	_prop(Prop.PILLAR, 12.5, 33.0, 1.0)
	_prop(Prop.PILLAR, 17.5, 33.0, 1.0)

	# камеры: обломки
	for q in [[8.0, 51.0], [20.0, 50.5], [11.5, 57.0], [19.5, 57.5], [7.5, 56.0]]:
		_prop(Prop.ROCK, q[0], q[1], rng.randf_range(0.5, 0.8))
	_deco(Deco.TORCH, 7.4, 49.4)
	_deco(Deco.TORCH, 21.6, 49.4)

	# мост: столбы
	for k in range(0, 13, 2):
		_deco(Deco.POST, 63.5 + float(k), 32.16, 1.0)
		_deco(Deco.POST, 63.5 + float(k), 34.86, 1.0)

	# восточный двор
	for q in [[77.0, 28.0], [86.0, 28.0], [77.0, 39.0], [86.0, 39.0]]:
		_prop(Prop.PILLAR, q[0], q[1], 1.1)
	_deco(Deco.STATUE, 84.0, 31.0, 1.0, 0.0, 1.3)
	for q in [[79.0, 37.0], [83.0, 38.5], [85.0, 34.0]]:
		_prop(Prop.ROCK, q[0], q[1], rng.randf_range(0.6, 0.9))
	_deco(Deco.TORCH, 79.2, 26.4)
	_deco(Deco.TORCH, 84.8, 26.4)

	# верхняя терраса (всё поднято на LIFT)
	for q in [[73.6, 8.6], [86.0, 8.6], [73.6, 20.2], [86.0, 20.2], [79.3, 21.2], [84.7, 21.2]]:
		_deco(Deco.TORCH, q[0], q[1], 1.0, G.LIFT)
	_deco(Deco.STATUE, 80.0, 8.0, 1.0, G.LIFT, 1.0)

	# выход на юг: арка и пустошь
	_deco(Deco.ARCH, 45.0, 48.95, 4.0)
	_scatter(25, 49, 75, 62, 105.0, 320, Rect2i(40, 49, 10, 5))
	_scatter(88, 29, 94, 37, 100.0, 60, Rect2i(88, 31, 1, 5))


func _scatter(x0: int, y0: int, x1: int, y1: int, gap: float, tries: int, free: Rect2i) -> void:
	var placed: Array[Vector2] = []
	for t in tries:
		var cx := rng.randf_range(float(x0) + 1.0, float(x1))
		var cy := rng.randf_range(float(y0) + 1.0, float(y1))
		var ix := int(cx)
		var iy := int(cy)
		if free.has_point(Vector2i(ix, iy)):
			continue
		var clear := true
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if kind_at(ix + dx, iy + dy) != G.FLOOR:
					clear = false
		if not clear:
			continue
		var p := Vector2(cx * G.W, cy * G.H)
		var ok := true
		for q in placed:
			if q.distance_squared_to(p) < gap * gap:
				ok = false
				break
		if not ok:
			continue
		placed.append(p)
		var roll := rng.randf()
		var k := Prop.TREE
		if roll >= 0.5 and roll < 0.7:
			k = Prop.ROCK
		elif roll >= 0.7:
			k = Prop.BUSH
		_prop(k, cx, cy, rng.randf_range(0.85, 1.25))
