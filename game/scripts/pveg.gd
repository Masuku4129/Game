extends RefCounted
## Живописная растительность: кроны — округлые «облака» с мягкими нормалями (как пятна краски),
## ель — ярусы зубчатых юбок, камни — гранёные глыбы, трава — кочки из широких мазков.
## Деревья в 300–900 треугольников вместо 3–11 тысяч.

var rng := RandomNumberGenerator.new()
var mats := {}
var _ico: Array = []

func _init() -> void:
	_ico = _icosphere()
	var fol := load("res://shaders/paint/foliage.gdshader")
	var brk := load("res://shaders/paint/bark.gdshader")
	for f in [
		["spruce", Color(0.07, 0.15, 0.13), Color(0.16, 0.3, 0.22), Color(0.36, 0.5, 0.3), 0.0],
		["pine", Color(0.1, 0.2, 0.14), Color(0.25, 0.4, 0.22), Color(0.52, 0.62, 0.3), 0.3],
		["birch", Color(0.2, 0.32, 0.14), Color(0.42, 0.58, 0.24), Color(0.78, 0.82, 0.4), 1.0],
		["leaf", Color(0.16, 0.28, 0.14), Color(0.34, 0.5, 0.22), Color(0.66, 0.74, 0.32), 1.0],
		["bush", Color(0.13, 0.24, 0.12), Color(0.3, 0.44, 0.2), Color(0.58, 0.66, 0.3), 0.8],
	]:
		var m := ShaderMaterial.new()
		m.shader = fol
		m.set_shader_parameter("col_dark", f[1])
		m.set_shader_parameter("col_mid", f[2])
		m.set_shader_parameter("col_light", f[3])
		mats[f[0]] = m
	for b in [["bark", Color(0.36, 0.27, 0.2), Color(0.2, 0.15, 0.11), 0.0], ["bark_pine", Color(0.62, 0.36, 0.2), Color(0.36, 0.22, 0.14), 0.0], ["bark_birch", Color(0.9, 0.88, 0.82), Color(0.72, 0.7, 0.66), 1.0], ["bark_dead", Color(0.48, 0.44, 0.38), Color(0.3, 0.27, 0.24), 0.0]]:
		var m := ShaderMaterial.new()
		m.shader = brk
		m.set_shader_parameter("col", b[1])
		m.set_shader_parameter("col2", b[2])
		m.set_shader_parameter("birch", b[3])
		mats[b[0]] = m
	var rk := ShaderMaterial.new()
	rk.shader = load("res://shaders/paint/rock.gdshader")
	mats["rock"] = rk
	var tf := ShaderMaterial.new()
	tf.shader = load("res://shaders/paint/tuft.gdshader")
	mats["tuft"] = tf

func R(a: float, b: float) -> float:
	return rng.randf_range(a, b)

## Икосфера 1-го уровня: 42 вершины, 80 граней.
func _icosphere() -> Array:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v: Array = [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	for i in v.size():
		v[i] = v[i].normalized()
	var f: Array = [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	var mid := {}
	var out: Array = []
	for tri in f:
		var m: Array = []
		for e in [[tri[0], tri[1]], [tri[1], tri[2]], [tri[2], tri[0]]]:
			var key := Vector2i(mini(e[0], e[1]), maxi(e[0], e[1]))
			if not mid.has(key):
				v.append(((v[e[0]] + v[e[1]]) * 0.5).normalized())
				mid[key] = v.size() - 1
			m.append(mid[key])
		out.append([tri[0], m[0], m[2]])
		out.append([tri[1], m[1], m[0]])
		out.append([tri[2], m[2], m[1]])
		out.append([m[0], m[1], m[2]])
	return [v, out]

## Облако листвы: искажённая шумом сфера, нормали — от центра (мягкий объём), чуть вверх.
func blob(st: SurfaceTool, c: Vector3, sc: Vector3, shade: float, autumn_k: float = 1.0) -> void:
	var verts: Array = _ico[0]
	var faces: Array = _ico[1]
	var off := R(0, 100)
	var pts: Array = []
	for p in verts:
		var q: Vector3 = p
		var n := 1.0 + 0.22 * sin(q.x * 3.1 + off) * cos(q.z * 2.7 + off) + 0.12 * sin(q.y * 5.3 + off * 2.0)
		# низ облака приплюснут — как у настоящих крон
		if q.y < 0:
			q.y *= 0.7
		pts.append(c + q * sc * n)
	for tri in faces:
		for k in [0, 2, 1]:
			var i: int = tri[k]
			var p: Vector3 = verts[i]
			var nrm := (p + Vector3(0, 0.35, 0)).normalized()
			st.set_color(Color(shade, autumn_k, 0, 1))
			st.set_normal(nrm)
			st.add_vertex(pts[i])

## Ствол: труба по кривой с малым числом граней.
func trunk(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, r0: float, r1: float, seg: int, rad: int) -> void:
	var rows: Array = []
	for i in seg + 1:
		var t := float(i) / seg
		var p := p0.lerp(p1, t).lerp(p1.lerp(p2, t), t)
		var tg := (p1 - p0).lerp(p2 - p1, t).normalized()
		var ref := Vector3.RIGHT if absf(tg.y) > 0.9 else Vector3.UP
		var nn := tg.cross(ref).normalized()
		var bb := tg.cross(nn).normalized()
		var r := lerpf(r0, r1, t)
		var row: Array = []
		for j in rad + 1:
			var a := TAU * j / rad
			var d := nn * cos(a) + bb * sin(a)
			row.append([p + d * r, d, Vector2(float(j) / rad, t * p0.distance_to(p2) * 0.5)])
		rows.append(row)
	for i in seg:
		for j in rad:
			for v in [rows[i][j], rows[i + 1][j], rows[i][j + 1], rows[i + 1][j], rows[i + 1][j + 1], rows[i][j + 1]]:
				st.set_normal(v[1])
				st.set_uv(v[2])
				st.add_vertex(v[0])

## Ярус ели: зубчатая юбка-конус с опущенными краями.
func skirt(st: SurfaceTool, y: float, r: float, h: float, teeth: int, shade: float) -> void:
	var top := Vector3(R(-0.05, 0.05), y + h, R(-0.05, 0.05))
	var n := teeth * 2
	var ring: Array = []
	var a0 := R(0, TAU)
	for i in n:
		var a := a0 + TAU * i / n
		var rr := r * (1.0 if i % 2 == 0 else R(0.62, 0.75))
		var dy := -r * 0.18 * (1.0 if i % 2 == 0 else 0.4) + R(-0.05, 0.05)
		ring.append(Vector3(cos(a) * rr, y + dy, sin(a) * rr))
	var inner := Vector3(0, y + h * 0.25, 0)
	for i in n:
		var a: Vector3 = ring[i]
		var b: Vector3 = ring[(i + 1) % n]
		for v in [top, b, a]:
			var d: Vector3 = v - Vector3(0, y, 0)
			var nrm := (Vector3(d.x, 0, d.z).normalized() * 0.8 + Vector3(0, 0.9, 0)).normalized() if v != top else Vector3.UP
			st.set_color(Color(shade * (1.0 if v == top else 0.85), 0, 0, 1))
			st.set_normal(nrm)
			st.add_vertex(v)
		# низ юбки — тёмный, закрывает просвет
		for v in [inner, a, b]:
			st.set_color(Color(0.1, 0, 0, 1))
			st.set_normal(Vector3.DOWN)
			st.add_vertex(v)

func _mesh(parts: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for pr in parts:
		var st: SurfaceTool = pr[0]
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mats[pr[1]])
	return mesh

func _st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st

## Ель: 7–10 ярусов, верхушка-пика.
func spruce(seed_v: int) -> Array:
	rng.seed = seed_v
	var H := R(8.0, 12.5)
	var bk := _st()
	var fl := _st()
	trunk(bk, Vector3.ZERO, Vector3(0, H * 0.5, 0), Vector3(0, H * 0.9, 0), 0.26, 0.05, 2, 6)
	var tiers := rng.randi_range(7, 10)
	var R0 := H * R(0.26, 0.32)
	for i in tiers:
		var t := float(i) / tiers
		var y := lerpf(H * 0.14, H * 0.86, t)
		var r := R0 * (1.0 - t * 0.85) * R(0.9, 1.1)
		skirt(fl, y, r, (H - y) * 0.35 + 0.6, rng.randi_range(6, 8), lerpf(0.4, 0.9, t))
	skirt(fl, H * 0.9, 0.35, H * 0.12, 4, 1.0)
	return [_mesh([[bk, "bark"], [fl, "spruce"]]), H]

## Сосна: высокий рыжий ствол, несколько плоских облаков наверху.
func pine(seed_v: int) -> Array:
	rng.seed = seed_v
	var H := R(11.0, 15.0)
	var bk := _st()
	var fl := _st()
	var top := Vector3(R(-0.6, 0.6), H, R(-0.6, 0.6))
	trunk(bk, Vector3.ZERO, Vector3(R(-0.3, 0.3), H * 0.5, R(-0.3, 0.3)), top, 0.28, 0.08, 4, 6)
	for i in rng.randi_range(3, 5):
		var a := R(0, TAU)
		var y := H * R(0.68, 0.96)
		var d := R(0.6, 2.0)
		var c := Vector3(cos(a) * d, y, sin(a) * d) + top * Vector3(1, 0, 1) * (y / H)
		trunk(bk, Vector3(top.x * y / H * 0.8, y - 0.8, top.z * y / H * 0.8), (Vector3(top.x * y / H, y - 0.6, top.z * y / H) + c) * 0.5, c, 0.07, 0.03, 1, 4)
		blob(fl, c + Vector3(0, 0.3, 0), Vector3(R(1.3, 2.0), R(0.6, 0.9), R(1.3, 2.0)), R(0.4, 1.0))
	return [_mesh([[bk, "bark_pine"], [fl, "pine"]]), H]

## Берёза: белый ствол с наклоном, вертикальные лёгкие облака.
func birch(seed_v: int, kind: String = "birch") -> Array:
	rng.seed = seed_v
	var H := R(8.0, 11.0)
	var bk := _st()
	var fl := _st()
	var top := Vector3(R(-0.8, 0.8), H, R(-0.8, 0.8))
	trunk(bk, Vector3.ZERO, Vector3(R(-0.3, 0.3), H * 0.5, R(-0.3, 0.3)), top, 0.17, 0.05, 4, 6)
	var n := rng.randi_range(5, 8)
	for i in n:
		var t := float(i) / n
		var a := R(0, TAU)
		var y := lerpf(H * 0.45, H * 0.95, t)
		var d := R(0.5, 1.6) * (1.0 - t * 0.5)
		var axis := top * (y / H)
		var c := axis + Vector3(cos(a) * d, 0, sin(a) * d)
		if i % 2 == 0:
			trunk(bk, axis - Vector3(0, 0.5, 0), (axis + c) * 0.5, c, 0.05, 0.02, 1, 4)
		blob(fl, c, Vector3(R(0.9, 1.4), R(1.0, 1.6), R(0.9, 1.4)) * (1.0 - t * 0.3), R(0.3, 1.0))
	return [_mesh([[bk, "bark_birch"], [fl, "birch" if kind == "birch" else "leaf"]]), H]

func bush(seed_v: int) -> Array:
	rng.seed = seed_v
	var fl := _st()
	for i in rng.randi_range(3, 5):
		var a := R(0, TAU)
		var d := R(0.1, 0.6)
		blob(fl, Vector3(cos(a) * d, R(0.35, 0.7), sin(a) * d), Vector3(R(0.45, 0.7), R(0.4, 0.6), R(0.45, 0.7)), R(0.3, 1.0))
	return [_mesh([[fl, "bush"]]), 1.0]

## Камень: гранёная глыба (шейдер считает плоские нормали сам).
func rock(seed_v: int) -> Array:
	rng.seed = seed_v
	var st := _st()
	var verts: Array = _ico[0]
	var faces: Array = _ico[1]
	var sc := Vector3(R(0.8, 1.3), R(0.45, 0.8), R(0.8, 1.3))
	var off := R(0, 50)
	var pts: Array = []
	for p in verts:
		var q: Vector3 = p
		var n := 1.0 + 0.25 * sin(q.x * 2.3 + off) * sin(q.z * 1.9 + off) + R(-0.08, 0.08)
		var w := q * sc * n
		if w.y < -0.1:
			w.y = -0.1 + (w.y + 0.1) * 0.3
		pts.append(w)
	for tri in faces:
		var shade := R(0.0, 1.0)
		for k in [0, 2, 1]:
			st.set_color(Color(shade, 0, 0, 1))
			st.set_normal(verts[tri[k]])
			st.add_vertex(pts[tri[k]])
	return [_mesh([[st, "rock"]]), sc.y]

## Кочка травы: 7–11 широких изогнутых листьев (по 3 треугольника), без одиночных волосков.
func tuft(seed_v: int, tall: float = 1.0) -> Array:
	rng.seed = seed_v
	var st := _st()
	var n := rng.randi_range(7, 11)
	for i in n:
		var a := TAU * i / n + R(-0.3, 0.3)
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x)
		var h := R(0.25, 0.5) * tall
		var w := R(0.05, 0.09)
		var lean := R(0.25, 0.6)
		var b := dir * R(0.0, 0.08)
		var m := b + dir * h * lean * 0.4 + Vector3(0, h * 0.6, 0)
		var tp := b + dir * h * lean + Vector3(0, h, 0)
		var shade := R(0.0, 1.0)
		var pts := [[b - side * w, 0.0], [b + side * w, 0.0], [m - side * w * 0.7, 0.6], [m + side * w * 0.7, 0.6], [tp, 1.0]]
		for tri in [[0, 1, 2], [1, 3, 2], [2, 3, 4]]:
			for k in tri:
				st.set_color(Color(shade, 0, 0, pts[k][1]))
				st.set_normal(Vector3.UP)
				st.add_vertex(pts[k][0])
	return [_mesh([[st, "tuft"]]), 0.5]
