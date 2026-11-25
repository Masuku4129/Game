extends RefCounted
## --- colony: ходьба по карте. Сетка проходимости 2 м и A* по ней. ---
## Сетка строится кусками 32×32 клетки (64 м) по мере надобности: считать всю карту
## (256×256 клеток) на старте слишком дорого для телефона.
## В клетке лежит цена шага: 0 — непроходимо (ствол, камень, постройка, глубокая вода,
## круча), 1 — ровно, больше — снег, мелкая вода, склон.
## Публичное:
##   passable(x, z) -> bool            — можно ли стоять
##   cost_at(x, z) -> int              — цена клетки (0 — нельзя)
##   find_path(from, to, lock) -> Array — точки пути (мир); lock — не выходить из области
##   nearest_free(p, r) -> Vector3     — ближайшая свободная точка (встать рядом)
##   invalidate(x, z, r)               — пересчитать куски (поставили/убрали постройку)

const CELL := 2.0
const CH := 32                  # клеток в куске
const MAX_STEPS := 4500         # предел расширений A* за один вызов

var main: Node3D
var chunks := {}                # Vector2i (кусок) → PackedByteArray
var area                        # zones.gd — разрешённая область (или null)

func setup(m: Node3D) -> void:
	main = m

func cell_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / CELL), floori(z / CELL))

func world_of(c: Vector2i) -> Vector3:
	var x := (float(c.x) + 0.5) * CELL
	var z := (float(c.y) + 0.5) * CELL
	return Vector3(x, main.ground_fast(x, z), z)

## Цена клетки: 0 — непроходимо.
func cost_cell(c: Vector2i) -> int:
	var ck := Vector2i(floori(float(c.x) / float(CH)), floori(float(c.y) / float(CH)))
	var arr: PackedByteArray = chunks.get(ck, PackedByteArray())
	if arr.is_empty():
		arr = _build_chunk(ck)
	var ix := c.x - ck.x * CH
	var iz := c.y - ck.y * CH
	return arr[iz * CH + ix]

func cost_at(x: float, z: float) -> int:
	return cost_cell(cell_of(x, z))

func passable(x: float, z: float) -> bool:
	return cost_at(x, z) > 0

## Посчитать кусок: цена каждой клетки по рельефу, воде и препятствиям.
func _build_chunk(ck: Vector2i) -> PackedByteArray:
	var arr := PackedByteArray()
	arr.resize(CH * CH)
	var half: float = main.SIZE * 0.5 - 6.0
	for iz in CH:
		for ix in CH:
			var cx := ck.x * CH + ix
			var cz := ck.y * CH + iz
			var x := (float(cx) + 0.5) * CELL
			var z := (float(cz) + 0.5) * CELL
			arr[iz * CH + ix] = _cost_point(x, z, half)
	chunks[ck] = arr
	return arr

func _cost_point(x: float, z: float, half: float) -> int:
	if absf(x) > half or absf(z) > half:
		return 0
	var g: float = main.grid_height(x, z)
	var wl: float = main.water_level(x, z)
	var depth := wl - g
	if depth > 0.75:
		return 0                        # глубоко — не ходим (зимой лёд всё равно скользкий)
	# крутизна по сетке рельефа
	var h1: float = main.grid_height(x + CELL, z)
	var h2: float = main.grid_height(x - CELL, z)
	var h3: float = main.grid_height(x, z + CELL)
	var h4: float = main.grid_height(x, z - CELL)
	var dh := maxf(maxf(absf(h1 - g), absf(h2 - g)), maxf(absf(h3 - g), absf(h4 - g)))
	if dh > 1.5:
		return 0
	if main.blocked(x, z, 0.45):
		return 0
	# тонкие преграды (лежачий ствол) между центрами клеток: щупаем ещё по краям клетки
	var nb := 0
	for o: Vector2 in [Vector2(0.8, 0), Vector2(-0.8, 0), Vector2(0, 0.8), Vector2(0, -0.8)]:
		if main.blocked(x + o.x, z + o.y, 0.3):
			nb += 1
	if nb >= 2:
		return 0
	var c := 1 + int(dh * 3.0)
	if depth > 0.05:
		c += 6
	var sn: float = main.weather.snow if main.weather != null else 0.0
	if sn > 0.4:
		c += 2
	return mini(c, 60)

## Запомнить клетку непроходимой (юнит упёрся в то, чего сетка не видит).
func mark_blocked(x: float, z: float) -> void:
	var c := cell_of(x, z)
	cost_cell(c)
	var ck := Vector2i(floori(float(c.x) / float(CH)), floori(float(c.y) / float(CH)))
	var arr: PackedByteArray = chunks[ck]
	arr[(c.y - ck.y * CH) * CH + (c.x - ck.x * CH)] = 0
	chunks[ck] = arr

## Пересчитать куски вокруг точки (постройка, упавшее дерево).
func invalidate(x: float, z: float, r: float) -> void:
	var c0 := cell_of(x - r, z - r)
	var c1 := cell_of(x + r, z + r)
	for cz in range(floori(float(c0.y) / float(CH)), floori(float(c1.y) / float(CH)) + 1):
		for cx in range(floori(float(c0.x) / float(CH)), floori(float(c1.x) / float(CH)) + 1):
			chunks.erase(Vector2i(cx, cz))

## Ближайшая проходимая точка не дальше r (сама p, если годится).
func nearest_free(p: Vector3, r: float) -> Vector3:
	if passable(p.x, p.z):
		return p
	var steps := int(r / CELL) + 1
	for ring in range(1, steps + 1):
		var best := Vector3.INF
		var bd := 1e9
		for k in ring * 8:
			var a := TAU * float(k) / float(ring * 8)
			var q := Vector3(p.x + cos(a) * ring * CELL, 0.0, p.z + sin(a) * ring * CELL)
			if not passable(q.x, q.z):
				continue
			var d := Vector2(q.x - p.x, q.z - p.z).length_squared()
			if d < bd:
				bd = d
				best = q
		if best != Vector3.INF:
			best.y = main.ground_fast(best.x, best.z)
			return best
	return p

const _DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]

## A* по клеткам. Возвращает точки в мире (без начальной) или [] если пути нет.
## Если цель непроходима, идём к ближайшей проходимой клетке рядом с ней.
func find_path(from: Vector3, to: Vector3, lock: bool = false) -> Array:
	var a := cell_of(from.x, from.z)
	var b := cell_of(to.x, to.z)
	var fence: bool = lock and area != null and bool(area.active())
	if a == b:
		return [to]
	if cost_cell(b) <= 0:
		var nf := nearest_free(to, 6.0)
		b = cell_of(nf.x, nf.z)
		if cost_cell(b) <= 0 or a == b:
			return []
	if fence and not _in_area(b):
		return []
	var came := {}
	var gsc := {a: 0.0}
	var heap: Array = [[_h(a, b), a]]
	var steps := 0
	var found := false
	while not heap.is_empty() and steps < MAX_STEPS:
		var cur: Vector2i = _heap_pop(heap)[1]
		if cur == b:
			found = true
			break
		steps += 1
		var gc: float = gsc[cur]
		for d: Vector2i in _DIRS:
			var nb := cur + d
			var cc := cost_cell(nb)
			if cc <= 0:
				continue
			var diag: bool = d.x != 0 and d.y != 0
			if diag and (cost_cell(Vector2i(cur.x + d.x, cur.y)) <= 0 or cost_cell(Vector2i(cur.x, cur.y + d.y)) <= 0):
				continue
			var step_g: float = gc + float(cc) * (1.414 if diag else 1.0)
			if gsc.has(nb) and float(gsc[nb]) <= step_g:
				continue
			gsc[nb] = step_g
			came[nb] = cur
			_heap_push(heap, [step_g + _h(nb, b), nb])
	if not found:
		return []
	var cells: Array = [b]
	var c: Vector2i = b
	while came.has(c):
		c = came[c]
		cells.push_front(c)
	cells.remove_at(0)
	return _smooth(from, cells, to)

func _in_area(c: Vector2i) -> bool:
	var x := (float(c.x) + 0.5) * CELL
	var z := (float(c.y) + 0.5) * CELL
	return bool(area.allowed(x, z))

func _h(a: Vector2i, b: Vector2i) -> float:
	var dx := absf(float(b.x - a.x))
	var dz := absf(float(b.y - a.y))
	return (dx + dz) + (1.414 - 2.0) * minf(dx, dz)

## Срезать углы: подряд идущие клетки заменяем прямыми отрезками, если по ним можно пройти.
func _smooth(from: Vector3, cells: Array, to: Vector3) -> Array:
	var pts: Array = []
	for c: Vector2i in cells:
		pts.append(world_of(c))
	if not pts.is_empty():
		pts[pts.size() - 1] = Vector3(to.x, main.ground_fast(to.x, to.z), to.z)
	var out: Array = []
	var cur := from
	var i := 0
	while i < pts.size():
		var j := pts.size() - 1
		while j > i:
			var q2: Vector3 = pts[j]
			if _clear_line(cur, q2):
				break
			j -= 1
		var q: Vector3 = pts[j]
		out.append(q)
		cur = q
		i = j + 1
	return out

func _clear_line(a: Vector3, b: Vector3) -> bool:
	var d := Vector2(b.x - a.x, b.z - a.z)
	var n := int(d.length() / (CELL * 0.6)) + 1
	if n > 40:
		return false
	for k in range(1, n + 1):
		var t := float(k) / float(n)
		if cost_at(a.x + d.x * t, a.z + d.y * t) <= 0:
			return false
	return true

# ---------- маленькая двоичная куча: [f, клетка] ----------

func _heap_push(h: Array, v: Array) -> void:
	h.append(v)
	var i := h.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if float((h[p] as Array)[0]) <= float((h[i] as Array)[0]):
			break
		var t: Array = h[p]
		h[p] = h[i]
		h[i] = t
		i = p

func _heap_pop(h: Array) -> Array:
	var top: Array = h[0]
	var last: Array = h.pop_back()
	if h.is_empty():
		return top
	h[0] = last
	var i := 0
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var s := i
		if l < h.size() and float((h[l] as Array)[0]) < float((h[s] as Array)[0]):
			s = l
		if r < h.size() and float((h[r] as Array)[0]) < float((h[s] as Array)[0]):
			s = r
		if s == i:
			break
		var t: Array = h[s]
		h[s] = h[i]
		h[i] = t
		i = s
	return top
