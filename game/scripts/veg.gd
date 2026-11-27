extends RefCounted
## Генератор растительности в стиле 4: ветки геометрией, хвоя и листва карточками-текстурами.
## Каждый build_* возвращает ArrayMesh (поверхности: кора, карточки, [сердцевина]) и высоту.

var lod := false
const CARD_SHADER := preload("res://shaders/card.gdshader")
const BLADE_SHADER := preload("res://shaders/grass_blade.gdshader")
const ROCK_SHADER := preload("res://shaders/rock.gdshader")

var rng := RandomNumberGenerator.new()
var mats := {}
var fade_list: Array = []

func _init() -> void:
	for k in ["bark_spruce", "bark_pine", "bark_birch", "bark_dead"]:
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/bark.gdshader")
		m.set_shader_parameter("tex", load("res://textures/%s.png" % k))
		mats[k] = m
		fade_list.append(m)
	_card("needle", Color(0.86, 0.96, 0.78), 0.03)
	_card("pine", Color(0.88, 0.95, 0.76), 0.03)
	_card("birch_leaf", Color(0.92, 0.98, 0.78), 0.06, 1.0, 1.0)
	_card("broad_leaf", Color(0.86, 0.92, 0.74), 0.05, 1.0, 1.0)
	_card("fern", Color(0.84, 0.92, 0.68), 0.08, 0.9, 0.8)
	_card("grass", Color(0.92, 0.96, 0.78), 0.12, 0.7, 0.0)
	_card("reed", Color(0.96, 1.0, 0.82), 0.07, 0.6, 0.0)
	_card("needle", Color(0.95, 1.05, 0.62), 0.04, 1.0, 1.0, "larch")
	_card("broad_leaf", Color(0.84, 0.92, 0.7), 0.09, 1.0, 1.0, "aspen")
	mats["aspen"].set_shader_parameter("fall_red", 1.0)
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var white := ImageTexture.create_from_image(img)
	for pair in [["berry", Color(0.62, 0.08, 0.1)], ["cap_red", Color(0.72, 0.12, 0.08)], ["cap_brown", Color(0.42, 0.27, 0.15)], ["stem", Color(0.85, 0.82, 0.74)]]:
		var sm := ShaderMaterial.new()
		sm.shader = load("res://shaders/bark.gdshader")
		sm.set_shader_parameter("tex", white)
		sm.set_shader_parameter("tint", pair[1])
		mats[pair[0]] = sm
		fade_list.append(sm)
	var wimg := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var dd := Vector2(x - 31.5, y - 31.5).length() / 32.0
			var ring := 0.5 + 0.5 * sin(dd * 38.0 + sin(atan2(y - 31.5, x - 31.5) * 3.0) * 0.6)
			var c := Color(0.72, 0.58, 0.4).lerp(Color(0.55, 0.42, 0.28), ring * 0.6)
			if dd > 0.9:
				c = Color(0.3, 0.22, 0.15)
			wimg.set_pixel(x, y, c)
	wimg.generate_mipmaps()
	var cut := ShaderMaterial.new()
	cut.shader = load("res://shaders/bark.gdshader")
	cut.set_shader_parameter("tex", ImageTexture.create_from_image(wimg))
	mats["cut"] = cut
	fade_list.append(cut)
	var lit := ShaderMaterial.new()
	lit.shader = load("res://shaders/bark.gdshader")
	lit.set_shader_parameter("tex", load("res://textures/ground_forest.png"))
	lit.set_shader_parameter("tint", Color(0.75, 0.6, 0.45))
	mats["litter"] = lit
	fade_list.append(lit)
	var blade := ShaderMaterial.new()
	blade.shader = BLADE_SHADER
	mats["blade"] = blade
	# брёвна, пни, ягоды, грибы и подстилка не растворяются: шейдер без discard (быстрее на мобильных)
	var solid := load("res://shaders/bark_solid.gdshader")
	var bds := ShaderMaterial.new()
	bds.shader = solid
	bds.set_shader_parameter("tex", load("res://textures/bark_dead.png"))
	mats["bark_dead_solid"] = bds
	fade_list.append(bds)
	for k in ["berry", "cap_red", "cap_brown", "stem", "cut", "litter"]:
		mats[k].shader = solid

func _card(k: String, tint: Color, sway: float, yellow: float = 0.0, drop: float = 0.0, key: String = "") -> void:
	var m := ShaderMaterial.new()
	m.shader = CARD_SHADER
	m.set_shader_parameter("tex", load("res://textures/%s.png" % k))
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("sway", sway)
	m.set_shader_parameter("yellow_k", yellow)
	m.set_shader_parameter("drop_k", drop)
	mats[key if key != "" else k] = m
	fade_list.append(m)

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
	var urep := maxf(1.0, roundf(TAU * r0 * 1.3))
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
			s.v(p + d * r, d, Vector2(float(j) / rad * urep, t * length * 0.5))
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
	tube(bark, Vector3.ZERO, Vector3(R(-0.2, 0.2), H * 0.5, R(-0.2, 0.2)), Vector3(0, H, 0), 0.32, 0.03, 3 if lod else 8, 5 if lod else 8)
	var h := 1.3
	while h < H - 0.4:
		var f := 1.0 - h / H
		var cnt := rng.randi_range(4, 5) if lod else rng.randi_range(6, 8)
		for b in cnt:
			var a := TAU * b / cnt + R(-0.3, 0.3) + h * 1.7
			var L := (f * 3.6 + 0.45) * R(0.85, 1.1)
			var st := Vector3(0, h, 0)
			var d := Vector3(cos(a), R(-0.25, -0.05) + (1.0 - f) * 0.35, sin(a)).normalized()
			var mid := st + d * L * 0.5 + Vector3(0, -L * 0.12, 0)
			var en := st + d * L + Vector3(0, -L * (0.05 if dead else 0.1) + L * 0.06, 0)
			if (L > 0.9 and not lod) or dead:
				tube(bark, st, mid, en, 0.05 * (f + 0.4), 0.01, 2 if lod else 3, 3 if lod else 4)
			if dead:
				continue
			var k := maxi(2, ceili(L / 0.6)) if lod else maxi(3, ceili(L / 0.27))
			for i in k:
				var t := (i + 0.5) / k
				var p := _bez(st, mid, en, t)
				var tg := _bez_d(st, mid, en, t)
				var sz := (0.75 + f * 0.55) * R(0.9, 1.25) * (1.7 if lod else 1.0)
				var shade := R(0.75, 1.05) * (0.8 + 0.2 * (1.0 - t))
				# слой 1: лежит вдоль лапы почти горизонтально
				var b1 := _basis_along(tg, R(-0.45, 0.45))
				card(nd, p - tg * sz * 0.5, b1, sz * 0.85, sz * 1.2, shade)
				if lod:
					continue
				# слой 2: под углом, даёт объём и густоту
				var b2 := _basis_along(tg, R(0.9, 1.4))
				card(nd, p - tg * sz * 0.45 + Vector3(0, 0.06, 0), b2, sz * 0.7, sz * 1.05, shade * 0.9)
		h += R(0.8, 1.0) if lod else R(0.30, 0.42)
	if not dead:
		# верхушка
		card(nd, Vector3(0, H - 0.9, 0), Basis.IDENTITY, 0.7, 1.4)
		card(nd, Vector3(0, H - 0.9, 0), Basis(Vector3.UP, PI * 0.5), 0.7, 1.4)
	return [_commit([bark, nd], ["bark_dead" if dead else "bark_spruce", "needle"]), H]

## Ветвистое дерево: сосна, берёза, лиственное или голое (без листвы).
func branchy(seed_v: int, kind: String) -> Array:
	rng.seed = seed_v
	var P: Dictionary = {
		"pine": {"H": R(12, 15), "r": 0.3, "start": 0.62, "lv": 3, "spread": 0.9, "leaf": "pine", "cs": 1.6, "bark": "bark_pine", "n": 3},
		"birch": {"H": R(8, 11), "r": 0.17, "start": 0.5, "lv": 3, "spread": 0.6, "leaf": "birch_leaf", "cs": 0.95, "bark": "bark_birch", "n": 3},
		"bare": {"H": R(7, 10), "r": 0.22, "start": 0.35, "lv": 4, "spread": 0.75, "leaf": "", "cs": 0.0, "bark": "bark_dead", "n": 3},
		"larch": {"H": R(13, 17), "r": 0.3, "start": 0.4, "lv": 3, "spread": 0.7, "leaf": "larch", "cs": 1.2, "bark": "bark_pine", "n": 4},
		"aspen": {"H": R(10, 14), "r": 0.2, "start": 0.55, "lv": 3, "spread": 0.6, "leaf": "aspen", "cs": 1.0, "bark": "bark_birch", "n": 3},
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
	if not lod:
		tube(bark, st, mid, en, r, r * 0.62, 8 if lv == 0 else 4, 8 if lv == 0 else 5)
	elif lv < 2:
		tube(bark, st, mid, en, r, r * 0.62, 3 if lv == 0 else 2, 5 if lv == 0 else 3)
	var maxlv: int = P["lv"]
	if P["leaf"] != "" and (lv >= maxlv - 1 or (lv >= 1 and rng.randf() < 0.25)):
		var k := 7 if kind == "birch" else 5
		var cs: float = P["cs"]
		if lod:
			k = 2
			cs *= 1.5
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

## Камень: угловатая глыба (ячеистый шум + хребтовый шум), мох сверху, трипланарная текстура скалы.
func rock(seed_v: int, detail: int = 2) -> Array:
	rng.seed = seed_v
	var sph := SphereMesh.new()
	sph.radial_segments = [10, 22, 32][detail]
	sph.rings = [6, 12, 18][detail]
	var arr := sph.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var cell := FastNoiseLite.new()
	cell.seed = seed_v
	cell.noise_type = FastNoiseLite.TYPE_CELLULAR
	cell.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	cell.frequency = 1.1
	var ridge := FastNoiseLite.new()
	ridge.seed = seed_v + 7
	ridge.frequency = 1.6
	ridge.fractal_octaves = 3
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var kind := seed_v % 4
	# 0 валун, 1 плоская плита, 2 высокая глыба, 3 колотая груда
	var sx := R(1.0, 1.6)
	var sz := R(0.9, 1.4)
	var sy: float = [0.62, 0.32, 1.0, 0.75][kind]
	var cs: float = [0.34, 0.2, 0.5, 0.62][kind]
	var tints := [Color(1.0, 1.0, 0.98), Color(1.0, 0.93, 0.82), Color(0.82, 0.86, 0.95), Color(0.92, 0.9, 0.88)]
	if kind == 2:
		sx *= 0.65
		sz *= 0.7
	for i in verts.size():
		var v := verts[i]
		var k: float = 1.0 + cell.get_noise_3dv(v * 1.7) * cs + (1.0 - absf(ridge.get_noise_3dv(v * 2.0)) - 0.6) * 0.3 + ridge.get_noise_3dv(v * 9.0) * 0.035
		v = Vector3(v.x * sx, v.y * sy, v.z * sz) * k
		var moss := clampf((v.y - 0.05) * 3.2, 0.0, 1.0) * clampf(ridge.get_noise_3dv(v * 3.0) + 0.65, 0.0, 1.0)
		var c: Color = tints[kind].lerp(Color(0.52, 0.66, 0.32), moss).darkened(R(0.0, 0.1))
		st.set_color(c)
		st.add_vertex(v)
	for i in idx:
		st.add_index(i)
	st.generate_normals()
	var m := ShaderMaterial.new()
	m.shader = ROCK_SHADER
	m.set_shader_parameter("rock", load("res://textures/ground_rock.png"))
	m.set_shader_parameter("tile", [0.55, 0.4, 0.75, 0.9][kind])
	fade_list.append(m)
	st.set_material(m)
	return [st.commit(), 0.6]

## Круглый срез (торец бревна, верх пня): диск с годичными кольцами.
func disc(s: Surf, c: Vector3, nrm: Vector3, r: float, seg: int = 14) -> void:
	var ref := Vector3.RIGHT if absf(nrm.y) > 0.9 else Vector3.UP
	var a1 := nrm.cross(ref).normalized()
	var a2 := nrm.cross(a1).normalized()
	var base := s.n
	s.v(c, nrm, Vector2(0.5, 0.5))
	for j in seg + 1:
		var a := TAU * j / seg
		s.v(c + (a1 * cos(a) + a2 * sin(a)) * r, nrm, Vector2(0.5 + cos(a) * 0.5, 0.5 + sin(a) * 0.5))
	for j in seg:
		s.tri(base, base + 1 + j, base + 2 + j)
		s.tri(base, base + 2 + j, base + 1 + j)

## Пень с корнями.
func stump(seed_v: int) -> Array:
	rng.seed = seed_v
	var bark := Surf.new()
	tube(bark, Vector3.ZERO, Vector3(0, 0.35, 0), Vector3(0, 0.75, 0), 0.55, 0.45, 3, 12)
	for i in 5:
		var a := TAU * i / 5 + R(-0.3, 0.3)
		var d := Vector3(cos(a), 0, sin(a))
		tube(bark, d * 0.35 + Vector3(0, 0.3, 0), d * 0.8 + Vector3(0, 0.08, 0), d * R(1.2, 1.6) + Vector3(0, -0.1, 0), 0.16, 0.04, 5, 6)
	var top := Surf.new()
	disc(top, Vector3(0, 0.75, 0), Vector3.UP, 0.45)
	return [_commit([bark, top], ["bark_dead_solid", "cut"]), 0.75]

## Упавшее бревно.
func log_fallen(seed_v: int) -> Array:
	rng.seed = seed_v
	var bark := Surf.new()
	var L := R(4.0, 6.0)
	tube(bark, Vector3(-L * 0.5, 0.3, 0), Vector3(0, 0.38, R(-0.2, 0.2)), Vector3(L * 0.5, 0.28, 0), 0.34, 0.26, 10, 10)
	for i in 3:
		var x := R(-L * 0.4, L * 0.4)
		tube(bark, Vector3(x, 0.4, 0), Vector3(x + R(-0.3, 0.3), 0.8, R(0.2, 0.4)), Vector3(x + R(-0.5, 0.5), 1.1, R(0.5, 0.9)), 0.06, 0.015, 4, 5)
	var ends := Surf.new()
	disc(ends, Vector3(-L * 0.5, 0.3, 0), Vector3.LEFT, 0.34)
	disc(ends, Vector3(L * 0.5, 0.28, 0), Vector3.RIGHT, 0.26)
	return [_commit([bark, ends], ["bark_dead_solid", "cut"]), 0.6]

## Клочок травы из ~50 тонких травинок с цветом по высоте. Клочки в сетке ~1 м сливаются в ковёр.
func grass_patch(seed_v: int) -> Array:
	rng.seed = seed_v
	var s := Surf.new()
	var tone := R(0.85, 1.1)
	for i in 50:
		var a := R(0, TAU)
		var r := sqrt(R(0.0, 1.0)) * 0.75
		var base := Vector3(cos(a) * r, 0, sin(a) * r)
		var h := R(0.2, 0.46)
		var w := R(0.013, 0.026)
		var dir := R(0, TAU)
		var lean := Vector3(cos(dir), 0, sin(dir)) * R(0.05, 0.3) * h
		var side := Vector3(cos(dir + PI * 0.5), 0, sin(dir + PI * 0.5)) * w
		var c0 := Color(0.05, 0.09, 0.03) * tone
		var c1 := Color(0.13, 0.21, 0.06).lerp(Color(0.2, 0.26, 0.08), R(0, 1)) * tone
		var c2 := Color(0.22, 0.3, 0.1).lerp(Color(0.32, 0.34, 0.12), R(0, 1) * R(0, 1)) * tone
		var p0 := base
		var p1 := base + lean * 0.35 + Vector3(0, h * 0.55, 0)
		var p2 := base + lean + Vector3(0, h, 0)
		var n := Vector3.UP
		var b := s.n
		s.v(p0 - side, n, Vector2.ZERO, c0)
		s.v(p0 + side, n, Vector2.ZERO, c0)
		s.v(p1 - side * 0.7, n, Vector2.ZERO, c1)
		s.v(p1 + side * 0.7, n, Vector2.ZERO, c1)
		s.v(p2, n, Vector2.ZERO, c2)
		s.tri(b, b + 1, b + 2)
		s.tri(b + 1, b + 3, b + 2)
		s.tri(b + 2, b + 3, b + 4)
	return [_commit([s], ["blade"]), 0.5]

## Камыш: три скрещённые карточки.
func reeds(seed_v: int) -> Array:
	rng.seed = seed_v
	var lf := Surf.new()
	var a := R(0, PI)
	for k in 3:
		card(lf, Vector3.ZERO, Basis(Vector3.UP, a + k * PI / 3.0), 1.1, 1.6, R(0.85, 1.05))
	return [_commit([lf], ["reed"]), 1.6]

## Сухая ветка на земле.
func twig(seed_v: int) -> Array:
	rng.seed = seed_v
	var bark := Surf.new()
	var L := R(0.8, 1.8)
	var d := Vector3(1, 0, R(-0.3, 0.3)).normalized()
	tube(bark, -d * L * 0.5 + Vector3(0, 0.04, 0), Vector3(0, R(0.05, 0.14), 0), d * L * 0.5 + Vector3(0, 0.04, 0), 0.035, 0.012, 4, 5)
	for i in rng.randi_range(1, 3):
		var t := R(-0.3, 0.3) * L
		var sd := Vector3(R(0.2, 0.8), 0, R(-1, 1)).normalized()
		tube(bark, d * t + Vector3(0, 0.05, 0), d * t + sd * 0.2 + Vector3(0, 0.1, 0), d * t + sd * R(0.35, 0.6) + Vector3(0, 0.05, 0), 0.015, 0.006, 3, 4)
	return [_commit([bark], ["bark_dead"]), 0.15]

## Ягодный куст (брусника/черника/шиповник): низкий куст с ягодами.
func berry_bush(seed_v: int) -> Array:
	rng.seed = seed_v
	var lf := Surf.new()
	var bark := Surf.new()
	var br := Surf.new()
	for i in 4:
		tube(bark, Vector3.ZERO, Vector3(R(-0.15, 0.15), 0.25, R(-0.15, 0.15)), Vector3(R(-0.35, 0.35), R(0.4, 0.6), R(-0.35, 0.35)), 0.02, 0.008, 3, 4)
	for i in 18:
		var d := Vector3(R(-1, 1), R(0.0, 1), R(-1, 1)).normalized()
		var p := Vector3(0, 0.3, 0) + d * R(0.15, 0.45)
		var b := Basis.from_euler(Vector3(R(0, 6), R(0, 6), R(0, 6)))
		card(lf, p - b.y * 0.25, b, 0.5, 0.5, R(0.75, 1.0))
	for i in 26:
		var d := Vector3(R(-1, 1), R(0.1, 1), R(-1, 1)).normalized()
		var p := Vector3(0, 0.3, 0) + d * R(0.3, 0.5)
		tube(br, p - Vector3(0, 0.025, 0), p, p + Vector3(0, 0.025, 0), 0.028, 0.02, 2, 5)
	return [_commit([bark, lf, br], ["bark_dead", "broad_leaf", "berry"]), 0.7]

## Гриб: ножка и шляпка (мухомор или боровик).
func mushroom(seed_v: int, red: bool) -> Array:
	rng.seed = seed_v
	var st := Surf.new()
	var cap := Surf.new()
	for i in rng.randi_range(1, 3):
		var o := Vector3(R(-0.25, 0.25), 0, R(-0.25, 0.25)) if i > 0 else Vector3.ZERO
		var h := R(0.1, 0.2)
		tube(st, o, o + Vector3(R(-0.02, 0.02), h * 0.5, 0), o + Vector3(R(-0.03, 0.03), h, R(-0.03, 0.03)), 0.022, 0.018, 3, 6)
		var top := o + Vector3(0, h, 0)
		var cr := R(0.06, 0.1)
		tube(cap, top - Vector3(0, 0.015, 0), top + Vector3(0, cr * 0.35, 0), top + Vector3(0, cr * 0.6, 0), cr, 0.005, 4, 10)
	return [_commit([st, cap], ["stem", "cap_red" if red else "cap_brown"]), 0.3]

## Муравейник: конус из хвои у основания ели.
func anthill(seed_v: int) -> Array:
	rng.seed = seed_v
	var s := Surf.new()
	var r := R(0.6, 0.9)
	tube(s, Vector3(0, -0.05, 0), Vector3(0, r * 0.5, 0), Vector3(0, r * 0.95, 0), r, 0.06, 6, 14)
	return [_commit([s], ["litter"]), 1.0]
