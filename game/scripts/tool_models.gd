extends RefCounted
## Модели инструментов: кремнёвый нож и топор на деревянной рукояти с обмоткой лыком,
## копьё из обожжённой жерди с кремнёвым наконечником, деревянная лопата, бревно.
## Все модели в одних осях: рукоять вдоль +Y, точка хвата — начало координат,
## лезвие/наконечник — к +Y, режущая кромка (ударная сторона) смотрит в +X.
## Камень — гранёный (сколы плоскостями, как у камней pveg._chisel), дерево — с волокнами.

static var _mat: ShaderMaterial = null
static var _cache := {}

static func mat() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = load("res://shaders/paint/tool.gdshader")
	return _mat

## Строитель: гладкие трубы (общие вершины) и гранёные треугольники (свои вершины у каждой грани).
class B extends RefCounted:
	var sm := SurfaceTool.new()
	var fl := SurfaceTool.new()
	var n_sm := 0
	var n_fl := 0
	var rng := RandomNumberGenerator.new()

	func _init(seed_v: int = 1) -> void:
		sm.begin(Mesh.PRIMITIVE_TRIANGLES)
		fl.begin(Mesh.PRIMITIVE_TRIANGLES)
		fl.set_smooth_group(-1)
		rng.seed = seed_v

	## Труба вдоль ломаной pts с радиусами rs и цветами cols; sides граней; закрыть концы.
	func tube(pts: Array, rs: Array, cols: Array, sides: int, caps: bool = true, uv_k: float = 6.0) -> void:
		var base := n_sm
		var n := pts.size()
		var along := 0.0
		var prev_n := Vector3.ZERO
		for i in n:
			var p: Vector3 = pts[i]
			var tg: Vector3
			if i == 0:
				tg = (pts[1] as Vector3) - p
			elif i == n - 1:
				tg = p - (pts[i - 1] as Vector3)
			else:
				tg = (pts[i + 1] as Vector3) - (pts[i - 1] as Vector3)
			tg = tg.normalized()
			if i > 0:
				along += p.distance_to(pts[i - 1])
			# опорная нормаль переносится по кривой — без закрутки граней
			var nn: Vector3
			if i == 0:
				var ref := Vector3.RIGHT if absf(tg.x) < 0.9 else Vector3.FORWARD
				nn = tg.cross(ref).normalized()
			else:
				nn = (prev_n - tg * prev_n.dot(tg)).normalized()
			prev_n = nn
			var bb := tg.cross(nn).normalized()
			var r: float = rs[i]
			var c: Color = cols[i]
			for j in sides + 1:
				var a := TAU * float(j) / sides
				var d := nn * cos(a) + bb * sin(a)
				sm.set_color(c)
				sm.set_uv(Vector2(float(j) / sides, along * uv_k))
				sm.add_vertex(p + d * r)
				n_sm += 1
		for i in n - 1:
			for j in sides:
				var k := base + i * (sides + 1) + j
				for q in [k, k + sides + 1, k + 1, k + 1, k + sides + 1, k + sides + 2]:
					sm.add_index(q)
		if caps:
			for e in [0, n - 1]:
				var ci := n_sm
				var c2: Color = cols[e]
				sm.set_color(c2.darkened(0.15))
				sm.set_uv(Vector2(0.5, 0.5))
				sm.add_vertex(pts[e])
				n_sm += 1
				var k0: int = base + int(e) * (sides + 1)
				for j in sides:
					if e == 0:
						sm.add_index(ci); sm.add_index(k0 + j + 1); sm.add_index(k0 + j)
					else:
						sm.add_index(ci); sm.add_index(k0 + j); sm.add_index(k0 + j + 1)

	## Гранёный треугольник.
	func tri(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
		for p: Vector3 in [a, b, c]:
			fl.set_color(col)
			fl.set_uv(Vector2(p.x + p.z, p.y) * 9.0)
			fl.add_vertex(p)
			n_fl += 1

	## Обмотка лыком: спираль тонкого жгута вокруг оси (от y0 до y1), радиус r, витков turns.
	func wrap(ctr: Vector3, axis: Vector3, r: float, y0: float, y1: float, turns: float, col: Color, th: float = 0.0028) -> void:
		var ax := axis.normalized()
		var ref := Vector3.RIGHT if absf(ax.x) < 0.9 else Vector3.FORWARD
		var u := ax.cross(ref).normalized()
		var v := ax.cross(u).normalized()
		var pts: Array = []
		var rs: Array = []
		var cols: Array = []
		var steps := int(turns * 9.0)
		for i in steps + 1:
			var t := float(i) / steps
			var a := TAU * turns * t
			var rr := r + th * 0.6 + sin(t * 37.0) * th * 0.25
			pts.append(ctr + ax * lerpf(y0, y1, t) + (u * cos(a) + v * sin(a)) * rr)
			rs.append(th)
			cols.append(col.darkened(rng.randf_range(-0.06, 0.12)))
		tube(pts, rs, cols, 4, true, 30.0)

	## Плоская полоса (плечо лука): сечение — эллипс шириной ws (по оси Z) и толщиной ts (в плоскости XY).
	func band(pts: Array, ws: Array, ts: Array, cols: Array, sides: int) -> void:
		var base := n_sm
		var n := pts.size()
		for i in n:
			var p: Vector3 = pts[i]
			var tg: Vector3 = ((pts[mini(i + 1, n - 1)] as Vector3) - (pts[maxi(i - 1, 0)] as Vector3)).normalized()
			var nz := Vector3(0, 0, 1)
			var nx := tg.cross(nz).normalized()
			for j in sides + 1:
				var a := TAU * float(j) / sides
				sm.set_color(cols[i])
				sm.set_uv(Vector2(float(j) / sides, float(i) * 0.4))
				sm.add_vertex(p + nx * cos(a) * float(ts[i]) * 0.5 + nz * sin(a) * float(ws[i]) * 0.5)
				n_sm += 1
		for i in n - 1:
			for j in sides:
				var k := base + i * (sides + 1) + j
				for q in [k, k + sides + 1, k + 1, k + 1, k + sides + 1, k + sides + 2]:
					sm.add_index(q)

	func commit(mt: Material) -> ArrayMesh:
		var m := ArrayMesh.new()
		if n_sm > 0:
			sm.generate_normals()
			sm.commit(m)
		if n_fl > 0:
			fl.generate_normals()
			fl.commit(m)
		for s in m.get_surface_count():
			m.surface_set_material(s, mt)
		return m

const WOOD := Color(0.56, 0.43, 0.29)
const WOOD_D := Color(0.4, 0.29, 0.19)
const FIBRE := Color(0.66, 0.56, 0.38)
const FLINT := Color(0.34, 0.31, 0.29, 0.5)
const FLINT_L := Color(0.58, 0.53, 0.45, 0.5)

## Икосфера (подразбиение 2): вершины и грани.
static func _ico() -> Array:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v: Array = [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	for i in v.size():
		v[i] = (v[i] as Vector3).normalized()
	var f: Array = [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for it in 2:
		var mid := {}
		var out: Array = []
		for tri: Array in f:
			var m: Array = []
			for e: Array in [[tri[0], tri[1]], [tri[1], tri[2]], [tri[2], tri[0]]]:
				var key := Vector2i(mini(e[0], e[1]), maxi(e[0], e[1]))
				if not mid.has(key):
					v.append((((v[e[0]] as Vector3) + (v[e[1]] as Vector3)) * 0.5).normalized())
					mid[key] = v.size() - 1
				m.append(mid[key])
			out.append([tri[0], m[0], m[2]])
			out.append([tri[1], m[1], m[0]])
			out.append([tri[2], m[2], m[1]])
			out.append([m[0], m[1], m[2]])
		f = out
	return [v, f]

## Кремнёвое лезвие: форма задаётся функцией shape(вершина сферы) → точка; затем сколы
## плоскостями (как отбойником) и плоские грани с разбросом оттенка.
static func _flint(b: B, shape: Callable, xf: Transform3D, cuts_n: int, depth: float) -> void:
	var ico := _ico()
	var vs: Array = ico[0]
	var fs: Array = ico[1]
	var pts: Array = []
	for p: Vector3 in vs:
		pts.append(shape.call(p))
	# сколы: плоскости с нормалями почти поперёк лезвия (по обе стороны), снимают выпуклость
	var cuts: Array = []
	for i in cuts_n:
		var side := 1.0 if i % 2 == 0 else -1.0
		var n := Vector3(b.rng.randf_range(-0.8, 0.8), b.rng.randf_range(-0.9, 0.9), side * b.rng.randf_range(0.8, 1.6)).normalized()
		var mx := -1e9
		for p: Vector3 in pts:
			mx = maxf(mx, p.dot(n))
		cuts.append([n, mx * (1.0 - depth * b.rng.randf_range(0.4, 1.0))])
	for i in pts.size():
		var w: Vector3 = pts[i]
		for c: Array in cuts:
			var n: Vector3 = c[0]
			var e := w.dot(n)
			if e > float(c[1]):
				w -= n * (e - float(c[1]))
		pts[i] = w
	for tri: Array in fs:
		var a: Vector3 = pts[tri[0]]
		var bb: Vector3 = pts[tri[1]]
		var c: Vector3 = pts[tri[2]]
		# кромка светлее (тонкий кремень просвечивает), середина темнее
		var ctr := (a + bb + c) / 3.0
		var thin := clampf(1.0 - absf(ctr.z) * 60.0, 0.0, 1.0)
		var col := FLINT.lerp(FLINT_L, thin * 0.7 + b.rng.randf_range(0.0, 0.25))
		col.a = 0.5
		b.tri(xf * a, xf * bb, xf * c, col)

## Нож: рукоять 11 см с расщепом, лезвие-листовидный скол 10 см, обмотка лыком.
static func knife() -> ArrayMesh:
	if _cache.has("knife"):
		return _cache["knife"]
	var b := B.new(11)
	var hp: Array = []
	var hr: Array = []
	var hc: Array = []
	for i in 8:
		var t := float(i) / 7.0
		hp.append(Vector3(0.002 * sin(t * 3.0), lerpf(-0.06, 0.05, t), 0))
		hr.append(lerpf(0.0145, 0.0125, t) * (1.08 if i == 0 else 1.0))
		hc.append(WOOD.darkened(0.08 * sin(t * 9.0) + 0.05))
	b.tube(hp, hr, hc, 7)
	var blade := func(p: Vector3) -> Vector3:
		var y := (p.y + 1.0) * 0.5
		var w := 0.016 * pow(sin(PI * clampf(y * 0.92 + 0.06, 0.0, 1.0)), 0.7) * (1.0 - y * 0.35)
		return Vector3(p.x * w + y * y * 0.004, y * 0.105, p.z * 0.0042 * (1.0 - y * 0.5))
	_flint(b, blade, Transform3D(Basis(), Vector3(0.002, 0.03, 0)), 22, 0.22)
	b.wrap(Vector3(0, 0, 0), Vector3.UP, 0.0128, 0.028, 0.052, 6.0, FIBRE)
	var m := b.commit(mat())
	_cache["knife"] = m
	return m

## Топор: топорище 55 см с утолщением у пятки, кремнёвый клин в проушине,
## крестовая обмотка лыком выше и ниже клина.
static func axe() -> ArrayMesh:
	if _cache.has("axe"):
		return _cache["axe"]
	var b := B.new(21)
	var hp: Array = []
	var hr: Array = []
	var hc: Array = []
	for i in 12:
		var t := float(i) / 11.0
		hp.append(Vector3(-0.012 * sin(t * PI) + 0.004 * t, lerpf(-0.1, 0.44, t), 0))
		var r := lerpf(0.0165, 0.0175, t)
		if i == 0:
			r = 0.021
		elif i == 1:
			r = 0.018
		hr.append(r)
		hc.append(WOOD.darkened(0.04 + 0.07 * sin(t * 13.0)))
	b.tube(hp, hr, hc, 8)
	var hy := 0.37
	var head := func(p: Vector3) -> Vector3:
		var x := p.x
		var u := (x + 1.0) * 0.5
		var th := lerpf(0.017, 0.0022, smoothstep(0.25, 1.0, u))
		var h := lerpf(0.017, 0.031, smoothstep(0.1, 1.0, u))
		return Vector3(lerpf(-0.045, 0.1, u), p.y * h, p.z * th)
	_flint(b, head, Transform3D(Basis(), Vector3(0.0, hy, 0.0)), 26, 0.2)
	b.wrap(Vector3(0.002, 0, 0), Vector3.UP, 0.0178, hy + 0.035, hy + 0.06, 5.0, FIBRE)
	b.wrap(Vector3(0.002, 0, 0), Vector3.UP, 0.0178, hy - 0.06, hy - 0.033, 5.0, FIBRE)
	# крест-накрест через клин по обе стороны
	for sz in [-1.0, 1.0]:
		for k in 3:
			var o := float(k - 1) * 0.006
			var a := Vector3(-0.016, hy - 0.032 + o, sz * 0.012)
			var c := Vector3(0.016, hy + 0.032 + o, sz * 0.012)
			var a2 := Vector3(0.016, hy - 0.032 + o, sz * 0.012)
			var c2 := Vector3(-0.016, hy + 0.032 + o, sz * 0.012)
			b.tube([a, (a + c) * 0.5 + Vector3(0, 0, sz * 0.006), c], [0.0026, 0.0028, 0.0026], [FIBRE, FIBRE.darkened(0.08), FIBRE], 4)
			b.tube([a2, (a2 + c2) * 0.5 + Vector3(0, 0, sz * 0.006), c2], [0.0026, 0.0028, 0.0026], [FIBRE.darkened(0.05), FIBRE, FIBRE], 4)
	var m := b.commit(mat())
	_cache["axe"] = m
	return m

## Копьё: жердь 1,9 м, к острию обожжена дочерна; кремнёвый наконечник с обмоткой.
static func spear() -> ArrayMesh:
	if _cache.has("spear"):
		return _cache["spear"]
	var b := B.new(31)
	var hp: Array = []
	var hr: Array = []
	var hc: Array = []
	var n := 24
	for i in n + 1:
		var t := float(i) / n
		var y := lerpf(-0.82, 1.02, t)
		hp.append(Vector3(0.006 * sin(t * 4.0), y, 0.004 * sin(t * 7.0 + 1.0)))
		hr.append(lerpf(0.0165, 0.0122, t) + (0.0025 if i in [6, 15] else 0.0))
		var c := WOOD.lerp(Color(0.62, 0.5, 0.33), 0.3).darkened(0.05 * sin(t * 31.0))
		if i in [6, 15]:
			c = WOOD_D
		c = c.lerp(Color(0.16, 0.11, 0.08), smoothstep(0.82, 0.97, t) * 0.75)
		hc.append(c)
	b.tube(hp, hr, hc, 8, true, 3.0)
	var tip := func(p: Vector3) -> Vector3:
		var y := (p.y + 1.0) * 0.5
		var w := 0.022 * pow(sin(PI * clampf(y * 0.85 + 0.12, 0.0, 1.0)), 0.8) * (1.0 - y * 0.15)
		return Vector3(p.x * w, y * 0.14, p.z * 0.0058 * (1.0 - y * 0.55))
	_flint(b, tip, Transform3D(Basis(), Vector3(0.0, 0.985, 0.0)), 26, 0.2)
	b.wrap(Vector3(0.004 * sin(4.0), 0, 0.0), Vector3.UP, 0.0128, 0.95, 1.01, 8.0, FIBRE)
	var m := b.commit(mat())
	_cache["spear"] = m
	return m

## Деревянная лопата: черенок и тёсаная лопасть (плоские грани), лопасть внизу (−Y).
static func shovel() -> ArrayMesh:
	if _cache.has("shovel"):
		return _cache["shovel"]
	var b := B.new(41)
	var hp: Array = []
	var hr: Array = []
	var hc: Array = []
	for i in 10:
		var t := float(i) / 9.0
		hp.append(Vector3(0, lerpf(-0.56, 0.6, t), 0))
		hr.append(0.017 if i < 9 else 0.02)
		hc.append(WOOD.darkened(0.05 * sin(t * 11.0)))
	b.tube(hp, hr, hc, 7)
	# лопасть: тёсаная доска 22×32 см, слегка вогнутая, кромка тоньше
	var W := 0.11
	var y0 := -0.55
	var y1 := -0.9
	var rows := 5
	var cols := 4
	var grid: Array = []
	for i in rows + 1:
		var t := float(i) / rows
		var row: Array = []
		var wv := W * lerpf(0.55, 1.0, smoothstep(0.0, 0.35, t))
		for j in cols + 1:
			var s := lerpf(-1.0, 1.0, float(j) / cols)
			var th := lerpf(0.014, 0.005, t)
			var dz := -0.018 * (1.0 - s * s)
			row.append([Vector3(s * wv, lerpf(y0, y1, t), dz + th * 0.5), Vector3(s * wv, lerpf(y0, y1, t), dz - th * 0.5)])
		grid.append(row)
	var col := WOOD.lerp(Color(0.66, 0.54, 0.38), 0.4)
	col.a = 1.0
	for i in rows:
		for j in cols:
			for side in 2:
				var a: Vector3 = grid[i][j][side]
				var bb: Vector3 = grid[i][j + 1][side]
				var c: Vector3 = grid[i + 1][j][side]
				var d: Vector3 = grid[i + 1][j + 1][side]
				var cc := col.darkened(b.rng.randf_range(0.0, 0.1))
				b.tri(a, bb, d, cc)
				b.tri(a, d, c, cc)
	# торцы лопасти
	for i in rows:
		for j: int in [0, cols]:
			var a: Vector3 = grid[i][j][0]
			var bb: Vector3 = grid[i][j][1]
			var c: Vector3 = grid[i + 1][j][0]
			var d: Vector3 = grid[i + 1][j][1]
			b.tri(a, bb, d, col.darkened(0.15))
			b.tri(a, d, c, col.darkened(0.15))
	for j in cols:
		for i: int in [0, rows]:
			var a: Vector3 = grid[i][j][0]
			var bb: Vector3 = grid[i][j][1]
			var c: Vector3 = grid[i][j + 1][0]
			var d: Vector3 = grid[i][j + 1][1]
			b.tri(a, bb, d, col.darkened(0.15))
			b.tri(a, d, c, col.darkened(0.15))
	var m := b.commit(mat())
	_cache["shovel"] = m
	return m

## Бревно: кора с бороздами, торцы светлые с годичными кольцами. Ось вдоль +Y, центр в 0.
static func log_mesh(L: float, r: float, bark: Color, seed_v: int = 5) -> ArrayMesh:
	var key := "log_%.2f_%.3f_%s_%d" % [L, r, bark.to_html(), seed_v]
	if _cache.has(key):
		return _cache[key]
	var b := B.new(seed_v)
	var pts: Array = []
	var rs: Array = []
	var cs: Array = []
	var n := maxi(3, int(L / 0.25))
	for i in n + 1:
		var t := float(i) / n
		pts.append(Vector3(b.rng.randf_range(-0.006, 0.006), lerpf(-L * 0.5, L * 0.5, t), b.rng.randf_range(-0.006, 0.006)))
		rs.append(r * lerpf(1.0, 0.93, t) * b.rng.randf_range(0.97, 1.03))
		cs.append(bark.darkened(b.rng.randf_range(-0.05, 0.12)))
	b.tube(pts, rs, cs, 9, false, 2.0)
	# торцы: кольца светлой древесины с тёмными годовыми
	var wood := Color(0.86, 0.72, 0.5)
	for e in 2:
		var p: Vector3 = pts[0] if e == 0 else pts[n]
		var rr: float = (rs[0] if e == 0 else rs[n]) * 0.97
		var sd := -1.0 if e == 0 else 1.0
		var rings := 4
		for k in rings:
			var r0 := rr * float(k) / rings
			var r1 := rr * float(k + 1) / rings
			var c := wood.darkened(0.04 * k + (0.18 if k == rings - 1 else 0.0))
			for j in 10:
				var a0 := TAU * j / 10.0
				var a1 := TAU * (j + 1) / 10.0
				var p00 := p + Vector3(cos(a0) * r0, 0, sin(a0) * r0)
				var p01 := p + Vector3(cos(a1) * r0, 0, sin(a1) * r0)
				var p10 := p + Vector3(cos(a0) * r1, 0, sin(a0) * r1)
				var p11 := p + Vector3(cos(a1) * r1, 0, sin(a1) * r1)
				if sd > 0.0:
					b.tri(p00, p10, p11, c)
					if k > 0:
						b.tri(p00, p11, p01, c)
				else:
					b.tri(p00, p11, p10, c)
					if k > 0:
						b.tri(p00, p01, p11, c)
	var m := b.commit(mat())
	_cache[key] = m
	return m

## Ножны: кожаный чехол с ремешком (для ножа на поясе). Ось как у ножа, вход у y = 0.035.
static func sheath() -> ArrayMesh:
	if _cache.has("sheath"):
		return _cache["sheath"]
	var b := B.new(51)
	var leather := Color(0.3, 0.2, 0.13)
	var pts: Array = []
	var rs: Array = []
	var cs: Array = []
	for i in 7:
		var t := float(i) / 6.0
		pts.append(Vector3(0.002, lerpf(0.035, 0.14, t), 0))
		rs.append(lerpf(0.017, 0.007, pow(t, 1.6)))
		cs.append(leather.darkened(0.06 * sin(t * 7.0)))
	b.tube(pts, rs, cs, 7)
	b.wrap(Vector3(0.002, 0, 0), Vector3.UP, 0.016, 0.05, 0.058, 1.2, Color(0.22, 0.14, 0.09), 0.003)
	var m := b.commit(mat())
	_cache["sheath"] = m
	return m

# --- combat: лук, стрела, тетива ---

## Изгиб плеча лука: x(y) — насколько плечо отходит назад (к стрелку, −X) на высоте y.
## Цельный лук 1,3 м, концы чуть загнуты вперёд (рекурв), рукоять — в начале координат.
const BOW_H := 0.66
static func bow_x(y: float) -> float:
	var t := absf(y) / BOW_H
	var x := -0.15 * t * t
	x += 0.05 * smoothstep(0.82, 1.0, t)
	return x

## Концы лука (ушки тетивы) в осях лука.
static func bow_tip(top: bool) -> Vector3:
	var y := BOW_H * (0.985 if top else -0.985)
	return Vector3(bow_x(y) - 0.006, y, 0)

## Лук: плечи — тёсаные плоские полосы (шире у рукояти, к концам уже), рукоять обмотана лыком,
## ушки потемнее. Ось лука +Y (вверх), спинка смотрит в +X (к цели), тетива — отдельно (string()).
static func bow() -> ArrayMesh:
	if _cache.has("bow"):
		return _cache["bow"]
	var b := B.new(61)
	var pts: Array = []
	var ws: Array = []
	var ts: Array = []
	var cs: Array = []
	var n := 26
	var wood := Color(0.6, 0.45, 0.28)
	for i in n + 1:
		var y := lerpf(-BOW_H, BOW_H, float(i) / n)
		var t := absf(y) / BOW_H
		pts.append(Vector3(bow_x(y), y, 0))
		var grip := 1.0 - smoothstep(0.08, 0.2, t)
		ws.append(lerpf(0.036, 0.013, smoothstep(0.15, 1.0, t)) + grip * 0.002)
		ts.append(lerpf(0.022, 0.011, smoothstep(0.1, 1.0, t)) + grip * 0.012)
		var c := wood.darkened(0.06 * sin(t * 17.0) + 0.03)
		if t > 0.93:
			c = Color(0.3, 0.2, 0.13)
		cs.append(c)
	b.band(pts, ws, ts, cs, 8)
	b.wrap(Vector3(-0.002, 0, 0), Vector3.UP, 0.016, -0.06, 0.06, 9.0, FIBRE, 0.0032)
	# ушки: обмотка у концов
	for top in [true, false]:
		var tp := bow_tip(top)
		b.wrap(Vector3(tp.x + 0.004, 0, 0), Vector3.UP, 0.007, tp.y - 0.025 if top else tp.y + 0.008, tp.y - 0.008 if top else tp.y + 0.025, 3.0, Color(0.5, 0.42, 0.3), 0.0022)
	var m := b.commit(mat())
	_cache["bow"] = m
	return m

## Отрезок тетивы единичной длины вдоль +Y (растягивается по длине масштабом).
static func string_seg() -> ArrayMesh:
	if _cache.has("string"):
		return _cache["string"]
	var b := B.new(62)
	var c := Color(0.7, 0.62, 0.45)
	b.tube([Vector3.ZERO, Vector3(0, 0.5, 0), Vector3(0, 1, 0)], [0.0024, 0.0024, 0.0024], [c, c.darkened(0.08), c], 4, false)
	var m := b.commit(mat())
	_cache["string"] = m
	return m

## Стрела 0,74 м: прямой прут, кремнёвый наконечник с обмоткой, оперение из трёх перьев.
## Ушко (выемка под тетиву) — в начале координат, наконечник к +Y.
static func arrow() -> ArrayMesh:
	if _cache.has("arrow"):
		return _cache["arrow"]
	var b := B.new(71)
	var sh := Color(0.66, 0.53, 0.36)
	b.tube([Vector3(0, 0.0, 0), Vector3(0, 0.35, 0), Vector3(0, 0.69, 0)], [0.0048, 0.0052, 0.0047], [sh.darkened(0.1), sh, sh.darkened(0.05)], 6)
	var tip := func(p: Vector3) -> Vector3:
		var y := (p.y + 1.0) * 0.5
		var w := 0.011 * pow(sin(PI * clampf(y * 0.85 + 0.12, 0.0, 1.0)), 0.8)
		return Vector3(p.x * w, y * 0.065, p.z * 0.0032)
	_flint(b, tip, Transform3D(Basis(), Vector3(0, 0.672, 0)), 18, 0.2)
	b.wrap(Vector3.ZERO, Vector3.UP, 0.005, 0.655, 0.685, 5.0, FIBRE, 0.0018)
	b.wrap(Vector3.ZERO, Vector3.UP, 0.005, 0.015, 0.03, 3.0, FIBRE, 0.0018)
	# оперение: три пера под 120°, у каждого — плоская трапеция с зубчатым краем
	var fc := Color(0.36, 0.3, 0.26)
	for k in 3:
		var a := TAU * k / 3.0 + 0.3
		var d := Vector3(cos(a), 0, sin(a))
		var y0 := 0.035
		var y1 := 0.15
		var p0 := Vector3(0, y0, 0) + d * 0.004
		var p1 := Vector3(0, y1, 0) + d * 0.004
		var q0 := Vector3(0, y0 + 0.01, 0) + d * 0.02
		var q1 := Vector3(0, y1 - 0.035, 0) + d * 0.016
		var c := fc.lerp(Color(0.62, 0.58, 0.52), 0.35 if k == 0 else 0.0)
		b.tri(p0, q0, q1, c)
		b.tri(p0, q1, p1, c.darkened(0.08))
		b.tri(p0, q1, q0, c)
		b.tri(p0, p1, q1, c.darkened(0.08))
	var m := b.commit(mat())
	_cache["arrow"] = m
	return m

static func mesh_of(id: String) -> Mesh:
	match id:
		"bow":
			return bow()
		"arrow":
			return arrow()
		"knife":
			return knife()
		"axe":
			return axe()
		"spear":
			return spear()
		"shovel":
			return shovel()
	return null
