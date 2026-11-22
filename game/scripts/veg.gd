extends RefCounted
## Генератор растительности в стиле 4: ветки геометрией, хвоя и листва карточками-текстурами.
## Каждый build_* возвращает ArrayMesh (поверхности: кора, карточки, [сердцевина]) и высоту.

const CARD_SHADER := preload("res://shaders/card.gdshader")

var rng := RandomNumberGenerator.new()
var mats := {}

func _init() -> void:
	for k in ["bark_spruce", "bark_pine", "bark_birch", "bark_dead"]:
		var m := StandardMaterial3D.new()
		m.albedo_texture = load("res://textures/%s.png" % k)
		m.roughness = 1.0
		mats[k] = m
	_card("needle", Color(0.78, 0.86, 0.70), 0.03)
	_card("pine", Color(0.80, 0.84, 0.68), 0.03)
	_card("birch_leaf", Color(0.86, 0.90, 0.70), 0.06)
	_card("broad_leaf", Color(0.78, 0.84, 0.66), 0.05)
	_card("fern", Color(0.72, 0.80, 0.62), 0.08)
	_card("grass", Color(0.86, 0.88, 0.70), 0.12)
	var core := StandardMaterial3D.new()
	core.albedo_color = Color(0.07, 0.13, 0.08)
	core.roughness = 1.0
	mats["core"] = core

func _card(k: String, tint: Color, sway: float) -> void:
	var m := ShaderMaterial.new()
	m.shader = CARD_SHADER
	m.set_shader_parameter("tex", load("res://textures/%s.png" % k))
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("sway", sway)
	mats[k] = m

func R(a: float, b: float) -> float:
	return rng.randf_range(a, b)

# ---------- геометрия ----------

class Surf:
	var st := SurfaceTool.new()
	var n := 0
	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
	func v(p: Vector3, nor: Vector3, uv: Vector2, c: Color = Color.WHITE) -> void:
		st.set_normal(nor)
		st.set_uv(uv)
		st.set_color(c)
		st.add_vertex(p)
		n += 1
	func tri(a: int, b: int, c: int) -> void:
		st.add_index(a); st.add_index(b); st.add_index(c)

func _bez(p0: Vector3, p1: Vector3, p2: Vector3, t: float) -> Vector3:
	return p0 * (1 - t) * (1 - t) + p1 * 2 * (1 - t) * t + p2 * t * t

func _bez_d(p0: Vector3, p1: Vector3, p2: Vector3, t: float) -> Vector3:
	return ((p1 - p0) * 2 * (1 - t) + (p2 - p1) * 2 * t).normalized()

## Изогнутая сужающаяся труба по кривой Безье: ствол, ветка, корень.
func tube(s: Surf, p0: Vector3, p1: Vector3, p2: Vector3, r0: float, r1: float, seg: int = 6, rad: int = 6) -> void:
	var length := p0.distance_to(p1) + p1.distance_to(p2)
	var base := s.n
	for i in seg + 1:
		var t := float(i) / seg
		var p := _bez(p0, p1, p2, t)
		var tg := _bez_d(p0, p1, p2, t)
		var ref := Vector3.RIGHT if absf(tg.y) > 0.9 else Vector3.UP
		var nn := tg.cross(ref).normalized()
		var bb := tg.cross(nn).normalized()
		var r := lerpf(r0, r1, t)
		for j in rad + 1:
			var a := TAU * j / rad
			var d := nn * cos(a) + bb * sin(a)
			s.v(p + d * r, d, Vector2(float(j) / rad, t * length * 0.5))
	for i in seg:
		for j in rad:
			var a := base + i * (rad + 1) + j
			var b := a + rad + 1
			s.tri(a, b, a + 1)
			s.tri(b, b + 1, a + 1)

## Карточка: прямоугольник с текстурой. Нормали приподняты вверх, чтобы крона светилась мягко.
func card(s: Surf, pos: Vector3, basis: Basis, w: float, h: float, shade: float = 1.0) -> void:
	var x := basis.x * w * 0.5
	var y := basis.y * h
	var face := basis.z
	var c := Color(shade, shade, shade)
	var base := s.n
	var pts := [pos - x, pos + x, pos + x + y, pos - x + y]
	var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for i in 4:
		var off: Vector3 = (pts[i] - pos - y * 0.5).normalized()
		var nor := (face * 0.3 + off * 0.5 + Vector3.UP).normalized()
		s.v(pts[i], nor, uvs[i], c)
	s.tri(base, base + 1, base + 2)
	s.tri(base, base + 2, base + 3)

func _basis_along(dir: Vector3, roll: float) -> Basis:
	var y := dir.normalized()
	var ref := Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z) * Basis(Vector3.UP, roll)

func _rand_dir(d: Vector3, ang: float) -> Vector3:
	var ax := Vector3(R(-1, 1), R(-1, 1), R(-1, 1)).cross(d)
	if ax.length() < 0.01:
		ax = Vector3.RIGHT
	return d.rotated(ax.normalized(), ang).normalized()

func _commit(surfs: Array, mat_keys: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for i in surfs.size():
		var s: Surf = surfs[i]
		if s.n == 0:
			continue
		s.st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mats[mat_keys[i]])
	return mesh

# ---------- породы ----------

## Ель: ярусы свисающих лап, хвоя карточками в два слоя, тёмная сердцевина для объёма.
func spruce(seed_v: int, dead: bool = false) -> Array:
	rng.seed = seed_v
	var H := R(10.0, 15.0)
	var bark := Surf.new()
	var nd := Surf.new()
	var core := Surf.new()
	tube(bark, Vector3.ZERO, Vector3(R(-0.2, 0.2), H * 0.5, R(-0.2, 0.2)), Vector3(0, H, 0), 0.32, 0.03, 8, 8)
	var h := 1.3
	while h < H - 0.4:
		var f := 1.0 - h / H
		var cnt := rng.randi_range(6, 8)
		for b in cnt:
			var a := TAU * b / cnt + R(-0.3, 0.3) + h * 1.7
			var L := (f * 3.6 + 0.45) * R(0.85, 1.1)
			var st := Vector3(0, h, 0)
			var d := Vector3(cos(a), R(-0.25, -0.05) + (1.0 - f) * 0.35, sin(a)).normalized()
			var mid := st + d * L * 0.5 + Vector3(0, -L * 0.12, 0)
			var en := st + d * L + Vector3(0, -L * (0.05 if dead else 0.1) + L * 0.06, 0)
			if L > 0.9 or dead:
				tube(bark, st, mid, en, 0.05 * (f + 0.4), 0.01, 3, 4)
			if dead:
				continue
			var k := maxi(3, ceili(L / 0.27))
			for i in k:
				var t := (i + 0.5) / k
				var p := _bez(st, mid, en, t)
				var tg := _bez_d(st, mid, en, t)
				var sz := (0.75 + f * 0.55) * R(0.9, 1.25)
				var shade := R(0.75, 1.05) * (0.8 + 0.2 * (1.0 - t))
				# слой 1: лежит вдоль лапы почти горизонтально
				var b1 := _basis_along(tg, R(-0.45, 0.45))
				card(nd, p - tg * sz * 0.5, b1, sz * 0.85, sz * 1.2, shade)
				# слой 2: под углом, даёт объём и густоту
				var b2 := _basis_along(tg, R(0.9, 1.4))
				card(nd, p - tg * sz * 0.45 + Vector3(0, 0.06, 0), b2, sz * 0.7, sz * 1.05, shade * 0.9)
		h += R(0.30, 0.42)
	if not dead:
		# верхушка
		card(nd, Vector3(0, H - 0.9, 0), Basis.IDENTITY, 0.7, 1.4)
		card(nd, Vector3(0, H - 0.9, 0), Basis(Vector3.UP, PI * 0.5), 0.7, 1.4)
		# сердцевина: тёмный конус внутри кроны, чтобы ель не просвечивала
		var cone := CylinderMesh.new()
		cone.top_radius = 0.05
		cone.bottom_radius = 1.9
		cone.height = H - 2.2
		cone.radial_segments = 10
		cone.rings = 1
		var arr := cone.get_mesh_arrays()
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var base := core.n
		for i in verts.size():
			core.v(verts[i] + Vector3(0, 1.3 + (H - 2.2) * 0.5, 0), norms[i], Vector2.ZERO)
		for i in range(0, idx.size(), 3):
			core.tri(base + idx[i], base + idx[i + 1], base + idx[i + 2])
	return [_commit([bark, nd, core], ["bark_dead" if dead else "bark_spruce", "needle", "core"]), H]

## Ветвистое дерево: сосна, берёза, лиственное или голое (без листвы).
func branchy(seed_v: int, kind: String) -> Array:
	rng.seed = seed_v
	var P := {
		"pine": {"H": R(12, 15), "r": 0.3, "start": 0.62, "lv": 3, "spread": 0.9, "leaf": "pine", "cs": 1.6, "bark": "bark_pine", "n": 3},
		"birch": {"H": R(8, 11), "r": 0.17, "start": 0.5, "lv": 3, "spread": 0.6, "leaf": "birch_leaf", "cs": 0.95, "bark": "bark_birch", "n": 3},
		"bare": {"H": R(7, 10), "r": 0.22, "start": 0.35, "lv": 4, "spread": 0.75, "leaf": "", "cs": 0.0, "bark": "bark_dead", "n": 3},
		"bare_birch": {"H": R(8, 10), "r": 0.17, "start": 0.45, "lv": 4, "spread": 0.6, "leaf": "", "cs": 0.0, "bark": "bark_birch", "n": 3},
	}[kind]
	var bark := Surf.new()
	var lf := Surf.new()
	_grow(bark, lf, P, Vector3(0, -0.2, 0), Vector3(R(-0.06, 0.06), 1, R(-0.06, 0.06)).normalized(), P["H"], P["r"], 0, kind)
	var keys := [P["bark"], P["leaf"] if P["leaf"] != "" else P["bark"]]
	return [_commit([bark, lf], keys), P["H"] * 1.1]

func _grow(bark: Surf, lf: Surf, P: Dictionary, st: Vector3, d: Vector3, L: float, r: float, lv: int, kind: String) -> void:
	var bend := _rand_dir(d, R(0.02, 0.06) if lv == 0 else R(0.1, 0.3))
	var mid := st + d * L * 0.5
	var en := st + bend * L
	if kind.begins_with("birch") and lv >= 2:
		en.y -= L * 0.15
	tube(bark, st, mid, en, r, r * 0.62, 8 if lv == 0 else 4, 8 if lv == 0 else 5)
	var maxlv: int = P["lv"]
	if P["leaf"] != "" and (lv >= maxlv - 1 or (lv >= 1 and rng.randf() < 0.25)):
		var k := 7 if kind == "birch" else 5
		var cs: float = P["cs"]
		for i in k:
			var p := _bez(st, mid, en, R(0.3, 1.0)) + Vector3(R(-0.5, 0.5), R(-0.4, 0.4), R(-0.5, 0.5)) * cs
			var b := Basis.from_euler(Vector3(R(-1.2, 1.2), R(0, TAU), R(-1.2, 1.2)))
			if kind == "birch":
				b = Basis.from_euler(Vector3(R(-0.3, 0.3), R(0, TAU), R(-0.3, 0.3)))
			var sz := cs * R(0.8, 1.2)
			card(lf, p - b.y * sz * 0.5, b, sz, sz * (1.6 if kind == "birch" else 1.0), R(0.8, 1.05))
	if lv >= maxlv:
		return
	var n: int = P["n"] + (1 if lv == 0 else 0)
	for i in n:
		var t := R(P["start"], 1.0) if lv == 0 else R(0.4, 1.0)
		var p := _bez(st, mid, en, t)
		var nd := _rand_dir(_bez_d(st, mid, en, t), R(0.4, P["spread"] * 1.3))
		if kind.contains("birch") and nd.y < 0.35:
			nd.y = 0.35
			nd = nd.normalized()
		_grow(bark, lf, P, p, nd, L * R(0.5, 0.72), r * 0.55 * (1.0 - t * 0.3), lv + 1, kind)

## Куст: шар из листовых карточек.
func bush(seed_v: int) -> Array:
	rng.seed = seed_v
	var lf := Surf.new()
	var bark := Surf.new()
	for i in 5:
		tube(bark, Vector3.ZERO, Vector3(R(-0.2, 0.2), 0.4, R(-0.2, 0.2)), Vector3(R(-0.5, 0.5), R(0.7, 1.0), R(-0.5, 0.5)), 0.03, 0.01, 3, 4)
	for i in 34:
		var d := Vector3(R(-1, 1), R(-0.2, 1), R(-1, 1)).normalized()
		var p := Vector3(0, 0.55, 0) + d * R(0.3, 0.75)
		var b := Basis.from_euler(Vector3(R(0, 6), R(0, 6), R(0, 6)))
		card(lf, p - b.y * 0.45, b, 0.9, 0.9, R(0.8, 1.05))
	return [_commit([bark, lf], ["bark_dead", "broad_leaf"]), 1.2]

## Папоротник: веер из листьев-вай.
func fern(seed_v: int) -> Array:
	rng.seed = seed_v
	var lf := Surf.new()
	var n := rng.randi_range(7, 11)
	for i in n:
		var a := TAU * i / n + R(-0.2, 0.2)
		var d := Vector3(cos(a) * R(0.6, 1.0), R(0.5, 0.9), sin(a) * R(0.6, 1.0)).normalized()
		var L := R(0.8, 1.2)
		card(lf, Vector3.ZERO, _basis_along(d, R(-0.4, 0.4)), L * 0.32, L, R(0.85, 1.05))
	return [_commit([lf], ["fern"]), 1.0]

## Пучок травы: две скрещённые карточки.
func grass(seed_v: int) -> Array:
	rng.seed = seed_v
	var lf := Surf.new()
	var a := R(0, PI)
	for k in 2:
		card(lf, Vector3.ZERO, Basis(Vector3.UP, a + k * PI * 0.5), 1.0, 0.8, R(0.85, 1.05))
	return [_commit([lf], ["grass"]), 0.8]

## Камень: искажённая сфера, мох сверху (цвет вершин).
func rock(seed_v: int) -> Array:
	rng.seed = seed_v
	var sph := SphereMesh.new()
	sph.radial_segments = 20
	sph.rings = 12
	var arr := sph.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var noise := FastNoiseLite.new()
	noise.seed = seed_v
	noise.frequency = 1.3
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sx := R(1.0, 1.6)
	var sz := R(0.9, 1.4)
	for i in verts.size():
		var v := verts[i]
		var k := 1.0 + noise.get_noise_3dv(v * 1.5) * 0.35 + noise.get_noise_3dv(v * 5.0) * 0.06
		v = Vector3(v.x * sx, v.y * 0.6, v.z * sz) * k
		var moss := clampf((v.y + 0.05) * 3.0, 0.0, 1.0) * clampf(noise.get_noise_3dv(v * 3.0) + 0.6, 0.0, 1.0)
		var c := Color(0.50, 0.49, 0.45).lerp(Color(0.30, 0.37, 0.18), moss)
		c = c.darkened(R(0.0, 0.08))
		st.set_color(c)
		st.add_vertex(v)
	for i in idx:
		st.add_index(i)
	st.generate_normals()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.95
	st.set_material(m)
	return [st.commit(), 0.6]

## Пень с корнями.
func stump(seed_v: int) -> Array:
	rng.seed = seed_v
	var bark := Surf.new()
	tube(bark, Vector3.ZERO, Vector3(0, 0.35, 0), Vector3(0, 0.75, 0), 0.55, 0.45, 3, 12)
	for i in 5:
		var a := TAU * i / 5 + R(-0.3, 0.3)
		var d := Vector3(cos(a), 0, sin(a))
		tube(bark, d * 0.35 + Vector3(0, 0.3, 0), d * 0.8 + Vector3(0, 0.08, 0), d * R(1.2, 1.6) + Vector3(0, -0.1, 0), 0.16, 0.04, 5, 6)
	return [_commit([bark], ["bark_dead"]), 0.75]

## Упавшее бревно.
func log_fallen(seed_v: int) -> Array:
	rng.seed = seed_v
	var bark := Surf.new()
	var L := R(4.0, 6.0)
	tube(bark, Vector3(-L * 0.5, 0.3, 0), Vector3(0, 0.38, R(-0.2, 0.2)), Vector3(L * 0.5, 0.28, 0), 0.34, 0.26, 10, 10)
	for i in 3:
		var x := R(-L * 0.4, L * 0.4)
		tube(bark, Vector3(x, 0.4, 0), Vector3(x + R(-0.3, 0.3), 0.8, R(0.2, 0.4)), Vector3(x + R(-0.5, 0.5), 1.1, R(0.5, 0.9)), 0.06, 0.015, 4, 5)
	return [_commit([bark], ["bark_dead"]), 0.6]
