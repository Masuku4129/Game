extends RefCounted
## Живописная растительность: кроны — округлые «облака» с мягкими нормалями (как пятна краски),
## ель — ярусы зубчатых юбок, камни — гранёные глыбы, трава — кочки из широких мазков.
## Деревья в 300–900 треугольников вместо 3–11 тысяч.

var rng := RandomNumberGenerator.new()
var mats := {}
var fade_list: Array = []
var _ico: Array = []
var _ico0: Array = []
## Лёгкая дальняя версия: без мазков-карточек, грубые облака.
var lod := false

func _init() -> void:
	_ico = _icosphere()
	_ico0 = _ico_base
	var fol := load("res://shaders/paint/foliage.gdshader")
	var brk := load("res://shaders/paint/bark.gdshader")
	for f in [
		["spruce", Color(0.1, 0.19, 0.1), Color(0.23, 0.37, 0.18), Color(0.5, 0.6, 0.27), 0.0],
		["pine", Color(0.1, 0.19, 0.11), Color(0.24, 0.38, 0.18), Color(0.55, 0.62, 0.26), 0.3],
		["birch", Color(0.14, 0.25, 0.11), Color(0.36, 0.5, 0.18), Color(0.7, 0.74, 0.3), 1.0],
		["leaf", Color(0.12, 0.22, 0.1), Color(0.3, 0.45, 0.17), Color(0.62, 0.68, 0.27), 1.0],
		["bush", Color(0.1, 0.2, 0.09), Color(0.26, 0.4, 0.15), Color(0.56, 0.62, 0.24), 0.8],
		["larch", Color(0.12, 0.2, 0.1), Color(0.34, 0.46, 0.2), Color(0.66, 0.7, 0.3), 1.0],
		["fern", Color(0.1, 0.2, 0.08), Color(0.25, 0.42, 0.14), Color(0.5, 0.62, 0.22), 1.0],
		["berry", Color(0.3, 0.03, 0.04), Color(0.6, 0.08, 0.08), Color(0.85, 0.25, 0.2), 0.0],
		["cap_red", Color(0.45, 0.06, 0.04), Color(0.72, 0.14, 0.08), Color(0.9, 0.35, 0.2), 0.0],
		["cap_brown", Color(0.25, 0.14, 0.07), Color(0.45, 0.28, 0.14), Color(0.62, 0.45, 0.26), 0.0],
		["anthill", Color(0.18, 0.12, 0.07), Color(0.34, 0.24, 0.14), Color(0.5, 0.38, 0.22), 0.0],
	]:
		var m := ShaderMaterial.new()
		m.shader = fol
		m.set_shader_parameter("col_dark", f[1])
		m.set_shader_parameter("col_mid", f[2])
		m.set_shader_parameter("col_light", f[3])
		m.set_shader_parameter("autumn_k", f[4])
		mats[f[0]] = m
	for b in [["cut", Color(0.78, 0.64, 0.44), Color(0.6, 0.46, 0.3), 0.0], ["stem", Color(0.9, 0.86, 0.76), Color(0.75, 0.7, 0.6), 0.0], ["log", Color(0.42, 0.34, 0.26), Color(0.24, 0.19, 0.15), 0.0], ["bark", Color(0.36, 0.27, 0.2), Color(0.2, 0.15, 0.11), 0.0], ["bark_pine", Color(0.52, 0.36, 0.24), Color(0.32, 0.22, 0.16), 0.0], ["bark_birch", Color(0.9, 0.88, 0.82), Color(0.72, 0.7, 0.66), 1.0], ["bark_dead", Color(0.48, 0.44, 0.38), Color(0.3, 0.27, 0.24), 0.0]]:
		var m := ShaderMaterial.new()
		m.shader = brk
		m.set_shader_parameter("col", b[1])
		m.set_shader_parameter("col2", b[2])
		m.set_shader_parameter("birch", b[3])
		# брёвна, пни, срезы и грибы не растворяются перед камерой
		m.set_shader_parameter("no_fade", b[0] in ["cut", "stem", "log"])
		mats[b[0]] = m
	var rk := ShaderMaterial.new()
	rk.shader = load("res://shaders/paint/rock.gdshader")
	mats["rock"] = rk
	var rd := ShaderMaterial.new()
	rd.shader = load("res://shaders/paint/grasscard.gdshader")
	rd.set_shader_parameter("col_root", Color(0.22, 0.28, 0.12))
	rd.set_shader_parameter("col_tip", Color(0.62, 0.6, 0.32))
	mats["reed"] = rd
	var tf := ShaderMaterial.new()
	tf.shader = load("res://shaders/paint/grasscard.gdshader")
	tf.set_shader_parameter("strokes_tex", _grass_tex())
	mats["tuft"] = tf
	# мазки листвы: те же цвета, что у сплошных крон
	var bt := _brush_tex()
	var lc := load("res://shaders/paint/leafcard.gdshader")
	for k in ["spruce", "pine", "birch", "leaf", "bush", "larch", "fern"]:
		var m := ShaderMaterial.new()
		m.shader = lc
		m.set_shader_parameter("brush", bt)
		for p in ["col_dark", "col_mid", "col_light", "autumn_k"]:
			m.set_shader_parameter(p, mats[k].get_shader_parameter(p))
		mats[k + "_card"] = m

	rd.set_shader_parameter("strokes_tex", _grass_tex())
	for k in mats.keys():
		if k != "tuft":
			fade_list.append(mats[k])

## Текстура мазка листвы: десяток листьев-эллипсов в круге, рваный край, g — оттенок.
func _brush_tex() -> Texture2D:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r := RandomNumberGenerator.new()
	r.seed = 77
	for i in 18:
		var a := r.randf() * TAU
		var d := sqrt(r.randf()) * 0.3
		var cx := 0.5 + cos(a) * d
		var cy := 0.5 + sin(a) * d
		var ang := r.randf() * PI
		var la := r.randf_range(0.1, 0.17)
		var lb := la * r.randf_range(0.4, 0.6)
		var g := clampf(0.55 - (cy - 0.5) * 1.2 + r.randf_range(-0.2, 0.2), 0.0, 1.0)
		var ca := cos(ang)
		var sa := sin(ang)
		for y in range(maxi(0, int((cy - la) * n)), mini(n, int((cy + la) * n) + 1)):
			for x in range(maxi(0, int((cx - la) * n)), mini(n, int((cx + la) * n) + 1)):
				var dx := float(x) / n - cx
				var dy := float(y) / n - cy
				var u := (dx * ca + dy * sa) / la
				var v := (-dx * sa + dy * ca) / lb
				if u * u + v * v < 1.0:
					img.set_pixel(x, y, Color(0, g, 0, 1))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

## Текстура пучка травы: вертикальные сужающиеся мазки от низа.
func _grass_tex() -> Texture2D:
	var w := 64
	var h := 96
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r := RandomNumberGenerator.new()
	r.seed = 91
	for i in 16:
		var x0 := r.randf_range(0.12, 0.88)
		var bend := r.randf_range(-0.25, 0.25)
		var top := r.randf_range(0.05, 0.5)
		var wd := r.randf_range(0.03, 0.06)
		var g := r.randf()
		for y in h:
			var t := float(y) / h
			if t < top:
				continue
			var k := (1.0 - t) / (1.0 - top)
			var cx := x0 + bend * k * k
			var half := wd * (1.0 - k) + 0.004
			for x in range(maxi(0, int((cx - half) * w)), mini(w, int((cx + half) * w) + 1)):
				img.set_pixel(x, y, Color(0, g, 0, 1))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

## Облако из мазков: сплошное ядро + карточки-мазки по поверхности (рваный край).
func leafblob(core: SurfaceTool, cards: SurfaceTool, c: Vector3, sc: Vector3, shade: float) -> void:
	if cards == null:
		blob(core, c, sc * 0.92, shade * 0.8)
		return
	blob(core, c, sc * 0.78, shade * 0.6)
	var verts: Array = _ico[0]
	var sz := (sc.x + sc.y + sc.z) / 3.0 * 0.62
	for p in verts:
		var q: Vector3 = p
		var pos := c + Vector3(q.x * sc.x, q.y * sc.y * (0.7 if q.y < 0 else 1.0), q.z * sc.z) * CR(0.85, 1.0)
		var nrm := (q + Vector3(0, 0.35, 0)).normalized()
		var rot := CR(0, TAU)
		var sh := clampf(shade + CR(-0.2, 0.2), 0.0, 1.0)
		var s2 := sz * CR(0.8, 1.2)
		for corner in [[0, 0], [1, 0], [1, 1], [0, 0], [1, 1], [0, 1]]:
			cards.set_color(Color(sh, 0, 0, 1))
			cards.set_normal(nrm)
			cards.set_uv(Vector2(corner[0], corner[1]))
			cards.set_uv2(Vector2(s2, rot))
			cards.add_vertex(pos)

var crng := RandomNumberGenerator.new()
func CR(a: float, b: float) -> float:
	return crng.randf_range(a, b)

func R(a: float, b: float) -> float:
	return rng.randf_range(a, b)

var _ico_base: Array = []
## Икосфера 1-го уровня: 42 вершины, 80 граней.
func _icosphere() -> Array:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v: Array = [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	for i in v.size():
		v[i] = v[i].normalized()
	var f: Array = [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	_ico_base = [v.duplicate(), f]
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

## Пятно кроны: 2–3 сросшихся облака дают неровный «живописный» край.
var cards: SurfaceTool = null

func clump(st: SurfaceTool, c: Vector3, sc: Vector3, shade: float) -> void:
	leafblob(st, cards, c, sc, shade)
	for i in rng.randi_range(0, 1):
		var o := Vector3(R(-0.6, 0.6), R(-0.2, 0.4), R(-0.6, 0.6)) * sc
		leafblob(st, cards, c + o, sc * R(0.55, 0.75), clampf(shade + R(-0.2, 0.3), 0.0, 1.0))

## Облако листвы: искажённая шумом сфера, нормали — от центра (мягкий объём), чуть вверх.
func blob(st: SurfaceTool, c: Vector3, sc: Vector3, shade: float, autumn_k: float = 1.0) -> void:
	var verts: Array = _ico0[0] if lod else _ico[0]
	var faces: Array = _ico0[1] if lod else _ico[1]
	var off := R(0, 100)
	var pts: Array = []
	for p in verts:
		var q: Vector3 = p
		var n := 1.0 + 0.25 * sin(q.x * 3.1 + off) * cos(q.z * 2.7 + off) + 0.15 * sin(q.y * 5.3 + off * 2.0) + 0.06 * sin(q.x * 17.3 + q.y * 11.1 + q.z * 7.7 + off)
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
		var rr := r * (R(0.95, 1.08) if i % 2 == 0 else R(0.7, 0.82))
		var dy := -r * (0.38 if i % 2 == 0 else 0.22) + R(-0.06, 0.06)
		ring.append(Vector3(cos(a) * rr, y + dy, sin(a) * rr))
	var inner := Vector3(0, y + h * 0.25, 0)
	if cards != null:
		for i in range(0, n, 2):
			var tip: Vector3 = ring[i]
			var outv := Vector3(tip.x, 0, tip.z).normalized()
			for corner in [[0, 0], [1, 0], [1, 1], [0, 0], [1, 1], [0, 1]]:
				cards.set_color(Color(clampf(shade + CR(-0.15, 0.15), 0.0, 1.0), 0, 0, 1))
				cards.set_normal((outv * 0.8 + Vector3(0, 0.6, 0)).normalized())
				cards.set_uv(Vector2(corner[0], corner[1]))
				cards.set_uv2(Vector2(r * 0.17 + 0.08, CR(0, TAU)))
				cards.add_vertex(tip - outv * r * 0.12)
	for i in n:
		var a: Vector3 = ring[i]
		var b: Vector3 = ring[(i + 1) % n]
		for v in [top, b, a]:
			var d: Vector3 = v - Vector3(0, y, 0)
			var nrm := (Vector3(d.x, 0, d.z).normalized() * 0.9 + Vector3(0, 0.55, 0)).normalized() if v != top else Vector3.UP
			st.set_color(Color(shade * (0.75 if v == top else 1.0), 0, 0, 1))
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
		if st == null:
			continue
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
	var H := R(7.0, 11.0)
	var bk := _st()
	var fl := _st()
	cards = null if lod else _st()
	trunk(bk, Vector3.ZERO, Vector3(0, H * 0.5, 0), Vector3(0, H * 0.9, 0), 0.24, 0.05, 2, 6)
	var tiers := rng.randi_range(8, 11)
	var R0 := H * R(0.2, 0.25)
	for i in tiers:
		var t := float(i) / tiers
		var y := lerpf(H * 0.14, H * 0.86, t)
		var r := R0 * (1.0 - t * 0.85) * R(0.9, 1.1)
		skirt(fl, y, r, r * 0.7 + 0.4, rng.randi_range(9, 13), lerpf(0.5, 1.0, t))
	skirt(fl, H * 0.9, 0.35, H * 0.12, 4, 1.0)
	var out := [_mesh([[bk, "bark"], [fl, "spruce"], [cards, "spruce_card"]]), H]
	cards = null
	return out

## Сосна: высокий рыжий ствол, несколько плоских облаков наверху.
func pine(seed_v: int) -> Array:
	rng.seed = seed_v
	var H := R(11.0, 15.0)
	var bk := _st()
	var fl := _st()
	cards = null if lod else _st()
	var top := Vector3(R(-0.6, 0.6), H, R(-0.6, 0.6))
	trunk(bk, Vector3.ZERO, Vector3(R(-0.3, 0.3), H * 0.5, R(-0.3, 0.3)), top, 0.28, 0.08, 4, 6)
	for i in rng.randi_range(3, 5):
		var a := R(0, TAU)
		var y := H * R(0.68, 0.96)
		var d := R(0.6, 2.0)
		var c := Vector3(cos(a) * d, y, sin(a) * d) + top * Vector3(1, 0, 1) * (y / H)
		trunk(bk, Vector3(top.x * y / H * 0.8, y - 0.8, top.z * y / H * 0.8), (Vector3(top.x * y / H, y - 0.6, top.z * y / H) + c) * 0.5, c, 0.07, 0.03, 1, 4)
		clump(fl, c + Vector3(0, 0.3, 0), Vector3(R(1.3, 2.0), R(0.6, 0.9), R(1.3, 2.0)), R(0.4, 1.0))
	return [_mesh([[bk, "bark_pine"], [fl, "pine"], [cards, "pine_card"]]), H]

## Берёза: белый ствол с наклоном, вертикальные лёгкие облака.
func birch(seed_v: int, kind: String = "birch") -> Array:
	rng.seed = seed_v
	var H := R(8.0, 11.0)
	var bk := _st()
	var fl := _st()
	cards = null if lod else _st()
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
		clump(fl, c, Vector3(R(0.8, 1.2), R(0.8, 1.3), R(0.8, 1.2)) * (1.0 - t * 0.3), R(0.3, 1.0))
	var lk := kind if kind in ["birch", "larch"] else "leaf"
	return [_mesh([[bk, "bark_birch"], [fl, lk], [cards, lk + "_card"]]), H]

func bush(seed_v: int) -> Array:
	rng.seed = seed_v
	var fl := _st()
	cards = null if lod else _st()
	for i in rng.randi_range(2, 4):
		var a := R(0, TAU)
		var d := R(0.1, 0.6)
		leafblob(fl, cards, Vector3(cos(a) * d, R(0.35, 0.7), sin(a) * d), Vector3(R(0.45, 0.7), R(0.4, 0.6), R(0.45, 0.7)), R(0.3, 1.0))
	return [_mesh([[fl, "bush"], [cards, "bush_card"]]), 1.0]

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
	return [_mesh([[st, "rock"]]), sc.y, sc]

## Пучок травы: три перекрещенные карточки с мазками травинок.
func tuft(seed_v: int, tall: float = 1.0) -> Array:
	rng.seed = seed_v
	var st := _st()
	var h := R(0.3, 0.45) * tall
	var w := R(0.35, 0.5)
	for k in 5:
		var a := TAU * k / 5.0 + R(-0.25, 0.25)
		var o := Vector3(cos(a), 0, sin(a))
		var d := Vector3(-o.z, 0, o.x) * w * 0.5
		# карточка наклонена наружу — сверху пучок читается веером, а не крестом
		var lean := o * h * R(0.5, 0.8)
		var sh := R(0.0, 1.0)
		var pts := [[-d * 0.6, Vector2(0, 1)], [d * 0.6, Vector2(1, 1)], [d + Vector3(0, h * 0.8, 0) + lean, Vector2(1, 0)], [-d + Vector3(0, h * 0.8, 0) + lean, Vector2(0, 0)]]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_color(Color(sh, 0, 0, 1))
			st.set_normal(Vector3.UP)
			st.set_uv(pts[idx][1])
			st.add_vertex(pts[idx][0])
	return [_mesh([[st, "tuft"]]), h]

## Круглая крышка (срез пня, торец бревна).
func disc(st: SurfaceTool, c: Vector3, nrm: Vector3, r: float, seg: int = 10) -> void:
	var t := nrm.cross(Vector3.UP if absf(nrm.y) < 0.9 else Vector3.RIGHT).normalized()
	var b := nrm.cross(t)
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		for v in [[c, Vector2(0.5, 0.5)], [c + (t * cos(a0) + b * sin(a0)) * r, Vector2(0.5 + cos(a0) * 0.5, 0.5 + sin(a0) * 0.5)], [c + (t * cos(a1) + b * sin(a1)) * r, Vector2(0.5 + cos(a1) * 0.5, 0.5 + sin(a1) * 0.5)]]:
			st.set_normal(nrm)
			st.set_uv(v[1])
			st.add_vertex(v[0])

## Папоротник: 6–9 вай из мазков, раскинутых веером.
func fern(seed_v: int) -> Array:
	rng.seed = seed_v
	var core := _st()
	cards = null if lod else _st()
	blob(core, Vector3(0, 0.15, 0), Vector3(0.25, 0.15, 0.25), 0.2)
	for i in rng.randi_range(6, 9):
		var a := R(0, TAU)
		var d := Vector3(cos(a), 0, sin(a))
		var L := R(0.6, 1.0)
		for k in 4:
			var t := (k + 0.5) / 4.0
			var p := d * L * t + Vector3(0, 0.45 * sin(t * PI * 0.8) + 0.1, 0)
			for corner in [[0, 0], [1, 0], [1, 1], [0, 0], [1, 1], [0, 1]]:
				cards.set_color(Color(R(0.3, 1.0), 0, 0, 1))
				cards.set_normal((d * 0.4 + Vector3.UP).normalized())
				cards.set_uv(Vector2(corner[0], corner[1]))
				cards.set_uv2(Vector2(0.22 * (1.1 - t * 0.5), R(0, TAU)))
				cards.add_vertex(p)
	return [_mesh([[core, "fern"], [cards, "fern_card"]]), 0.6]

## Камыш: высокие пучки штрихов.
func reeds(seed_v: int) -> Array:
	var r: Array = tuft(seed_v, 3.2)
	var mesh: ArrayMesh = r[0]
	mesh.surface_set_material(0, mats["reed"])
	return r

## Хворост: пара сухих веток на земле.
func twig(seed_v: int) -> Array:
	rng.seed = seed_v
	var st := _st()
	for i in rng.randi_range(2, 3):
		var a := R(0, TAU)
		var d := Vector3(cos(a), 0, sin(a))
		var L := R(0.6, 1.1)
		trunk(st, -d * L * 0.5 + Vector3(0, 0.03, 0), Vector3(R(-0.1, 0.1), 0.06, R(-0.1, 0.1)), d * L * 0.5 + Vector3(0, 0.03, 0), 0.025, 0.012, 2, 4)
	return [_mesh([[st, "bark_dead"]]), 0.1]

## Ягодный куст: облако листвы и россыпь ягод.
func berry_bush(seed_v: int) -> Array:
	rng.seed = seed_v
	var fl := _st()
	cards = null if lod else _st()
	var bs := _st()
	leafblob(fl, cards, Vector3(0, 0.3, 0), Vector3(0.4, 0.3, 0.4), R(0.4, 0.9))
	for i in 14:
		var a := R(0, TAU)
		var p := Vector3(cos(a) * R(0.2, 0.42), R(0.15, 0.55), sin(a) * R(0.2, 0.42))
		blob(bs, p, Vector3.ONE * 0.045, R(0.5, 1.0))
	return [_mesh([[fl, "bush"], [cards, "bush_card"], [bs, "berry"]]), 0.6]

## Гриб: ножка и шляпка (красная — мухомор).
func mushroom(seed_v: int, red: bool) -> Array:
	rng.seed = seed_v
	var stem := _st()
	var cap := _st()
	var h := R(0.1, 0.18)
	trunk(stem, Vector3.ZERO, Vector3(0, h * 0.5, 0), Vector3(0, h, 0), 0.025, 0.02, 1, 6)
	blob(cap, Vector3(0, h, 0), Vector3(0.075, 0.04, 0.075), 0.8)
	return [_mesh([[stem, "stem"], [cap, "cap_red" if red else "cap_brown"]]), h]

## Пень: широкий низкий ствол с корнями и светлым срезом.
func stump(seed_v: int) -> Array:
	rng.seed = seed_v
	var st := _st()
	var top := _st()
	trunk(st, Vector3.ZERO, Vector3(0, 0.35, 0), Vector3(0, 0.75, 0), 0.55, 0.45, 2, 9)
	for i in 4:
		var a := TAU * i / 4 + R(-0.4, 0.4)
		var d := Vector3(cos(a), 0, sin(a))
		trunk(st, d * 0.3 + Vector3(0, 0.3, 0), d * 0.75 + Vector3(0, 0.08, 0), d * R(1.1, 1.4) + Vector3(0, -0.1, 0), 0.15, 0.04, 2, 5)
	disc(top, Vector3(0, 0.75, 0), Vector3.UP, 0.45)
	return [_mesh([[st, "log"], [top, "cut"]]), 0.75]

## Бревно: лежит вдоль X, торцы со срезом.
func log_fallen(seed_v: int) -> Array:
	rng.seed = seed_v
	var st := _st()
	var ends := _st()
	var L := 4.6
	trunk(st, Vector3(-L * 0.5, 0.3, 0), Vector3(0, 0.36, R(-0.15, 0.15)), Vector3(L * 0.5, 0.28, 0), 0.33, 0.27, 4, 9)
	for i in 2:
		var x := R(-L * 0.35, L * 0.35)
		trunk(st, Vector3(x, 0.45, 0), Vector3(x + R(-0.2, 0.2), 0.75, R(0.15, 0.3)), Vector3(x + R(-0.4, 0.4), 0.95, R(0.4, 0.7)), 0.05, 0.015, 2, 4)
	disc(ends, Vector3(-L * 0.5, 0.3, 0), Vector3.LEFT, 0.33)
	disc(ends, Vector3(L * 0.5, 0.28, 0), Vector3.RIGHT, 0.27)
	return [_mesh([[st, "log"], [ends, "cut"]]), 0.6]

## Муравейник: бурый холмик.
func anthill(seed_v: int) -> Array:
	rng.seed = seed_v
	var st := _st()
	blob(st, Vector3(0, 0.0, 0), Vector3(0.7, 0.65, 0.7), 0.6)
	return [_mesh([[st, "anthill"]]), 0.6]

## Сухая ель: голый ствол с короткими серыми сучьями.
func dead_tree(seed_v: int) -> Array:
	rng.seed = seed_v
	var st := _st()
	var H := R(6.0, 10.0)
	trunk(st, Vector3.ZERO, Vector3(R(-0.3, 0.3), H * 0.5, R(-0.3, 0.3)), Vector3(R(-0.4, 0.4), H, R(-0.4, 0.4)), 0.22, 0.04, 3, 6)
	var y := 1.5
	while y < H - 0.5:
		var a := R(0, TAU)
		var d := Vector3(cos(a), R(-0.3, 0.1), sin(a)).normalized()
		var L := (1.0 - y / H) * 1.8 + 0.3
		trunk(st, Vector3(0, y, 0), Vector3(0, y, 0) + d * L * 0.5, Vector3(0, y, 0) + d * L + Vector3(0, -0.2, 0), 0.04, 0.01, 1, 4)
		y += R(0.5, 0.9)
	return [_mesh([[st, "bark_dead"]]), H]
